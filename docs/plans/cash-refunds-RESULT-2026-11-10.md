# Unified payment operations - local execution evidence

Date: 2026-11-10. Scope: local implementation and verification only. No commit,
push, production migration/deploy, tenant activation or actual refund was performed.
Existing unrelated working-tree changes were preserved.

## Implemented ownership

- One SQL installed-method registry with concrete cash/bank/external handlers;
  matching TS/Dart/web method registration separates optional hosted checkout.
  Existing incoming membership/configuration callers select actual capabilities.
- `command_payment_operation` owns record/prepare/cancel/correct with stable
  receipts, typed scope policies, locks and server context/amount previews.
  Requests reserve intent; ledger facts alone confirm money. Cash writes a
  negative CASH movement; bank classifies the actual authenticated debit and
  retains raw identity/type. Shared financial readers distinguish gross,
  refunded, net and pending, preserving historical signed corrections.
- Bank instructions target the validated recipient, retain the original VS or
  existing EUR RF, and require canonical original ownership. SPD/EPC reuse the
  shared encoder. Unsupported codecs return manual instructions, never fake QR.
- Provider dispatch is leased and recoverable through the existing payment
  runtime. Stripe implements and fixture-tests the original PaymentIntent/account/mode/currency
  boundary; timeout recovery never posts a second operation. SQL
  `refund_write_enabled` defaults false for external connectors, so transport
  implementation alone never enables an operator refund. Money still enters through
  existing provider observation/ingestion/effects. Barion writes remain unavailable.
- Forward `20261110140000_payment_operations.sql` has an explicit ordered
  manifest. Historical cash/provider/Barion migration bytes remain frozen;
  superseded owners are checked through the current forward and older
  assemblers cannot regenerate stale implementations over installed history.

## Runtime and client verification

Tests use disposable local data and frozen external transport responses. They
exercise the actual Stripe request boundary, generic dispatch/recovery executor,
original-session observation and existing provider ingestion seam. They do not
prove merchant API permissions or a real provider refund.

- Deno payments/Stripe/Barion: final complete affected run passed 107 tests,
  with 1 existing ignored case. Includes original provider ingestion and
  amount-preview routing regressions.
- Web owning payment/connector/controller/picker/handoff/status suites: 27/27
  passed. The final affected controller/registry follow-up passed 9/9 after
  adding fail-closed hosted-capability guards.
- Portable Dart payment/options/report suites: 19/19 passed, including signed
  report corrections. Targeted analysis reported no errors; the unchanged
  `FormPage.formLink` immutability warning and existing style/deprecation infos
  remain. Flutter resource exclusivity was preserved.
- Deno checks passed for payment-operation/reconcile/webhook and existing
  order/email hosted-capability callers. Source whitespace checks passed.

## Remaining operational gates and explicit limitations

No live tenant was enrolled or activated. Production requires canonical CI and
release gates, the selected-tenant migration/Edge/client rollout, and verification
of original-reference enrollment/history ownership. EUR RF round-trip behavior
with the real source bank (`bank_sync_connections.refund_rf_verified` defaults false) and real provider write permissions/test-mode account
evidence remain operational readiness gates. External refund write activation remains disabled pending independently
verified account permissions; Barion production sales and refund writes are closed. Reference deviations require authorized evidence-based repair;
there is no automatic guessing or default manual order-selection flow for valid
issued instructions.

Compatibility: published `insert_manual_transaction` signed RPCs retain old
client/receipt semantics over the protected writer, and released Stripe transports
remain adapters for issued links/callbacks. Current admin callers use the generic
operation boundary. Remove published adapters only after their released consumers
and issued callback/link lifetime are retired; preserve historical facts/references.

## Final SQL, concurrency and UI evidence

The dedicated disposable `festapp-refunds-20261110` database on loopback port
55462 bootstrapped successfully from the canonical baseline and every current
forward migration. No existing database project was reset. The final ordered
payment forward was reapplied atomically after the last metadata/sync changes.

- 25 affected SQL files pass on final relevant inputs. A 25-file batch passed
  24 and exposed an actual user-adoption sync actor issue; after correction the
  four affected operation/bank/provider/parity files passed. The remaining
  passing files had no covered financial changes. Earlier deletion/history
  suites also passed in the focused 18-file batch.
- Nine two-writer tests pass on final command inputs. An observer verified actual
  PostgreSQL blocking for prepare/prepare, cash/bank in both orders,
  correction/reservation, cancel/late verified ingest, prepare/verified ingest,
  delete/refund, source unlink and source suspension. This is bounded coverage,
  not a claim to have enumerated every lock interleaving.
