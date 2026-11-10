# Isolated form measurement

`FormMeasurementSession` is the only owner of visitor role, eligibility, freshness,
generation and transport selection. It forwards saved consent as state. `FormDataLayer` owns
catalogue/funnel semantics, baseline and visit deduplication. Construction is
inert; `start()` subscribes synchronously and resolves policy asynchronously.
Policy errors recover; disposal is terminal. Captured senders belong permanently
to their original active grant. They never queue or replay earlier activity.

Measurement does not wait for consent: on an eligible form the runtime loads GTM and
Unit code at once. Consent Mode is set before GTM and later choices reach the frame
as an update, so the organizer's container decides what its tags may do. Missing or
broken CMP reports denied state. Absent/old embed helper or an unapproved host leaves
measurement off while checkout/layout continue. No same-origin script fallback.

The isolated `gtm-v1` frame sets Google's `cookie_flags` to
`SameSite=None;Secure` before loading the container so Google collection works in
this cross-site context. Consent Mode still determines whether storage is granted;
the cookie setting does not grant either purpose.

`purchase` and `generate_lead` carry `user_data` with the buyer's e-mail and E.164
phone, allowlisted at every boundary and cleared after the event. Nothing else from
form answers leaves, and contacts do not enter SQL conversion facts. Purchase means
an accepted order, not a settled payment. SQL facts retain stable event IDs on
authorized replay and remain independent of temporary runtime outages. Browser
delivery is best effort, not exactly-once or proof of delivery to Ads/Meta.

## Revision and handshake

`processing_revision` fingerprints stored organization/Unit switches, destinations,
privacy URL, profile, collectors, approved recipients, deployment/policy revisions
and `measurement_consent_version`. Cosmetic notice changes do not change it.
The positive Unit consent version defaults to 1 and can only increase through the
existing authorized aggregate mutation with optimistic concurrency. Increase it
when purposes, remote GTM content or privacy text at the same URL change. Festapp
cannot detect remote content changes at an unchanged ID/URL.

The public policy and service-only runtime RPC share the SQL projection. Worker
serializes an explicit manifest from the actual fetched configuration. Protocol 3
`festapp-measurement` ready/init/ACK bind that manifest, source window, origin,
instance and generation before any Unit script is inserted. Parent policy A and
Worker configuration B fail closed. Layout/scroll/theme `festapp-embed` stays at
protocol 1; old measurement messages never grant protocol 3 permission.

Pagehide/BFCache, role/identity changes, expiry or relevant policy changes invalidate
grant and pending sends, then remove the runtime. Hiding the page and consent changes
do not, so the container runs once per visit. Equivalent policy renewal preserves
the grant. Browser scheduling cannot promise instantaneous backend
revocation in a suspended process. Already delivered data cannot be recalled.

## Host CMP integration

New generated snippets explicitly opt into the host page's `window.dataLayer`
with `data-festapp-datalayer`; its GTM and CMP control the tags. Unit mode omits
the attribute, preserving existing embeds and working with older helpers.
Live attribute changes reinitialize transport. WordPress/Joomla expose the same
choice and retain Unit mode for missing or invalid settings.
Both modes still require an approved host and show no consent bar inside the embed.
Direct visits keep the Unit runtime and Klaro bar.

For Unit runtime measurement, the helper measures on its own. A host CMP adapter is
optional and only reports the choice (without one, runtime consent stays denied):

```js
const disconnect = FestappEmbed.connectMeasurementConsent(frame, {
  read(context) {
    // Stored record for organization + Unit, confirmed for its saved revision.
    const saved = cmp.readSavedChoice(context.organization, context.unit);
    return saved && {
      processingRevision: saved.processingRevision,
      analytics: saved.analytics,
      marketing: saved.marketing,
    };
  },
  subscribe(notify) { return cmp.subscribe(notify); },
});
```

A read returning null, or another revision, reports denied state. Simpler hosts use
`connectKlaro(frame, manager)` or `setMeasurementConsent(frame, {analytics, marketing})`;
a boolean means analytics only. The lease is random, local and lasts at most 60
seconds; it proves a live helper and carries no permission from the visitor.

## Isolation and operation

Each Unit runs on a separate canonical `*.pages.dev` site. The service credential
stays in Worker environment, never HTML or messages. The CSP restricts collectors,
rejects frames, workers and form actions; sandbox remains `allow-scripts
allow-same-origin` on the separate site. No new origin, collector or runtime is
provisioned by this change. Deterministic test tags demonstrate execution/network
boundaries, not live Google/Meta attribution.

Forward migration is generated by
`automation/assemble-form-measurement-consent-migration.py`. Historical migrations
remain immutable. Production application, compatible runtime/helper rollout,
source publication and enabling measurement are separate operations.

