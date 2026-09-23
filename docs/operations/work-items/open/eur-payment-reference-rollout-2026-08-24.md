# Work item: roll out canonical EUR payment references

Opened: 2026-08-24
Updated: 2026-09-23
Status: blocked
Verification: release

> Revalidation required (2026-09-10): this item records an August rollout
> snapshot. Before any production action, compare the canonical migrations,
> current `main`, tenant configuration and live schema; never replay the old
> branch instructions by assumption.

## Authoritative sources

- Plan: [`../../../archive/plans/2026-08-05_eur_payment_reference_plan.md`](../../../archive/plans/2026-08-05_eur_payment_reference_plan.md)
- Execution prompt: [`../../../archive/plans/2026-08-05_eur_payment_reference_execution_prompt.md`](../../../archive/plans/2026-08-05_eur_payment_reference_execution_prompt.md)

## Outcome

EUR orders use one creditor-reference contract end to end, production payment
pairing is verified, and obsolete pairing paths are absent.

## Fixed point

- Implementation branch: `origin/feature/eur-payment-cutover`.
- Source SHA: `a903ea681`.
- Production migration state: not rechecked after the 2026-09-10 self-hosted
  cutover; the August statement above is not current production evidence.
- The two ordered migration files and corresponding RF functions are present
  in current `main`; the old feature-branch fixed point is historical.

## Completed actions

- Implementation and targeted local verification are complete.
- The exact source commit is preserved on the remote feature branch.

## Next action

Resolve the selected tenant from canonical activation and run a read-only schema,
migration-ledger, bank-account and active-consumer preflight against the
self-hosted database. `SUPABASE_URL` in `automation/project.conf` is a compiled
legacy fallback and must not select the live SQL target. Scope any later rollout
to the selected tenant; the old plan's multi-tenant sequence needs a new fixed
point before execution.

## Remaining order

1. Record production pre-state and rollback identifiers.
2. Obtain explicit authorization and apply the two ordered migrations.
3. Deploy compatible Edge/client surfaces in the plan's order.
4. Run the pilot, pairing reconciliation and observation gates.
5. Remove obsolete compatibility paths and integrate through canonical main/tenant generation.

## Current blocker

The live migration state, eligible EUR account and current consumers have not
been rechecked since the self-hosted cutover. Production rollout remains a
release operation after that preflight.

## Authority gates

| Action | Required authority | State |
|---|---|---|
| Production preflight | Canonical activation identity and read-only access | pending |
| Apply migrations | Exact project ref, migration IDs, pre-state and rollback confirmation | pending |
| Client/backend rollout | Exact source/artifact/deployment identities | pending |

## Rollback and recovery

- Keep the current production schema and client path until preflight passes.
- Forward-fix with a higher migration/version after activation; never partially reorder the two migrations.

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
