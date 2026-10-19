# Retired external HTTP importer

`setup_external_source` and `sync_source_via_http` are retained service-role-only
stubs. Both raise `unbounded_http_import_retired`; they cannot start a source or
schedule imports. The old SQL HTTP transport buffered unbounded remote bodies.
Do not restore its former cron setup as an installation or debugging step.

`stop_external_source_sync` remains available for explicit cleanup, and
`get_sync_occasions` exposes the filtered public occasion catalog. Their presence
does not mean the importer is active. A replacement importer needs a reviewed
bounded transport and complete-snapshot/deletion semantics.

This feature is separate from the current
[Client Sync v1 protocol](../../../docs/runbooks/client-sync-v1.md).