## Canonical protocol and choice ownership

Measurement protocol 3 denotes advanced execution with bounded conversion
contacts. SQL includes `measurement_protocol: 3` in the policy and processing
fingerprint; the shared contract requires it in every manifest. Layout/embed
protocol 1 is independent. The registered `gtm-v1` deployment profile stays the
same. Production has no protocol 2 fallback. Frozen protocol 2 code lives only in
negative compatibility fixtures with an exact source SHA.

`consent_required: true` in status/MCP means the visitor must have notice and
choice controls. It is not an execution gate. `required_purposes` lists the
reported analytics/marketing choices; both need not be granted to run.

All three public host choice adapters replace one active binding. A disconnected
or failed source reports denied, and an old disposer cannot change its successor.
Setter/Klaro choices bind to organization, Unit and processing revision; a setter
before the first context binds once when that context arrives. A new scope
requires a new choice. Revision-aware sources reread the new scope. Teardown
owns the source, lease, heartbeat and load listener. Pagehide stops liveness;
BFCache resume starts current liveness again, and a retired record stays inert.
Consent updates publish a fresh nested `festapp_consent` snapshot in the update
event itself, retaining its top-level analytics/marketing fields.

A rollout updates canonical SQL first, then the Worker, host helper and selected
web client. Unsupported mixed peers leave measurement off while checkout stays
available. A fully old client/helper/Worker group can temporarily retain its old
limited behavior against the new SQL; this does not prove protocol 3 delivery.
Never reuse an old saved choice under the new processing fingerprint. Applying
the forward migration twice preserves its hash, configuration, enablement and
conversion facts. Existing disabled measurement is never enabled by migration.
See the protocol fixture matrix and the dated implementation plan for the exact
compatibility cases. `/runtime` and `/runtime.js` must be one immutable build;
a dynamic policy hash alone does not identify the executing JavaScript.


## Stable page-event contract

`page_view` is the protocol 3 wire event. The shared contract's
`measurementDataLayerPayload` owns the sole destination projection, producing
`form_page_view` for embeds and `page_view` for direct visits, with a strict
`form_embedded` marker. Neither the embed bridge nor the runtime transport
changes event names. Receivers retain their own page context and the shared
projection attaches it to each event. Host frame context is cleared on revocation
and grant-generation changes. The host resets the embedded marker after each
push so native website events do not inherit it. Frozen pre-change protocol 3 receiver tests protect the
rolling-upgrade boundary. Existing receivers accept new senders and retain their
previous page-event name until upgraded. Deploy receivers before the client to
establish the new destination semantics without losing events.

## Deployment

Deploy receivers before the web client and embed helper, as described in the
[form measurement contract](../../docs/integrations/form-datalayer.md). Run this
release separately before `automation/deploy_direct.sh`. Neither script invokes
the other. Runtime outages must never block orders or payments.

Install the web client's dependencies with pnpm 11.24.0 using
`pnpm --dir web_client install --frozen-lockfile`. Generate the receiver after
changing its sources, then build the Pages advanced mode Worker:

```sh
node web_client/scripts/build_measurement_runtime.mjs
node web_client/scripts/build_measurement_worker.mjs
```

The Worker build checks `runtime_source.mjs` against its sources before writing
`dist/_worker.js` and `dist/_routes.json`. A stale generated receiver fails the
build. Artifacts are deterministic and ignored by Git; no credentials are bundled.

`runtimes.json` is the public deployment registry. Each entry has exactly
`project`, `organization` and `unit`, with positive safe integer IDs and a unique
project and Unit. The project name must be `festapp-measurement-unit-<unit>`.

```sh
bash automation/deploy_measurement_runtimes.sh --dry-run
bash automation/deploy_measurement_runtimes.sh --only festapp-measurement-unit-17
# Alternatively use the environment credential or a dotenv file:
bash automation/deploy_measurement_runtimes.sh --env-file /path/to/private.env
node automation/verify_measurement_runtimes.mjs
node automation/verify_measurement_runtimes.mjs --only festapp-measurement-unit-17
```

Without `--only`, deployment targets every registered runtime. `--dry-run` only
prints the plan, without credentials, builds or network requests. A real release
requires a clean checkout on branch `main`. Tenant branches and detached HEAD are
rejected. After `git fetch origin main`, HEAD must equal `origin/main` exactly.
The release gate requires successful canonical CI for that SHA and runs again
before each upload. A directory lock in the shared Git directory prevents concurrent
runtime releases from linked worktrees. After an interrupted process, confirm that
no deployment is running before removing a stale `measurement-runtime-deploy.lock`.

