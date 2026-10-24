# Festapp internal operation catalog

Status: source inventory and domain mapping, 2026-10-20; selected backend
families implemented and verified locally. See the [execution record and remaining gates](backend-refactor-execution-2026-10-20.md).
The three broader validation blockers are repaired; [local release preparation](backend-refactor-release-preparation-2026-10-20.md) records the scoped preflight and production evidence still required.

The authoritative [implementation plan](../../plans/festapp-canonical-operations-plan-2026-10-20.md)
requires canonical refactoring before exposing each affected operation. Its
E0-E6 schedule starts with visual ticket preview and gated layout saving;
unrelated refactors remain required without blocking that first useful slice.
The catalog alone does not implement or activate any change.

The [cross-domain sequence review](sequence-review-2026-10-20.md) follows
multi-call operations through callers and backend owners. It adds product save,
group membership and price-wave refactors, and distinguishes legacy alternatives,
external workflows, read bundles and deliberate separate user decisions.

The [remaining-write cutover ledger](remaining-write-cutover-ledger-2026-10-20.md)
specifies concrete canonical owners and removals for CW01-CW24, including facade
recursion hazards and scope gaps. The parent now separates shared handlers,
local MCP and [hosted remote MCP](../../plans/festapp-remote-mcp-plan-2026-10-20.md).
Local MCP already accesses the remote backend; hosting the connector is a
distinct access mode with delegated grants and revocation.

The required [ticketing MCP plan](../../plans/festapp-ticketing-mcp-plan-2026-10-20.md)
adds creation/editing of seating plans, forms, products/capacity and ticket
artwork, plus issued-ticket edits. Parent 1I gates each write family on atomic
rejection, scope/version/legacy-writer safety and durable intent replay; hosted
write grants are separate from the initial four-read pilot.

This is the internal list of operations to consolidate and eventually expose
through CLI/MCP. It is not an API allowlist, a permission audit or a promise that
every listed operation will be exposed. The catalog is descriptive; only the linked execution record identifies
implemented backend behavior. Production state and resource consumption have not been inspected.

Read the domain map below alongside the complete generated
[technical inventory](inventory.md) and [machine-readable evidence](inventory.json).
The inventory covers literal RPC calls and known wrappers in Flutter, public web,
Edge Functions, Worker sources and the portable Dart core; SQL definitions and
the Edge runtime policy supply additional ownership evidence. It retains dynamic
call sites and missing-definition evidence instead of hiding gaps.

## How to read and maintain the catalog

An operation is a user or system intention with an observable outcome, such as
`orders.cancel`. It can invoke several SQL helpers inside one transaction.
An RPC, an Edge endpoint and an internal SQL helper are not necessarily three
different operations. Conversely an endpoint accepting an `operation` argument
can implement several domain operations.

The IDs below name operation families. Lists such as create/save/delete are
explicit suboperations, not a proposal for an unrestricted JSON dispatcher.
Existing RPC names are evidence, not new preferred names. Within a family,
preserve separate contracts when authorization, lifecycle or effects differ.

Kinds: **Q** = domain query; **C** = domain command; **W** = workflow with external
effects; **S** = system job/protocol; **A** = authentication/capability lifecycle.
Reading a capability can consume it or create a session and is not automatically Q.
Family mappings are an initial interpretation of named callers. Only the detailed
records later in this document have traced multi-step behavior. Do not infer
idempotency, read-only behavior or audited authorization from a name or kind.

For each operation promoted to an implementation contract, record:

| Field | Required content |
|---|---|
| Stable ID and outcome | One intention and observable result; no UI-dependent success definition. |
| Current entrypoints and callers | Exact RPC/Edge/Worker routes, dynamic selectors, branch conditions and callers. |
| Context and authority | Organization, unit, occasion, actor or verified capability; exact server guard and execute grants. |
| Inputs and result | Validation, bounded projection, bigint/money representation and stable domain errors. |
| Transaction and effects | Atomic DB writes, durable external intents and effects that happen later. |
| Retry and concurrency | Command identity, receipt/replay policy, version conflict and lock order. |
| Ownership and lifecycle | Canonical SQL/Edge owner; accepted partial states and recovery owner. |
| Migration and checks | Old callers/definitions to remove, forward-migration ordering and targeted behavior tests. |
| Tool eligibility | Internal query, user command, privileged system-only, or explicitly deferred. |

Regenerate source evidence after application/backend edits:

```sh
node automation/generate_operation_inventory.mjs
node automation/generate_operation_inventory.mjs --check
node --test automation/tests/operation_inventory.test.mjs
```

The generator is local and credential-free. It does not connect to Supabase,
load `.env`, switch branches or execute operations. A generated name is not proof
of deployed availability or reachability. Line locations are source evidence.
The curated catalog remains the owner of business meaning; generated files own
the raw call/definition inventory and are not edited manually.

## Domain operation map

### Organization, units and event occasions

Tenant/organization identity is mandatory. Occasion means an event instance;
schedule event means an item in its program. Unit is the real-world organizer.
Administrative access and public discovery remain separate.

