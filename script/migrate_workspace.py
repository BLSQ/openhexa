#!/usr/bin/env python3
"""Migrate a workspace from a remote OpenHEXA server to the local Docker setup.

Source auth: WorkspaceMembership.access_token (the same token format the
OpenHEXA CLI uses), sent as ``Authorization: Bearer <token>``.

Target auth: Django superuser email/password from .env, exchanged for a
session cookie via the GraphQL ``login`` mutation.

Scope:
  - Workspace metadata (name, description, dockerImage, configuration,
    countries) is migrated.
  - All pipelines and all their versions (zipfile bytes + parameters +
    per-version metadata) are migrated.
  - Pipeline-level fields (schedule, config, webhookEnabled, tags,
    functionalType, scheduledPipelineVersion) are applied after upload.

Out of scope: members, invitations, connections, recipients, templates,
runs, shortcuts, workspace files, datasets, database tables.
"""

import argparse
import base64
import json
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urljoin, urlparse

try:
    import requests
except ImportError:
    sys.stderr.write(
        "error: this script requires the 'requests' package "
        "(install with: pip install requests)\n"
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
# GraphQL client
# ---------------------------------------------------------------------------

class GraphQLError(RuntimeError):
    pass


class GraphQLClient:
    def __init__(self, url: str, label: str):
        self.url = url
        self.label = label
        self.session = requests.Session()
        self.session.headers["Accept"] = "application/json"

    def _csrf_priming_get(self) -> None:
        """Trigger Django to set the csrftoken cookie."""
        self.session.get(self.url, timeout=30)

    def _maybe_csrf_header(self) -> dict[str, str]:
        token = self.session.cookies.get("csrftoken")
        if not token:
            return {}
        return {
            "X-CSRFToken": token,
            "Referer": f"{urlparse(self.url).scheme}://{urlparse(self.url).netloc}/",
        }

    def execute(
        self, query: str, variables: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        payload = {"query": query, "variables": variables or {}}
        headers = {"Content-Type": "application/json", **self._maybe_csrf_header()}
        resp = self.session.post(
            self.url, data=json.dumps(payload), headers=headers, timeout=120
        )
        if resp.status_code != 200:
            raise GraphQLError(
                f"[{self.label}] HTTP {resp.status_code}: {resp.text[:500]}"
            )
        body = resp.json()
        if body.get("errors"):
            raise GraphQLError(
                f"[{self.label}] GraphQL errors: "
                + json.dumps(body["errors"], indent=2)
            )
        return body["data"]


def build_source_client(url: str, token: str) -> GraphQLClient:
    client = GraphQLClient(url, label="source")
    client.session.headers["Authorization"] = f"Bearer {token}"
    # Bearer-auth POSTs don't need a CSRF token (no session cookie), but
    # priming costs nothing and is harmless.
    client._csrf_priming_get()
    return client


def build_target_client(url: str, email: str, password: str) -> GraphQLClient:
    client = GraphQLClient(url, label="target")
    client._csrf_priming_get()
    data = client.execute(
        """
        mutation Login($input: LoginInput!) {
            login(input: $input) { success errors }
        }
        """,
        {"input": {"email": email, "password": password}},
    )
    result = data["login"]
    if not result["success"]:
        raise GraphQLError(
            "target login failed: " + ",".join(result.get("errors") or [])
        )
    return client


# ---------------------------------------------------------------------------
# Fetch from source
# ---------------------------------------------------------------------------

WORKSPACE_QUERY = """
query SourceWorkspace($slug: String!) {
    workspace(slug: $slug) {
        slug
        name
        description
        dockerImage
        configuration
        countries { code alpha3 name flag }
    }
}
"""

PIPELINES_QUERY = """
query SourcePipelines($slug: String!, $page: Int!, $perPage: Int!) {
    pipelines(workspaceSlug: $slug, page: $page, perPage: $perPage) {
        pageNumber
        totalPages
        totalItems
        items {
            id
            code
            name
            description
            type
            functionalType
            notebookPath
            schedule
            config
            webhookEnabled
            tags { name }
            scheduledPipelineVersion { id versionNumber }
        }
    }
}
"""

VERSIONS_QUERY = """
query SourcePipelineVersions($id: UUID!, $page: Int!, $perPage: Int!) {
    pipeline(id: $id) {
        versions(page: $page, perPage: $perPage) {
            pageNumber
            totalPages
            totalItems
            items {
                id
                versionNumber
                name
                description
                externalLink
                config
                timeout
                zipfile
                parameters {
                    code
                    name
                    type
                    multiple
                    required
                    default
                    help
                    widget
                    connection
                    choices
                    choicesFromFile { path format column }
                    directory
                }
            }
        }
    }
}
"""


def fetch_source_workspace(client: GraphQLClient, slug: str) -> dict[str, Any]:
    data = client.execute(WORKSPACE_QUERY, {"slug": slug})
    if data["workspace"] is None:
        raise GraphQLError(f"source workspace '{slug}' not found")
    return data["workspace"]


def fetch_source_pipelines(
    client: GraphQLClient, slug: str
) -> list[dict[str, Any]]:
    pipelines: list[dict[str, Any]] = []
    page = 1
    while True:
        data = client.execute(
            PIPELINES_QUERY,
            {"slug": slug, "page": page, "perPage": PIPELINES_PAGE_SIZE},
        )
        result = data["pipelines"]
        pipelines.extend(result["items"])
        if page >= result["totalPages"] or result["totalPages"] == 0:
            break
        page += 1
    return pipelines


def fetch_pipeline_versions(
    client: GraphQLClient, pipeline_id: str
) -> list[dict[str, Any]]:
    versions: list[dict[str, Any]] = []
    page = 1
    while True:
        data = client.execute(
            VERSIONS_QUERY,
            {"id": pipeline_id, "page": page, "perPage": VERSIONS_PAGE_SIZE},
        )
        result = data["pipeline"]["versions"]
        versions.extend(result["items"])
        if page >= result["totalPages"] or result["totalPages"] == 0:
            break
        page += 1
    # Upload oldest first so versionNumber order is preserved locally.
    versions.sort(key=lambda v: v["versionNumber"])
    return versions


# ---------------------------------------------------------------------------
# Apply to target
# ---------------------------------------------------------------------------

TARGET_WORKSPACE_QUERY = """
query TargetWorkspace($slug: String!) {
    workspace(slug: $slug) { slug }
}
"""

TARGET_PIPELINE_QUERY = """
query TargetPipeline($slug: String!, $code: String!) {
    pipelineByCode(workspaceSlug: $slug, code: $code) { id code }
}
"""

CREATE_WORKSPACE = """
mutation CreateWorkspace($input: CreateWorkspaceInput!) {
    createWorkspace(input: $input) {
        success errors
        workspace { slug name }
    }
}
"""

UPDATE_WORKSPACE = """
mutation UpdateWorkspace($input: UpdateWorkspaceInput!) {
    updateWorkspace(input: $input) {
        success errors
        workspace { slug }
    }
}
"""

UPLOAD_PIPELINE = """
mutation UploadPipeline($input: UploadPipelineInput!) {
    uploadPipeline(input: $input) {
        success errors details
        pipelineVersion { id versionNumber versionName }
    }
}
"""

UPDATE_PIPELINE = """
mutation UpdatePipeline($input: UpdatePipelineInput!) {
    updatePipeline(input: $input) {
        success errors
        pipeline { id code name }
    }
}
"""


def target_workspace_exists(client: GraphQLClient, slug: str) -> bool:
    try:
        data = client.execute(TARGET_WORKSPACE_QUERY, {"slug": slug})
    except GraphQLError:
        return False
    return data.get("workspace") is not None


def target_pipeline_get(
    client: GraphQLClient, slug: str, code: str
) -> dict[str, Any] | None:
    try:
        data = client.execute(
            TARGET_PIPELINE_QUERY, {"slug": slug, "code": code}
        )
    except GraphQLError:
        return None
    return data.get("pipelineByCode")


def create_target_workspace(
    client: GraphQLClient, src_ws: dict[str, Any], target_slug: str
) -> dict[str, Any]:
    countries = [
        {
            "code": c["code"],
            "alpha3": c.get("alpha3"),
            "name": c.get("name"),
            "flag": c.get("flag"),
        }
        for c in (src_ws.get("countries") or [])
    ]
    input_ = {
        "name": src_ws["name"],
        "slug": target_slug,
        "description": src_ws.get("description") or "",
        "countries": countries,
        "loadSampleData": False,
        "configuration": src_ws.get("configuration") or {},
    }
    data = client.execute(CREATE_WORKSPACE, {"input": input_})
    result = data["createWorkspace"]
    if not result["success"]:
        raise GraphQLError(
            "createWorkspace failed: " + ",".join(result.get("errors") or [])
        )
    created_slug = result["workspace"]["slug"]

    docker_image = src_ws.get("dockerImage")
    if docker_image:
        data = client.execute(
            UPDATE_WORKSPACE,
            {
                "input": {
                    "slug": created_slug,
                    "dockerImage": docker_image,
                }
            },
        )
        upd = data["updateWorkspace"]
        if not upd["success"]:
            print(
                f"  warning: could not set dockerImage='{docker_image}': "
                + ",".join(upd.get("errors") or []),
                file=sys.stderr,
            )
    return result["workspace"]


def _clean_parameters(parameters: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Strip nulls that the input type doesn't accept verbatim."""
    cleaned = []
    for p in parameters:
        item = {k: v for k, v in p.items() if v is not None}
        cfile = item.get("choicesFromFile")
        if cfile is not None:
            item["choicesFromFile"] = {
                k: v for k, v in cfile.items() if v is not None
            }
        cleaned.append(item)
    return cleaned


def upload_pipeline_version(
    client: GraphQLClient,
    workspace_slug: str,
    pipeline_code: str,
    version: dict[str, Any],
    pipeline_meta: dict[str, Any],
) -> dict[str, Any]:
    # zipfile from source is already base64-encoded (per schema).
    # We forward it verbatim, but defensively re-validate it decodes.
    try:
        base64.b64decode(version["zipfile"], validate=True)
    except Exception as exc:
        raise GraphQLError(
            f"version {version['versionNumber']} has invalid base64 zipfile: {exc}"
        )

    tags = [t["name"] for t in (pipeline_meta.get("tags") or [])]
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
        "tags": tags,
        "functionalType": pipeline_meta.get("functionalType"),
    }
    input_ = {k: v for k, v in input_.items() if v is not None}
    data = client.execute(UPLOAD_PIPELINE, {"input": input_})
    result = data["uploadPipeline"]
    if not result["success"]:
        raise GraphQLError(
            f"uploadPipeline failed for {pipeline_code} v{version['versionNumber']}: "
            + ",".join(result.get("errors") or [])
            + (f" ({result.get('details')})" if result.get("details") else "")
        )
    return result["pipelineVersion"]


def update_pipeline_after_upload(
    client: GraphQLClient,
    target_pipeline_id: str,
    src_pipeline: dict[str, Any],
    scheduled_version_id: str | None,
) -> None:
    tags = [t["name"] for t in (src_pipeline.get("tags") or [])]
    input_: dict[str, Any] = {
        "id": target_pipeline_id,
        "name": src_pipeline.get("name"),
        "description": src_pipeline.get("description"),
        "config": src_pipeline.get("config") or {},
        "schedule": src_pipeline.get("schedule"),
        "webhookEnabled": src_pipeline.get("webhookEnabled"),
        "autoUpdateFromTemplate": False,
        "tags": tags,
        "functionalType": src_pipeline.get("functionalType"),
        "scheduledPipelineVersionId": scheduled_version_id,
    }
    input_ = {k: v for k, v in input_.items() if v is not None}
    data = client.execute(UPDATE_PIPELINE, {"input": input_})
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
    src: GraphQLClient,
    dst: GraphQLClient,
    source_slug: str,
    target_slug: str,
) -> None:
    print(f"=> Fetching source workspace '{source_slug}' ...")
    src_ws = fetch_source_workspace(src, source_slug)
    print(f"   name: {src_ws['name']!r}")

    if target_workspace_exists(dst, target_slug):
        raise SystemExit(
            f"error: target workspace '{target_slug}' already exists; aborting."
        )

    print(f"=> Creating target workspace '{target_slug}' ...")
    create_target_workspace(dst, src_ws, target_slug)

    print("=> Listing source pipelines ...")
    src_pipelines = fetch_source_pipelines(src, source_slug)
    print(f"   found {len(src_pipelines)} pipeline(s)")

    created_summary: list[tuple[str, list[str]]] = []
    skipped: list[str] = []
    warnings: list[str] = []

    for pipeline in src_pipelines:
        code = pipeline["code"]
        existing = target_pipeline_get(dst, target_slug, code)
        if existing is not None:
            msg = f"pipeline '{code}' already exists on target — skipping"
            print(f"   - {msg}")
            skipped.append(code)
            continue

        if pipeline.get("type") == "notebook":
            warnings.append(
                f"pipeline '{code}' is a notebook pipeline; its source file "
                f"at notebookPath='{pipeline.get('notebookPath')}' must be "
                "copied into the local workspace files for it to run."
            )

        print(f"   - migrating pipeline '{code}' ({pipeline['name']!r})")
        versions = fetch_pipeline_versions(src, pipeline["id"])
        if not versions:
            warnings.append(
                f"pipeline '{code}' has no versions on source; nothing uploaded."
            )
            continue

        uploaded_versions: list[dict[str, Any]] = []
        scheduled_version_id: str | None = None
        scheduled_src = pipeline.get("scheduledPipelineVersion") or {}
        scheduled_src_number = scheduled_src.get("versionNumber")

        for v in versions:
            up = upload_pipeline_version(
                dst, target_slug, code, v, pipeline
            )
            uploaded_versions.append(up)
            print(
                f"       uploaded version v{v['versionNumber']} "
                f"-> {up['versionName']}"
            )
            if (
                scheduled_src_number is not None
                and up.get("versionNumber") == scheduled_src_number
            ):
                scheduled_version_id = up["id"]

        target_pipeline = target_pipeline_get(dst, target_slug, code)
        if target_pipeline is None:
            raise GraphQLError(
                f"could not find pipeline '{code}' on target after upload"
            )
        update_pipeline_after_upload(
            dst, target_pipeline["id"], pipeline, scheduled_version_id
        )

        created_summary.append(
            (code, [v["versionName"] for v in uploaded_versions])
        )

    # ----------- summary -----------
    print("\n=== Migration summary ===")
    print(f"Workspace: {src_ws['name']!r} -> slug '{target_slug}'")
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
    print("Note: connections were not migrated; recreate them locally if "
          "any pipeline depends on connection-typed parameters.")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Migrate a workspace from a remote OpenHEXA server "
        "to the local Docker setup.",
    )
    parser.add_argument(
        "--token", required=True,
        help="WorkspaceMembership access token from the source server "
             "(same token used by the OpenHEXA CLI).",
    )
    parser.add_argument(
        "--slug", required=True,
        help="Slug of the source workspace on the remote server.",
    )
    parser.add_argument(
        "--target-slug",
        help="Slug to use locally (defaults to the source slug).",
    )
    parser.add_argument(
        "--source-url", default=DEFAULT_SOURCE_URL,
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
        src = build_source_client(args.source_url, args.token)
        dst = build_target_client(target_url, superuser, password)
        migrate(src, dst, args.slug, target_slug)
    except GraphQLError as exc:
        sys.stderr.write(f"\nerror: {exc}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
