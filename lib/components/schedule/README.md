# Schedule (Public Program)

Attendee-facing festival program. NOT volunteer tasks (that's `lib/components/activities/`).

- **Activities** writes to `activities` table (admin editor)
- **Schedule** reads from `events` table (populated/synced from activities)

## Sign In/Out Error Codes (CRITICAL)

`sign_user_to_event` RPC enforces all business rules server-side. Error codes:
- `100` = event over
- `101` = full
- `102` = exclusive event already taken
- `103` = already signed in
- `104` = too early
- `105`/`106` = gender limits reached (male/female)
- `107` = conflicting event schedule
- `108` = workshop registration not enabled

These map to localized messages in Dart.

## My Schedule & Offline Sync

Dual storage: remote `event_users_saved` table + local `OfflineDataService`.
Writes go through the occasion-scoped `set_saved_program` / Client Sync command
and the process-wide mutation coordinator; read refreshes never replace remote
state from a client snapshot.

Transition clients retain one narrow RPC boundary for cloud tenants that have
not selected Client Sync v1. All supported sources expose the atomic
`set_saved_program` RPC; a missing function is a visible deployment/parity
failure and never falls back to direct table DML. Remove the adapter after every
tenant has activated the canonical `set_saved_program_client_sync_v1` path.

Detail-page toggles use a latest-intent queue: the UI changes optimistically,
backend writes stay serialized, rapid opposite clicks converge to the newest
choice, and failed writes roll back to the last confirmed state.
While a write is in flight, its latest intent is projected over the shared
saved-program cache so opening My Program reflects the click immediately. The
overlay is owner-guarded against stale completions and cleared with user data.

## Exclusive Groups

`exclusive_groups` and `exclusive_events` tables enforce mutual exclusivity (e.g., parallel workshops -- can only attend one).

## SQL RPCs

- `get_events` -- all events with places, groups, roles, counts in one payload
- `get_event_participants_for_edit` -- participant names for editor-view,
  editor, or organization admin
- `sign_user_to_event` -- sign-in with full validation (capacity, timing, exclusivity, gender)
- `sign_user_out_of_event` -- sign-out with validation
- `set_saved_program` -- atomically joins/removes saved event IDs within one occasion
- `get_my_events_and_activities` -- user's events + volunteer activities
