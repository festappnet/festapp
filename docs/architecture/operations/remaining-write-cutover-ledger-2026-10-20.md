# Remaining write paths: canonical owner and removal ledger

Date: 2026-10-20. The table below preserves the pre-refactor evidence.
Current local changes and every remaining CW gate are recorded in the
[execution closure matrix](backend-refactor-execution-2026-10-20.md#cw01-cw24-closure-matrix).
The full refactor and production activation remain unfinished.

This makes phase 1F of the
[parent plan](../../plans/festapp-canonical-operations-plan-2026-10-20.md)
executable. The [sequence review](sequence-review-2026-10-20.md) describes the
multi-call intentions; this ledger distinguishes actual duplicate domain logic
from alternate public entrypoints, missing command effects and scope differences.

## Important correction to a naive cutover

Several old endpoints already delegate to a canonical command. Others are
the shared implementation called by that command. Neither situation is solved
by blindly replacing every old function body with a call to the new command.

Confirmed examples from current source/migration evidence:

- `save_inventory_pool_client_sync_v1` calls `update_inventory_pool_bundle`.
  Redirecting the latter to the command would create recursion.
- `report_cleaning_issue_client_sync_v1` calls `report_cleaning_issue`.
  The same recursion hazard applies.
- `save_unit_client_sync_v1` and `update_unit` call
  `update_unit_internal_v1`; business logic is already shared, but the old
  route omits the command receipt/version/publication work.
- `create_form_ws` and `delete_form_ws` already call their corresponding
  receipt-bearing commands and translate result shape. They are adapters,
  not another form business engine.

For shared-helper cases, first extract/revoke a definition-only internal helper
with the existing permission/locking logic. Point the canonical command at that
helper. Only then route a required legacy facade through the command. Test that
the call graph has no cycle and each request records effects once. Current
clients call the typed command adapter directly, without choosing by read-sync
mode. Revoke authenticated/anonymous direct access to internal helpers, while
preserving any separately justified machine caller.

Migration references below identify textual source evidence, not the deployed
winner. Author future definitions under `database/functions/`; preserve immutable
historic migrations. Existing authored files and later migration overrides must
be compared before extraction, especially `update_inventory_pool_bundle`.

## Concrete cutover slices

Classification: **D** duplicate/split domain writes; **E** shared domain helper
with alternate command effects; **F** facade already delegates; **S** scope or
identity contract needs explicit treatment. All rows require server permission
and applicable role/tenant/version behavior tests before runtime changes.

| Slice | Pre-refactor caller / alternate writer | Canonical operation and owner | Migration and removal |
|---|---|---|---|
| CW01 D | `DbGroups.updateUserGroupInfo`, group delete, private-place helpers and the membership loop | `save_user_group_client_sync_v1`, `delete_user_group_client_sync_v1`; [group commands](../../../lib/components/groups/group_commands.dart). Additive membership is its separate phase-1E command over the same internal membership owner. | Remove direct group/member/place DML and `updateUserGroupParticipants`; move the Users UI caller first. Preserve leader/editor permissions, admin membership, private-place lifetime and version conflicts. |
| CW02 D | `DbEvents.updateExclusiveGroup` / delete: write group, delete links, insert links | `save_exclusive_group_client_sync_v1`, `delete_exclusive_group_client_sync_v1`; [adapter](../../../lib/components/schedule/exclusive_group_commands.dart). | Extract effective definitions under `database/functions/events/` if migration-only. Remove direct `exclusive_groups`/`exclusive_events` writes in `db_events.dart`; test all-or-nothing replacement and affected signup invariants. |
| CW03 D | `DbActivities.saveActivitiesForEdit`: history then assignments in fallback | `publish_activities_client_sync_v1`; [adapter](../../../lib/components/activities/activity_commands.dart). | One authored publish owner under `database/functions/activities/`; remove client legacy publish branch. Integrate chosen-draft semantics from A05 separately from HTML upload and explicit draft deletion. |
| CW04 D | `DbNews.sendMessage`: news insert then enqueue; deletion reconstructs readers | `publish_news_client_sync_v1`, `delete_news_client_sync_v1`, `mark_news_read_client_sync_v1`; ordinary create/edit uses `save_news_client_sync_v1`; [adapter](../../../lib/components/news/news_commands.dart). | Preserve add-to-news/send/test choices and one notification intent. Remove client publication/deletion/read-pointer DML; retain deliberate read acknowledgements via their canonical command. |
| CW05 D/S | `DbUsers.updateOccasionUser`: `update_user`, membership, occasion upsert | `save_profile_client_sync_v1` / `create_occasion_user_client_sync_v1`; [adapter](../../../lib/components/users/profile_commands.dart). | Remove only migrated profile branches and direct occasion-user upsert. Preserve invitations, companion restrictions, allowed fields and returned identity/version. Do not treat partial profile save, membership ensure and account creation as interchangeable. |
| CW06 E | `DbInventoryPools.updateInventoryPoolBundle` -> `update_inventory_pool_bundle`; canonical pool command calls that same public writer | `save_inventory_pool_client_sync_v1` over one internal pool/context reconciliation helper; [adapter](../../../lib/components/inventory/inventory_commands.dart). | Extract current pool/context logic into `update_inventory_pool_bundle_internal_v1` with internal grants. Command calls helper; required old facade calls command. Remove client selector and test no recursive facade/command cycle. Preserve resource-derived spot reconciliation and omitted/empty context semantics. |
| CW07 D | `DbInventoryPools.updateResource` -> old `update_resource`; canonical resource command contains its own DML | `save_resource_client_sync_v1` over one scoped internal resource writer. | Consolidate guard/normalization/capacity/spot adjustment in the internal owner; do not pick older validation because it is shorter. Remove legacy client branch; retain thin legacy result adapter only for a concrete consumer. |
| CW08 S | Pool/resource deletion branches | `delete_inventory_pool_client_sync_v1`, `delete_resource_client_sync_v1`; [caller](../../../lib/components/inventory/db_inventory_pools.dart). | Compare zero-capacity/in-use constraints and old signatures before facade conversion. Remove current routing split and direct helper reachability; test deletion conflicts and publication. |
| CW09 F | Form create/delete alternate entrypoints | `create_form_client_sync_v1`, `delete_form_client_sync_v1`; [existing create facade](../../../database/functions/eshop_forms/create_form_ws.sql), [delete facade](../../../database/functions/eshop_forms/delete_form_ws.sql). | Domain business consolidation is already present in these sources. Remove the current client's read-mode route split; retain old 201/code/message shapes only at justified external adapters. Do not build another create/delete API. |
| CW10 F/E | Form save/duplicate and blueprint update alternatives | `update_form_client_sync_v1`, `duplicate_form_to_occasion_client_sync_v1`, `update_blueprint_client_sync_v1`; [adapter](../../../lib/components/forms/supabase_form_commands.dart). | Inspect effective later definitions and existing internal helpers. Remove only alternate client routing and obsolete implementation copies. Preserve form field/product scope, editor draft patch semantics, capacity and blueprint locks. Parent 1I and the [ticketing-write plan](../../plans/festapp-ticketing-mcp-plan-2026-10-20.md) additionally require rollback on late JSON rejection, blueprint-scoped seat IDs, secret-free errors/reads, original expected versions and a supported legacy-writer fence before MCP writes. |
| CW11 E/F | Product save/delete/context alternatives | `update_product_client_sync_v1`, `delete_product_client_sync_v1`, `update_product_inventory_contexts_client_sync_v1`; [adapter](../../../lib/components/eshop/supabase_eshop_commands.dart). | Product-with-contexts is A02. Extract one shared context writer; remove `_legacyRpc`/`_useClientSync` only after other callers move. Existing delete/context facades that already delegate need no new business engine. |
| CW12 F | Spot assignment and seat swap alternatives | `update_spot_assignments_client_sync_v1`, `swap_spot_tickets_client_sync_v1`; [spot caller](../../../lib/components/inventory/db_spots.dart), [ticket caller](../../../lib/components/eshop/db_tickets.dart). | Route current mutations directly; preserve seat locks/roles and old return shape only at necessary boundaries. Selection/hold, swap and order creation remain distinct operations. |
| CW13 D | Speaker/topic create/save/delete: old SQL has independent record/link DML | `save_speaker_client_sync_v1`, `delete_speaker_client_sync_v1`, `save_speaker_topic_client_sync_v1`, `delete_speaker_topic_client_sync_v1`; [adapter](../../../lib/components/speakers/speaker_commands.dart). | Extract effective canonical bodies into authored speaker files and internal helpers shared by retained old adapters. Remove legacy mutation branches. Preserve omitted/null patch differences, topic association replacement, authorizing occasion and versions. |
| CW14 E/S | Counseling slot creation, delete-empty, delete-one alternatives | Corresponding `*_client_sync_v1` bindings in [speaker commands](../../../lib/components/speakers/speaker_commands.dart). | Compare exact old/canonical helper graph and occupied-slot behavior, then remove current selector routes. Creation batches and deletion of empty slots are different intentions; do not discard booked slots to simplify parity. |
| CW15 E | Cleaning issue report public writer is called inside canonical command | `report_cleaning_issue_client_sync_v1` over one internal reporting helper; [source](../../../database/functions/cleaning/report_cleaning_issue.sql). | First extract the current abuse-admitted reporting body to an internal owner; point command there before adapting the old name. Preserve duplicate-window/blocked-reporter behavior, charge rules and exactly one push intent. |
| CW16 E | Cleaning resolve/mute/block public wrappers call internal helpers outside full command effects | `resolve_cleaning_place_client_sync_v1`, `set_cleaning_notifications_muted_client_sync_v1`, `set_cleaning_reporter_blocked_client_sync_v1`; [adapter](../../../lib/components/cleaning/cleaning_commands.dart). | Move clients; retained facade translates canonical response. Keep crew-versus-editor block/unblock asymmetry, self-only mute and unchanged outcomes. Remove raw internal access and duplicate effects, not the shared helper. |
| CW17 E | `DbUnits.updateUnit` -> `update_unit`; shared internal save without full command semantics | `save_unit_client_sync_v1` -> `update_unit_internal_v1`; [adapter](../../../lib/components/unit/unit_commands.dart). | Keep manager/unit scope and expected version; old wrapper obtains any compatibility version inside the same locked request, never a client read-then-write. Remove current save selector. Unit creation+manager and deletion stay separate commands. |
| CW18 F/E | Occasion create/save/delete and service/game settings alternatives | Bindings in [occasion commands](../../../lib/components/occasion/occasion_commands.dart); existing `update_occasion` already delegates create/save in later migration evidence. | Preserve occasion scope, feature defaults, version conflicts and partial settings semantics. Remove current alternate writers once covered. Keep service force-confirmation behavior and media duplication outside this SQL slice. |
| CW19 S | Occasion information mutation versus unit information direct DML | Occasion `save_information_client_sync_v1` / delete; unit-scoped typed operation if supported, sharing one validated internal field writer; [caller](../../../lib/components/information/db_information.dart). | A06 decides valid unit/type combinations. Never synthesize an occasion or grant hidden-answer access to route a unit writer through an occasion command. Remove occurrence-specific fallback after parity; keep distinct scope contracts explicit. |
| CW20 E/S | Map path and place-type save/delete plus move alternatives | `save_path_client_sync_v1`, `delete_path_client_sync_v1`, `save_place_type_client_sync_v1`, `delete_place_type_client_sync_v1`, `move_place_client_sync_v1`; [map commands](../../../lib/components/map/map_commands.dart). | Remove alternate client table writes/legacy location route after owner/grant parity. Preserve protected group places and versions. Ordinary place save/delete are already canonical; do not reintroduce direct DML for non-sync contexts. |
| CW21 S | SVG icon insert/delete supports unit ownership and legacy organization-wide reads, while modern command needs an occasion | `icons.manage` with explicit unit/organization ownership and optional authorized publication context; [caller](../../../lib/components/icons/db_icons.dart). | Establish a canonical unit-capable command/internal owner before removing the unit-only writer. Do not require an arbitrary current occasion or broaden org visibility. Preserve size/reference checks; resolve unlocated `delete_icon` definition before dropping it. |
| CW22 E/S | Companion self-create old route; modern self-create/owned-delete/admin assignment routes | `create_companion_client_sync_v1`, `delete_owned_companion_client_sync_v1`, assign/unassign commands; [caller](../../../lib/components/users/companion/db_companions.dart). | Remove self-create selector only after proving owner/occasion relationship and outcome parity. Never substitute account deletion for unassignment or remove the explicit admin-assigned restriction. Reads may keep projection alternatives. |
| CW23 S | Event feedback anonymous-client versus signed-user paths | Typed feedback commands for supported actor kinds; [caller](../../../lib/components/event_feedback/db_event_feedback.dart). | Preserve anonymous identity/proof and editor moderation scope. A browser client ID is not a user principal. Remove old mutation path only when canonical contract serves the same allowed actor; never turn anonymous use into an unintended login requirement. |
| CW24 E/S | Program signup/attendance/saved program/event delete alternatives | Attendance, saved-program and event command bindings; [event adapter](../../../lib/components/schedule/supabase_event_commands.dart), [saved program](../../../lib/components/schedule/saved_program_commands.dart). | Map self/companion/admin callers, capacity, conflicts and remove-by-user semantics before route migration. Keep local outbox/coordinator/freshness logic; these are not independent business writers. |

The source paths above are starting points, not permission to blindly replay
their files in production. Latest textual migration evidence for the pool
writer includes `20261013200000_waitlist_canonical_tickets.sql`; speaker save
has an override in `20260803164500_fix_speaker_topic_reference_aliases.sql`;
resolve-cleaning audit behavior has a later
`20260808130000_fix_cleaning_resolve_audit_operation.sql` override. Preserve those
fixes when materializing one authored owner. A scoped local catalog assertion
must establish final signatures/bodies/ACL; source filename order is not live proof.

## Required closure record per slice

Before editing runtime code, record the precise signatures, internal call graph,
old/new input and result mapping, guards/ACL, current callers and published-client
compatibility. For partial-update adapters distinguish omitted fields from null;
for versioned commands record any legacy compatibility limits explicitly.

After implementation require all of:

1. Current callers use one typed operation, independent of read-sync selection.
2. One internal business writer exists for each capability; old public paths are
   deleted or mechanical adapters to the canonical command, never to a competing
   writer that omits required receipts/publication.
3. No command/facade/helper recursion and no double admission, notification,
   history or publication effects.
4. Actor/scope denial, rollback, replay, omitted/empty values and concurrency
   behavior pass targeted tests, including both supported read-context modes.
5. Authored definitions and new forward assembly agree; historic migrations stay
   immutable. Internal helper grants and dropped endpoint grants are verified.

Scope/identity gaps CW19/CW21/CW23/CW24 cannot be signed off by deleting a branch.
Implement the equivalent safe contract or explicitly retain a scoped delegating
boundary with a concrete consumer. No claim of a completed global cutover while
an independent in-scope writer remains. None of these writes becomes an MCP
tool automatically; the initial exposed MCP surface stays read-only.


## Local execution closure

The selected CW01-CW24 cutovers are implemented and locally verified. The
[execution record](backend-refactor-execution-2026-10-20.md)
records the canonical integration and compatibility boundaries; the
[verification receipt](backend-refactor-verification-2026-10-20.json) identifies
exact integration sources and executed lanes. The subsequent [production closure](backend-refactor-release-result-2026-10-20.md) records the applied migration, tenant deployment and live checks.

Specific reconciliations of the investigation requirements:

- Modern product/form deletes require the original revision in their new
  three-argument shape. Released two-argument shapes share a private owner and
  retain existing request hashes. JSON/array legacy controls still require an
  enforceable upgrade/fence policy before MCP writes.
- CW07's resource command is itself the sole scoped DML owner. Its old facade
  delegates to it, so introducing another business helper would not remove an
  independent writer. Pool/report owners were extracted because their previous
  call graph actually required that separation to prevent recursion.
- Product, profile, parent-pool, group-place and surviving event-link revisions
  now cover their competing selected writers. Ordinary form capacity counters,
  scanner credentials and quote rotation retain distinct operational semantics.
- CW12/CW14/CW24 share ordered dependency locks and event teardown where the same
  deletion rules apply. A new parent after a lock wait causes `40001` before
  mutation; a newly booked counseling slot keeps both its row and version.
- Public old scalar/facade shapes are compatibility adapters for released
  Flutter/external consumers. Obsolete raw writers have no ordinary executor
  grant; migrated table DML is fenced. Installed-client and pending-intent
  inventory remains mandatory before removing retained compatibility signatures or enabling MCP writes.
- W03/W05 and R01-R07 retain their explicit workflow/read-candidate dispositions.
  A new remote orchestrator and optional read consolidation are outside this
  backend-only execution, not unexplained CW engineering work.

## Local validation follow-up

The scanner, broad client-sync assertion and stale SQL source-fingerprint gates
listed in the execution record are repaired. Runtime SQL and compatibility
reachability are unchanged. See [release preparation](backend-refactor-release-preparation-2026-10-20.md)
for the read-only preflight and explicit migration/client, shared-grant,
installed-version and pending-intent decisions. The preparation snapshot is historical; production activation is now verified in the release result. MCP writes remain disabled.
