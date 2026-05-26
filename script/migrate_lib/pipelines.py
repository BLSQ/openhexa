"""Pipeline migration: list source pipelines, copy each (with versions) to target."""

import base64
from dataclasses import dataclass, field
from typing import Any

from openhexa.graphql.graphql_client.client import Client
from openhexa.graphql.graphql_client.input_types import CreatePipelineInput

from . import files
from .transport import GraphQLError, gql


PIPELINES_PAGE_SIZE = 50
VERSIONS_PAGE_SIZE = 50


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
                }
            }
        }
    }
}
"""

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


@dataclass
class PipelinesResult:
    """What migrate_all() did, for the orchestrator to print."""

    created: list[tuple[str, list[str]]] = field(default_factory=list)
    """(pipeline_code, [version_name, ...]) for each pipeline created on target."""

    skipped: list[str] = field(default_factory=list)
    """Pipeline codes that already existed on target or could not be migrated."""

    warnings: list[str] = field(default_factory=list)
    """Human-readable warnings to print in the summary."""


# ---------------------------------------------------------------------------
# Source fetch
# ---------------------------------------------------------------------------


def _list_source_ids(source: Client, slug: str) -> list[tuple[str, str]]:
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


def _fetch_source_detail(source: Client, pipeline_id: str) -> dict[str, Any]:
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
# Target writes
# ---------------------------------------------------------------------------


def _create_on_target(
    target: Client, target_slug: str, src_pipeline: dict[str, Any]
) -> tuple[str, str]:
    """Create an empty pipeline on the target and return (id, code).

    The server (see ``Pipeline.objects.create_if_has_perm`` in
    openhexa-app/.../pipelines/models.py) auto-generates the pipeline
    code from ``slugify(name)`` with a collision suffix and rejects any
    code the caller tries to pass. So we never pass a code; we always
    read the actual one back from the response.
    """
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
    created_code = result.pipeline.code

    # createPipeline returns only the code; fetch by code to get the id
    # needed for subsequent updatePipeline.
    created = target.pipeline(workspace_slug=target_slug, pipeline_code=created_code)
    if created is None:
        raise GraphQLError(f"could not look up created pipeline '{created_code}'")
    return str(created.id), created_code


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


def _upload_version(
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


def _update_settings(
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
# Orchestration (one resource)
# ---------------------------------------------------------------------------


def migrate_all(
    source: Client,
    target: Client,
    source_slug: str,
    target_slug: str,
) -> PipelinesResult:
    """Migrate every pipeline from `source_slug` into `target_slug`."""
    result = PipelinesResult()

    print("=> Listing source pipelines ...")
    pairs = _list_source_ids(source, source_slug)
    print(f"   found {len(pairs)} pipeline(s)")

    for pipeline_id, src_code in pairs:
        existing = target.pipeline(workspace_slug=target_slug, pipeline_code=src_code)
        if existing is not None:
            print(f"   - pipeline '{src_code}' already exists on target — skipping")
            result.skipped.append(src_code)
            continue

        print(f"   - migrating pipeline '{src_code}' ...")
        detail = _fetch_source_detail(source, pipeline_id)
        is_notebook = detail.get("type") == "notebook"

        if is_notebook and not _copy_notebook_file(
            source, target, source_slug, target_slug, src_code, detail, result
        ):
            continue

        target_pid, target_code = _create_on_target(target, target_slug, detail)
        if target_code != src_code:
            print(
                f"       created pipeline as '{target_code}' (source was "
                f"'{src_code}'; server re-derives code from name) — id={target_pid}"
            )
        else:
            print(f"       created pipeline '{target_code}' (id={target_pid})")

        uploaded_names, scheduled_version_id = _upload_versions(
            target, target_slug, target_code, detail, is_notebook, result
        )

        _update_settings(target, target_pid, detail, scheduled_version_id)
        result.created.append((target_code, uploaded_names))

    return result


def _copy_notebook_file(
    source: Client,
    target: Client,
    source_slug: str,
    target_slug: str,
    src_code: str,
    detail: dict[str, Any],
    result: PipelinesResult,
) -> bool:
    """Copy a notebook pipeline's .ipynb from source to target bucket.

    Returns True on success (caller proceeds to create the pipeline), False
    if the notebook is missing or transfer failed (caller skips the pipeline).

    createPipeline for notebook pipelines requires the notebook file to
    already exist in the workspace bucket (openhexa-app
    pipelines/schema/mutations.py:82) — hence this happens before the
    createPipeline call.
    """
    nbpath = detail.get("notebookPath")
    if not nbpath:
        result.warnings.append(
            f"notebook pipeline '{src_code}' has no notebookPath; skipped."
        )
        result.skipped.append(src_code)
        return False
    try:
        print(f"       fetching notebook '{nbpath}' from source ...")
        nb_bytes = files.download(source, source_slug, nbpath)
        print(f"       uploading notebook to target ({len(nb_bytes)} bytes) ...")
        files.upload(
            target,
            target_slug,
            nbpath,
            nb_bytes,
            content_type="application/x-ipynb+json",
        )
    except GraphQLError as exc:
        result.warnings.append(
            f"notebook pipeline '{src_code}': could not migrate notebook file "
            f"'{nbpath}' ({exc}); pipeline skipped."
        )
        result.skipped.append(src_code)
        return False
    return True


def _upload_versions(
    target: Client,
    target_slug: str,
    target_code: str,
    detail: dict[str, Any],
    is_notebook: bool,
    result: PipelinesResult,
) -> tuple[list[str], str | None]:
    """Upload all zipfile versions; return (uploaded_version_names, scheduled_version_id)."""
    uploaded_names: list[str] = []
    scheduled_version_id: str | None = None
    scheduled_src = detail.get("scheduledPipelineVersion") or {}
    scheduled_src_number = scheduled_src.get("versionNumber")

    if is_notebook:
        if detail.get("versions"):
            result.warnings.append(
                f"pipeline '{target_code}' has {len(detail['versions'])} version(s) "
                "on the source, but uploadPipeline is not supported for "
                "notebook pipelines — versions were not migrated."
            )
        return uploaded_names, scheduled_version_id

    versions = detail.get("versions") or []
    if not versions:
        result.warnings.append(
            f"pipeline '{target_code}' has no versions on source; created with no version."
        )
    for v in versions:
        up = _upload_version(target, target_slug, target_code, v)
        uploaded_names.append(up["versionName"])
        print(f"       uploaded version v{v['versionNumber']} -> {up['versionName']}")
        if (
            scheduled_src_number is not None
            and up.get("versionNumber") == scheduled_src_number
        ):
            scheduled_version_id = up["id"]
    return uploaded_names, scheduled_version_id