| ID / kind | Operation or explicit suboperations | Current evidence and consolidation direction |
|---|---|---|
| `context.bootstrap` Q | Resolve tenant configuration, app context and supported platforms | `get_app_config_v2`, `get_app_config_v218`, `get_app_config_v219`, `get_current_organization_data`, `get_available_platforms`; [runtime context](../../../lib/data_services/rights_service.dart). Different generations need caller mapping before contraction. |
| `organizations.admin` Q/C | Read/save organization settings and notification delivery settings | `get_my_admin_organization_id`, `get_organization_admin`, `update_organization_admin`, `get_organization_notification_delivery_config`; [organization SQL](../../../database/functions/organization/). Never expose system secrets in tool output. |
| `units.manage` Q/C | Read/create/save/delete unit | `get_unit_for_edit`, `create_unit_and_assign_manager`, `save_unit_client_sync_v1`, `update_unit`, `delete_unit`; [commands](../../../lib/components/unit/unit_commands.dart). Creation and manager assignment are one intention. |
| `units.verification` Q/C | Read legal profile/queue, save draft, submit, review | `get_unit_legal_profile`, `get_unit_verification_queue`, `save_unit_legal_profile`, `submit_unit_verification`, `review_unit_verification`; [adapter](../../../lib/components/unit/verification/db_unit_verification.dart). Preserve expected revision and different submit/reviewer permissions. |
| `occasions.discover` Q | Browse public promoted/local/external occasions | `get_available_occasions`, `get_public_occasions`; [web catalog adapter](../../../web_client/src/components/occasion/db_occasions.js). Intentional public/external visibility, not operator inventory. |
| `occasions.inspect` Q | Read occasion/editor configuration and copy destinations | `get_occasion_by_link`, `get_occasion_for_edit_v1`, `get_all_occasions_for_edit_v212`, `get_occasion_copy_units`; [adapter](../../../lib/components/occasion/db_occasions.dart). Distinct public/editor authorization. |
| `occasions.manage` C | Create/save/delete occasion | `create_occasion_client_sync_v1`, `save_occasion_client_sync_v1`, `delete_occasion_client_sync_v1`, legacy `update_occasion`/`delete_occasion`; [commands](../../../lib/components/occasion/occasion_commands.dart). Preserve version conflicts and sync replacements. |
| `occasions.duplicate` W | Duplicate occasion into permitted destination and prepare its media | `duplicate_occasion_client_sync_v1`, `duplicate_occasion` plus client media copy; [adapter](../../../lib/components/occasion/db_occasions.dart). Detailed partial-state record below. |
| `occasions.setup` Q/C | Create/read/save/delete wizard draft, select sources and finalize | `create_occasion_setup_draft`, `save_occasion_setup_draft`, `delete_occasion_setup_draft`, `finalize_occasion_setup_draft`; [domain SQL](../../../database/functions/occasion_setup/). Keep draft lifecycle separate from ordinary occasion saves. |
| `occasion-services.manage` Q/C | List/create/save/delete service definitions and game settings | `get_all_service_items`, `create_service_item_client_sync_v1`, `update_service_item_client_sync_v1`, `delete_service_item_client_sync_v1`, `game_update_settings_client_sync_v1` and legacy alternatives; [occasion commands](../../../lib/components/occasion/occasion_commands.dart). |

### Forms, checkout, waitlist and customer access

Public form access, editor access and opaque customer capabilities are separate
authorities. Do not turn a customer token into an editor identity.

| ID / kind | Operation or explicit suboperations | Current evidence and consolidation direction |
|---|---|---|
| `forms.read` Q | Read public form, editor form, fields and copy sources | `get_form_by_link`, `get_forms_by_link`, `get_form_for_edit`, `get_all_form_fields`, `get_all_viewable_forms_for_copying`; [adapter](../../../lib/components/forms/db_forms.dart). Different projections and audiences. |
| `forms.manage` C | Create/save/delete form | `create_form_client_sync_v1`, `update_form_client_sync_v1`, `delete_form_client_sync_v1`; legacy `create_form_ws`, `update_form`, `delete_form_ws`; [commands](../../../lib/components/forms/supabase_form_commands.dart). Preserve field/capacity locking. |
| `forms.duplicate` C | Copy form into a permitted occasion | `duplicate_form_to_occasion_client_sync_v1`, `duplicate_form_to_occasion`; [domain SQL](../../../database/functions/eshop_forms/). Check which associated assets are shared versus copied before calling it a complete workflow. |
| `checkout.create` W | Submit order and prepare its payment presentation | Edge `send-ticket-order` -> `create_ticket_order_client_sync_v1`; [Edge handler](../../../supabase/functions/send-ticket-order/index.ts). Receipts, transactional confirmation intent and optional Fakturoid work; do not replace it with direct SQL creation from a new client. |
| `checkout.replace-seats` W | Replace blueprint order from selected seats | `send-ticket-order` replacement selector -> `replace_blueprint_order_client_sync_v1`; [Dart caller](../../../lib/components/eshop/db_orders.dart). Same Edge endpoint, different domain intent. |
| `checkout.delivery-status` Q | Observe bounded confirmation receipt | Edge `email-confirmation-status`; [observer](../../../web_client/src/components/forms/order_delivery_status.js). Observation does not create/re-send an order. |
| `waitlist.read` Q | Read offer form, proposal, preview and order detail | `get_waitlist_offer_form`, `get_waitlist_offer_proposal`, `get_waitlist_offer_email_preview`, `get_waitlist_order_detail`; [Dart adapter](../../../lib/components/forms/waitlist_commands.dart). Editor and capability projections differ. |
| `waitlist.commands` C/W | Offer/accept/decline/withdraw according to command selector | Edge `waitlist-commands` -> `execute_waitlist_command_client_sync_v1`; acceptance also uses `send-ticket-order`; [Edge handler](../../../supabase/functions/waitlist-commands/index.ts). Enumerate exact accepted operation values before exposing writes. |
| `customer-orders.overview` Q/A | Resolve/bootstrap customer access, read overview, request reissue | Edge `customer-order-access`, `get_customer_order_overview`, `resolve_customer_order_access_v1`, `enqueue_order_overview_reissue_v1`; [Edge](../../../supabase/functions/customer-order-access/index.ts). Reissue creates an email intent and is not read-only. |
| `waitlist.expire` S | Expire outstanding offers and recover capacity | `expire_waitlist_offers`; [scheduled roots](../../../database/functions/seed/crons.sql). System-only, bounded batch, never a customer tool. |

