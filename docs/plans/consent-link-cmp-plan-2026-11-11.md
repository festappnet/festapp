# Standalone form consent transfer - PR #803

Status: implemented and locally verified; standard verification (public consent contract).
Base: PR #803, 3ed6914d1fc7c9a5dcfc0658edc80440a8c0b4c8, based on main 5ee4d7e8.

## Outcome and boundaries

An approved organizer website can share a valid Complianz choice with a form
without a bespoke JavaScript adapter. The website owner configures the standard
helper once and marks ordinary new-tab links. Unknown, expired, unsupported or
out-of-scope records leave the form's own notice. Keep explicit adapters, local
choice precedence, visit-only import and the existing live lease transport.
Initial implementation excluded publication. The subsequent user instruction authorizes integration and source publication to main. Production SQL/deployment and issue #787 remain outside this integration step.

## Evidence and decisions

- `host_consent_link.js` already owns exact peer/origin/nonce/scope/sequence and
  the renewable lease. Preserve it, including PR close/unload revocation fixes.
- PR `hostConsentModeDecided` infers an affirmative choice from granted defaults
  or any update. Remove that inference from standalone links. Google documents
  defaults independently from user responses and says GCM does not save choices.
- Existing iframe GCM fallback remains unchanged; when a Complianz source is
  configured it supplies the existing shared registry and both entry points.
- Complianz's public prefix-aware `cmplz_get_cookie`, category API, banner API,
  `complianz.current_policy_id`, opt-in mode and events are the supported boundary.
  Do not parse fixed cookie names or use telemetry-only saved-once flags.
- Its close button dismisses without choosing; forced statistics can write an
  allow cookie without a choice, and category API can allow bots. Require saved
  category values, reject forced statistics and non-opt-in modes, and intersect
  stored allow with the category API. TCF marketing remains denied.
- CMP APIs alone do not prove coverage. Script JSON binds provider, organization,
  unit, a configured CMP policy ID and an archived Festapp semantic revision.
  Compare configured, saved and current CMP IDs and the requested semantic scope.
  Never copy a requested revision into a saved record.
- `processing_revision` hashes technical state. Add `consent_revision` for scope,
  destinations/scripts, notice content/URL, consent version and collector origins;
  omit runtime build revision/origin and approved parent hosts. Preserve existing
  processing hashes for default notices and runtime invalidation. Custom notice
  text/title also invalidate processing scope so local choices cannot outlive them. Remote GTM/policy content changes
  still require increasing `measurement_consent_version` explicitly.

Sources: Google https://developers.google.com/tag-platform/security/guides/consent ;
Complianz https://complianz.io/help/wordpress/configuration/developers-guide-for-third-party-integrations/
and https://github.com/Really-Simple-Plugins/complianz-gdpr/blob/master/cookiebanner/js/complianz.js ;
OneTrust https://developer.onetrust.com/onetrust/docs/cross-domain-cross-device .
There is no claimed universal cross-domain wire standard; these are documented
CMP patterns and the selected conservative Festapp policy.

## Wave 1 - semantic scope

Add the SQL projection and a forward migration; retain all historical migration
bytes. Preserve the existing unification assembler as an immutable historical
check, and add a new assembler for the current policy. Carry the optional semantic
revision through manifest and consent scope; absent means automatic CMP reuse is
unavailable. Explicit external sources may return a matching semantic revision;
existing processing-revision sources remain an intentional external API boundary.
SQL tests prove technical revisions/host additions do not change semantic scope,
while notice/version, scripts/destinations and collector changes do.

## Wave 2 - Complianz source and standalone cutover

Add one source owner under `web_client/src/embed/`. Read script attribute
`data-festapp-consent` JSON with provider `complianz`, positive organization/unit,
32-character consentRevision and positive policyId. Invalid configured sources
must stay configured and denied. Subscribe before reading, coalesce CMP events
in a microtask, poll for expiration/other-tab changes, dispose listeners/timers.
Use the existing source registry; later explicit registration keeps precedence.
A missing/invalid source never falls back to GCM for links. Remove the linked GCM
heuristic and its obsolete tests; preserve default iframe reader behavior.

## Wave 3 - end-to-end evidence and documentation

Replace GCM-link fixtures/scenarios with configured Complianz cases. Test saved
accept/decline/partial choice; undecided, close-only, forced-statistics, opt-out,
broken/missing API, mismatched policy/scope and fresh form after scope change;
withdrawal, expiration, concurrent category updates, old-source retirement,
local choice precedence and lease limits. Browser fixtures model CMP APIs and do
not claim a live-site audit. Keep deterministic browser checks in the canonical
CI commands; delegate browser execution if needed under personal rules.
Update integration docs and existing CS/EN help paragraphs for static configuration,
coverage mapping, failure behavior and version lifecycle. Regenerate embed and
runtime bundles through their build scripts. Add new tests/assembler to existing
CI owners, without introducing a new lane.

