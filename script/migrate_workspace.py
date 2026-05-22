#!/usr/bin/env python3
"""Migrate a workspace from a remote OpenHEXA server to the local Docker setup.

Source auth: WorkspaceMembership.access_token (the same token format the
OpenHEXA CLI uses), sent as ``Authorization: Bearer <token>``.

Target auth: Django superuser email/password from .env, exchanged for a
session cookie via the GraphQL ``login`` mutation.

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
import base64
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urljoin

try:
    import httpx
    from openhexa.graphql.graphql_client.client import Client
    from openhexa.graphql.graphql_client.exceptions import (
        GraphQLClientGraphQLMultiError,
        GraphQLClientHttpError,
    )
    from openhexa.graphql.graphql_client.input_types import (
        CountryInput,
        CreatePipelineInput,
        CreateWorkspaceInput,
        UpdateWorkspaceInput,
    )
    from openhexa.sdk.utils import OpenHexaClient
except ImportError:
    sys.stderr.write(
        "error: this script requires the 'openhexa.sdk' package "
        "(install with: pip install openhexa.sdk)\n"
    )
    sys.exit(1)


DEFAULT_SOURCE_URL = "https://api.openhexa.org/graphql/"
PIPELINES_PAGE_SIZE = 50
VERSIONS_PAGE_SIZE = 50


# ---------------------------------------------------------------------------
# .env loading
# ---------------------------------------------------------------------------


def parse_env_file(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if (value.startswith("'") and value.endswith("'")) or (
            value.startswith('"') and value.endswith('"')
        ):
            value = value[1:-1]
        env[key.strip()] = value
    return env


# ---------------------------------------------------------------------------
# GraphQL transport (SDK-backed)
# ---------------------------------------------------------------------------


class GraphQLError(RuntimeError):
    pass


def gql(
    client: Client,
    query: str,
    variables: dict[str, Any] | None = None,
    operation_name: str | None = None,
) -> dict[str, Any]:
    """Execute a raw GraphQL query through the SDK client and return data."""
    resp = client.execute(
        query=query, variables=variables or {}, operation_name=operation_name
    )
    return client.get_data(resp)


def build_source(server_url: str, token: str) -> OpenHexaClient:
    return OpenHexaClient(token=token, server_url=server_url)


def build_target(target_url: str, email: str, password: str) -> Client:
    http = httpx.Client(headers={"User-Agent": "openhexa-migrate/1.0"})
    # Prime CSRF cookie. Defensive — GraphQLView is csrf_exempt on the
    # current backend, but a future change would otherwise silently
    # break every mutation.
    http.get(target_url)
    csrf = http.cookies.get("csrftoken")
    if csrf:
        http.headers["X-CSRFToken"] = csrf
        http.headers["Referer"] = target_url

    client = Client(url=target_url, http_client=http)
    data = gql(
        client,
        "mutation Login($input: LoginInput!) { login(input: $input) { success errors } }",
        {"input": {"email": email, "password": password}},
        "Login",
    )
    if not data["login"]["success"]:
        raise GraphQLError(
            "target login failed: " + ",".join(data["login"]["errors"] or [])
        )
    return client


# ---------------------------------------------------------------------------
# Source fetch helpers
# ---------------------------------------------------------------------------

PIPELINE_DETAIL_QUERY = """
query PipelineDetail($id: UUID!, $vPage: Int!, $vPerPage: Int!) {
    pipeline(id: $id) {
        id code name description type functionalType notebookPath
        schedule config webhookEnabled
        tags { name }
        scheduledPipelineVersion { id versionNumber }
        versions(page: $vPage, perPage: $vPerPage) {
            pageNumber
            totalPages
            items {
                id versionNumber name description externalLink config timeout
                zipfile
                parameters {
                    code name type multiple required default help
                    widget connection choices
                    choicesFromFile { path format column }
                    directory
                }
            }
        }
    }
}
"""


def fetch_source_pipeline_ids(
    source: OpenHexaClient, slug: str
) -> list[tuple[str, str]]:
    """Return [(pipeline_id, pipeline_code), ...] across all pages."""
    pairs: list[tuple[str, str]] = []
    page = 1
    while True:
        result = source.pipelines(
            workspace_slug=slug, page=page, per_page=PIPELINES_PAGE_SIZE
        )
        pairs.extend((str(item.id), item.code) for item in result.items)
        if page >= result.total_pages or result.total_pages == 0:
            break
        page += 1
    return pairs


def fetch_source_pipeline_detail(
    source: OpenHexaClient, pipeline_id: str
) -> dict[str, Any]:
    """Fetch full pipeline data + all versions for one pipeline."""
    first = gql(
        source,
        PIPELINE_DETAIL_QUERY,
        {"id": pipeline_id, "vPage": 1, "vPerPage": VERSIONS_PAGE_SIZE},
        "PipelineDetail",
    )
    detail = first["pipeline"]
    if detail is None:
        raise GraphQLError(f"source pipeline id={pipeline_id} disappeared")
    versions = list(detail["versions"]["items"])
    total_pages = detail["versions"]["totalPages"]
    for vpage in range(2, total_pages + 1):
        more = gql(
            source,
            PIPELINE_DETAIL_QUERY,
            {"id": pipeline_id, "vPage": vpage, "vPerPage": VERSIONS_PAGE_SIZE},
            "PipelineDetail",
        )
        versions.extend(more["pipeline"]["versions"]["items"])
    detail["versions"] = sorted(versions, key=lambda v: v["versionNumber"])
    return detail


# ---------------------------------------------------------------------------
# Target apply helpers
# ---------------------------------------------------------------------------

UPLOAD_PIPELINE_MUTATION = """
mutation UploadPipeline($input: UploadPipelineInput!) {
    uploadPipeline(input: $input) {
        success errors details
        pipelineVersion { id versionNumber versionName }
    }
}
"""

UPDATE_PIPELINE_MUTATION = """
mutation UpdatePipeline($input: UpdatePipelineInput!) {
    updatePipeline(input: $input) {
        success errors
        pipeline { id code }
    }
}
"""


def create_target_workspace(target: Client, src_ws: Any, target_slug: str) -> str:
    """Create the workspace on target, returning the created slug."""
    countries = [
        CountryInput(code=c.code, alpha3=c.alpha_3, name=c.name, flag=c.flag)
        for c in (src_ws.countries or [])
    ]
    result = target.create_workspace(
        input=CreateWorkspaceInput(
            name=src_ws.name,
            slug=target_slug,
            description=src_ws.description or "",
            countries=countries,
            load_sample_data=False,
            configuration=src_ws.configuration or {},
        )
    )
    if not result.success or result.workspace is None:
        raise GraphQLError("createWorkspace failed: " + ",".join(result.errors or []))
    created_slug = result.workspace.slug

    if src_ws.docker_image:
        upd = target.update_workspace(
            input=UpdateWorkspaceInput(
                slug=created_slug, docker_image=src_ws.docker_image
            )
        )
        if not upd.success:
            print(
                f"  warning: could not set dockerImage="
                f"'{src_ws.docker_image}': " + ",".join(upd.errors or []),
                file=sys.stderr,
            )
    return created_slug


def create_target_pipeline(
    target: Client, target_slug: str, src_pipeline: dict[str, Any]
) -> str:
    """Create an empty pipeline on the target and return its UUID."""
    is_notebook = src_pipeline.get("type") == "notebook"
    tags = [t["name"] for t in (src_pipeline.get("tags") or [])]
    create_input = CreatePipelineInput(
        name=src_pipeline["name"] or src_pipeline["code"],
        description=src_pipeline.get("description") or None,
        workspace_slug=target_slug,
        notebook_path=src_pipeline.get("notebookPath") if is_notebook else None,
        functional_type=src_pipeline.get("functionalType"),
        tags=tags or None,
    )
    result = target.create_pipeline(input=create_input)
    if not result.success or result.pipeline is None:
        raise GraphQLError(
            f"createPipeline failed for '{src_pipeline['code']}': "
            + ",".join(e.value for e in (result.errors or []))
        )

    # createPipeline returns only the code; fetch by code to get the id
    # needed for subsequent updatePipeline.
    created = target.pipeline(
        workspace_slug=target_slug, pipeline_code=result.pipeline.code
    )
    if created is None:
        raise GraphQLError(
            f"could not look up created pipeline '{result.pipeline.code}'"
        )
    return str(created.id)


def _clean_parameters(parameters: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Strip nulls that the input type doesn't accept verbatim."""
    cleaned = []
    for p in parameters:
        item = {k: v for k, v in p.items() if v is not None}
        cfile = item.get("choicesFromFile")
        if cfile is not None:
            item["choicesFromFile"] = {k: v for k, v in cfile.items() if v is not None}
        cleaned.append(item)
    return cleaned