### Orders, tickets and seating

Order-view, order-editor, unit-manager and scanner capabilities are not
interchangeable. Receipt replay must not repeat a side effect.

Planned extension: [pregenerated tickets and manual cash sales](../../plans/pregenerated-manual-ticket-sales-plan-2026-10-23.md)
defines `ticket-batches.preview/create/inspect/sell/void/export` as proposed
operation contracts. The batch retains existing ticket, product-item and seat
identities; stock creation and sale have separate transaction boundaries.
These operations are not implemented entries in the runtime inventory or an
authorization to expose new CLI/MCP writes. The plan owns their integration
with the existing families below, including indirect allocation writers.

| ID / kind | Operation or explicit suboperations | Current evidence and consolidation direction |
|---|---|---|
| `orders.list` Q | Read orders tab/event/form reservation bundle | `get_orders`, `get_orders_tab_data`; [adapter](../../../lib/components/eshop/db_orders.dart). Keep whole-grid bundle distinct from a bounded single-order inspection. |
| `orders.report` Q | Read server-calculated occasion report | `get_report_ws`; [domain SQL](../../../database/functions/eshop/get_report_ws.sql). Reuse money/currency/capacity definitions, no client recomputation. |
| `orders.history` Q/C | Read historical order state; delete history through permitted admin path | `get_order_history`, `get_latest_order_history`, `delete_order_history`; [adapter](../../../lib/components/eshop/db_orders.dart). History deletion is a separate command, never part of a query. |
| `orders.cancel` C | Cancel order, tickets, allocations/membership and required notification intent | `storno_order_client_sync_v1`, legacy `update_order_and_tickets_to_storno_ws_221`, then client `send-email`; detailed record below. |
| `orders.delete` W | Remove order with required external invoice cleanup and sync state cleanup | Edge `delete-order`, `get_order_deletion_context_v1`, `delete_order_client_sync_v1`, legacy `delete_order_221`; detailed record below. |
| `orders.edit-responses` C | Update validated form answers | `update_order_responses`; [SQL](../../../database/functions/eshop_orders/update_order_responses.sql). Must use form definitions, terminal-state checks and canonical lock order. |
| `orders.edit-note` C | Update internal order note | `update_order_note_hidden`; [SQL](../../../database/functions/eshop_orders/update_order_note_hidden.sql). Do not include private notes in default MCP reads. |
| `orders.mark-paid` C | Apply supported manual paid transition | `update_order_and_tickets_to_paid_ws`; [eshop adapter](../../../lib/components/eshop/db_eshop.dart). Preserve ledger/payment ownership and email intent semantics. |
| `orders.agreement` W | Generate configured order agreement PDF | Edge `generate-order-agreement`, `get_order_agreement_data_v1`; [Edge](../../../supabase/functions/generate-order-agreement/index.ts). Keep binary generation out of SQL. |
| `tickets.inspect` Q | Read tickets/products/details for management or generation | `get_tickets_with_details`, `get_products_for_ticket`, `get_products_for_ticket_all_available`; [ticket adapter](../../../lib/components/eshop/db_tickets.dart). Different manager/scanner/document projections. |
| `tickets.cancel` C | Cancel selected tickets, possibly cancelling the entire order | `storno_tickets_client_sync_v1`, internal `storno_tickets_bulk`; [SQL](../../../database/functions/eshop_orders/storno_tickets_bulk.sql). Final-ticket cancellation already queues notification atomically. |
| `tickets.edit-products` C | Change products on an existing ticket | `update_ticket_products_client_sync_v1`, `update_ticket_products_wsv2`; [commands](../../../lib/components/eshop/supabase_eshop_commands.dart). Capacity and pricing are server-owned. |
| `tickets.edit-note` C | Update private ticket note | `update_ticket_note_hidden`; [SQL](../../../database/functions/eshop/update_ticket_note_hidden.sql). Separate projection/permission from public ticket data. |
| `tickets.swap-seats` C | Swap seat allocations between tickets | `swap_spot_tickets_client_sync_v1`, `swap_spot_tickets`; [commands](../../../lib/components/eshop/ticket_commands.dart). Atomic allocation change. |
| `tickets.set-usage` C | Mark used/unused through management path | `update_ticket_to_used`, `update_ticket_to_used_ws`, `update_ticket_to_unused_ws`; [adapter](../../../lib/components/eshop/db_tickets.dart). Compare with scanner commands before consolidating. |
| `tickets.document` W | Generate/download one authorized PDF ticket | Edge `download-ticket`, `get_ticket_document_data_v1`; [Edge](../../../supabase/functions/download-ticket/index.ts). No implicit email send. |
| `seats.select` C | Temporarily select/release a seat | `select_spot`; [order adapter](../../../lib/components/eshop/db_orders.dart). This is a mutation with expiration, not a query or final booking. |
| `blueprints.manage` Q/C | Read/edit blueprint and spot assignments | `get_blueprint`, `get_blueprint_for_edit`, `update_blueprint_client_sync_v1`, `update_spot_assignments_client_sync_v1`; [SQL](../../../database/functions/eshop/). Separate visual editing from inventory commitment. |
| `blueprints.preview-order` Q | Analyze selected seats before submitting an order | `analyze_new_order_spots`; [eshop adapter](../../../lib/components/eshop/db_eshop.dart). Advisory preview does not reserve capacity or authorize commit. |
| `ticket-layouts.preview` W | Generate synthetic/editor ticket preview | Edge `preview-ticket-layout`; [Edge](../../../supabase/functions/preview-ticket-layout/index.ts). Bounded generation, not an actual ticket issuance. |

### Products, prices, inventory, payments and bank integration

