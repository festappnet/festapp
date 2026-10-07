# Reviewed SQL operations

These files are outside the unconditional migration chain. Preparing, checking
or testing them locally does not authorize execution against production.

`canonical_mutation_inventory.sql` is a read-only G2 schema/ACL inventory.
`automation/client_sync_preflight.mjs --remote` executes it only after canonical
activation, organization/occasion and protected database identity checks. Remote
preflight still requires separate authority. Former cloud configuration is not
a live target.

`canonical_mutation_contraction.sql` is the complete shared ACL proposal,
including places. Generate its bounded or complete dry-run through
`automation/release/client_sync_cutover.mjs --mutation-dry-run`, optionally with
`--include-shared-places`. The evidence manifest records the exact SHA-256.
The CLI requires dated G2/G3 evidence, hashed artifact references, every shared
consumer, mixed-client write restriction and separate G4 authority before apply.
A proposal excluding places cannot pass the complete closure gate.

The contracted SQL fixture injects PUBLIC column and inherited role grants,
checks effective denial and canonical positive operations, then rolls back.
Use the guarded disposable runner with explicit DATABASE_URL after the local
bootstrap. Do not run the destructive test runner against production or a
shared development database. Tests leave additive readiness unchanged.

See `docs/runbooks/client-sync-v1.md` and the canonical mutation plan for rollout
order and exact remaining boundaries. A full registry activation has separate
scope and evidence; mutation evidence cannot enable global client sync.
