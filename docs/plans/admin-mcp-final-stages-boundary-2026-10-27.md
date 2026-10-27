# Remaining admin/MCP stages - execution boundary

Status 2026-10-27: all stages 0-10 are completed and deployed to
`prod/festapptickets` / vstupenky.online **0.20.432+936**. PR #641 and #642
are merged. The user separately authorized this final rollout and cleanup.
[Production receipt](../operations/releases/festapptickets-mcp-final-2026-10-27.json).
The execution boundary below records the completed implementation contract.
Existing owners, current UI semantics and explicit operation scopes remain
authoritative; historical no-deployment instructions describe the earlier phase.

## Stage 7 - exact blueprint drafts and ticket appearance

- `can_read_blueprints` / `can_write_blueprints` -> existing blueprint aggregate
  owner `update_blueprint_client_sync_v1` -> `SupabaseFormCommands.saveBlueprint`
  -> bounded blueprint list/inspect/save and advisory validate tools.
- Geometry, names, selection units, group products and standing-area bindings
  remain one immutable document + binding-change command. SQL owns validation,
  reservation locks, revisions and rollback. Draft/Cancel is local and issues no
  command. No new geometry, inventory allocator or PDF renderer.
- Named text preparation uses the existing whole-text renderer and its immutable
  resource protocol. Scoped registration must bind stored scope and live actor
  inside SQL; the service role owns font registration, never substitutes for the
  caller's ordinary blueprint predicate.
- Existing ticket artwork inspect/preview/save/pending/resume implementation is
  retained. Add explicit hosted scopes and atomic scope binding at save/replay;
  keep the existing scoped runtime readiness gate, canonical synthetic renderer
  and durable pending identity. The renderer gate must not gate geometry writes.
- Existing order updates already change issued-ticket products through their
  canonical owner. Check-in must reuse scanner eligibility/admission/operation
  receipts and never expose session tokens, QR payloads or a second scan engine.

Minimum meaningful batch: disposable ordinary-user PostgreSQL blueprint save,
conflict, exact replay, protected seat rejection and concurrent hold/save;
canonical renderer/Edge tests; actual SDK executor; existing blueprint draft,
form-command and ticket-layout tests. Browser only if the actual editor flow
changes. Record the next stages' precise owners before implementing them.

## Completion ledger

- [x] 7 - blueprint drafts, bindings, text resources, appearance and admission
- [x] 8 - schedule, attendance, exclusive groups, activities, map, speakers,
  services and game, each with current typed predicates and canonical commands
- [x] 9 - confirmed reports, history and exports, bounded SQL projections and
  exact ordinary permissions; do not promise unaudited bulk send/export features
- [x] 10 - bank/provider boundaries, occasion lifecycle and remaining unit tabs;
  one existing recovery owner for distributed asset/provider effects

Only mark a stage complete after its supported current UI operations, MCP scopes,
actual SQL/executor verification and removal ledger are all accounted for.

## Stage 8 - owner ledger before implementation

| Slice | Live predicate | Existing SQL owner / current UI producer |
| --- | --- | --- |
| Schedule event | `can_read_schedule_editor` / `can_write_schedule` | `get_event_editor_v1`, `save_event_client_sync_v1`, `delete_event_client_sync_v1` / `SupabaseEventCommands` |
| Attendance | Schedule editor reader plus existing attendance self/editor checks | `set_event_attendance_client_sync_v1` / `SupabaseAttendanceCommands` |
| Exclusive events | Schedule editor predicates | Existing exclusive-group save/delete / `SupabaseExclusiveGroupCommands` |
| Activities and assignments | `can_read_activity_editor` / `can_write_activity_plan` | Existing canonical graph/history, draft/discard/publish commands / `SupabaseActivityCommands` |
| Places/types/paths | `can_read_map_editor_bundle` / `can_write_places` | Existing map aggregate save/delete/move / `SupabaseMapCommands` |
| Speakers/topics/event links/counseling slots | `can_read_speakers_editor` / `can_write_speakers` | Existing speaker/topic/event-link/counseling commands / `SupabaseSpeakerCommands` |
| Food/accommodation services | `can_write_service_items` | Existing service item create/update/delete / `SupabaseOccasionCommands` |
| Game | Existing stage-5 game editor boundary | Existing game inspect/save, no second tool or game writer |

Admin schedule/map/speaker tabs require the app-supported variant. Activities
also require the volunteer feature; services require their feature, including in
otherwise ticketing-only reservations. These are variant/feature preconditions,
not a replacement ACL. Reads page by stored ID before projection; aggregate
inspection returns one original entity/version or one bounded complete activity
graph, never the complete editor bundle with unrelated people/contacts. Activity
history conversion uses the existing canonical graph helper, not a Node copy.
Every mutation delegates to the existing receipted command. Existing UI producers
already use those owners; no replacement client-side multi-call save is needed.