| ID / kind | Operation or explicit suboperations | Current evidence and consolidation direction |
|---|---|---|
| `products.read` Q | Read products/types for public or editor use | `get_products_and_types`, `get_products_and_types_for_edit`; [eshop adapter](../../../lib/components/eshop/db_eshop.dart). Preserve visibility and price rules. |
| `products.manage` C | Save/delete product and inventory contexts | `update_product_client_sync_v1`, `delete_product_client_sync_v1`, `update_product_inventory_contexts_client_sync_v1`; [commands](../../../lib/components/eshop/supabase_eshop_commands.dart). Current product saves include explicitly submitted inventory contexts in one command; the adapter has no mutation selector. |
| `prices.plan` C | Create/move/cancel price waves and save/cancel scheduled price changes/targets | `create_product_price_wave`, `move_product_price_wave`, `cancel_product_price_wave`, `save_product_price_change`, `cancel_product_price_change`, `save_product_wave_target`; [price SQL](../../../database/functions/eshop/product_price_waves.sql). |
| `prices.apply-due` S | Apply scheduled changes | `apply_planned_changes`; [cron](../../../database/functions/seed/crons.sql). System clock-driven execution, not an editor save. |
| `inventory.read` Q | Read pools, resources, spots and user allocations | `get_inventory_pool_bundle`, `get_inventory_pools_by_occasion_link`, `get_resources_for_inventory_pool`, `get_spot_management_bundle`, `get_user_inventory`; [domain SQL](../../../database/functions/inventory/). |
| `inventory.manage` C | Save/delete pools and resources; update spot allocations | `save_inventory_pool_client_sync_v1`, `delete_inventory_pool_client_sync_v1`, `save_resource_client_sync_v1`, `delete_resource_client_sync_v1`, `update_spot_assignments_client_sync_v1`; [commands](../../../lib/components/inventory/inventory_commands.dart). Preserve locks and allocation constraints. |
| `payments.transactions` Q/C | Read, attach/detach, pair or remove manual transactions | `add_transaction_to_payment_info_ws`, `remove_transaction_from_payment_info_ws`, `delete_manual_transaction_ws`, `get_transactions_for_order`, `apply_transaction_pairing`; [domain SQL](../../../database/functions/eshop_transactions/). Distinct commands; never collapse into unrestricted payment patching. |
| `bank-accounts.manage` Q/C | Read/save account, memberships and unit links | `get_bank_account_users`, `get_bank_accounts_for_unit_management`, `update_bank_account`, `update_bank_account_user`, `link_bank_account_to_unit`; [adapter](../../../lib/components/bank_accounts/db_bank_accounts.dart). Do not return bank credentials. |
| `banksync.control` W | Connect/update/reconnect/suspend/pull according to authorized selector | Edge `bank-sync-manage`, `fetch-transactions`; [control handler](../../../supabase/functions/bank-sync-manage/index.ts). Durable fenced intents, not a direct bank API client. |
| `banksync.ingest` S | Verify signed bank delivery and ingest/match transaction atomically | Edge `bank-sync-webhook` -> `ingest_bank_sync_transaction`; [handler](../../../supabase/functions/bank-sync-webhook/index.ts). No user-callable equivalent. |
| `banksync.recover` S | Recover incomplete control intents | Edge `bank-sync-reconcile`, `claim_bank_sync_operation`, `complete_bank_sync_operation`; [orchestrator](../../../supabase/functions/_shared/bankSyncOperation.ts). Preserve uncertain external outcomes and fencing. |
| `exchange-rates.read` W | Fetch dated indicative CNB rates | Edge `report-exchange-rates`; [handler](../../../supabase/functions/report-exchange-rates/index.ts). External read, no order recalculation. |

Payment-reference allocation and reservation are internal transactional checkout
responsibilities under `database/functions/eshop_payment_references/`. They are
not independent CLI actions merely because SQL helpers exist.

### Authentication, users, groups, companions and reception

