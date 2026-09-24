# Work item: legacy Supabase source cleanup

Opened: 2026-09-23
Closed: 2026-09-23
Status: closed by user decision; legacy resources retained
Verification: standard

## Decision

The user directed us to stop pursuing the old Supabase projects because the
service has already moved to the self-hosted backend. This closes the cleanup
investigation as an operational task. It does **not** establish that any old
project was paused or deleted, and it authorizes no source, key, Worker or data
deletion. Preserve the retained resources and existing recovery evidence. If a
specific legacy resource needs removal later, create a new scoped work item
with a fresh inventory and explicit authorization for that resource.

## Evidence and limits at closure

- The [canonical cutover record](canonical-self-hosted-cutover-2026-09-02.md)
  reports production promotion on 2026-09-10. On 2026-09-23, all 11 active web
  activation manifests pointed to the canonical self-hosted backend and matched
  their compiled digests. Festapp Tickets production password reset was applied
  and verified on that backend.
- On 2026-09-23, the available Supabase Management API account listed `a` and
  `slunovrat` as `ACTIVE_HEALTHY`. Read-only checks observed their freeze guards,
  no active cron or Edge Functions, no observed mutating sessions, no publishable
  keys and rejected old anon keys. Provider status alone does not prove traffic.
- The former `default` project (`kjdpmixlnhntmxjedpxh`) was absent from that
  account's list and returned `403` when queried directly. The user's impression
  is that it may be paused; its actual state and ownership were not verified.
- A read-only legacy keepalive Worker still exists. Older installed mobile
  clients and their legacy credential use were not independently inventoried.
  These uncertainties do not block the canonical service, but they preclude a
  claim that all legacy clients or resources are gone.
- The [deletion ledger](../../supabase-self-hosted/deletion-ledger.md) retains
  the 2026-08-27 instruction to delete nothing. The latest observed encrypted
  R2 backup run was `20260922T024347Z`, with five nonempty expected objects and
  a manifest declaring 30-day retention.

## Closure receipt

No legacy source, credential, Worker or backup was changed or deleted during
this investigation. The user withdrew the request to pursue old projects; the
remaining disposition is intentional retention with unknown `default` status.
