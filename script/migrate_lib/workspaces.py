"""Workspace-level migration (workspace metadata; later: members, settings)."""

import sys
from typing import Any

from openhexa.graphql.graphql_client.client import Client
from openhexa.graphql.graphql_client.input_types import (
    CountryInput,
    CreateWorkspaceInput,
    UpdateWorkspaceInput,
)

from .transport import GraphQLError


def create(target: Client, src_ws: Any) -> str:
    """Create the workspace on target, returning the slug the server picked.

    Note: the server (see resolve_create_workspace + create_workspace_slug
    in openhexa-app) ignores any `slug` passed in the input — it derives
    the slug from the name with a random suffix. So we never pass a slug
    and always read the actual slug back from the response.
    """
    countries = [
        CountryInput(code=c.code, alpha3=c.alpha_3, name=c.name, flag=c.flag)
        for c in (src_ws.countries or [])
    ]
    result = target.create_workspace(
        input=CreateWorkspaceInput(
            name=src_ws.name,
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