def upload_pipeline_version(
    target: Client,
    workspace_slug: str,
    pipeline_code: str,
    version: dict[str, Any],
) -> dict[str, Any]:
    """Upload one version to an existing target pipeline."""
    try:
        base64.b64decode(version["zipfile"], validate=True)
    except Exception as exc:
        raise GraphQLError(
            f"version {version['versionNumber']} has invalid base64 zipfile: {exc}"
        )

    input_: dict[str, Any] = {
        "workspaceSlug": workspace_slug,
        "pipelineCode": pipeline_code,
        "name": version.get("name"),
        "description": version.get("description"),
        "externalLink": version.get("externalLink"),
        "parameters": _clean_parameters(version.get("parameters") or []),
        "zipfile": version["zipfile"],
        "config": version.get("config") or {},
        "timeout": version.get("timeout"),
    }
    input_ = {k: v for k, v in input_.items() if v is not None}
    data = gql(target, UPLOAD_PIPELINE_MUTATION, {"input": input_}, "UploadPipeline")
    result = data["uploadPipeline"]
    if not result["success"]:
        raise GraphQLError(
            f"uploadPipeline failed for {pipeline_code} v{version['versionNumber']}: "
            + ",".join(result.get("errors") or [])
            + (f" ({result['details']})" if result.get("details") else "")
        )
    return result["pipelineVersion"]