## Completion and validation

Run targeted Node tests for adapters, link transport, real form/Klaro/session,
manifest compatibility and iframe regressions; SQL consent tests against the
repository disposable local PostgreSQL runtime; generated bundle/migration parity
checks. Run affected canonical CI mirror lanes before any future publication.
No production changes are implied. Record executed checks and material limits
here after implementation. Historical explicit-adapter support is intentional;
standalone GCM inference has no remaining producer/caller/docs/test acceptance.

## Residual assumptions

The organizer archives and configures correct CMP coverage and purpose mapping.
A trusted website can misrepresent choices; this integration does not provide a
cryptographic attestation or replace its CMP consent records. Initial support is
Complianz opt-in category consent only, not opt-out, forced statistics, per-service
or TCF advertising integration. Unproven configurations fall back to local choice.

## Execution result

Implemented in isolated worktree `festapp-consent-link-cmp-20261111`, branch
`fix/consent-link-cmp-20261111`, on the exact PR head recorded above. Other
worktrees and the original dirty workspace were not changed.

- Replaced standalone GCM inference with the configured Complianz source; kept
  shared registry, explicit adapters, local precedence and live leases. Configured
  iframe integration is covered through the actual generated helper as well.
- Added semantic SQL projection and forward migration
  `20261111120000_form_consent_scope.sql`. Historical migrations are unchanged.
  Custom notice text/title also invalidate local processing-revision cookies;
  the existing default-notice fingerprint and layout-only behavior are preserved.
- Updated integration docs, affected existing CS/EN help paragraphs, CI discovery
  and generated helper/measurement-runtime assets. Removed GCM-link heuristic
  functions and their grant-acceptance tests. Issue #787 was not modified.

Executed verification:

- Canonical `web-measurement` Node selection: 330 tests passed before the final
  additional mixed-version/external-adapter/iframe assertions. Final affected
  files then passed separately: 45 compatibility/adapter/contract tests and
  22 host/iframe tests. No skipped or cancelled tests in these runs.
- `run_db_tests.js database/tests/eshop_forms/form_measurement_consent_test.sql`:
  passed on disposable local PostgreSQL, including semantic/technical separation,
  changed notice, version, destinations and collector coverage.
- `test:measurement-browser -- --both`: four Chromium scenario groups passed
  (link transport, configured CMP link, host, Klaro). Initial fixture cookie-path
  leakage across loopback ports was corrected; no product bypass was added.
- `test:measurement-runtime-browser`, `test:measurement-nested-browser`, and
  `test:measurement-adversarial-browser`: passed in headless Chromium. The
  canonical helper closes isolated contexts and its local servers after each run.
- CI contract: 18 Python tests passed using the existing CI Python environment.
  Help-page contracts: 3 passed. Migration, canonical SQL parity, embed, update
  runtime and measurement-runtime generator checks passed; diff whitespace clean.

Limits: Complianz browser APIs are modeled fixtures, supported against inspected
upstream source; no live Kuřín/CMP audit or Firefox/WebKit run is claimed. The
initial integration supports category-level opt-in only. No source publication,
PR review/comment, production SQL or deployment was performed.

Future release order: run publication gates against the eventual canonical main;
apply the forward SQL migration, deploy the updated form/helper and Unit runtime
artifacts under existing release gates, then configure each approved website's
archived CMP policy mapping. Mixed versions fall back to the local notice. Do
not copy current request revisions into older CMP choices. Runtime-only changes
preserve imported CMP coverage, while local form cookies and legacy explicit
adapters intentionally retain their existing stricter processing-revision rules.

## Integration on current main

The later user instruction authorizes publishing the implementation to main.
Upstream advanced to `4146dbb642929e8dd17d2d95e00e989284220bc3`: #803 was
squash-merged and reverted in #805 to defer it. Reapply only the final owned
consent files on this current base; preserve #798 regression coverage, #805's
blueprint/vendor changes and the current package lockfiles. Retain the original
PR's close/unload revocation fix, not its GCM grant inference. Integration worktree:
`festapp-consent-complianz-integration-20261111`. Add new test inventory ownership
and require canonical CI mirror lanes before source publication.

After initial source integration (`71963159b`), read-only HTTP inspection of
Kuřín's actual Complianz 7.4.4 configuration found disabled `forceEnableStats`
and `tcf_active` serialized as empty strings. Accept these upstream false values
(and null) while keeping truthy/ambiguous configurations denied; add explicit
regressions before the follow-up publication. Real saved-choice browser flows
on the external site remain unverified; all browser interaction tests use the
isolated canonical fixtures.
