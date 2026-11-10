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
`SameSite=None;Secure;Partitioned` before loading the container so Google collection works in
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
optional and only reports the choice. Automatic reading requires the Unit opt-in `measurement_consent_bridge`, disabled
by default, including for existing organizers. Enabling it confirms that the host
website and form have the same controller and the website banner explicitly
covers the embedded vstupenky.online form, purposes, GTM services, `*.pages.dev`
runtime and Festapp as processor. The organizer retains CMP consent evidence.
The switch changes processing_revision and is included in the manifest.
Marketing requires explicit grants for all three ad consent types; missing types
mean denied. TCF presence (`__tcfapi`) always denies marketing without reading TCF;
analytics follows Consent Mode. ICS is polled every 250 ms, Arguments commands in
dataLayer every second with incremental scanning. Arrays are ignored. A withdrawal
can race a purchase within that 250 ms or 1 s window; browser suspension can extend
it. Delivered data cannot be recalled. Website mode unsubscribes polling and Unit
mode reconnects. A changed Unit or processing revision stays denied until a new
binding. See the full host consent contract for banner and adapter requirements.
An explicit adapter replaces that source, including after disconnection. Website
transport keeps consent in the host's GTM. See the
[host consent contract](../../docs/integrations/form-datalayer.md#runtime-consent-and-transport).
For a revision-aware explicit source:

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
release separately before `automation/deploy_direct.sh`. The web deploy verifies
the selected organization's receivers before build and again before upload. A
failed receiver blocks a new release; it does not stop the running checkout.

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

`runtimes.json` is the public deployment registry. Each entry has
`project`, `organization` and `unit`, with an optional `probe: {form, parent}`
containing an eligible public form link and approved HTTPS parent origin. No
private form data or credentials belong here. IDs are positive safe integers with a unique
project and Unit. The project name must be `festapp-measurement-unit-<unit>`.

```sh
bash automation/deploy_measurement_runtimes.sh --dry-run --only festapp-measurement-unit-17
bash automation/deploy_measurement_runtimes.sh --only festapp-measurement-unit-17 --wrangler-oauth
# Alternatively use the environment credential or a dotenv file:
bash automation/deploy_measurement_runtimes.sh --only festapp-measurement-unit-17 --env-file /path/to/private.env
node automation/verify_measurement_runtimes.mjs
node automation/verify_measurement_runtimes.mjs --only festapp-measurement-unit-17
```

Deployment requires explicit `--only`; it never chooses all organizers implicitly. `--dry-run` only
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
separate change; this release preserves that version choice and adds receiver gates.
`CLOUDFLARE_ACCOUNT_ID` defaults to the same Festapp account as the direct web
deploy. The env file is parsed only for `CLOUDFLARE_API_TOKEN`, never executed.
It accepts optional `export`, quoted values and trailing comments; missing, empty
or malformed values fail without printing the value.

Before upload, the script discovers each project's production branch from
`wrangler pages project list --json`. If absent, it uses the Pages project GET API
with the explicitly selected bearer credential. `--wrangler-oauth` reuses
the existing encrypted Wrangler login; its supported `auth token --json` output
is validated and held in process memory for Pages API requests. Stale environment
tokens are unset first, and no new credential file or login is created.
`--wrangler-oauth` and `--env-file` are mutually exclusive. `--branch`
only asserts that the discovered branch matches. Each upload uses that project's
production branch and the canonical SHA through `--commit-hash`.
Every project API lookup validates production plain-text ORGANIZATION_ID,
UNIT_ID and FESTAPP_API_URL against the selected registry entry and canonical
backend before upload. Raw bindings and secrets never leave the sanitizer.
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
unavailability or mismatch exits with status 1. Scope headers also prove the
live organization, Unit and canonical backend setting. A registered probe fetches
`/runtime` and checks its actual backend-generated manifest, scope, form, parent,
CSP and build identity, without executing any tag or conversion. This does not
prove collector delivery. `--require-probe` rejects incomplete onboarding entries.
`--organization ID` selects only that tenant organization; an empty selection is
valid. Web deployment requires this mode automatically. If a public probe form
closes, replace it with another eligible public form through a reviewed registry
update; do not reopen the form or change customer policy just to pass a probe.

The `measurement-runtime-drift.yml` workflow runs daily at 06:17 UTC and manually.
It installs no packages, uses no secrets and never deploys. Checkout does not
persist credentials. Maintainers should enable GitHub Actions failure notifications.

## Rollback

Before each upload the script resolves `canonical_deployment` from the project
GET API. For an update, it verifies the exact active ID through the deployment
GET API, requiring the same ID, production environment and successful latest
stage. It does not require that ID in the first page of deployment history:
a previous rollback may have activated a much older version. Failed lookups or
invalid metadata stop the release before upload. A bearer credential is required: export an API token, use `--env-file`, or
explicitly select the existing encrypted login with `--wrangler-oauth`.

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

Run the printed command with an authorized bearer token held in the environment, or select the saved
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
and verify the runtime. Initial provisioning may omit the probe, but a web release
requires an eligible public-form probe for every registered runtime of its
organization. Verify stored DB runtime origin and approved parent against the
registry before enrollment; never copy a service credential into that registry. Backend policy approval
and measurement enablement remain separate authorized operations.

The release gate ignores only a check named `measurement-runtime-drift` whose
Actions workflow path resolves to `.github/workflows/measurement-runtime-drift.yml`.
It resolves the check-suite ID through the GitHub Actions runs API because
check-run records do not carry the workflow path. Missing suite metadata, an
unavailable lookup or an ambiguous result leaves the check blocking. Required
checks always remain required, including a required drift check. Every other
check still has to pass.
## Consent storage exceptions and keyboard behavior

All seven Consent Mode types are explicit. `security_storage` and
`functionality_storage` remain `granted`, including before a choice and after
Decline. Organizer tags requiring `functionality_storage` therefore run without
consent. Analytics storage follows analytics; ad storage, ad user data, ad
personalization and personalization storage follow marketing.
Mapping content personalization (`personalization_storage`) to marketing is an
intentional organizer choice; the organizer's privacy information must describe
this purpose together with advertising.

The initial central notice is blocking: Escape focuses the notice without saving
a choice or closing it. Decline is available for a decision without optional
consent. Escape in Settings discards the draft. Reopened Settings always offer
Decline; after a saved decision focus returns to the floating Consent settings
button. The button is fixed at the bottom left, with reserved scroll clearance.
Custom notice text always retains a fixed explanation of how to change consent.

## Processing revision lifecycle

All consent sources share the host `bindChoice` owner. An automatic choice is
bound to its first processing revision. After changing processing configuration,
reload the host page to create a new frame record; another CMP accept click
alone does not authorize the replacement revision. Unknown/mixed manifests
remain denied. Deploy the new receiver before exposing the bridge setting.

## Host identity and direct linker signals

Unit mode embeds can receive optional, purpose scoped raw host cookies: `_ga`
and `_ga_<ID>` with analytics, and `_gcl_aw`, `_gcl_gb`, `_gcl_au`, `_fbp`, `_fbc`
with marketing. Missing choice transfers nothing. The shared validator limits
names, characters, values to 512 characters and snapshots to ten cookies.
Before each copy bootstrap deletes all host-only/domain and partitioned/ordinary
variants at Path=/, then writes with `Domain=location.hostname; Path=/;
SameSite=None; Secure; Partitioned`. Readback requires a single matching value;
ambiguous or blocked GA storage uses a GA1 client ID fallback. A host `_ga`
snapshot with analytics consent removes frame `_ga_<ID>` cookies absent
from the snapshot only when the existing `_ga` identifies a different client.
An unchanged client preserves sessions for other measurement IDs. Revocation deletes all four variants, including tag cookies.
Identity refresh alone copies cookies silently without emitting a consent update.
A loaded tag may retain its client ID in memory; no undocumented gtag reset is used.

GA copies use two years. Timestamped `GCL.<seconds>` and `_fbc`
`fb.1.<milliseconds>` copies use the remaining part of 90 days from their timestamp,
capped at 90 days; expired values are deleted. Other advertising cookies use 90
days because `document.cookie` exposes no original expiry. An unknown shorter
host expiry cannot be preserved. `_gcl_aw` never populates URL gclid. On marketing
revocation bootstrap removes all campaign click IDs from the frame URL and
`_gcl_*` localStorage entries, including `_gcl_ls`. Click IDs are restored from
the validated context only after marketing is granted again.
GA continuity requires the same G- measurement ID on website and organizer tags;
browser storage policy and partitioning support can prevent continuity.

Direct visits pass validated `_gl` (up to 2048 characters) only with both
analytics and marketing consent because it can carry advertising identity; revocation removes
it from the frame URL. `gtm_debug` remains available independently of consent.
Both signals stay outside dataLayer and page_location; embeds exclude both.
GTM Preview in a cross-site frame does not connect reliably and is not supported.
Protocol 3 remains unchanged; the manifest includes `measurement_consent_bridge`.
Deploy the Unit Worker/runtime before the helper and client: a new client with
an old Worker and the bridge enabled rejects its manifest and stops measurement.
Older receivers ignore optional hostIdentity. See the [Attribution contract](../../docs/integrations/form-datalayer.md#attribution-and-gtm-profile).

Known limitation: cookies copied at Path=/ can accompany requests for `/runtime`
and `/runtime.js` in the Cookie header before bootstrap can delete them after
revocation. This is the same transport limitation as ordinary GA cookies on a
website. The Worker neither reads nor logs cookies and does not forward incoming
request headers to the configuration RPC. Deletion cannot recall requests or data
already sent, nor clear identifiers held in a loaded third-party tag's memory.

After direct runtime initialization the form removes `_gl` from its address with
`history.replaceState`, retaining it in memory for a later consent decision.
An embed adopting website identity omits the website referrer from event context.
Configure both the website and checkout domains in GA4 cross-domain settings;
review unwanted referrals as well. Set `cookie_flags` in the Google tag settings
too and verify actual tag behavior in browsers. Third-party advertising cookies
and identifiers held in a loaded tag cannot be removed by this runtime.