def update_pipeline_settings(
    target: Client,
    target_pipeline_id: str,
    src_pipeline: dict[str, Any],
    scheduled_version_id: str | None,
) -> None:
    """Apply pipeline-level fields that createPipeline/uploadPipeline cannot set."""
    input_: dict[str, Any] = {
        "id": target_pipeline_id,
        "schedule": src_pipeline.get("schedule"),
        "webhookEnabled": src_pipeline.get("webhookEnabled"),
        "config": src_pipeline.get("config") or None,
        "scheduledPipelineVersionId": scheduled_version_id,
        "autoUpdateFromTemplate": False,
    }
    # Only call updatePipeline if at least one migrated field has a value.
    meaningful = {
        k: v
        for k, v in input_.items()
        if k != "id"
        and k != "autoUpdateFromTemplate"
        and v not in (None, False, {}, "")
    }
    if not meaningful:
        return
    input_ = {k: v for k, v in input_.items() if v is not None}
    data = gql(target, UPDATE_PIPELINE_MUTATION, {"input": input_}, "UpdatePipeline")
    result = data["updatePipeline"]
    if not result["success"]:
        raise GraphQLError(
            f"updatePipeline failed for {src_pipeline['code']}: "
            + ",".join(result.get("errors") or [])
        )


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------


