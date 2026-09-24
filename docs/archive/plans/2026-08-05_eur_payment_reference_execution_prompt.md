# Execute: Kanonický EUR platební kontrakt a bezpečné párování

Start in `<repo-root>`, read the plan, then create a clean
isolated worktree from the fixed point recorded there. If the plan pair is not
yet committed, copy only those two planning artifacts into the isolated
worktree. Do not copy, overwrite or include any other current dirty-worktree
change.

Read all repository instructions, especially `docs/architecture/ai_context.md`,
then read this authoritative plan in full before editing:

`docs/archive/plans/2026-08-05_eur_payment_reference_plan.md`

Use `verification: standard`. Implement local Waves 0–5 in dependency order.
The completed cutover has one RF/payment identity owner, one provider-aware bank
ingest model, one automatic matcher, one pairing mutation owner and one
currency-aware customer presenter. Every automatic and manual attach/unlink
path must use the canonical mutation owner.

Completion requires deletion—not coexistence—of inline importer matchers,
fuzzy date/amount dedupe, the Fio email ID semantic mismatch, duplicated
paid/returned arithmetic, unsafe internal RPC grants, swallowed pairing errors,
dead unlink placeholders and the producer-less `payment_qr.spd` contract. Keep
only the explicitly bounded CZK VS/SPD and strict legacy message-VS boundaries.
Do not add a second implementation, trigger, dual write, permanent pilot flag,
compatibility alias, fuzzy fallback, `LIMIT 1` ambiguity decision or placeholder.

Treat Fio `column22` as movement ID, `column17`/email `ID pokynu` as command ID
and `column27` as raw payer reference. Cross-channel reconciliation requires a
provider-issued shared ID with the same semantics; never deduplicate on
amount/date/name/VS. An email without verified identity must fail closed as
unpaired.

EPC output requires explicit bank-account `creditor_name`, valid IBAN, EUR
amount and structured ISO 11649 RF. Never infer the creditor name from the
occasion title or generic account title, and never emit structured plus
unstructured remittance together.

If current source, baseline or live evidence invalidates a factual premise,
update the authoritative plan with exact evidence before adapting the affected
wave. Do not silently weaken any invariant. Run only the validations required
by the plan/repository and record exact commands/results.

Do not perform Production steps P0–P4, live introspection, migration/deploy,
real bank payment, customer RF activation, RF backfill, historical pairing,
commit, push or branch cherry-pick without separate user authority.

At handoff report: canonical contracts and call graph; provider identity and RPC
grant changes; migrated/deleted artifacts against the ledger; exact validation
results; residual risks; and every pilot/production action still unapplied.
