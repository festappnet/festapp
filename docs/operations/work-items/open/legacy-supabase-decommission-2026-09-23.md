# Work item: reconcile legacy Supabase sources and credentials

Opened: 2026-09-23
Updated: 2026-09-23
Status: blocked
Verification: standard

## Authoritative sources

- Completed operational switch: [`../completed/canonical-self-hosted-cutover-2026-09-02.md`](../completed/canonical-self-hosted-cutover-2026-09-02.md)
- Retention/deletion policy: [`../../supabase-self-hosted/deletion-ledger.md`](../../supabase-self-hosted/deletion-ledger.md)
- Transition contract: [`../../supabase-self-hosted/cutover-runbook.md`](../../supabase-self-hosted/cutover-runbook.md)

## Outcome

Record an accurate disposition for every legacy cloud source and credential.
Remove or retain each legacy activation path and keepalive by an explicit,
evidence-backed decision without affecting the live canonical backend.

## Fixed point and evidence

- The 2026-09-10 operator record reports production promotion and opened
  canonical writes. On 2026-09-23, all 11 active web manifests point to the
  canonical backend and match their compiled digests.
- Sources `a` and `slunovrat` passed 2026-09-23 read-only freeze checks:
  complete observed guards, zero active cron/Edge Functions, no observed active
  mutating sessions, zero publishable keys, and old anon keys rejected (`401`).
- Source `default` is absent from the available Management API project list;
  that token receives `403` and the former hostname has no DNS answer. Its
  ownership, deletion and retention state are unverified.
- The same Management API account lists source `a` and `slunovrat` as
  `ACTIVE_HEALTHY` on 2026-09-23; this is provider status, not proof of current
  client traffic or permission to delete them.
- A read-only legacy keepalive still exists. Older compiled mobile endpoints,
  keys and installed-client adoption have not been independently inventoried
  after the switch. The original private cutover JSON receipts are unavailable
  in this checkout.
- The latest observed encrypted R2 backup run is `20260922T024347Z`; its five
  expected objects are nonempty and its manifest declares 30-day retention.

## Next action

Use the owning Supabase account or final archive to establish the exact status
of source `default`. Record the result without inferring deletion from the
current token's `403` response or absent DNS.

## Remaining order

1. Reconcile installed mobile clients and legacy credential use against the
   canonical runtime; recover private final receipts if still retained.
2. Decide the disposition of each retained source, key and keepalive according
   to the deletion ledger and current production evidence.
3. Execute separately authorized cleanup, verify each result and close this
   item. Do not delete a source merely to make the ledger look complete.

## Current blocker

The available Supabase token cannot inspect source `default`, and the recorded
production-host SSH route is unreachable from this workstation. The existing
2026-08-27 instruction in the deletion ledger says to delete nothing; no later
source-deletion approval is recorded here.

## Authority gates

| Action | Required authority | State |
| --- | --- | --- |
| Delete or mutate a retained source | Superseding explicit source-specific authorization and verified backup/retention disposition | pending |
| Revoke a legacy client key or remove the keepalive | Current client-use inventory and approved compatibility disposition | pending |

## Rollback and recovery

- This inventory is read-only. Before a cleanup mutation, record its exact
  pre-state, affected clients and recovery path in this item.
- A deleted cloud source cannot be restored by switching DNS. Preserve the
  encrypted backup/restore evidence required by the deletion ledger.

## Definition of complete

- [ ] All three source dispositions and credential owners are recorded.
- [ ] Remaining legacy activation paths, credentials and keepalive are removed
  with evidence or documented as an intentionally retained compatibility path.
- [ ] The item is moved to `../completed/` and the open index is updated.

## Operational log

| Date | Action | Result |
| --- | --- | --- |
| 2026-09-23 | Split legacy cleanup from the completed operational switch | Outstanding source and key disposition stays visible without reopening the production cutover. |
| 2026-09-23 | Read-only source `default` recheck | Current Management API credential still receives `403`; its ownership, retention and deletion state remain unknown. No legacy source or credential was changed. |
| 2026-09-23 | Read-only visible-project inventory | Sources `a` and `slunovrat` remain `ACTIVE_HEALTHY` in the accessible Management API account; `default` is absent. No cleanup mutation was attempted. |
