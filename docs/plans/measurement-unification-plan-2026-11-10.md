# Unified measurement configuration and release

Date: 2026-11-10
Status: Implementation complete; validation and release in progress
Verification: standard; canonical release gates remain mandatory

## Outcome and scope

Integrate Frantisek's PRs #778, #779 and #780, remove duplicate runtime support
rules, and make a successful release prove both the selected runtime identity
and its connection to an eligible public form. Publish shared changes to main
and deploy only `prod/festapptickets` / https://vstupenky.online (organization 3).
The user authorized planning, implementation, merging and deployment in this
session. Other production branches, customer measurement enablement, stored
consents and credential rotation are outside scope.

## Evidence and decisions

| Fact | Evidence | Decision |
| --- | --- | --- |
| All three PRs include main ff74ddd41152982b00008fe1eee2677773670b14 | fetched PR refs | Preserve their commits and merge ancestry in one integration candidate. |
| Unit approval duplicates profile/origin/parents support rules | `unit_measurement_approval_internal`, `form_measurement_status_internal` | One private immutable expression owns only structural runtime support; retain Unit versus Occasion demo checks at their existing owners. |
| Deployment registry scope is discarded after validation | `deploy_measurement_runtimes.sh`, `verify_measurement_runtimes.mjs` | Assert public production environment against registry before upload and verify scope headers after upload. |
| `/runtime.js` works without a functioning backend | `serveMeasurement` | An explicitly registered public form probe must verify the actual `/runtime` response without executing GTM or sending conversion events. |
| Runtime and web release are currently separate instructions | `workers/form-measurement/README.md`, `deploy_direct.sh` | Web deploy verifies all registered runtime receivers of the selected organization before build and again before upload. It never deploys another tenant implicitly. |
| Consent sources already share `bindChoice` | `host_measurement.js` | Retain that owner and the Google adapter. Document processing-revision reload behavior; do not add another consent framework. |
| Backend identity and one active Unit were confirmed read-only | protected SSH, current_database, organization 3, runtime Unit 17 | Runtime registry probe is public form hwnsne2t and approved parent https://kurin.skauting.cz; recheck eligibility at release. |
| Main requires one PR approval | GitHub main protection | Use an existing contributor PR as the aggregate candidate and retain all three PR heads as ancestors. Review final candidate before merging; never bypass branch protection. |

Read-only preflight additionally confirmed that pinned Wrangler 4.159.0
`auth token --json` can reuse its existing encrypted OAuth login for the Pages
project API. Runtime deploy therefore gains the same explicit `--wrangler-oauth`
choice as web deploy; bearer extraction stays in memory and a safe parser.
No credential is created, rotated or copied to a file.

## Invariants and ownership

1. SQL owns permission, eligibility and stored resource scope. Runtime registry
   owns deployment targets and optional public probe coordinates, never secrets.
2. `form_measurement_runtime_supported_internal(text,text,text[])` owns the
   structural support expression. Demo exclusions remain scope-specific.
3. Registry organization/unit, Cloudflare production variables and live runtime
   response must agree. Backend origin must be https://api.festapp.net.
4. Public probes only fetch HTML/JavaScript; no browser tag execution, orders,
   conversions, customer rows, synthetic production fixtures or policy changes.
5. All registered receivers for the selected organization must be verified before
   its web build/upload. Initial runtime provisioning may omit a probe; releasing
   a web client requires one for every selected registered runtime.
6. Default-off bridge, explicit adapter precedence, expiry and fail-closed mixed
   versions remain unchanged. A new processing revision requires host reload.
7. Applied migration files remain immutable. New SQL ships in a forward migration.

## Execution waves

### 1. Integrate the three PRs

Use an isolated worktree from exact main; merge #780, #778, #779 preserving
ancestry. Resolve source conflicts semantically, retain both migration assembler
checks, and regenerate embed/runtime, translations, MCP reference and client
inventory from final sources. Keep the original dirty worktree untouched.
Exit: one coherent source tree contains all three features and generated outputs.

### 2. One SQL support owner

