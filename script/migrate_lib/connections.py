"""Connection migration: copy every workspace connection to the target.

Secret field values come through the source API only because we authenticate
as a Django superuser: the ``value`` resolver redacts secret fields unless the
caller has ``workspaces.update_connection``, which a superuser short-circuits
to True. If a secret still comes back empty, we create the connection anyway
and warn — the user must set that secret manually on the target.

Connection slugs are preserved: unlike createWorkspace / createPipeline (which
re-derive the slug/code server-side), createConnection honors a caller-supplied
slug and only suffixes it on collision. The target workspace is fresh, so the
source slug carries over intact, keeping pipeline parameters that reference a
connection by slug valid.
"""

import sys
from dataclasses import dataclass, field
from typing import Any

from openhexa.graphql.graphql_client.client import Client
from openhexa.graphql.graphql_client.input_types import (
    ConnectionFieldInput,
    ConnectionType,
    CreateConnectionInput,
)

from .transport import GraphQLError, gql


# `workspace.connections` is a (non-paginated) field on Workspace returning the
# full list; the SDK's workspace() doesn't pull fields, so we query it raw.
LIST_CONNECTIONS_QUERY = """
query ListConnections($slug: String!) {
    workspace(slug: $slug) {
        connections {
            id name slug description type
            fields { code value secret }
        }
    }
}
"""


@dataclass
class ConnectionsResult:
    """What migrate_all() did, for the orchestrator to print."""

    created: list[tuple[str, int]] = field(default_factory=list)
    """(slug, field_count) for each connection created on target."""

    skipped: list[str] = field(default_factory=list)
    """Slugs that already existed on target."""

    failed: list[str] = field(default_factory=list)
    """Slugs whose creation failed; user must handle manually."""

    warnings: list[str] = field(default_factory=list)
    """Human-readable warnings (e.g. secret fields created with no value)."""


def _list_connections(client: Client, slug: str) -> list[dict[str, Any]] | None:
    """Return the workspace's connections, or None if the workspace is absent."""
    data = gql(client, LIST_CONNECTIONS_QUERY, {"slug": slug}, "ListConnections")
    ws = data["workspace"]
    if ws is None:
        return None
    return list(ws["connections"])


def _build_fields(
    conn: dict[str, Any], result: ConnectionsResult
) -> list[ConnectionFieldInput]:
    """Map source fields to ConnectionFieldInput, warning on empty secrets."""
    fields_in: list[ConnectionFieldInput] = []
    for f in conn.get("fields") or []:
        value = f.get("value")
        if f.get("secret") and not value:
            result.warnings.append(
                f"connection '{conn['slug']}' field '{f['code']}' is a secret "
                "with no readable value on source — created empty; set it "
                "manually on the target."
            )
        fields_in.append(
            ConnectionFieldInput(
                code=f["code"], secret=bool(f.get("secret")), value=value
            )
        )
    return fields_in


def migrate_all(
    source: Client,
    target: Client,
    source_slug: str,
    target_slug: str,
) -> ConnectionsResult:
    """Copy every connection from `source_slug` into `target_slug`."""
    result = ConnectionsResult()

    print("=> Listing source connections ...")
    conns = _list_connections(source, source_slug)
    if conns is None:
        raise GraphQLError(
            f"source workspace '{source_slug}' not found while listing connections"
        )
    print(f"   found {len(conns)} connection(s)")

    existing = {c["slug"] for c in (_list_connections(target, target_slug) or [])}

    for conn in conns:
        slug = conn["slug"]
        if slug in existing:
            print(f"   - connection '{slug}' already exists on target — skipping")
            result.skipped.append(slug)
            continue
        try:
            print(f"   - migrating connection '{slug}' ...")
            fields_in = _build_fields(conn, result)
            res = target.create_connection(
                input=CreateConnectionInput(
                    workspace_slug=target_slug,
                    name=conn["name"],
                    slug=slug,
                    type=ConnectionType(conn["type"]),
                    description=conn.get("description") or "",
                    fields=fields_in,
                )
            )
            if not res.success or res.connection is None:
                raise GraphQLError(
                    f"createConnection failed for '{slug}': "
                    + ",".join(e.value for e in (res.errors or []))
                )
            result.created.append((slug, len(fields_in)))
        except GraphQLError as exc:
            # Collect and continue (like files.py) so one bad connection
            # doesn't abort the rest of the migration.
            print(f"\tFAILED to migrate connection '{slug}': {exc}", file=sys.stderr)
            result.failed.append(slug)

    return result
