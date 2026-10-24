# Volunteer activities

This feature schedules volunteer/staff work. Public attendee events belong to
[Schedule](../schedule/README.md).

## Drafts and publication

The editor loads `get_activities_for_edit` into an `EditDataBundle`. Local edits
are periodically autosaved with `save_activity_history` and history type
`AUTOSAVE`; that snapshot does not change the live activity graph. An empty
activity list is not autosaved by the current adapter.

When Client Sync v1 is selected, Publish calls
`publish_activities_client_sync_v1` through `SupabaseActivityCommands`. One
receipted command writes the publication history and live graph atomically,
checks `expectedVersion`, and returns the aggregate version and history ID.
The editor updates its baseline from that response. A conflict must be resolved
against the newer publication; an autosave is not evidence of a live publish.

The retained legacy adapter calls `save_activity_history` with `PUBLISH`, then
`update_activities` in a second request. Those calls describe only that adapter,
not the atomic v1 publication contract. Do not copy the two-request sequence
into a new client.

## Source entrypoints

- `db_activities.dart`: loading, autosave and capability-selected publication
- `activity_commands.dart`: typed v1 publish transport and response application
- `activities_content.dart`: editor state, restore/merge UI and publish actions

SQL owns version checks and live persistence. UI/history drafts do not become
public activity data until publication succeeds.
