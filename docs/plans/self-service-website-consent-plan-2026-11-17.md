# Self-service website consent without platform domain approval

Date: 2026-11-17
Status: Implemented and verified locally; production rollout pending
Verification: standard (authorization and SQL/public contracts)
Base: origin/main 7601a640a; isolated worktree festapp-self-service-consent-20261117.

## Outcome and scope

A Unit manager saves an exact HTTPS website, selects its CMP, confirms that its
notice covers the configured purposes, and exports the integration immediately.
Adding a website does not require platform approval or send an approval email.
Measurement execution keeps its existing independent platform/runtime gates.
This task implements and verifies the change locally. Production migration,
source publication and vstupenky.online release are separate operational steps;
no other tenant is in scope.

## Evidence and target ownership

- `website_consent_bindings.sql`: `website_consent_binding_effective_internal`
  currently requires organization measurement switches, platform policy and
  `unit_runtime.parent_origins`; `get_unit_website_consent_bindings` reports
  `approval_required`. Remove those measurement dependencies from consent.
- `form_measurement_policy.sql`: the public policy hides privacy/notice when
  measurement is ineligible. Expose saved notice configuration for an effective transfer independently
  so the consent transport can work with measurement blocked. Leave runtime
  origins, `approved_hosts`, eligibility, typed runtime authorization and tags
  under their current owner.
- `form_consent_link.js`: linked-window admission currently requires
  `approved_hosts`. Admit an effective server binding for its exact origin too;
  retain the existing approved-host boundary for established unmanaged adapters.
- `probe-complianz/handler.ts` and Flutter consent settings currently require
  platform-approved origins. Authorize probing using the existing manager RPC's
  saved exact websites, retaining pinned public DNS/HTTPS, size/time limits and
  redirect restrictions. A probe detects configuration; it does not prove notice
  coverage and must not replace organizer confirmation.
- `unit_measurement_approval.sql` requests platform review for any newly saved
  origin. Limit requests to missing measurement policy/runtime, preserving its
  notification delivery/retry state and historical receipts.

## Invariants and decisions

1. Only the current Unit manager may create, confirm, export or disable a binding.
   Exact-origin syntax and membership in the saved Unit remain mandatory.
2. Consent readiness requires enabled binding, current semantic confirmation,
   bridge opt-in, saved website membership and a non-demo Unit. It does not
   depend on measurement switches, platform approval or a provisioned runtime.
3. An integration installed on the website plus the existing exact WindowProxy,
   origin, nonce, version, revision and expiring-lease checks establishes the
   live connection. No new manual, DNS-token or email approval workflow is added.
   Merely entering an address neither grants visitor consent nor proves ownership.
4. No runtime parent origins or platform policy are added or changed by binding
   authoring. Unapproved measurement remains blocked even after consent import.
5. Invalidated policy, disabled/removed website, foreign origin, stale binding,
   revision mismatch, missing actual CMP choice and expired lease fail closed.
6. Existing semantic revisions/confirmations retain byte-for-byte scope. A later
   measurement configuration change can require renewed coverage, as today.
7. Existing platform measurement requests and delivered emails are retained as
   historical/runtime administration records, not domain approval authority.

## Execution waves

### 1. Canonical SQL and forward migration

Remove measurement dependencies from binding effectiveness and approval state.
Return saved websites from the manager-only binding scope RPC for probe admission.
Publish the privacy notice when measurement is eligible or a confirmed transfer
is effective; disabled measurement without a transfer must not show a new banner. Remove new
website differences from measurement `can_request`; runtime requests remain.
Add one forward migration from canonical function bodies, freeze affected applied
assemblers rather than rewriting historical migrations, register the new forward
in canonical source inventory/parity and CI checks. Do not update existing runtime,
policy, request or confirmation rows. Validate existing SQL binding, consent,
runtime and request tests with additional negative/independence cases.
Exit: confirmed binding exports without any runtime/policy; measurement stays off.

Iframe transport currently requires a measurement runtime manifest. Add an explicit
`consent_only` transport snapshot validated independently at both peers, rejected
by the unchanged strict runtime manifest/activation boundary. Regenerate embed.js.

### 2. Existing clients and CMS probe

