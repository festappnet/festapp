# Activities Component (Volunteer Management)

The editor schedules volunteer tasks. Initial load uses
`get_activity_editor_session_v1`, one snapshot containing master lists, the live
aggregate version, latest publish parent and the signed-in actor's draft.

- `save_activity_draft_client_sync_v1` saves history only. An empty draft is valid.
- `publish_activities_client_sync_v1` checks the captured live version and parent,
  then atomically replaces the graph, stores publish history, clears the matching
  actor draft, advances versions and completes the existing mutation receipt.
- `discard_activity_draft_client_sync_v1` checks the captured draft ID. A newer
  draft cannot be deleted by an older dialog.

`ActivityCommands` owns typed write transport regardless of read-sync capability.
Ambiguous retries retain the command identity and immutable request; changed
content starts a new intent. Publish drains autosave and freezes editor input.
Undo/redo keep current concurrency tokens. History restore and explicit conflict
continuation fetch a new session as separate user intents. Delayed responses
cannot reconcile after disposal, actor change or a later editor generation.

New history carries `schemaVersion: 1` and `timeBasis: UTC`. Legacy unmarked wall
times are interpreted in the occasion timezone by the same graph normalizer;
stored old history is never rewritten. Assignment UUID ownership is checked
again in the upsert to protect concurrent writes from different occasions.

`canonical_activity_graph.sql`, `canonical_activity_history.sql` and
`canonical_activity_lifecycle.sql` are the domain owners. Released
`update_activities(bigint,jsonb)`, `save_activity_history` and
`delete_autosave_history` remain named G3 compatibility boundaries. Their
presence does not permit mixed-client production writes. Read overload
`update_activities(bigint)` is retained separately. Local contracted tests and
prepared SQL are not evidence of production ACL closure. See the canonical
mutation plan and runbook for pending G2-G4.