| ID / kind | Operation or explicit suboperations | Current evidence and consolidation direction |
|---|---|---|
| `auth.session` A | Password login, refresh, local/global logout as explicitly selected | Supabase Auth SDK, [Dart owner](../../../lib/data_services/auth_service.dart), [web owner](../../../web_client/src/services/auth_service.js). Outside SQL RPC inventory; no service-role session manufacture. |
| `auth.google` A/W | Identity/capability checks, start, callback, claim/complete login or linking | `google-auth-start`, `google-auth-callback`, `google-auth-complete`; [Dart](../../../lib/services/google_auth_service.dart), [web](../../../web_client/src/services/google_auth_service.js). Dynamic endpoint suffixes; preserve nonce/handoff/lease lifecycle. |
| `auth.register` A/W | Register account and enqueue required account message | Edge `register`; [handler](../../../supabase/functions/register/index.ts). Auth/domain/email effects must be understood together. |
| `auth.sign-in-code` A/W | Issue/admin-send or exchange an existing sign-in code | `send-sign-in-code`; `exchange-sign-in-code` exists in source but is absent from the inspected runtime policy. [source](../../../supabase/functions/exchange-sign-in-code/index.ts). Do not treat source presence as deployed support. |
| `auth.password-reset` A/W | Request reset, validate/set token password or perform authorized reset | Edge `send-reset-password-link`, `set_user_password_token`, `reset_user_password`; [Auth owner](../../../lib/data_services/auth_service.dart). Keep user/admin/proof contracts distinct. |
| `accounts.delete` W | Request/confirm account deletion and recover external cleanup | `request-account-deletion`, `confirm-account-deletion`, `claim_account_deletion`, `cleanup_account_deletion_domain`, `update_account_deletion_job`; [Edge](../../../supabase/functions/confirm-account-deletion/index.ts). Durable multi-system workflow, not one SQL deletion. |
| `users.read` Q | Read editable occasion/unit users, groups and relevant basics | `get_occasion_users_for_edit`, `get_all_users_from_unit`, `get_all_user_basics_from_occasion`, `get_users_from_occasion_with_orders`; [user adapter](../../../lib/components/users/db_users.dart). Bound projections; do not expose all personal data by default. |
| `users.profile` C | Save allowed own/editor profile fields | `save_profile_client_sync_v1`, `update_user`; [commands](../../../lib/components/users/profile_commands.dart). Field-level authority belongs on the server; shared identity edits advance affected occasion versions and imports/deletion share receipt-owned effects. |
| `users.membership` C | Create/add/save/remove occasion or unit membership | `create_occasion_user_client_sync_v1`, `add_user_to_occasion_client_sync_v1`, `delete_occasion_user_client_sync_v1`, `delete_unit_user_client_sync_v1`, `save_occasion_user_for_edit`, legacy counterparts; [user adapter](../../../lib/components/users/db_users.dart). Membership deletion differs from Auth deletion. |
| `users.import` C | Import profiles, occasion CSV, ticket users and group assignments | `import_profiles_client_sync_v1`, `import_users_from_tickets_client_sync_v1`, `import_occasion_users_from_csv`, `replace_group_assignments_client_sync_v1`; [profile commands](../../../lib/components/users/profile_commands.dart). Define each batch's atomicity and rejection report. |
| `groups.manage` Q/C | List/save/delete groups; replace assignments | `get_user_groups`, `get_all_user_groups`, `get_user_group_info_with_users`, `save_user_group_client_sync_v1`, `delete_user_group_client_sync_v1`, `replace_group_assignments_client_sync_v1`, `add_user_group_members_client_sync_v1`; [commands](../../../lib/components/groups/group_commands.dart). |
| `companions.manage` Q/C | Create/delete owned companion; assign/unassign existing companion | `create_companion_client_sync_v1`, `delete_owned_companion_client_sync_v1`, `assign_existing_companion_client_sync_v1`, `unassign_existing_companion_client_sync_v1`; [commands](../../../lib/components/users/companion/companion_commands.dart). Unassignment must not delete the existing account. |
| `reception.register` Q/C | Read registration options/recent entries; create reception user | `get_reception_registration_options_v1`, `get_my_recent_reception_registrations_v1`, `create_reception_user_v1`; [adapter](../../../lib/components/reception/reception_service.dart). Registration command identity is explicit. |
| `reception.credentials` A | Issue QR/manual login proof and exchange it for session | `issue_reception_login_qr_v1`, Edge `exchange-login-qr`; [adapter](../../../lib/components/reception/reception_service.dart). Opaque proof, expiration, consumption and rate limits. |
| `reception.cancel` W | Cancel membership then revoke Auth sessions, with pending-revocation recovery | Edge `cancel-reception-registration`, `cancel_reception_registration_v1`, `mark_reception_auth_revoked_v1`; [orchestrator](../../../supabase/functions/cancel-reception-registration/cancel.ts). Immediate domain revocation and eventual Auth cleanup are distinct states. |

### Scanner

Scanner session/capability authority and persistent operation receipts are
separate from editor access. Offline reads and queued commands are intentional.

| ID / kind | Operation or explicit suboperations | Current evidence and consolidation direction |
|---|---|---|
| `scanner.open` A | Open bounded scanner session | `open_scanner_session`; [web adapter](../../../web_client/src/services/scanner_api.js). Not read-only merely because it returns session data. |
| `scanner.lookup` Q | Lookup/search tickets, read summary and receipts | `lookup_scanner_ticket`, `search_scanner_tickets`, `get_scanner_summary`, `get_scanner_receipts`; [adapter](../../../web_client/src/services/scanner_api.js). Explicit session/token injection in forwarding wrapper. |
| `scanner.sync` C | Submit/replay offline scanner operations | `sync_scanner_operations`; [sync owner](../../../web_client/src/services/scanner_sync.js). Preserve operation IDs and domain receipt outcomes. |
| `scanner.snapshot` S/Q | Prepare and download bounded offline snapshot pages | `prepare_scanner_snapshot`, `get_scanner_snapshot_page`; [adapter](../../../web_client/src/services/scanner_api.js). Preparation may persist artifacts; page reading is separate. |
| `scanner.legacy` Q/C/A | Legacy scan code management, ticket scan and scan-password reset | `get_scan_code`, `update_scan_code`, `get_occasion_by_scan_code`, `get_all_tickets_for_scan`, `scan_ticket`, `reset_password_via_scan`; [SQL](../../../database/functions/eshop_orders/). Do not equate this flow with the new scanner without a supported-client inventory. |

### Program, activities and speakers