Remove `approvedWebsites` from the Flutter consent component and its owner. Use
saved persisted websites for probing, unaffected by measurement-status loading.
Keep unsaved-state and stale-response cancellation. Show saved/draft website
status without platform pending/approved labels; keep measurement request controls
explicitly for measurement. Update all six locale catalogs and active integration
help references. Let linked consent admit effective managed bindings independent
of runtime host approval. Preserve unmanaged integrations' approved-host contract.
Exit: the self-service UI and Edge path reach the same server owner with no
platform approval prerequisite; runtime controls retain their separate behavior.

### 3. Verification and completion

Run targeted SQL cases using the owned disposable database runner, Deno probe tests,
linked-consent/session tests and the canonical Flutter navigation test entrypoint
containing unit_measurement_settings_cases (one Flutter task, concurrency 1).
Check generated migration/parity, embed/runtime artifacts if affected and CI test
inventory. Verify denial paths and that adding a website no longer queues mail
when measurement is already approved. Record commands/results and remaining live
rollout explicitly in this plan. No independent review agents are required.

## Deletion ledger

| Old artifact | Action/proof |
|---|---|
| Binding `approval_required` state | Remove canonical producer and UI locale keys; bindings use ready/confirmation_required/unavailable |
| Flutter `approvedWebsites` parameter/getter | Delete; saved Unit origin owns probe eligibility |
| Website pending/unrequested approval badges | Remove branches/getters/locale keys and update behavioral tests |
| Domain differences triggering measurement requests | Remove from SQL `can_request`; keep stored request origins for old email history |
| Existing unmanaged adapter allowlist | Retain intentionally at external integration boundary; no change in its authority |
| Applied migration bytes | Retain immutable; changes only in a new forward |

## Rollout, rollback and residual risks

Backend forward precedes the matching Edge function and web/Flutter release.
Older clients may continue showing approval language until upgraded, but the new
backend must not demand domain review. Do not broaden runtime CSP/parent origins
as a shortcut; execution on a new host remains separately governed by runtime
provisioning. Rollback must disable the bridge or restore the prior reviewed
functions explicitly; do not silently reinstate domain approval in a new path.
The runtime profile/collectors remain part of the semantic scope: provisioning a
previously absent runtime can invalidate early coverage and require reconfirmation.
Actual ownership and cookie notice truth cannot be inferred from a saved URL;
existing integration installation and organizer coverage confirmation remain the
operational boundary. No live approval, migration or release is claimed by local
checks.

## Completion record

All three implementation waves are complete locally.

- SQL: owned disposable database upgraded through the new forward migration;
  five selected tests passed (binding independence, runtime gates, consent,
  measurement-request lifecycle and canonical function parity). The first run
  exposed two superseded notice-redaction expectations; final assertions also
  preserve absence of a banner when measurement and managed transfer are off.
- JavaScript: 204 tests passed in the final measurement/iframe batch; the earlier
  linked-consent batch passed, including the new exact-origin managed-link test.
  Generated host-helper tests prove consent-only snapshots cannot activate tags
  or forward analytics. Embed/runtime/measurement generated-artifact checks pass.
- Deno: 12 probe/parser/email tests passed, including manager authorization,
  saved-origin admission, pinned public DNS, unsafe redirects and fresh policy ID.
- Flutter: 36 consent/settings cases passed through the existing explicit CI
  entrypoint `test/components/unit/unit_measurement_settings_cases.dart`, plus
  14 settings-save cases through `test/components/unit/unit_settings_save_test.dart`.
  Removing approval gating exposed duplicate detection after save; fixed in the
  component and verified by the probe-lifetime case. Targeted `fvm dart analyze`
  exits 0 with two existing informational findings (an unrelated identifier and
  async BuildContext use). No new diagnostics.
- `python3 automation/ci/run.py inventory` passed; existing test roots remain
  registered. Migration assemblers/source parity, whitespace check and UI detector
  passed (no detector findings). No schema, request, runtime or permission rows
  were changed outside the disposable local database.

Source remains in branch `fix/self-service-website-consent-20261117` in the
isolated worktree. No commit, push, production migration, live email approval or
web/Edge release was performed. A live rollout must apply the forward first,
then release the matching probe-complianz function and vstupenky.online clients
using the repository's canonical CI/release gates. Existing unmanaged integrations
remain on their established runtime-host allowlist boundary intentionally.


