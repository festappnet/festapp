# Work item: rotate exposed runtime credentials

Opened: 2026-08-24
Updated: 2026-08-29
Status: blocked
Verification: release

> Revalidation required (2026-09-10): retain this incident item until every
> revocation is proven, but inventory current provider state before acting.
> Never record credential values, private repository locators or private commit
> identifiers in this public repository.

## Authoritative sources

- Cutover plan: [`../../../archive/plans/unified-main-production-branches-cutover-plan-2026-08-23.md`](../../../archive/plans/unified-main-production-branches-cutover-plan-2026-08-23.md)
- Private provisioning contract: locator and revision retained outside this
  public repository

## Outcome

Every credential formerly tracked in the three removed Supabase runtime env
files is replaced and revoked; provisioning uses the private configuration
repository without restoring secret values to Festapp or Git.

## Fixed point

- Private removal/contract fixed point: retained in the private incident record.
- Festapp boundary SHA: `5028473a466b7c318f0ca34c3ccb21e592a00203`.
- Secret rotation/revocation receipts: not yet recorded.

## Completed actions

- Tracked runtime env files were removed from the private repository's current
  tree.
- A versioned, tested provisioning contract and non-secret example were added.
- Festapp shared/tenant branches now document the external provisioning boundary.
- The OneSignal REST credential was removed from the Flutter organization model,
  editor and broad admin RPC contract. Migration
  `20260828110000_move_onesignal_credentials_server_side.sql` extracts existing
  values into a no-direct-grants server-only table, and delivery consumers use
  a service-role-only RPC. An isolated migration test moved 10/10 rows and left
  zero legacy JSON keys without recording any value.

## Next action

Using the authorized service consoles and private configuration process,
inventory the
credential types from `supabase/aksmcz.env`, `supabase/festapp.env` and
`supabase/slunovratopava.env` without printing values; rotate each live value and
record only service, timestamp and revocation receipt.

For OneSignal specifically, provision the replacement only into the server-only
notification secret store, run notification plus account-deletion vendor
canaries, revoke the historical credential and prove its authentication fails.
Never put the replacement back into `organizations.data`.

Do not use in-place rotation for the first replacement: OneSignal invalidates
the old secret immediately. Create a second App API Key with an authenticated
Organization API Key, canary it, atomically provision it to the canonical
server-only store and the ignored private operator environment, and only then
delete the historical key and prove denial.

## Remaining order

1. Provision replacements to every active consumer.
2. Verify replacement health without exposing values.
3. Revoke the historical values and verify denial.
4. Run a history-aware secret scan and close the incident ledger.

## Current blocker

Rotation requires authenticated external service access and destructive revocation authority.

## Authority gates

| Action | Required authority | State |
|---|---|---|
| Rotate and provision each service credential | Exact service/account and affected consumer confirmation | OneSignal Slunovrat app verified; Organization API login/key still pending |
| Revoke historical credentials | Replacement health receipt and explicit revocation confirmation | pending |

## Rollback and recovery

- Keep old credentials valid only until replacement consumers pass health checks.
- Revocation is irreversible; recovery uses a newly issued credential, never restoration of the historical value.

## Definition of complete

- [ ] Every affected service has a replacement and healthy consumers.
- [ ] Every historical value is revoked and fails authentication.
- [ ] No secret value is present in current tracked files, logs or work items.
- [ ] Non-secret rotation receipts are recorded.
- [ ] This item is moved to `../completed/` and the index is updated.

## Operational log

| Date | Action | Receipt/evidence | Result |
|---|---|---|---|
| 2026-08-24 | Remove tracked runtime env files | private operational receipt | current tree clean; historical values still require rotation |
| 2026-08-28 | Remove OneSignal credential from client/admin JSON boundary | isolated server-only migration and SQL/Edge tests | code path complete; provider rotation and revocation still pending |
| 2026-08-29 | Verify Slunovrat OneSignal app and current server-only credential | app `4c5b7280-510f-4628-8fb8-b4bdd4fed1b2`; provider read HTTP 200; zero-recipient send HTTP 200 | Chrome/Safari origin remains `https://app.festivalslunovrat.cz`; no subscriber notified; no provider setting changed |