## Stage 9 - confirmed reports/history/export ledger

- Sales report: existing `get_operator_order_report_v1` / `orders.report` remains
  the sole accounting/count authority. Export its canonical JSON, not recalculated
  totals or a second text-report engine.
- Client audit: existing commit page/detail owners and typed audit predicates.
  Preserve the UI's public readers; add a private scope-qualified variant of the
  same page query so occasion consent cannot inherit unit/organization visibility
  merely from the human's broader roles. Compound time/UUID cursors retain ties.
- Client activity: existing `get_client_activity_v1`, its local-day semantics and
  31-day bound. No Node time bucket or accounting math.
- Order history: bounded projection of the existing `eshop.orders_history` source,
  with order/occasion binding and live order-read predicate. Do not export raw
  historical order snapshots containing QR/hold/auth data.
- Delivery history: existing `get_email_delivery_page` / `email_report_allowed`,
  sanitized metadata only, never message bodies, links, provider secrets or keys.
- Feedback: same feedback export projection and predicate as the editor, with a
  bounded ID page added before aggregation. Preserve the existing public export.
- CSV pages: participant identities/selected contacts, order summaries and program
  identities use their existing scoped readers/typed predicates. CSV is transport
  formatting, not an independent entity/accounting projection. Closed datasets and
  columns, explicit export scopes, cursor + at most 100 rows per artifact.
- Artifacts: reuse one bounded expiring in-memory store for PDF/CSV/JSON, shared
  across hosted MCP requests. Bind every artifact to its actor, connection and
  resource scope and reauthorize before every read. No durable data export ledger.

The former catalogue audit row did not establish a generic bulk-send feature.
Ticket delivery and waitlist sending already have explicit commands. Any further
bulk send must be traced to a real UI owner before it can count as supported.

## Stage 10 - owner ledger before implementation

- Bank account details, bank-user roles and organizer links remain owned by
  `update_bank_account`, `update_bank_account_user` and
  `link_bank_account_to_unit`. Their existing live bank predicates are mandatory
  before every command and receipt replay. A shared receipted transport wraps
  these owners for the current Flutter producer and MCP; no second bank writer.
- BankSync uses `bank-sync-manage`, `begin_bank_sync_operation` and its existing
  staged request/lease/recovery ledger. Credentials and receiving/pairing secrets
  are configured in the ordinary UI, never exported through MCP. Details updates
  already queue a durable provider intent in the same SQL transaction.
- Card provider uses `stripe-connect` and its existing connection/disconnect
  intent owners. OAuth remains an ordinary human onboarding flow. The current
  refund UI is a local admission decision AFTER a provider-observed refund:
  `get_stripe_order_admin_detail` and
  `decide_stripe_partial_refund_client_sync_v1`. It does not issue a refund.
- Organizer quotes use the existing versioned unit information commands.
  Legal identity uses `get_unit_legal_profile`, `save_unit_legal_profile` and
  `submit_unit_verification`; tenant-wide reviewer queue/review is outside an
  organizer consent. Current unit settings/members were completed in stages5/6.
- Occasion copying uses `duplicate_occasion_client_sync_v1` and
  `OccasionDuplicator`/`copyOccasionMedia`, then the canonical image Worker
  upload. Current deletion uses `delete_occasion_client_sync_v1`; SQL detaches
  image records. Distributed asset completion requires a durable resumable
  intent shared with the current UI, not a second MCP-only copier.

Additional confirmed controls discovered during stage10: physical order deletion
is `OrderCommands.delete` / `delete_order_client_sync_v1`; optional Fakturoid
invoice deletion is `delete-order` / `deleteOrderWithInvoice` and its existing
lookup-before-delete gateway. Preserve that owner, scope/revision gates and
same-command recovery. Persisted order-history deletion is actually offered by
`OrdersHistoryContent` to organizer managers; `delete_order_history` owns it.
Add a separate destructive consent and a shared UI/MCP receipt wrapper; never
confuse the synthetic current-state row with a persisted history entry.

The proposed generic bulk-send row has no current producer in
`AdministrationTabs`. Current `send-email` accepts only four exact order
notification codes; ticket and waitlist sends already use their canonical
owners. No arbitrary mass-mail tool is inferred. Provider refund issuance has
no current admin command; only observed-refund admission decisions are exposed.
Deletion explicitly retains detached image blobs (`delete_occasion.sql` lines165+),
so a destructive R2 purge would be a new effect, not parity with the current UI.


## Closure

Stages 7-10 are locally complete. 109 catalogue rows represent 193 remote tools.
See the final checkpoint and `docs/reports/admin-authoring-final-evidence-2026-10-27.json`.
Current producers, frozen migrations, actual SDK/HTTP routes and recovery fixtures
are covered. Original role facts and the bank exception remain authoritative;
new grants never expand old OAuth tokens. No live provider calls or deployment.
