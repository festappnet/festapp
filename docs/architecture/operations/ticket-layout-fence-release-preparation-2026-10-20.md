# Ticket artwork fence and MCP release preparation

Scope: canonical main and `prod/festapptickets` / vstupenky.online only. Blueprint
V2 remains excluded. Earlier E0/E1 and cleanup receipts describe their respective
checkpoints; this follow-up closes the concrete E1 legacy-writer/executor gate.
The user's prior approval for the ongoing selected-tenant rollout is retained.

All three released legacy occasion signatures now delegate through one private
facade in `others/legacy_occasion_facades.sql`. Their old definitions were removed
from `update_occasion.sql` and `public_links/legacy_writers.sql`. Signature and
return types are retained. Creation delegates to its existing owner and roles.
General settings with unchanged artwork continue to work. Explicit layout
changes or changed background/type snapshots are rejected with SQLSTATE 40001
and `ticket_layout_editor_upgrade_required`, before receipt/domain effects.
The canonical modern versioned occasion writer is unchanged, including the media
copy workflow. Ordinary editors/managers retain their existing domain permissions.

This is the explicit upgrade/fence policy for artwork: old clients can continue
general settings but must upgrade to the versioned writer to change appearance.
The policy does not infer installed-client inventories or retire their RPCs.
No current Dart/JS/Edge literal caller of these three legacy APIs was found.
The effective local catalog identified four direct feature-update routines: the
two private existing-occasion owners and two new-occasion materializers. The latter
operate on newly created IDs; they are not alternate edits of existing artwork.
Direct ordinary DML is already fenced and is checked by the new contract.

`get_ticket_layout_write_contract_v1` checks authored body hashes, SECURITY DEFINER
properties, trusted search paths and relevant ACLs, including column DML and
inherited privileges. Its generated hashes come from repository SQL using the
existing canonical parser, never from live definitions. It grants no extra
executor power. Changing a protected definition or grant makes readiness false.
The new migration installs facades and contract atomically and notifies PostgREST.

All MCP profiles now use that same authenticated backend readiness probe. The
previous local-only registration exception is removed. Startup without a verified
contract remains E0; each subsequent artwork action rechecks the contract before
claim/submission and disables the three registered family tools if it drifts.
The existing Auth/organization and per-resource permission checks remain in force.
Pending command identity and logout recovery are unchanged; no payment state is
migrated or reset. No active ticket artwork, issued ticket, email or tenant record
is modified by this release preparation.

## Final local evidence

- Fresh baseline and all forwards passed via `automation/bootstrap_local_db.sh`
  on the owned, marked `festapp-db-tests-pg15` fixture. No other DB client session
  was active before that fixture was rebuilt.
- 31 package cases passed, including real PostgreSQL owner integration, SDK
  registration after authenticated contract verification, rollback disabling
  exposure before the next write, strict contracts and pending/replay behavior.
- Four SQL files passed after fresh assembly: legacy fence, existing authoring,
  scoped MCP projection and generated source parity. All three legacy signatures
  reject stale artwork, retain current settings/create behavior, and preserve the
  version on rejection. Column/private-writer grant drift and body drift disable
  readiness; restoration recovers it. Tests roll back synthetic data.
- 13 source/inventory cases and 9 Python contract regressions passed. The runtime
  contract generator is included in the source freshness check. The immutable
  installed foundation remains byte-identical; `--check` passed.
- `git diff --check` passed. Earlier focused Flutter identity/waitlist/duplication
  results remain valid for unchanged Dart inputs; no extra Flutter task ran here.

Logs: `/tmp/festapp-layout-fence-fresh.log`,
`/tmp/festapp-layout-fence-node-final.log`,
`/tmp/festapp-layout-fence-sql-fresh.log`,
`/tmp/festapp-layout-fence-source-final.log`.

## Release inputs and ordering

Publish the validated shared source to main, then apply only the two new forward
migrations `20261020150000_canonical_profile_ownership_cleanup.sql` and
`20261020173000_ticket_layout_legacy_fence.sql` from that exact main. Preserve the
existing installed foundation and release gate. Back up protected catalog/schema
and verify the migration ledger and source digests before applying; never run
fixtures/tests on production. Confirm organization 3 and canonical activation
before reads/writes. Both migrations require their ledger entry in the same
transaction. Verify authored definitions/retirements, ordinary execution fences,
and the authenticated readiness result after application.

Then release the selected tenant from that main using local Flutter/web builds
and direct deployment. Follow current tenant overlays, ancestry/drift, private
manifest, build/legal and coherent live-version probes. Routine execution is
delegated per AGENTS.md. Publish no other tenant and do not use a GitHub-hosted
production build. Real operator login and client configuration remain user-owned;
no credentials are copied from their application/browser.
