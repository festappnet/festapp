# Work item: roll out canonical EUR payment references

Opened: 2026-08-24
Updated: 2026-09-24
Status: blocked
Verification: release

> 2026-09-24 follow-up: the user authorized an organization-title fallback for
> paid EUR orders with no account-specific payee. The repository change keeps
> an explicit account payee first, cleans control/whitespace characters in the
> fallback and leaves bank account 1025 untouched. This behavior is pending the
> canonical SQL migration and Function deployment; the live blocker below
> describes the pre-deployment state.

> The August rollout sequence is superseded by the live 2026-09-23 readback.
> Both migrations are already present in the self-hosted database. Do not
> replay either migration or target the compiled legacy `SUPABASE_URL`.

## Authoritative sources

- Plan: [`../../../archive/plans/2026-08-05_eur_payment_reference_plan.md`](../../../archive/plans/2026-08-05_eur_payment_reference_plan.md)
- Execution prompt: [`../../../archive/plans/2026-08-05_eur_payment_reference_execution_prompt.md`](../../../archive/plans/2026-08-05_eur_payment_reference_execution_prompt.md)
- Read-only canonical preflight: [`../../../../automation/hetzner-supabase/runtime/eur-payment-readiness.sql`](../../../../automation/hetzner-supabase/runtime/eur-payment-readiness.sql)

## Outcome

EUR orders use one creditor-reference contract end to end, production payment
pairing is verified, and obsolete pairing paths are absent.

## Fixed point

- Historical implementation source SHA: `a903ea681`; the old feature branch is
  no longer an authoritative rollout source.
- Canonical live database `festapp_rehearsal_20260909220601` has both ledger
  versions `20260806001000` and `20260806002000`, the
  `payment_info.creditor_reference` column, and RF/IBAN functions.
- Read-only preflight SHA-256:
  `78c896b92a9ca78e2971618737c3ead593a8897b99b2eeaa75c41defd28b17a8`.

## Completed actions

- Implementation and targeted local verification are complete in current `main`.
- Both ordered migrations were already applied to the canonical live database.
- On 2026-09-23, live counts showed EUR-capable accounts `8` and `737` in
  organization `3` (`vstupenky.online`) and `1025` in organization `7`
  (`Hvězda Mořská`). All three have valid-looking IBAN shapes but no
  `creditor_name`; no open form is assigned to them and no EUR payment info was
  created in the prior 30 days. Historical EUR payment-info counts are 0, 16
  and 20 respectively, with zero stored RF references.
- The live `public.create_ticket_order_internal_v1` function contains the
  `EUR_CREDITOR_NAME_REQUIRED` guard. Account `8` is labeled as a test account;
  `737` belongs to unit AKH and `1025` to Hvězda Mořská. Neither the unit nor
  organization data provides a verified legal payee name.
- The live order function uses the bank account selected on the form or falls
  back to an account linked to the occasion's unit for the required currency.
  Its account number and `creditor_name` flow into the order result and payment
  templates. Account administrators already edit these fields in Festapp;
  `BankAccountGeneralTab` requires a nonempty name when EUR is selected.
- Mendelio's EUR QR uses a fixed `Mendelio` beneficiary for its shared billing
  owner. Festapp's bank account owners differ by unit, so its per-account
  configuration is the correct equivalent. No central payee assignment is
  needed or authorized by this work item.

## Next action

Deploy the new organization-title fallback through the canonical SQL and
Function release workflow. Then verify live EUR order/QR/RF output and bank
pairing as a scoped pilot. Do not change account `8`, `737` or `1025` centrally
or replay the already applied migrations.

## Remaining order

1. Check live order/RF output consumers and current pairing function against
   the canonical contract.
2. Run a controlled EUR pilot, pairing reconciliation and observation when an
   account owner enables EUR on an active form; preserve historical orders and
   references.
3. Remove any proven obsolete pairing path only after current runtime checks.

## Current blocker

No open form currently uses the three legacy EUR-capable accounts, so there is
no active EUR order to pilot. Their administrators can configure the missing
names through the existing account settings before use. The live order
function deliberately rejects a paid EUR order with a missing name; no
bank account, order, function or migration was changed in this read-only
inspection. This is not a request for the operator to collect account-holder
names from the user.

## Authority gates

| Action | Required authority | State |
|---|---|---|
| Production preflight | Canonical activation identity and named-user read-only access | completed 2026-09-23 |
| Update EUR bank account payees | Owning account administrator uses Festapp account settings | owner-managed when an account is activated |
| EUR pilot or client/backend rollout | Current consumer inventory and exact pilot/artifact identities | pending if EUR is activated |

## Rollback and recovery

- Preserve the already applied migration ledger and historical EUR payment
  records. Any follow-up schema change needs a new forward migration.
- A payee correction is an account-data change; record exact pre-state and
  verify new instructions before exposing new EUR orders.

## Definition of complete

- [ ] Ordered migrations and all runtime consumers use the canonical reference contract.
- [ ] Production pilot and reconciliation are verified.
- [ ] Obsolete pairing paths are removed.
- [ ] Observation evidence is recorded.
- [ ] This item is moved to `../completed/` and the index is updated.

## Operational log

| Date | Action | Receipt/evidence | Result |
|---|---|---|---|
| 2026-08-24 | Preserve implementation | `origin/feature/eur-payment-cutover` at `a903ea681` | no local-only implementation remains |
| 2026-09-23 | Repository-only revalidation | current `main` contains both ordered RF migrations and RF functions | live migration state and EUR account remain unverified; old `SUPABASE_URL` target is not authoritative |
| 2026-09-23 | Live-access preflight | SSH port unreachable; no currently authorized Access tab | SQL ledger cannot be read from this workstation session; no database mutation |
| 2026-09-23 | Prepare scoped SQL inspection | read-only preflight file returns migration/function presence and EUR account counts by organization, without account values | ready for named-user Access SQL CLI when MFA is available |
| 2026-09-23 | Named-user canonical preflight | database identity verified; query SHA-256 `78c896b92a9ca78e2971618737c3ead593a8897b99b2eeaa75c41defd28b17a8` | both migrations, RF/IBAN functions and live order guard present; three EUR accounts lack creditor name; zero recent EUR payment info and zero open forms; no mutation |
| 2026-09-23 | Read-only payee-source check | account/unit/organization labels and relevant JSON keys for accounts `8`, `737`, `1025` | test, AKH and Hvězda Mořská ownership context found; no verified legal payee name in the checked records |
| 2026-09-23 | Correct ownership boundary | form/unit account selection, user-admin account settings and live order guard checked | account details are managed by their owners in Festapp; central payee collection request withdrawn |