| ID / kind | Operation or explicit suboperations | Current evidence and consolidation direction |
|---|---|---|
| `program.read` Q | Browse program/catalog; read editor and participant projections | `get_events`, `get_events_catalog`, `get_all_events_for_datagrid`, `get_event_editor_v1`, `get_event_participants_for_edit`; [schedule SQL](../../../database/functions/events/). Private participant data is not a public program field. |
| `program.manage` C | Save/delete schedule event | `save_event_client_sync_v1`, `delete_event_client_sync_v1`, legacy `delete_event`; [commands](../../../lib/components/schedule/supabase_event_commands.dart). Preserve editor versions and affected projection updates. |
| `program.saved` C | Add/remove/replace own saved program | `set_saved_program_client_sync_v1`, `set_saved_program`; [commands](../../../lib/components/schedule/saved_program_commands.dart). Keep command mode semantics and current-user identity. |
| `program.attendance` Q/C | Read attendance summary and sign user in/out | `get_event_attendance_summary`, `set_event_attendance_client_sync_v1`, `sign_user_to_event`, `sign_user_out_of_event`; [commands](../../../lib/components/schedule/attendance_commands.dart). Capacity/concurrency rules remain atomic. |
| `program.exclusive-groups` Q/C | Read/save/delete exclusive signup groups | `get_exclusive_groups_for_edit_v1`, `save_exclusive_group_client_sync_v1`, `delete_exclusive_group_client_sync_v1`; [commands](../../../lib/components/schedule/exclusive_group_commands.dart). |
| `program.feedback` Q/C | Submit/delete own feedback; read/export/moderate editor feedback | `submit_event_feedback_client_sync_v1`, `delete_event_feedback_client_sync_v1`, `get_event_feedback_for_edit`, `get_event_feedback_export_for_edit`, `delete_event_feedback_for_edit_client_sync_v1`; [commands](../../../lib/components/event_feedback/event_feedback_commands.dart). Respondent versus moderator scopes differ. |
| `activities.draft` Q/C | Read/edit activity draft, autosave and history versions | `get_activities_for_edit`, `update_activities`, `get_latest_autosave`, `save_activity_history`, `list_activity_history`, `get_activity_history_version`, `delete_autosave_history`; [SQL](../../../database/functions/activities/). History operations are not publication. |
| `activities.publish` C | Publish validated volunteer assignments | `publish_activities_client_sync_v1`; [commands](../../../lib/components/activities/activity_commands.dart). One publish outcome with required projection consequences. |
| `speakers.manage` Q/C | Read/save/delete speakers, topics and event associations | `get_speakers`, `get_speakers_for_edit`, `save_speaker_client_sync_v1`, `delete_speaker_client_sync_v1`, `save_speaker_topic_client_sync_v1`, `delete_speaker_topic_client_sync_v1`, `save_event_speakers_client_sync_v1`; [commands](../../../lib/components/speakers/speaker_commands.dart). |
| `counseling.slots` Q/C | Read topics/availability; create slots, delete one or empty slots | `get_counseling_topics_overview`, `get_counseling_availability`, `create_counseling_slots_client_sync_v1`, `delete_counseling_slot_client_sync_v1`, `delete_empty_counseling_slots_client_sync_v1`; [commands](../../../lib/components/speakers/speaker_commands.dart). |

### Content, map, cleaning and media

| ID / kind | Operation or explicit suboperations | Current evidence and consolidation direction |
|---|---|---|
| `news.manage` Q/C | Read/save/delete/publish news and mark own news read | `get_news_with_views`, `save_news_client_sync_v1`, `delete_news_client_sync_v1`, `mark_news_read_client_sync_v1`; [commands](../../../lib/components/news/news_commands.dart). Publication and read acknowledgements have different effects. |
| `information.manage` Q/C | Read/save/delete information pages | `get_information_editor_bundle_v1`, `save_information_client_sync_v1`, `delete_information_client_sync_v1`; [commands](../../../lib/components/information/information_commands.dart). |
| `game.guess` C | Submit checkpoint guess; read own completed checkpoints | `game_guess_client_sync_v1`, `game_get_correctly_guessed_checkpoints`; [commands](../../../lib/components/information/information_commands.dart). Answer submission is a command, even when result looks like a lookup. |
| `map.manage` Q/C | Read editor map; save/delete/move places, types and paths | `get_map_editor_bundle_v1`, `get_group_places_for_map_v1`, `save_place_client_sync_v1`, `delete_place_client_sync_v1`, `move_place_client_sync_v1`, `save_place_type_client_sync_v1`, `delete_place_type_client_sync_v1`, `save_path_client_sync_v1`, `delete_path_client_sync_v1`, legacy `save_place_location`; [commands](../../../lib/components/map/map_commands.dart). |
| `icons.manage` C | Save/delete map icons | `save_icon_client_sync_v1`, `delete_icon_client_sync_v1`, legacy `delete_icon`; [commands](../../../lib/components/icons/icon_commands.dart). Unit-owned `save_unit_icon_client_sync_v1` / delete are canonical; the authored legacy `delete_icon` delegates and shared historic organization assets remain read-only. |
| `cleaning.report` Q/C | Read status, report issue and resolve place | `report_cleaning_issue_client_sync_v1`, `resolve_cleaning_place_client_sync_v1`; [commands](../../../lib/components/cleaning/cleaning_commands.dart). Notification intent/public-state effects must remain explicit. |
| `cleaning.preferences` C | Mute notifications or block a reporter with appropriate role | `set_cleaning_notifications_muted_client_sync_v1`, `set_cleaning_reporter_blocked_client_sync_v1`; [commands](../../../lib/components/cleaning/cleaning_commands.dart). Self preferences and moderation are different permissions. |
| `images.upload` W | Authorize upload, reserve limits, store R2 bytes and register metadata | Image Worker; `check_upload_permission`, `admit_image_upload_v1`, `admit_image_storage_v1`, `add_image_record`; [Worker](../../../workers/image-worker/src/upload.ts). Storage writes and DB records are a recoverable workflow, not one DB transaction. |
| `images.read` Q/W | Resolve public/private image and permitted project access | Image Worker; `get_image_project_access_v1`; [Worker auth](../../../workers/image-worker/src/auth.ts). Do not expose private image capability URLs by default. |
| `images.copy-delete` W | Copy/purge/delete owned image bytes and records | [client](../../../lib/components/images/image_control_client.dart), [Worker](../../../workers/image-worker/src/index.ts); `authorize_image_deletion`, `remove_image_records`. Worker routes are not captured by RPC names alone. |
| `images.fetch-external` W | Fetch bounded authorized external image | Edge `fetch-http-data`; [handler](../../../supabase/functions/fetch-http-data/index.ts). External read with admission/SSRF controls, not a generic URL fetch tool. |

### Messaging, notifications and system operations

System-only queue/receipt/budget operations must not become user-facing tools.
The same applies to publication maintenance and provider callbacks.