def migrate(
    source: OpenHexaClient,
    target: Client,
    source_slug: str,
    target_slug: str,
) -> None:
    print(f"=> Fetching source workspace '{source_slug}' ...")
    src_ws = source.workspace(slug=source_slug)
    if src_ws is None:
        raise GraphQLError(f"source workspace '{source_slug}' not found")
    print(f"   name: {src_ws.name!r}")

    if target.workspace(slug=target_slug) is not None:
        raise SystemExit(
            f"error: target workspace '{target_slug}' already exists; aborting."
        )

    print(f"=> Creating target workspace '{target_slug}' ...")
    create_target_workspace(target, src_ws, target_slug)

    print("=> Listing source pipelines ...")
    pairs = fetch_source_pipeline_ids(source, source_slug)
    print(f"   found {len(pairs)} pipeline(s)")

    created_summary: list[tuple[str, list[str]]] = []
    skipped: list[str] = []
    warnings: list[str] = []

    for pipeline_id, code in pairs:
        existing = target.pipeline(workspace_slug=target_slug, pipeline_code=code)
        if existing is not None:
            print(f"   - pipeline '{code}' already exists on target — skipping")
            skipped.append(code)
            continue

        print(f"   - migrating pipeline '{code}' ...")
        detail = fetch_source_pipeline_detail(source, pipeline_id)
        is_notebook = detail.get("type") == "notebook"

        target_pid = create_target_pipeline(target, target_slug, detail)
        print(f"       created pipeline (id={target_pid})")

        uploaded_names: list[str] = []
        scheduled_version_id: str | None = None
        scheduled_src = detail.get("scheduledPipelineVersion") or {}
        scheduled_src_number = scheduled_src.get("versionNumber")

        if is_notebook:
            warnings.append(
                f"pipeline '{code}' is a notebook pipeline; its source file "
                f"at notebookPath='{detail.get('notebookPath')}' must be "
                "copied into the local workspace files for it to run."
            )
            if detail.get("versions"):
                warnings.append(
                    f"pipeline '{code}' has {len(detail['versions'])} version(s) "
                    "on the source, but uploadPipeline is not supported for "
                    "notebook pipelines — versions were not migrated."
                )
        else:
            versions = detail.get("versions") or []
            if not versions:
                warnings.append(
                    f"pipeline '{code}' has no versions on source; "
                    "created with no version."
                )
            for v in versions:
                up = upload_pipeline_version(target, target_slug, code, v)
                uploaded_names.append(up["versionName"])
                print(
                    f"       uploaded version v{v['versionNumber']} "
                    f"-> {up['versionName']}"
                )
                if (
                    scheduled_src_number is not None
                    and up.get("versionNumber") == scheduled_src_number
                ):
                    scheduled_version_id = up["id"]

        update_pipeline_settings(target, target_pid, detail, scheduled_version_id)

        created_summary.append((code, uploaded_names))

    # ----------- summary -----------
    print("\n=== Migration summary ===")
    print(f"Workspace: {src_ws.name!r} -> slug '{target_slug}'")
    print(f"Pipelines created: {len(created_summary)}")
    for code, vnames in created_summary:
        print(f"  * {code}")
        for vn in vnames:
            print(f"      - {vn}")
    if skipped:
        print(f"Pipelines skipped (already existed): {len(skipped)}")
        for code in skipped:
            print(f"  * {code}")
    if warnings:
        print("Warnings:")
        for w in warnings:
            print(f"  - {w}")
    print(
        "Note: connections were not migrated; recreate them locally if "
        "any pipeline depends on connection-typed parameters."
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


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
        "--target-slug",
        help="Slug to use locally (defaults to the source slug).",
    )
    parser.add_argument(
        "--source-url",
        default=DEFAULT_SOURCE_URL,
        help=f"Source GraphQL endpoint (default: {DEFAULT_SOURCE_URL}).",
    )
    parser.add_argument(
        "--env-file",
        default=str(Path(__file__).resolve().parent.parent / ".env"),
        help="Path to the .env file (default: repo .env).",
    )
    parser.add_argument(
        "--target-url",
        help="Override the local GraphQL endpoint (default derived from "
        "APP_PORT in .env: http://localhost:${APP_PORT}/graphql/).",
    )
    args = parser.parse_args()

    env_path = Path(args.env_file)
    if not env_path.exists():
        sys.stderr.write(f"error: env file not found: {env_path}\n")
        return 2
    env = parse_env_file(env_path)

    superuser = env.get("DJANGO_SUPERUSER_USERNAME")
    password = env.get("DJANGO_SUPERUSER_PASSWORD")
    if not superuser or not password:
        sys.stderr.write(
            "error: DJANGO_SUPERUSER_USERNAME and DJANGO_SUPERUSER_PASSWORD "
            "must be set in the env file.\n"
        )
        return 2

    target_url = args.target_url or urljoin(
        f"http://localhost:{env.get('APP_PORT', '8000')}/", "graphql/"
    )
    target_slug = args.target_slug or args.slug

    print(f"Source: {args.source_url}")
    print(f"Target: {target_url}")

    try:
        source = build_source(args.source_url, args.token)
        target = build_target(target_url, superuser, password)
        migrate(source, target, args.slug, target_slug)
    except (
        GraphQLError,
        GraphQLClientGraphQLMultiError,
        GraphQLClientHttpError,
    ) as exc:
        sys.stderr.write(f"\nerror: {exc}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
