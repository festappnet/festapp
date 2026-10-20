# Backend refactor production closure, 2026-10-20

The authorized backend refactor is published on canonical main and deployed to **vstupenky.online, 0.20.296+785**. The three broader validation failures are repaired. The prior preparation and integration receipts are historical snapshots before publication; [the production receipt](backend-refactor-release-result-2026-10-20.json) records the completed release.

- Canonical source: `5b82540b6bfe86cbb10c9ca639c6f5d676745d7f`.
- Selected tenant: `493fdb569c9590a1a90370b16a41260cbe8eb435`, preserving the prior production tip and canonical-main ancestry. The main-owned drift check passed.
- Forward migration: `20261020120000`, applied with its ledger row atomically from the verified canonical source. SHA-256: `83709f07dadf93094974385d4c2c43605c936ccd79112780c8533454e34f2a60`.
- Local Flutter/web build passed the required build gates. Direct deployment used the same verified artifact, and the production version/legal/assets check passed three consecutive probes. No GitHub-hosted production build was dispatched.
- Production catalog verification passed all 326 expected definitions and ordinary table, column, inherited and TRUNCATE write fences. Protected pre-release schema/catalog evidence was captured. Read-only SQL impersonation verified an authorized editor read, foreign-principal denial and exact retained completed order-deletion receipt recovery. This is SQL-role evidence, not an end-to-end user login test.

Integration coverage passed 71 SQL cases, 26 multi-connection/catalog cases, 36 selected Flutter cases, 8 product-core cases, 28 Deno handler cases and 20 source/policy/inventory cases, combining the initial batch with focused corrections. Invalid interrupted Flutter output was excluded. No production fixtures, test emails or provider mutations were used.

## Intentional compatibility boundary

Current selected callers reach canonical command owners. Released fixed-signature adapters delegate to those same owners; they are not alternate business implementations. Unsafe legacy two-step activity publication returns 426. Existing request/receipt hashes, payment policies and Auth budgets are preserved.

The existing shared release gate remains unpaused at minimum build 620. The selected web release does not establish that dormant native installations have upgraded or that offline pending intents are absent. Those inventories and the existing guarded contraction conditions remain prerequisites for removing the retained external signatures or declaring MCP write eligibility. No MCP writes, CLI or OAuth connector were activated. No other tenant branch was published or deployed.

The Canonical Cutover completion criteria are therefore met for the selected backend ownership and current-client migration, with the retained external boundaries explicitly identified. Global compatibility contraction and MCP exposure are separate gated work, not unfinished deployment of this release.
