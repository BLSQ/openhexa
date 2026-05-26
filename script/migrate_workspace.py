#!/usr/bin/env python3
"""Migrate a workspace from one OpenHEXA server to another.

Source auth: WorkspaceMembership.access_token (the same token format the
OpenHEXA CLI uses), sent as ``Authorization: Bearer <token>``.

Target auth: Django superuser email/password passed via CLI flags,
exchanged for a session cookie via the GraphQL ``login`` mutation.

Scope:
  - Workspace metadata (name, description, dockerImage, configuration,
    countries) is migrated.
  - Each pipeline is created via createPipeline; each zipfile-pipeline
    version is uploaded via uploadPipeline; pipeline-level schedule /
    config / webhookEnabled / scheduledPipelineVersionId are applied via
    updatePipeline.

Out of scope: members, invitations, connections, recipients, templates,
runs, shortcuts, workspace files, datasets, database tables. Notebook
pipelines are created with their notebookPath but the notebook file
itself is not migrated (a warning is emitted).
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

from migrate_lib import pipelines, transport, workspaces
from migrate_lib.pipelines import PipelinesResult
from migrate_lib.transport import GraphQLError, build_source, build_target


DEFAULT_SOURCE_URL = "https://api.openhexa.org/graphql/"
DEFAULT_TARGET_URL = "http://localhost:8000/graphql/"


def migrate(source, target, source_slug: str) -> None:
    print(f"=> Fetching source workspace '{source_slug}' ...")
    src_ws = source.workspace(slug=source_slug)
    if src_ws is None:
        raise GraphQLError(f"source workspace '{source_slug}' not found")
    print(f"   name: {src_ws.name!r}")

    print("=> Creating target workspace ...")
    target_slug = workspaces.create(target, src_ws)
    print(f"   created with slug '{target_slug}'")
    if target_slug != source_slug:
        print(
            f"   note: the server picked its own slug — '{target_slug}' "
            f"instead of source slug '{source_slug}'. The createWorkspace "
            "mutation always derives the slug from the workspace name."
        )

    pipelines_result = pipelines.migrate_all(source, target, source_slug, target_slug)

    _print_summary(src_ws.name, target_slug, pipelines_result)


def _print_summary(
    src_ws_name: str, target_slug: str, pipelines_result: PipelinesResult
) -> None:
    print("\n=== Migration summary ===")
    print(f"Workspace: {src_ws_name!r} -> slug '{target_slug}'")
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
        "--token",
        required=True,
        help="WorkspaceMembership access token from the source server "
        "(same token used by the OpenHEXA CLI).",
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
        source = build_source(args.source_url, args.token)
        target = build_target(args.target_url, args.target_email, args.target_password)
        migrate(source, target, args.slug)
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