Wrangler is pinned to **4.159.0** in the script, matching the published
[Cloudflare release](https://github.com/cloudflare/workers-sdk/releases/tag/wrangler%404.159.0).
Use pnpm 11.24.0. `automation/deploy_direct.sh` should also pin Wrangler in a
separate change; this release leaves that script untouched.
`CLOUDFLARE_ACCOUNT_ID` defaults to the same Festapp account as the direct web
deploy. The env file is parsed only for `CLOUDFLARE_API_TOKEN`, never executed.
It accepts optional `export`, quoted values and trailing comments; missing, empty
or malformed values fail without printing the value.

Before upload, the script discovers each project's production branch from
`wrangler pages project list --json`. If absent, it uses the Pages project GET API
with an environment token; without one it stops with instructions. `--branch`
only asserts that the discovered branch matches. Each upload uses that project's
production branch and the canonical SHA through `--commit-hash`.
No project variables or DNS records are changed and no projects are created.
The project's compatibility date remains managed in Cloudflare; this script does
not enforce equality across projects.

The build defines `BUILD_ID` as SHA-256 of the listed source inputs, build tooling
and dependency lockfile in `automation/lib/measurement_build.mjs`. The Worker
returns it as `x-festapp-runtime-build` on `/runtime.js` and on 404 responses.
Verification uses public GET requests to each canonical `/runtime.js`, with a
10 second timeout and four attempts separated by five seconds. Both response-byte
SHA-256 and build ID must match the local sources. Worker-only source changes
therefore cause drift too. Results print bounded hash prefixes and `OK` or `DRIFT`;
unavailability or mismatch exits with status 1. This does not prove environment
configuration, the `/runtime` handshake or collector delivery.

The `measurement-runtime-drift.yml` workflow runs daily at 06:17 UTC and manually.
It installs no packages, uses no secrets and never deploys. Checkout does not
persist credentials. Maintainers should enable GitHub Actions failure notifications.

## Rollback

Before each upload the script resolves `canonical_deployment` from the project
GET API. For an update, it verifies the exact active ID through the deployment
GET API, requiring the same ID, production environment and successful latest
stage. It does not require that ID in the first page of deployment history:
a previous rollback may have activated a much older version. Failed lookups or
invalid metadata stop the release before upload. An API token in the environment
(or loaded with `--env-file`) is required; Wrangler OAuth alone is unsupported.

When the project has no canonical deployment, the script lists production
history with `wrangler pages deployment list --project-name PROJECT --environment production --json`.
Only an empty history permits a first deployment. Missing active metadata with
existing history is ambiguous and stops the release. Before a first upload the
script explicitly reports that rollback is unavailable because no previous version
exists. If upload or verification fails, subsequent projects stop. Keep measurement
disabled, correct the configuration or artifact and rerun deployment and verification
before enabling measurement or releasing the web client. There is no previous
runtime to restore; the script never constructs a rollback command for this case.

For updates, the script prints the previous production ID. If upload or verification fails,
it stops subsequent projects and prints an exact manual curl command for
`POST /accounts/{account}/pages/projects/{project}/deployments/{previous}/rollback`.
The command contains only a literal environment-variable reference for authentication.
This is the documented [Pages rollback API](https://developers.cloudflare.com/api/resources/pages/subresources/projects/subresources/deployments/methods/rollback/);
there is no Pages rollback subcommand in the documented Wrangler command list.

Run the printed command with an authorized environment token, or select the saved
ID in the project's Pages dashboard. Check that the API response reports success.
Verify the canonical runtime against the previous release's sources and build ID
from a separate checkout using `verify_measurement_runtimes.mjs`; current main is
expected to report drift after rollback. Projects already verified earlier in the
loop remain deployed; decide explicitly whether each also needs rollback.
Rollback is manual and is never executed by the deployment script.

For a new organizer, manually create its Cloudflare Pages project with the
production branch selected, then set `ORGANIZATION_ID`, `UNIT_ID`,
`FESTAPP_API_URL` and the secret `SUPABASE_SERVICE_ROLE_KEY` in its production
Worker environment. Keep credentials in Cloudflare, outside this registry.
Add the public project and scope to `runtimes.json`, review the dry run, deploy
and verify the runtime before releasing its web client. Backend policy approval
and measurement enablement remain separate authorized operations.

The release gate ignores only a check named `measurement-runtime-drift` whose
Actions workflow path resolves to `.github/workflows/measurement-runtime-drift.yml`.
It resolves the check-suite ID through the GitHub Actions runs API because
check-run records do not carry the workflow path. Missing suite metadata, an
unavailable lookup or an ambiguous result leaves the check blocking. Required
checks always remain required, including a required drift check. Every other
check still has to pass.
