"""Workspace file transfer (low-level utility used by other resource modules)."""

import httpx
from openhexa.graphql.graphql_client.client import Client

from .transport import GraphQLError, _dbg, gql


PREPARE_DOWNLOAD_MUTATION = """
mutation PrepareDownload($input: PrepareObjectDownloadInput!) {
    prepareObjectDownload(input: $input) {
        success errors downloadUrl
    }
}
"""

PREPARE_UPLOAD_MUTATION = """
mutation PrepareUpload($input: PrepareObjectUploadInput!) {
    prepareObjectUpload(input: $input) {
        success errors uploadUrl headers
    }
}
"""


def download(source: Client, ws_slug: str, file_path: str) -> bytes:
    """Download a file from the source workspace via a presigned URL."""
    data = gql(
        source,
        PREPARE_DOWNLOAD_MUTATION,
        {
            "input": {
                "workspaceSlug": ws_slug,
                "objectKey": file_path,
                "forceAttachment": False,
            }
        },
        "PrepareDownload",
    )
    result = data["prepareObjectDownload"]
    if not result["success"] or not result.get("downloadUrl"):
        raise GraphQLError(
            f"prepareObjectDownload failed for '{file_path}': "
            + ",".join(result.get("errors") or [])
        )
    url = result["downloadUrl"]
    _dbg(f"download {file_path} <- {url}")
    with httpx.Client(timeout=300) as c:
        resp = c.get(url)
    if not resp.is_success:
        raise GraphQLError(
            f"download of '{file_path}' returned HTTP {resp.status_code}: "
            f"{resp.text[:500]}"
        )
    return resp.content


def upload(
    target: Client,
    ws_slug: str,
    file_path: str,
    content: bytes,
    content_type: str = "application/octet-stream",
) -> None:
    """Upload bytes to the target workspace at the given object key."""
    data = gql(
        target,
        PREPARE_UPLOAD_MUTATION,
        {
            "input": {
                "workspaceSlug": ws_slug,
                "objectKey": file_path,
                "contentType": content_type,
            }
        },
        "PrepareUpload",
    )
    result = data["prepareObjectUpload"]
    if not result["success"] or not result.get("uploadUrl"):
        raise GraphQLError(
            f"prepareObjectUpload failed for '{file_path}': "
            + ",".join(result.get("errors") or [])
        )
    url = result["uploadUrl"]
    headers = dict(result.get("headers") or {})
    headers.setdefault("Content-Type", content_type)
    _dbg(f"upload {file_path} ({len(content)} bytes) -> {url}")
    with httpx.Client(timeout=300) as c:
        resp = c.put(url, content=content, headers=headers)
    if not resp.is_success:
        raise GraphQLError(
            f"upload of '{file_path}' returned HTTP {resp.status_code}: "
            f"{resp.text[:500]}"
        )