Add the private immutable helper to canonical SQL and restrict EXECUTE for
PUBLIC/anon/authenticated/service_role. Replace the duplicate expressions in
both existing internal projections, preserving their demo exclusions and public
response shapes. Add a forward assembler/migration after both PR migrations;
freeze the now-historical approval and bridge assemblers by digest. Update ACL
inventory and canonical source parity. Tests exercise structural support, scope
distinction and the existing approval/eligibility paths.
Exit: the support expression occurs once in current canonical owners, old
migrations are unchanged, and SQL tests cover shared behavior.

### 3. Bind deployment to scope and functionality

Keep `measurement_project.mjs` as the sanitized Cloudflare metadata boundary;
validate only ORGANIZATION_ID, UNIT_ID and FESTAPP_API_URL from production
plain-text bindings against the selected registry entry before uploading.
Never expose raw bindings or service credentials. Serve bounded public scope
headers on `/runtime.js`; verifier checks scope, build ID and exact bytes.
Support an optional registry `probe: {form,parent}` with strict validation;
verify returned bootstrap manifest, scope, form, parent, CSP and build against
the actual `/runtime` HTTP response. Unit 17 receives its verified public probe.
Retain the existing API-token input and add explicit encrypted Wrangler OAuth
reuse, with safe parsing and no automatic login. Require explicit `--only` for runtime deployment to prevent an accidental bulk
release. Daily read-only monitoring may still inspect the registry.
Exit: wrong environment, wrong scope, missing backend and malformed/ineligible
runtime response are failures; secrets never appear in diagnostics.

### 4. Enforce receivers before web

Add verifier organization selection and required-probe mode. `deploy_direct.sh`
uses the selected activation organization from its canonical tenant config and
requires receiver verification before build and immediately before upload,
including --skip-build. No registered runtime for that organization is a valid
empty set; unrelated organizations are not probed. Document onboarding,
probe retirement when a public form closes, rollback and host reload behavior.
Tests use actual entrypoints with simulated network/process boundaries and
prove the upload cannot proceed when its receiver fails.

### 5. Validate, publish, release

Run the affected canonical mirror lanes via `automation/test_ci.sh` on final
inputs, plus new targeted deployment tests. Preserve exact receipts. Fetch main
and all three contributor heads immediately before publication; reconcile any
advancement and invalidate only affected evidence. Push the final aggregate as
a fast-forward update of #778, adjust its description to final scope, and review
and merge normally. All three original heads must be ancestors of merged main.
Require all eight GitHub jobs on that exact main SHA via release_gate.py before
creating or pushing the tenant overlay.

Delegate routine deployment to the required lower-cost deployment agent with
exact main/tenant revisions and gates. Use local build plus deploy_direct.sh,
never the GitHub Deploy workflow. Backend order: canonical email renderer code
reload with queue paused/drained and guarded restart; verify worker and resume;
then missing authorized SQL migrations with atomic ledger updates; then selected
runtime receiver; then canonical tenant overlay, local web build and upload.
Runtime deployment is explicitly only festapp-measurement-unit-17. Inspect any
other registered tenant runtime read-only; do not deploy it implicitly.

## Rollback and residual risks

Retain previous Functions files and runtime deployment ID. Leave email paused on
restart failure. SQL changes are additive/function replacements and preserve
existing rows; stop on ledger/source mismatch rather than rewriting history.
Runtime rollback uses the recorded Pages deployment ID. Stop before web upload
if receiver verification fails. Never silently re-enable old consent semantics.
An event closing can invalidate the public probe; replace its registry probe
with another eligible public form through reviewed source changes. Google ICS
remains undocumented and isolated behind the existing fail-closed adapter.

## Definition of complete

- One current structural runtime-support expression and restricted private ACL.
- One verified consent lifecycle and combined generated receiver/helper outputs.
- Wrong runtime scope/backend and failed functional probe block web release.
- Canonical mirror and exact-main GitHub gates pass, three PR heads reach main.
- Approved backend changes, runtime Unit 17 and only festapptickets web deployed.
- Coherent live-version/build/legal probes and email health pass; exact revisions,
  migration ledger, prior deployment IDs and any limitation recorded at handoff.