| ID / kind | Operation or explicit suboperations | Current evidence and consolidation direction |
|---|---|---|
| `email.order-request` W | Explicit reminder/update/storno notice or ticket delivery request | Edge `send-email`, `send-tickets` -> `enqueue_order_email`; [producer](../../../supabase/functions/send-email/index.ts). Separate automatic lifecycle effects from deliberate manual resend. |
| `email.custom` W | Render/enqueue authorized custom message | Edge `send-custom-email`; [handler](../../../supabase/functions/send-custom-email/index.ts). Preserve recipient authority, snapshot and global queue limits. |
| `email.app-links` W | Send configured app links to resolved delivery address | Edge `send-app-links`; [handler](../../../supabase/functions/send-app-links/index.ts). Uses the same queue. |
| `email.templates` Q/C | Read/save/delete inherited entity templates and banners; preview | `get_entity_email_templates`, `get_all_email_templates_via_occasion_link`, `get_email_template_and_wrapper`, `update_email_template`, `delete_entity_email_template`, `update_entity_email_banner`; [adapter](../../../lib/components/email_templates/db_email_templates.dart). Respect inheritance and editor scope. |
| `email.delivery-read` Q | Read delivery overview, bounded history and detail | `get_email_delivery_overview`, `get_email_delivery_page`, `get_email_delivery_detail`, `get_order_email_summary`; [UI](../../../lib/components/email_delivery/email_delivery_history.dart). Private queue tables are not public read roots. |
| `email.dispatch` S | Claim/prepare/fence/send/finalize queued message and apply post-actions | Edge `process-email-queue`, `claim_email`, `prepare_email`, `begin_email_send`, `finish_email_attempt`, `apply_email_post_actions`; [queue SQL](../../../database/functions/emails/email_queue.sql). Only this worker owns provider sending credentials. |
| `email.recover` S | Wake/recover due intents, reconcile provider events and quota state | `wake_email_worker`, `recover_email_delivery`, `reconcile_email_events`, quota helpers; [cron](../../../database/functions/seed/crons.sql). Recovery continues existing intents, not another queue. |
| `email.provider-feedback` S | Verify provider callback and record delivery facts | Edge `email-provider-events` -> `record_email_events`; [handler](../../../supabase/functions/email-provider-events/handler.ts). Provider-authenticated, not ordinary JWT access. |
| `email.auth-hook` S | Verify Auth callback and persist prepared Auth-email intent | Edge `auth-email-hook`, `get_auth_email_context`, `enqueue_prepared_email`; [handler](../../../supabase/functions/auth-email-hook/handler.ts). No bypass of global send gates. |
| `notifications.deliver` S | Admit and deliver intended push notification | Edge `notify`, `admit_notification_delivery_v1`, `enqueue_notification_v1`; [handler](../../../supabase/functions/notify/index.ts). Signed machine boundary and external OneSignal effect. |
| `sync.client-read` Q/S | Resolve sync endpoints, heads/components and identity-scoped private state | [Dart endpoint resolver](../../../lib/data_services/client_sync/client_sync_endpoint_service.dart), [Worker](../../../workers/sync-worker/src/index.ts), `get_private_client_sync_v1`. Immutable public artifacts and private RPC are distinct. |
| `sync.publish` S | Claim dirty scopes, build/store/publish artifacts and release exact claims | [publisher adapter](../../../workers/sync-publisher/src/supabase_database.ts), `claim_client_projection_dirty_v1`, `complete_client_sync_publication_classes_v1`, `release_client_projection_claims_v1`. Keep exact-token fencing and publication ordering. |
| `sync.retention` S | Select/delete unreferenced artifacts and compact receipts | `get_client_sync_artifact_retention_candidates_v1`, `delete_client_sync_artifact_metadata_v1`, `compact_client_mutation_receipts_v1`; [publisher adapter](../../../workers/sync-publisher/src/supabase_database.ts). Explicit maintenance authority; preserve replay tombstones. |
| `monitoring.abuse-read` S/Q | Observe bounded abuse/admission health | `get_abuse_monitor_v1`; [monitor](../../../workers/self-hosted-monitor/src/index.mjs). Operational access, not a tenant report. |

Infrastructure/deploy/backup/SQL-install scripts are intentionally outside this
application-operation catalog. The legacy keepalive Worker's source may still
appear in the source inventory; presence is not authorization to contact a
former cloud project. Admission/budget/permission/identity helpers are implementation
details of these families, not proposed standalone business tools.

## Traced consolidation records

### `orders.cancel`: atomic automatic notification

The full transition in `cancel_order_domain_internal_v1` owns cancellation,
history and its durable automatic queue intent. Single/bulk/legacy calls share
that owner. Current Dart no longer requests an automatic email afterward; old
Edge requests without an explicit resend identity join the same version/recipient
key. Manual resend and Fakturoid abort remain explicit different intentions.
Queue failure rolls back cancellation; provider delay does not replay it.
See [local concurrency/rollback proof and activation gates](backend-refactor-execution-2026-10-20.md).

### Editor versions and deleted-source recovery

Current form/product clients submit the original revision for deletion through
`delete_form_client_sync_v1(bigint,uuid,bigint)` and
`delete_product_client_sync_v1(bigint,uuid,bigint)`. Modern missing revisions are
rejected. Released two-argument signatures delegate to the same private owner
and preserve their receipt hashes; their removal is an installed-client and
pending-intent gate. Product/context saves share revisions with form editors and
scheduled changes. Group-place readers retain original revisions, and a private
location move also invalidates its group draft.

Completed receipts survive deletion of their source rows. Current actor/scope
permissions and normalized request binding still apply; expired tombstones
cannot cause a new mutation. No family becomes an MCP tool through this cutover.

### `checkout.create`: preserve the complete payment workflow

