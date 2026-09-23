# Work item: roll out canonical EUR payment references

Opened: 2026-08-24
Updated: 2026-09-23
Status: blocked
Verification: release

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
- Mendelio's EUR QR uses the fixed beneficiary name `Mendelio` for its shared
  billing owner. That is not a safe replacement for the three separately owned
  Festapp bank accounts; the existing per-account `creditor_name` field is the
  appropriate configuration boundary here.

## Next action

Decide whether EUR ordering is needed now. If yes, obtain the actual legal
creditor name for each EUR bank account in use; organization titles and account
labels do not establish the payee. Then verify live runtime consumers and run
the scoped pilot without replaying the already applied migrations.

## Remaining order

1. Confirm EUR feature demand and verified payee names for active accounts.
2. Check live order/RF output consumers and current pairing function against
   the canonical contract.
3. Run a controlled EUR pilot, pairing reconciliation and observation if EUR
   is being activated; preserve historical orders and references.
4. Remove any proven obsolete pairing path only after current runtime checks.

## Current blocker

The correct legal creditor names and current EUR feature demand are not known.
No open form currently uses these accounts, so there is no observed active EUR
ordering to pilot. New paid EUR orders would fail the canonical
`EUR_CREDITOR_NAME_REQUIRED` guard while those names remain empty. No bank
account, order, function or migration was changed in this read-only inspection.

## Authority gates

| Action | Required authority | State |
|---|---|---|
| Production preflight | Canonical activation identity and named-user read-only access | completed 2026-09-23 |
| Update EUR bank account payees | Verified legal creditor name for each affected account | pending |
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
