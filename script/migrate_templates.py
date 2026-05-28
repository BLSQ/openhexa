#!/usr/bin/env python3
"""Migrate all pipeline templates from one OpenHEXA server to another.

Templates are globally visible on a server, so this script runs once per
target server (independently of any workspace migration). For each
source template it:

  - finds or creates a host pipeline on target (the source pipeline in
    its original workspace if already migrated, otherwise inside a
    "Template pipelines" workspace this script creates as needed),
  - uploads any missing pipeline versions,
  - calls ``createPipelineTemplateVersion`` per missing template version
    (matched against target by name + ``versionNumber``),
  - applies ``description`` / ``functionalType`` / ``tags`` via
    ``updatePipelineTemplate``.

Re-runnable. Auth: Django superuser email/password on both ends, same
shape as ``migrate_workspace.py``.

Out of scope: ``validatedAt`` (not settable via the API; warned about);
relinking pipelines that were created from templates on source back to
those templates on target.
"""

import argparse
import sys

try:
    from openhexa.graphql.graphql_client.exceptions import (
        GraphQLClientGraphQLMultiError,
        GraphQLClientHttpError,
    )
except ImportError:
    sys.stderr.write(
        "error: this script requires the 'openhexa.sdk' package "
        "(install with: pip install openhexa.sdk)\n"
    )
    sys.exit(1)

from migrate_lib import templates, transport
from migrate_lib.templates import TemplatesResult
from migrate_lib.transport import GraphQLError, build_client


DEFAULT_SOURCE_URL = "https://api.openhexa.org/graphql/"
DEFAULT_TARGET_URL = "http://localhost:8000/graphql/"


def _print_summary(result: TemplatesResult) -> None:
    print("\n=== Template migration summary ===")
    print(f"Templates created on target: {len(result.created)}")
    for name in result.created:
        print(f"  * {name}")
    if result.versions_added:
        print(
            f"Template versions added: {sum(len(v) for _, v in result.versions_added)}"
        )
        for name, nums in result.versions_added:
            nums_str = ", ".join(f"v{n}" for n in nums)
            print(f"  * {name}: {nums_str}")
    if result.skipped_unchanged:
        print(
            f"Templates already up to date (skipped): {len(result.skipped_unchanged)}"
        )
        for name in result.skipped_unchanged:
            print(f"  * {name}")
    if result.warnings:
        print("Warnings:")
        for w in result.warnings:
            print(f"  - {w}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Migrate every pipeline template from a source "
        "OpenHEXA server to a target server.",
    )
    parser.add_argument(
        "--source-url",
        default=DEFAULT_SOURCE_URL,
        help=f"Source GraphQL endpoint (default: {DEFAULT_SOURCE_URL}).",
    )
    parser.add_argument(
        "--source-email",
        required=True,
        help="Email of the Django superuser on the source server.",
    )
    parser.add_argument(
        "--source-password",
        required=True,
        help="Password of the Django superuser on the source server.",
    )
    parser.add_argument(
        "--target-url",
        default=DEFAULT_TARGET_URL,
        help=f"Target GraphQL endpoint (default: {DEFAULT_TARGET_URL}).",
    )
    parser.add_argument(
        "--target-email",
        required=True,
        help="Email of the Django superuser on the target server.",
    )
    parser.add_argument(
        "--target-password",
        required=True,
        help="Password of the Django superuser on the target server.",
    )
    parser.add_argument(
        "--debug",
        "-v",
        action="store_true",
        help="Print each GraphQL request (operation + variables) and response status.",
    )
    args = parser.parse_args()

    transport.DEBUG = args.debug

    print(f"Source: {args.source_url}")
    print(f"Target: {args.target_url}")

    try:
        source = build_client(
            args.source_url, args.source_email, args.source_password, label="source"
        )
        target = build_client(
            args.target_url, args.target_email, args.target_password, label="target"
        )
        result = templates.migrate_all(source, target)
        _print_summary(result)
    except GraphQLClientHttpError as exc:
        sys.stderr.write(
            f"\nerror: HTTP {exc.status_code} from server:\n{exc.response.text[:4000]}\n"
        )
        return 1
    except GraphQLClientGraphQLMultiError as exc:
        sys.stderr.write("\nerror: GraphQL errors from server:\n")
        for e in exc.errors:
            sys.stderr.write(f"  - {e.message}")
            if e.path:
                sys.stderr.write(f"  (at path: {'.'.join(map(str, e.path))})")
            sys.stderr.write("\n")
        return 1
    except GraphQLError as exc:
        sys.stderr.write(f"\nerror: {exc}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