## Authorized production cutover - 2026-11-17

User subsequently authorized deployment and completion of the canonical cutover.
Scope: main shared source, prod/festapptickets -> vstupenkyonline, canonical backend
organization 3 and Unit 17 Akce Kuřín. No other tenant publication or builds.

Canonical consent authority is `analytics.website_consent_bindings` through its
manager RPCs. Remove dead Dart approved/requested-origin fields and remaining
active help claims that consent needs website review. Runtime policy, request
history and the unmanaged external adapter allowlist are retained intentionally:
they govern execution/established external consumers, not managed consent.

Read-only live preflight: backend activation generation 1/canonical matches org 3;
protected SSH hostname, .env active database and current_database match the
persisted target. Org 3 measurement policy is already enabled. Unit 17 runtime
revision 5 permits vstupenky.online and kurin.skauting.cz, while its saved websites
also contain cmp-test.frantisekbujnovsky.com and cc-test.frantisekbujnovsky.com.
Add only these two requested test origins to Unit 17 runtime parent_origins,
advance its technical revision and preserve all other settings/semantic coverage.
Do not manufacture CMP confirmations for the two new websites.

Release order: freeze/validate source; fetch upstream and publish via required PR
review; require exact-main CI release gate; verify and atomically apply only the
new consent migration and its ledger; update the scoped runtime host grant;
release matching probe-complianz and shared measurement email code using the
canonical pause/drain/restart Functions path; deploy the Unit 17 measurement
runtime if generated bytes require it; build/deploy selected web tenant locally;
verify version, activation, public artifacts, runtime hosts and consent policy.
Keep rollback function definitions and scoped policy snapshot outside the repo;
never rewrite migration history or reset unrelated migrations. Pending old
request emails become non-deliverable under the new canonical intent validator;
delivered history is retained.

The main branch requires one GitHub approving review. This is a real publication
gate; no admin bypass or forged approval is included in authorization. Prepare
and validate the concrete PR before reporting a missing-review blocker.

## Authorized automatic website measurement - 2026-11-17

The user explicitly selected automatic admission for every manager-saved website
after the initial platform/runtime approval, then requested commits and a verified
production release to vstupenky.online. This supersedes the earlier per-host
runtime-provisioning restriction and manual Unit17 test-domain patch.

`unit_measurement_parent_origins_internal` owns the effective exact-origin set:
operator-owned application/runtime origins plus at most ten validated saved Unit
websites. Public policy, typed runtime authorization, bootstrap/CSP and manager
status consume this same projection. Manager changes never rewrite runtime rows.
Removing a self-service website revokes that grant; explicit operator grants remain
explicit. Reordering/duplicates preserve the technical revision; an effective host
change refreshes it while retaining the semantic notice revision.

Initial platform permission, supported provisioned runtime, tenant/Unit/form
switches, destinations, privacy URL, binding/peer/revision checks and visitor
consent remain independent requirements. Website authoring retains the existing
manager predicate and ownership statement. Unknown/invalid origins fail closed.
The Worker admits the bounded32+10 origin projection; only the registered org3
receiver is in this production rollout. The reviewed907 embedded-consent fix is
included; the909 layout proposal remains a separate design follow-up on this model.

Release tooling also needs selected Function closure recognition of Deno's
`node:` built-ins. This does not permit changed shared dependencies/locks or a full
Functions/Wallet rollout. Preserve all canonical source, SQL, Function, Worker and
web release checks and recovery evidence.

Review hardening: the shared configuration contract now requires browser-canonical
HTTPS origins. The editor normalizes ordinary casing/default-port input before
saving. Numeric IPv4 shorthands/noncanonical ports are rejected at authoring and
filtered from old saved data; invalid historical binding identities remain
unavailable and are omitted from public manifests. This prevents a single bad
website from poisoning the whole receiver CSP or splitting consent/runtime IDs.
No old confirmation is silently normalized into a new effective permission.

API-v1 compatibility: retain the released lexical website constraint and express
the canonical-origin rule as a standard JSON Schema allOf intersection. SQL, Dart
and operation validation consume the same shared rule. The API checker recognizes
only the provable response-narrowing case where an allOf member is exactly the
complete old schema; request narrowing, unions and partial matches still fail.
No schema-digest waiver or weakened release check is used.
