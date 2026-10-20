# Cross-domain review of multi-call operations

Date: 2026-10-20. These are the original source findings and dispositions.
See [execution evidence](backend-refactor-execution-2026-10-20.md) for locally
implemented A02-A05 paths and the still-unfinished CW/1G gates.

This extends the [operation catalog](README.md) and the authoritative
[canonical refactor plan](../../plans/festapp-canonical-operations-plan-2026-10-20.md).
It examines where several calls implement one intention, rather than counting
RPC names or assuming every sequence should become an Edge Function.

## Coverage and evidence limits

The source sweep covered the same five runtime roots as the technical inventory:
`lib`, `web_client/src`, `supabase/functions`, `workers`, and
`packages/festapp_core/lib`: 1,045 source files at the time of investigation.
A lexical scan using the inventory tokenizer identified 749 async blocks with
two or more `await` tokens, including nested blocks, alternatives, local I/O,
UI dialogs and cache work. Those are candidates, not 749 network sequences or
749 defects. Also inspected scoped `.then`, `Future.wait` and `Promise.all`
patterns, UI callers and SQL helpers behind the material findings.

The table below is the curated cross-domain disposition. Each row represents
a path/family, not necessarily one RPC. The raw source inventory remains the
complete literal-call reference index. This investigation is not a complete
static call graph, proof that all dynamic paths are reachable, or an audit of
production behavior. Installed clients and selected runtime branch are unverified.

Disposition vocabulary:

- **Atomic:** one DB intention split across requests; consolidate the selected
  transaction, not merely place both calls in an Edge handler.
- **Cutover:** a canonical aggregate command already exists; migrate remaining
  callers and delete their parallel writes instead of inventing another owner.
- **Workflow:** effects cross DB/provider/storage/session boundaries; retain
  explicit stages, durable identity and recovery outside a DB transaction.
- **Read:** potentially redundant or excessive projections; optimize only with
  equivalent authorization, bounded payload and consistent meaning.
- **Separate:** independent user intentions, alternatives, UI or local cache work;
  no automatic merge is justified by sequential syntax alone.

## Concrete path decisions

### Current split writes and canonical-command bypasses

