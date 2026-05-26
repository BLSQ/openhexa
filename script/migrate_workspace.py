#!/usr/bin/env python3
"""Migrate a workspace from one OpenHEXA server to another.

Auth (both source and target): Django superuser email/password passed via
CLI flags, exchanged for a session cookie via the GraphQL ``login`` mutation.

Scope:
  - Workspace metadata (name, description, dockerImage, configuration,
    countries) is migrated.
  - All files in the workspace bucket are copied from source to target
    (must run before pipelines, since notebook pipelines require their
    .ipynb to exist on the target before createPipeline succeeds).
  - Each pipeline is created via createPipeline; each zipfile-pipeline
    version is uploaded via uploadPipeline; pipeline-level schedule /
    config / webhookEnabled / scheduledPipelineVersionId are applied via
    updatePipeline.

Out of scope: members, invitations, connections, recipients, templates,
runs, shortcuts, datasets, database tables.
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

from migrate_lib import files, pipelines, transport, workspaces
from migrate_lib.files import FilesResult
from migrate_lib.pipelines import PipelinesResult
from migrate_lib.transport import GraphQLError, build_client


DEFAULT_SOURCE_URL = "https://api.openhexa.org/graphql/"
DEFAULT_TARGET_URL = "http://localhost:8000/graphql/"


def migrate(
    source, target, source_slug: str, target_organization_id: str | None = None
) -> None:
    print(f"=> Fetching source workspace '{source_slug}' ...")
    src_ws = source.workspace(slug=source_slug)
    if src_ws is None:
        raise GraphQLError(f"source workspace '{source_slug}' not found")
    print(f"   name: {src_ws.name!r}")

    print("=> Creating target workspace ...")
    target_slug = workspaces.create(target, src_ws, target_organization_id)
    print(f"   created with slug '{target_slug}'")
    if target_slug != source_slug:
        print(
            f"   note: the server picked its own slug — '{target_slug}' "
            f"instead of source slug '{source_slug}'. The createWorkspace "
            "mutation always derives the slug from the workspace name."
        )

    files_result = files.migrate_all(source, target, source_slug, target_slug)
    pipelines_result = pipelines.migrate_all(source, target, source_slug, target_slug)

    _print_summary(src_ws.name, target_slug, files_result, pipelines_result)


def _print_summary(
    src_ws_name: str,
    target_slug: str,
    files_result: FilesResult,
    pipelines_result: PipelinesResult,
) -> None:
    print("\n=== Migration summary ===")
    print(f"Workspace: {src_ws_name!r} -> slug '{target_slug}'")
    total_bytes = sum(b for _, b in files_result.copied)
    print(f"Files copied: {len(files_result.copied)} ({total_bytes} bytes)")
    if files_result.failed:
        print(
            f"Files that could NOT be migrated "
            f"({len(files_result.failed)} — handle manually):"
        )
        for path in files_result.failed:
            print(f"  * {path}")
    print(f"Pipelines created: {len(pipelines_result.created)}")
    for code, vnames in pipelines_result.created:
        print(f"  * {code}")
        for vn in vnames:
            print(f"      - {vn}")
    if pipelines_result.skipped:
        print(f"Pipelines skipped (already existed): {len(pipelines_result.skipped)}")
        for code in pipelines_result.skipped:
            print(f"  * {code}")
    if pipelines_result.warnings:
        print("Warnings:")
        for w in pipelines_result.warnings:
            print(f"  - {w}")
    print(
        "Note: connections were not migrated; recreate them locally if "
        "any pipeline depends on connection-typed parameters."
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Migrate a workspace from a remote OpenHEXA server "
        "to the local Docker setup.",
    )
    parser.add_argument(
        "--slug",
        required=True,
        help="Slug of the source workspace on the remote server.",
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
        help=f"Local GraphQL endpoint (default: {DEFAULT_TARGET_URL}).",
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
        "--target-organization",
        default=None,
        help="Optional UUID of the organization on the target server to create "
        "the workspace under. If omitted, the workspace is created without an "
        "organization.",
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
        migrate(source, target, args.slug, args.target_organization)
    except GraphQLClientHttpError as exc:
        # SDK's __str__ only includes the status code. Print the body too.
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
