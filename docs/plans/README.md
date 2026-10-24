# Plans and remaining gates

Current operating procedures start at [the documentation map](../README.md).
This directory holds proposals and implementation designs with remaining work.
A plan's future tense describes its design; its latest status and linked evidence
establish what has actually been implemented or released.

- Proposed work remains a proposal until separately requested. The
  [canonical operations plan](festapp-canonical-operations-plan-2026-10-20.md)
  is the parent of the [CLI/MCP design](festapp-operations-plan-2026-10-20.md).
- Local completion does not establish production activation. For example,
  [public links](pretty-public-links-plan-2026-10-15.md),
  [payment references](banksync-payment-reference-reservations-plan-2026-10-17.md),
  [organization verification](organization-verification-plan-2026-10-18.md) and
  [web scanner](web-scanner-plan-2026-10-18.md) retain explicit operational gates.
- Later evidence supersedes older snapshots for its named scope. Google broker
  web deployment and abuse SQL/Auth/proxy activation have dated receipts; native
  login and remaining security/operational evidence are separate gates.
- Approved external work and blockers belong in
  [operational work items](../operations/work-items/README.md). A dated plan or
  prompt alone does not authorize a new production action.

Move completed plans and their execution prompts to [the archive](../archive/README.md)
when the supported scope is closed. Preserve only useful decision rationale and
release evidence; update incoming links. Keep current contracts in architecture,
feature READMEs or runbooks, without the old implementation checklist. Evidence
subdirectories contain dated results and fixtures, not independent work queues.