**Observed:** Dart and web call `send-ticket-order` with stable command/client
identities. The Edge handler selects create/replacement/waitlist SQL. The create
SQL owns the receipt and transactionally queues confirmation; Edge also handles
payment presentation and optional Fakturoid preparation/completion/recovery.

**Target:** maintain one complete checkout outcome across clients. Do not expose
only `create_ticket_order_client_sync_v1` as a shortcut that skips necessary
external work. Extract or simplify orchestration only with its existing receipt,
external-outcome and recovery invariants preserved. This is a case where Edge
can earn its role; fewer HTTP calls alone is not a correctness argument.

### `orders.delete`: one authored command and external cleanup owner

`eshop_orders/delete_order_client_sync_v1.sql` is the authored command owner.
`delete_order.sql` retains private teardown and the legacy facade. The command
merges admission, capacity/order/activity/group locking, queue cleanup and sync
effects. Authorized receipt recovery precedes dependence on a deleted row;
expired tombstones remain non-replayable. `delete-order` retains explicit optional
invoice deletion and provider recovery. Ordinary deletion does not authorize it.
The [forward manifest](../../../automation/operations-foundation-sources.json)
replaces the retired fixed-target assembler paths. See the execution record;
production state and installed-client compatibility remain release gates.

### `occasions.duplicate`: resumable database and media outcome

**Observed:** database duplication commits before Dart copies media through the
image Worker. The client already distinguishes a committed occasion from failed
media setup and must not repeat SQL creation to recover the latter.

**Target proposal:** preserve `occasionId` plus media stage/result, with a
resumable media step and stable creation identity before exposing cross-client
duplication. Keep byte copying outside PostgreSQL. An Edge orchestrator is an
option if it removes duplicated client workflow; it needs durable recovery, not
just two sequential calls hidden inside a function.

### Read projections: reuse meanings, specialize bounded results

**Observed:** `get_orders` loads event/form-wide related collections;
`get_orders_tab_data` composes that with forms and email summaries but uses a
different success/error shape. `get_report_ws` already calculates a typed report.
Public discovery can include external events, while operator inventory needs
authenticated tenant and occasion permissions.

**Target:** keep the typed report authoritative. Add/reuse a bounded order
inspection and authenticated inventory projection, with domain-owned names.
Unify the selected contracts' error semantics; do not force public catalogs,
admin grids and single-object reads into one oversized reader. Exclude personal
responses, hidden notes and ticket/capability secrets from default tool output.

### Authentication, provider work and storage: retain real workflow boundaries

Reception cancellation, account deletion, BankSync control, Google login and
image upload/copy have effects outside a PostgreSQL transaction. Their current
pending/lease/fence/recovery states are part of the operation contract. Removing
Edge execution must not mean moving external HTTP inside a long database
transaction or leaving every client to coordinate partial failure.

## Follow-up queue and architecture rules

| Priority | Work | Completion evidence |
|---|---|---|
| P1 | Contract `orders.cancel` across single/bulk/legacy paths | One state transition with required durable notification intent; callers stop issuing the automatic follow-up; replay/concurrency tests. |
| P1 | Consolidate the two authored order-deletion definitions | One canonical owner and unambiguous forward assembly, preserving all guards/admission/locks; external invoice caller map. |
| P1 | Prepare report, authenticated event inventory and bounded order inspection | Domain-scoped readers and errors shared by all adapters; cross-tenant and bounded-payload tests. |
| P2 | Establish ownership for migration-only client commands | Each selected active contract has an authored owner or an explicit migration-only ownership decision. Do not mass-copy stale migration bodies or rewrite history. |
| P2 | Resolve `delete_icon` / `get_can_manage_images` source evidence and source-only `exchange-sign-in-code` | Check active callers, dynamic creation and release policy before adding/removing anything; no assumption of a live failure. |
| P2 | Define replayable occasion/media duplication | A committed occasion is never duplicated again to recover media; observable stages and recovery owner. |
| P2 | Review remaining dynamic wrappers and direct table access by domain | Literal selector coverage and actual read/write/guard contracts documented; generated candidates are not auto-promoted. |
| P3 | Measure representative hot operations before performance rewrites | Same outcome and workload; latency, backend calls, DB time/locks and Edge CPU/memory measured separately. No unmeasured resource-saving claims. |

Use one RPC transaction for related DB effects; call internal SQL helpers freely
inside it. Persist required external intents in that transaction and execute
them after commit. Retain Edge/Workers for external systems, binaries and durable
multi-system orchestration. Avoid a new generic API server, universal operation
dispatcher, duplicate business engines or a parallel email queue.

Consolidate one operation family at a time. First record callers and policy,
then implement and test the canonical owner, move callers, and delete the
superseded path where client/release compatibility permits it. A valid legacy
mobile contract cannot be silently dropped to make source look cleaner. No
listed finding authorizes live writes, migrations or deployment.

The [CLI/MCP implementation plan](../../plans/festapp-operations-plan-2026-10-20.md)
uses this catalog during its contract phase. This catalog is broader than that
first read-only tool; its system and write families do not expand that scope.

### Pregenerated ticket batches

Implemented source family: `database/functions/eshop_ticket_batches/`.
Operator reads are `get_ticket_batches`, `get_ticket_batch_detail`,
`get_ticket_batch_create_options` and `preview_ticket_batch`. Static authenticated
commands `create_ticket_batch_client_sync_v1`,
`sell_ticket_batch_items_client_sync_v1` and
`void_ticket_batch_items_client_sync_v1` use the existing mutation protocol with
`inventory.ticket_batch.create/sell/void` names. The Flutter adapter is
`TicketBatchCommands`; the document adapter is `prepare-ticket-batch-document`.
These entries add no hosted CLI/MCP write authority. Local code and tests do
not establish production migration or deployment.