| ID | Path and observed sequence | Decision |
|---|---|---|
| A01 | [Whole-order cancellation](../../../lib/components/eshop/db_orders.dart#L99): command/legacy RPC -> `sendStornoTicketOrderEmail`. | **Atomic.** Existing parent-plan cancellation slice; state and automatic intent in one transaction. |
| A02 | [Product grid save](../../../lib/components/eshop/product_grid_record.dart#L204): `commands.saveProduct` -> `commands.updateProductInventoryContexts`. The [product DTO](../../../packages/festapp_core/lib/src/eshop/product_model.dart#L259) omits inventory links. | **Atomic.** Product configuration and submitted inventory links need one receipted save. The split also occurs through the current sync command adapter. |
| A03 | [Users: add to group](../../../lib/components/users/views/users_tab_helper.dart#L53) -> [participant writer](../../../lib/components/groups/db_groups.dart#L176): delete every membership -> one insert per participant. | **Atomic/Cutover.** This helper is directly called independently of the aggregate save's sync selector. Add a server-side additive-members operation; do not replace all members from a stale UI snapshot. |
| A04 | [Price-wave target](../../../lib/components/eshop/views/product_price_waves_dialog.dart#L90): if the displayed wave is not persisted, `createProductPriceWave` -> `saveProductWaveTarget`. [Wave creation SQL](../../../database/functions/eshop/product_price_waves.sql#L30) also adopts existing planned changes. | **Atomic.** Resolve/create wave and save the selected target in one transaction. A failure must not leave wave/adoption changes from half the action. Preserve legitimate standalone wave creation. |
| A05 | [Publish activities](../../../lib/components/activities/activities_content.dart#L1663): prepare HTML -> publish -> `deleteAutosave` -> refresh. [Cleanup helper](../../../lib/components/activities/db_activities.dart#L282) deletes all this actor's autosaves and suppresses failure. | **Atomic candidate + Workflow.** Keep media preparation separate; make consumption of the chosen draft conditional/versioned inside publish if it belongs to publish success. Never delete a newer draft from another tab. If cleanup is best effort, label it and do not replay publication for its failure. |
| A06 | [Unit-scoped information](../../../lib/components/information/db_information.dart#L126): for game-shaped data, write hidden answer row -> write public information row. Occasion-scoped save already uses one command. | **Atomic candidate, supported shape needs confirmation.** Unit scope is not a legacy selector. Existing [hidden-info RLS](../../../database/policies/02_policies.sql#L387) is occasion-based. Verify whether unit games are supported; implement one valid scoped command or reject the unsupported combination before any write, without expanding permissions. |

A06 implementation decision: `QuotesTab` is the unit caller and hidden-info RLS
is exclusively occasion-scoped. The local unit command supports ordinary
information/quotes and rejects game/hidden data before writes. No unit hidden
answer permission was added. See the execution record for tests and gates.


### Legacy/alternate implementations where a canonical command already exists

These paths can be selected when the read-sync capability is not selected.
Do not assume they are unreachable; do not execute both branches in a proposed
replacement. Mutation routing should not need to depend on read projection mode.

| ID | Path and observed sequence | Decision |
|---|---|---|
| L01 | [Group save](../../../lib/components/groups/db_groups.dart#L109): optional private-place save -> group upsert -> membership replacement -> previous private-place cleanup. Sync path calls `save_user_group_client_sync_v1`. | **Cutover.** Existing aggregate owns participants/place; remove direct-DML branch and legacy private-place helpers after moving callers. A03's additive intent remains distinct from full-group replacement. |
| L02 | [Group delete](../../../lib/components/groups/db_groups.dart#L192): delete members -> delete group -> delete private place. | **Cutover.** Use existing group-delete command and version/permission semantics for every supported context. |
| L03 | [Exclusive signup group save/delete](../../../lib/components/schedule/db_events.dart#L628): group write -> delete links -> insert replacements; deletion similarly uses two table requests. | **Cutover.** `save_exclusive_group_client_sync_v1` / delete command already represent the aggregate. No new Edge wrapper. |
| L04 | [Activity publication](../../../lib/components/activities/db_activities.dart#L136): save PUBLISH history -> update activities in the alternate branch. | **Cutover.** Existing `publish_activities_client_sync_v1` combines history/assignment/projection changes. Remove the two-request publication implementation. |
| L05 | [News publication](../../../lib/components/news/db_news.dart#L97): insert news -> enqueue push in alternate branch. | **Cutover.** Existing publish command accepts explicit add-to-news/send-notification flags. Preserve standalone test notification and publication without push. |
| L06 | [News deletion](../../../lib/components/news/db_news.dart#L19): read previous message/readers -> rewrite read positions -> delete news. | **Cutover.** Existing delete command should own the invariant; preserve read-pointer semantics, not client-side reconstruction. |
| L07 | [New occasion-user fallback](../../../lib/components/users/db_users.dart#L386): update/create user -> add occasion membership -> upsert occasion-user data. | **Cutover.** Existing create/save profile commands already return identity/version and own membership; remove only corresponding fallback code after authority/field parity checks. |
| L08 | [Map place operations](../../../lib/components/map/db_places.dart#L82): legacy group-specific private-place helpers coexist with canonical map commands. | **Cutover.** Remove the helpers with L01/L02, not by routing every group operation through independent public map calls. Ordinary place save/delete already use canonical commands. |
| L09 | [Path save](../../../lib/components/map/db_places.dart#L224): sync aggregate versus direct table save. | **Cutover, not a confirmed serial-transaction bug.** Move alternate writer to existing path command; preserve path JSON semantics. |
| L10 | [Forms](../../../lib/components/forms/db_forms.dart#L43), [products](../../../lib/components/eshop/supabase_eshop_commands.dart#L22), [inventory](../../../lib/components/inventory/db_inventory_pools.dart#L66), [speakers](../../../lib/components/speakers/db_speakers.dart), [cleaning](../../../lib/components/cleaning/db_cleaning.dart), [units](../../../lib/components/unit/db_units.dart): canonical command versus legacy RPC in separate branches. | **Cutover per domain where parity is proven.** Several awaits in the method do not mean both execute. Register residual alternate writers in the cutover ledger; do not merge different permissions or guess unreachable branches. |
| L11 | [Occasion information save/delete](../../../lib/components/information/db_information.dart#L126): save uses canonical command when `unit == null`; deletion still checks read-sync selection. | **Cutover.** Align occasion mutation routing; keep unit authority separate. A06 covers a different scope, not just this selector. |
| L12 | [Legacy image deletion](../../../lib/components/images/db_images.dart#L60): Supabase Storage remove -> `remove_image_records`. R2 uses image Worker. | **Workflow/compatibility cutover.** Inspect historic object ownership before removal. Do not treat storage plus metadata as an atomic SQL transaction or authorize deleting frozen legacy backend data. |

### External and durable workflows: several calls are intentional

| ID | Path and observed sequence | Decision |
|---|---|---|
| W01 | [Checkout](../../../supabase/functions/send-ticket-order/index.ts): create/replace/accept RPC -> identity/payment presentation -> optional Fakturoid stages -> confirmation receipt. | **Workflow.** Keep existing receipted SQL, confirmation intent and external payment recovery. A direct creation-RPC shortcut would skip behavior. |
| W02 | [Optional invoice/order deletion](../../../supabase/functions/delete-order/delete.ts#L21): authorized preflight -> protected config -> external invoice delete -> canonical SQL deletion. | **Workflow.** Keep explicit user choice and replay recovery. No external provider request inside DB transaction; local deletion source duplication is separately fixed. |
| W03 | [Occasion/demo duplication](../../../lib/components/occasion/db_occasions.dart#L196): duplicate DB aggregate -> read new occasion -> copy media -> save new references. | **Workflow.** Stable creation result and resumable media stage; never re-create the occasion when copying fails. |
| W04 | [Bank account details](../../../lib/components/bank_accounts/supabase_bank_accounts.dart#L78): `update_bank_account` -> `manage(update_details)`. [SQL](../../../database/functions/eshop_bank_accounts/update_bank_account.sql) already persists the remote intent; [Edge](../../../supabase/functions/bank-sync-manage/index.ts#L46) claims that pending intent. | **Workflow already consolidated at DB boundary.** The second call accelerates the same durable intent, not a duplicate local update. Expose saved/pending/completed result and preserve cron recovery. Do not delete it based only on call count. |
| W05 | [Bank token setup](../../../lib/components/bank_accounts/supabase_bank_accounts.dart#L154): status -> conditional create -> set-token. | **Workflow candidate.** One user intent spans multiple remote commands. Consider an ensure-and-configure orchestrator over existing fenced intents; preserve known remote-account mapping and resume stages. Do not merge remote operations into a DB transaction. |
| W06 | [Bank status](../../../lib/components/bank_accounts/supabase_bank_accounts.dart#L49): status Edge -> read connection -> remote status -> record pull result -> read refreshed connection. | **Workflow/observation with writes.** `getConnection` is not a pure DB query: the handler persists observed facts. Separate cached query from refresh intent if tool semantics require read-only status. |
| W07 | [Bank pull/recovery](../../../supabase/functions/fetch-transactions/index.ts), [reconciler](../../../supabase/functions/bank-sync-reconcile/index.ts), [operation runner](../../../supabase/functions/_shared/bankSyncOperation.ts): read eligible connections/intents -> external call -> record/complete. | **Workflow.** Preserve HMAC/fenced control/uncertain outcome rules; bounded per-account fanout is intentional. |
| W08 | [Reception cancellation](../../../supabase/functions/cancel-reception-registration/cancel.ts): cancel membership -> obtain bounded revocation session -> revoke -> mark result. | **Workflow.** Immediate domain denial and pending Auth revocation are explicit states. Keep resumable cleanup. |
| W09 | [Account deletion](../../../supabase/functions/confirm-account-deletion/index.ts): claim job -> domain cleanup -> Auth/storage/OneSignal effects -> progress -> completion message. | **Workflow.** Keep durable job and resumable phases. One SQL transaction cannot cover these systems. |
| W10 | [Google login](../../../lib/services/google_auth_service.dart), [web adapter](../../../web_client/src/services/google_auth_service.js), Google Edge handlers: start/proof/callback/claim -> install session -> verify identity -> refresh context. | **Workflow/auth lifecycle.** Preserve one-use handoffs, lease ownership and organization checks; do not collapse validation into trusted client claims. |
| W11 | [Registration](../../../supabase/functions/register/index.ts#L70): read duplicate/config data -> prepare template -> `enqueue_account_email(register)` -> await acceptance. | **Workflow, DB/domain-email owner already shared.** The enqueue RPC receives the registration payload and owns the domain result with intent. Preliminary reads are not the authoritative race/duplicate guard. |
| W12 | [Password reset/admin sign-in](../../../supabase/functions/send-sign-in-code/index.ts), [reset handler](../../../supabase/functions/send-reset-password-link/index.ts): resolve identity/guards -> prepare -> domain+email RPC -> optional acceptance observation. | **Workflow with existing atomic owner.** Preserve normal queue and auth budgets; do not classify preparation/read steps as duplicate writes. |
| W13 | [App links](../../../supabase/functions/send-app-links/appLinksDelivery.ts): render -> shared deliver helper -> provider acceptance and projection. | **Workflow already canonical.** `app_links_sent` projection is explicitly owned by SQL; do not add a second client update after sending. |
| W14 | [Email request/worker](../../../supabase/functions/send-email/index.ts), [queue worker](../../../supabase/functions/_shared/emailDispatcher.ts): authorize -> enqueue -> await acceptance; claim/prepare/fence/send/finalize downstream. | **Workflow.** Producer call, wake and observation are different stages; only worker sends. Use receipt status instead of interpreting timeout as permission to resend. |
| W15 | [HTML preparation](../../../lib/components/html/html_media_service.dart#L205), [form traversal](../../../lib/components/forms/form_html_content.dart), [banner upload](../../../lib/components/email_templates/views/email_banner_settings_card.dart#L241): upload/resolve assets -> save referencing document/banner. | **Workflow.** Track uploaded assets and retry document attachment without re-uploading; retain old referenced bytes until commit succeeds. Do not delete shared assets as speculative compensation. |
| W16 | [Image upload/delete](../../../workers/image-worker/src/upload.ts), [auth/metadata](../../../workers/image-worker/src/auth.ts): permission/admission -> R2 bytes -> record or remove metadata. | **Workflow.** Some checks must precede byte acceptance and final accounting. Assess combined control RPC only if it preserves limits, partial-upload cleanup and identity. |
| W17 | [Sync publication](../../../workers/sync-publisher/src/supabase_database.ts): claim -> build/read -> object write -> complete exact claims, with release/recovery. | **Workflow.** Claim tokens, immutable artifacts, receipt retention and publication fencing are semantic requirements, not redundant calls. |
| W18 | [Ticket/contract PDF](../../../supabase/functions/download-ticket/index.ts), [agreement](../../../supabase/functions/generate-order-agreement/index.ts): auth -> scoped data -> load assets/fonts -> generate bytes. | **Workflow/read generation.** Keep CPU/binary work outside DB. A scoped data reader may consolidate reads, not rendering or provider effects. |

### Read composition, explicit user decisions and local follow-ups

| ID | Path and observed sequence | Decision |
|---|---|---|
| R01 | [Orders tab](../../../lib/components/eshop/views/orders_content.dart#L76): parallel orders-tab bundle and occasion read, partly to obtain unit metadata. | **Read candidate.** Return the minimal already-authorized occasion/unit metadata in the canonical bundle if this removes a redundant fetch; do not fetch a public occasion object to infer admin context. |
| R02 | [Form responses](../../../lib/components/forms/db_forms.dart#L270): fields -> entire order bundle -> local response construction. | **Read candidate.** Add/reuse a bounded response projection with field definitions and cursor; preserve field visibility. Same pattern also appears in `form_responses_content.dart`. |
| R03 | [Waitlist offers](../../../lib/components/forms/views/waitlist_offers_dialog.dart#L60): parallel proposal, preview and full orders bundle. | **Read candidate.** A scoped editor bundle can return consistent bounded offer inputs. Template preview and actual offer command remain different operations. |
| R04 | [Information list](../../../lib/components/information/db_information.dart#L98): public rows -> editor rows -> replace selected types locally. | **Read candidate.** One audience-aware projection can reduce overlap while preserving edit versions and public/offline types. Do not expose hidden answers in the public projection. |
| R05 | [Email template editor](../../../lib/components/email_templates/views/email_templates_tab.dart#L39): entity templates -> inherited occasion templates. | **Read candidate.** Consider a resolved inheritance/editor bundle; do not flatten independent entity scopes or write inherited values accidentally. |
| R06 | [Map and offline bootstrap](../../../lib/components/map/map_page.dart#L1577), [sync fallback](../../../lib/data_services/synchro_service.dart): icons/types/places/group places/paths -> cache/search updates. | **Read/local.** Prefer existing sync projection where available, retain bounded public/private scope. Cache writes and search indexing are not extra backend commands. |
| R07 | [Program and companion schedule](../../../lib/components/schedule/my_schedule_page.dart#L107), [counseling picker](../../../lib/components/speakers/counseling_picker.dart#L103), [inventory settings](../../../lib/components/inventory/views/inventory_pool_settings_view.dart#L110): supporting readers compose one screen. | **Read candidates.** Consider bundles only for measured repeated over-fetch or consistency needs; companion identity and audience filters remain explicit. |
| S01 | [Ticket product editing](../../../lib/components/eshop/views/products_dialog.dart#L121): save -> separately open send-update confirmation -> explicit email. | **Separate.** Email is a deliberate second intention, not an omitted automatic part of product saving. Do not silently send after every edit. |
| S02 | [Partial ticket cancellation](../../../lib/components/eshop/tickets_tab.dart#L174): cancel -> read surviving order/history -> show change preview -> optional send-update. | **Separate/read candidate.** Automatic full cancellation differs from optional partial-change notification. Preserve prompt semantics; bound the preview reads rather than auto-send. |
| S03 | [Orders: mark paid then send](../../../lib/components/eshop/views/orders_content.dart#L325): re-read selection -> confirm paid -> per-order transition -> separate send confirmation. | **Separate batch intentions.** Preserve two user decisions and partial results. Verify automatic paid-ticket delivery policy/dedupe, not a new all-or-nothing mass transaction. |
| S04 | [Product dialog](../../../lib/components/blueprint/views/blueprint_product_dialogs.dart#L49), [wave time](../../../lib/components/eshop/views/product_price_waves_dialog.dart#L63), [transaction remove](../../../lib/components/eshop/views/transactions_dialog.dart#L114): create versus update, move versus create, delete-manual versus detach. | **Separate alternatives.** These branches do not execute in series; preserve different intents. A04 is the actual wave initialization sequence. |
| S05 | [Invites/password/group/user selections](../../../lib/components/users/views/users_tab_helper.dart): per-user work with confirmation/error collection; chooser read -> one selected mutation -> reload. | **Separate batch/local follow-up.** Batch reporting/idempotency may improve, but user/provider failures must not automatically roll back unrelated completed work. A03 is the distinct unsafe membership writer. |
| S06 | [Service deletion](../../../lib/components/occasion_services/service_dialog.dart#L147): attempt delete -> explicit force confirmation -> retry with force -> reload. | **Separate escalation.** Do not remove confirmation or auto-force merely to reduce calls. |
| S07 | [Scanner sync](../../../web_client/src/services/scanner_sync.js), [snapshot](../../../web_client/src/services/scanner_api.js#L24): lease/receipt recovery -> submit -> local reconciliation; manifest -> bounded pages -> activate local snapshot. | **Workflow/local.** Receipt-before-retry and paging are intentional, with offline and uncertain-state semantics. |
| S08 | [Auth/bootstrap/router](../../../web_client/src/startup/initialize_core_services.js), [runtime handoff](../../../web_client/src/services/flutter_runtime_handoff.js), [Dart context](../../../lib/data_services/rights_service.dart): initialize/refresh -> navigate/cache/install worker. | **Separate/local/read.** Deduplicate simultaneous refresh by identity/context generation if needed. Do not replace this with a privileged bootstrap RPC or remove freshness checks. |
| S09 | Typed command adapters across domains: invoke once -> `applyClientCommandReplacements`. | **Separate local sync follow-up.** Applying returned replacements is not a second business mutation. Recovery/read refresh must not replay a completed command. |
| S10 | [Unit verification](../../../lib/components/unit/verification/db_unit_verification.dart), [occasion setup](../../../database/functions/occasion_setup/): save draft, submit/finalize, review, or read status. | **Separate state transitions.** Different user roles and lifecycle steps are intentional. Keep each command atomic, rather than merging a draft save with approval or finalization. Ordinary organization/unit settings use their existing scoped owners. |
| S11 | [Public seat-selection queue](../../../web_client/src/components/forms/form_session.js#L403), [order preview](../../../lib/components/blueprint/views/blueprint_create_order_dialog.dart#L72): serialize select/release actions, later preview and submit. | **Separate reservation/checkout intentions.** Temporary holds expire; preview does not commit an order. Preserve queue ordering and revalidation, not one oversized transaction across user interactions. |

The reviewed dispositions cover ticketing/pricing/payments; groups/users/Auth;
organization/unit/setup/verification; program/activities/speakers; forms/waitlist;
content/news/cleaning/maps; media/templates/messaging; BankSync; scanning/offline
and publication/retention. Single-request commands in those domains remain in
the technical inventory; the absence of a multi-call finding is not a new
security or correctness certification for them.

## Refactor contracts for the new definite findings

### Product configuration and inventory links (A02)

Prefer extending the existing product aggregate save with an optional explicitly
present inventory-context collection, rather than another independent product
save RPC. Omitted collection means preserve links; explicit empty collection
means clear them. Use one shared SQL implementation of context validation and
replacement from both full product save and any still-supported context-only
operation. Keep standalone context editing as a distinct intention if it has
callers; it must not be removed based on A02 alone.

Find the effective product-save definition across later migrations before
extracting it into its authored owner. Preserve occasion/order-editor authority,
product type/currency/deposit/price-wave rules, locks, command hash and sync
impacts. Include context input in the receipt payload hash. All selected values
must validate before committing the product, so a failed link update cannot
leave a partially saved new product.

Move `ProductGridRecord.updateMethod` to one invocation and delete its follow-up
RPC. Test changed title plus invalid/foreign context rolls back both, explicit
clear versus omission, receipt replay, concurrent edits and correct publication.
Do not change form-product ownership or price calculations as collateral work.

### Add selected users to group (A03)

The UI intention is additive. `replace_group_assignments_client_sync_v1` maps
user IDs to group titles across groups; it is not automatically equivalent to
this group-specific membership addition. Saving a stale complete group object
would also risk overwriting concurrent members, description or place.

Add a typed `GroupCommands.addMembers` operation over a scoped, receipted SQL
command. Under one group/occasion lock, validate every selected user and role,
union additions with current members, preserve existing admin flags, and emit
normal private-profile/group/sync effects. Reuse a shared internal membership
writer with full-group save, not a second membership engine. Determine the
existing leader/editor permission intersection from canonical commands and RLS;
do not grant more authority to make the new path work.

Move `UsersTabHelper.addToGroup` to pass selected IDs, not the entire stale set.
Delete `updateUserGroupParticipants` once its aggregate-save legacy caller also
moves, together with L01/L02 private-place helpers. Test denied/foreign member
causes no deletion, duplicate selection, preserved admin flags, replay and
simultaneous additions without lost members.

### Resolve/create wave and assign target (A04)

Reuse the internal wave-resolution and target-validation logic inside one
receipted command for this intention. Existing wave creation, movement and
per-product targeting remain valid separate operations. Validate future time,
occasion, product, wave and target revisions under consistent locks. Preserve
the existing adoption of unambiguous scheduled changes, but it must roll back
with failed target creation in the combined action.

Move only the inline unpersisted-wave path to that command. Test conflict after
wave resolution leaves no newly committed wave/adoption, retries return the same
wave/target, and concurrent creation at the same time converges without duplicate
targets. Never broaden into a general scheduled-change dispatcher.

## Integration order and closure policy

1. Preserve the parent's cancellation/deletion/Auth-source slices.
2. Add A02, A03 and A04 as mandatory phase-1 atomic refactors, in separate coherent
   changes with their own caller/deletion/behavior evidence.
3. Resolve A05 and A06 contracts before exposing the corresponding writes.
   A05 needs chosen-draft/version semantics; A06 needs a real supported scope/type
   decision. Do not use uncertainty as permission to create new game features.
4. Complete the grouped L01-L11 mutation-routing cutover where the canonical
   owner serves the supported scope. Remove direct-DML implementations, not
   simply hide them behind another selector. Preserve required deployed boundary
   adapters and historical snapshots as the parent requires. L12 needs separate
   storage/legacy-source authority before any destructive remote action.
5. Keep W/S dispositions explicit. W04's pending-intent runner and S01/S02's
   manual email choices must not be removed as supposed duplicates. Read
   consolidation R01-R07 is a later measured/bounded improvement; it is not a
   requirement to turn every screen into a new backend endpoint.

For each implementation slice add its exact grants/caller matrix, canonical
owner, fresh forward migration, removal set and tests to the parent execution
ledger before editing runtime code. Validate authorization/transaction/receipt
behavior and absence of the superseded caller. No production query, test run,
deployment or code refactor was performed for this investigation.