- Original VS, repeated partial refunds, wrong currency/reference, original EUR
  RF, source alias, late debit after cancellation, actual amount deviations,
  duplicate movement delivery, and adoption of a previously imported debit are
  exercised through real SQL commands and verified-ingress envelope handling.
  Synthetic EUR readiness is enabled only inside rollback fixtures.
- SQL provider dispatch contracts execute Stripe's real SQL adapter and a
  second distinct temporary ledger adapter through the same command, leased
  claim and completion. They cover activation-off, original binding, missing/
  wrong/stale lease, unknown recovery, confirmed-ledger-only settlement, revoked
  replay and no bank/provider shadow movements. External API calls remain frozen
  transport fixtures; no live refund or account permission proof is claimed.
- Source parity and baseline coverage pass. The unified migration manifest and
  immutable original connector/Barion histories pass their checks. Published
  cash signatures keep signed correction/receipt compatibility; current admin
  Dart callers and operator incoming records use the generic operation boundary.
- Flutter owning dialog cases cover exact amount preview, stale preview fencing,
  keyboard/dismiss/double-submit protection, EUR reopening, manual currency
  instructions and read-only pending permissions. Integration, summary/chart and
  public web tests passed. Final durable storage/integration cases passed 5/5,
  the existing identity owner 12/12 and changed dialog cases 3/3. Exact recovery
  survives storage reopening; concurrent dispatches retain their fence; a fresh
  dialog nonce permits intentional equal payments without reusing an old effect. No browser session or screenshot check was run;
  these UI results come from executable widget/integration tests.
- Edge operation tests pass 5/5, including proof that only a definite SQL rollback
  can report `mutationNotApplied`; transport loss and post-commit encoder errors
  remain uncertain and retain the original command.

Reproduction uses `DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:55462/postgres?sslmode=disable`
with `node web_client/scripts/run_db_tests.js database/tests/payment_providers/`
and the affected lifecycle/report/parity suites, then
`node --test database/tests/eshop/payment_operations_concurrency.test.mjs`.
New SQL/concurrency and durable UI cases are registered in the existing canonical
`seat-contract` and `ticket-client` lanes; no new parallel CI engine was added.

## Preserved pre-existing verification blockers

These whole-workspace checks still fail on work present before this task; no
historical SQL was rewritten and no check was weakened to hide it:

- Hardening history: `occasion_setup/drafts.sql` differs from its older owner.
- Integration history: `eshop_forms/form_creation_domain.sql`,
  `eshop_forms/update_form.sql`, `occasion_setup/finalize.sql` differ from their
  older integration owner.
- Cash history: `occasion_setup/email_preview.sql` differs from its older owner.
- CI contract: `test_webview_release_gate_is_shared` still expects exactly
  `bash automation/test_web_startup.sh`, while the existing workspace adds a
  ticket-wallet page test. The other six CI contract tests pass, including
  ordered GitHub/local mirror checks for the updated owning lanes.

These remain publication/release blockers. No canonical publication lanes or
production gates were waived or represented as executed. Production/deployment
and real provider/bank readiness remain outside the authorized local scope.

## Reachability and contraction

| Entry | Canonical path |
|---|---|
| Admin plus/minus, transaction detail | Same dialog/Edge -> command -> installed method handler -> original ledger/effects |
| Public incoming checkout | Finalizer -> same installed initialization handler, bank instruction owner/provider attempt owner |
| Form incoming availability | Registered builtin/provider capability handler, hosted-only connection configuration |
| BankSync credit/debit | Same bank handler -> original matcher / refund observation -> actual movement classification |
| Provider refund/recovery | Same runtime registry -> original bound provider -> existing observation/ingestion/effects |
| Released signed manual RPC | Bounded receipt/scope adapter -> same protected cash movement writer; historical corrections retained |

Removed internal Dart cash writer/UI classes have no current call sites.
`PaymentConnector` identity and hosted checkout capability are separate; builtin
methods carry no dummy checkout URL, account mode or provider payment identity.
Bank raw type is preserved. No refund VS/RF allocator, business trigger,
`eshop_refunds` public engine or separate financial balance counter was added.
A durable deletion preflight fence prevents a refund from appearing after an
external invoice deletion has begun; uncertainty keeps the fence and requires
resuming the same authorized deletion command.

Final resource cleanup stops only the dedicated SQL test project. No application
server, user browser tab or other session's Flutter task was started or stopped.
