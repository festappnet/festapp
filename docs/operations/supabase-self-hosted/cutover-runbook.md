# Festapp self-hosted Supabase cutover runbook

This runbook is a fail-closed gate. Rehearsal completion does not authorize a
production cutover, DNS change, client activation or cloud deletion.

## 1. Release and writer adoption gate

Inventory every writer and reader: Flutter mobile builds, App Store and Google
Play releases, web tenants, admin surfaces, Edge Functions, cron jobs, payment
and bank callbacks, e-mail/image workers and manual scripts. For each entry,
record its deployed version, canonical endpoint capability, write path, owner
and rollback behavior.

The authoritative client inventory and per-lane evidence contract is
[`client-cutover-release-matrix-2026-08-28.md`](client-cutover-release-matrix-2026-08-28.md).
Cutover is blocked until every row is closed; an unlisted active writer is a
failed inventory, not an implicit exception.

Before cutover:

- approved iOS and Android builds must be published with canonical endpoint
  support before the migration window;
- the enforced minimum version must exclude every build that could write to an
  obsolete endpoint or bypass the journal;
- old builds may remain only if telemetry proves they are compatible and either
  read-only during the window or use the covered journaled RPC path;
- every web/admin/Function/worker deployment must be pinned and staged with the
  same endpoint contract;
- store approval alone is not adoption evidence: active-version telemetry and
  direct-DML telemetry must both pass;
- any unknown writer, unsupported active build or direct-DML bypass is a hard
  no-go. Choose a full maintenance freeze if journal coverage cannot be proven.

Run the repository-only gate before requesting any production window:

```bash
node automation/hetzner-supabase/merge/repository-cutover-preflight.mjs
```

It requires clean synchronized `main`, every active production ref containing
that `main`, coherent immutable runtime pins, zero unknown tenant refs and zero
unclassified repository writer entrypoints. Its `repository_ready` result does
not close the separately listed operational blockers or authorize a freeze,
snapshot, promotion or activation.

The exact runtime surface contract is
`automation/hetzner-supabase/merge/runtime-writer-policy.json`. It covers every
Edge Function and Worker entrypoint and fails closed when source adds an
unclassified one. `sync-worker` has a checked-in deploy manifest. The mutating
`sync-publisher` uses `wrangler.example.toml`; create its ignored
`wrangler.toml` only from fresh final-merge evidence, replace the scope
placeholder with final canonical occasion IDs, and verify its canonical URL
before deployment. Never reuse the historical cloud-`a` scope `643`.

Do not carry the historical blanket `--no-verify-jwt` deployment practice into
canonical production. `bank-mail-parser` now requires an exact-topic AWS SNS
Signature Version 2 proof and constrains certificate/confirmation URLs;
`notify` requires a constant-time bearer proof shared with a Vault-backed
database trigger; `fetch-http-data` requires an occasion editor and constrains
DNS, redirects, content type and response size. Live provider/Vault canaries
remain activation gates. `instance-install` is an operator bootstrap surface
that executes remote SQL and is explicitly excluded from canonical production.

Auth continuity is a separate hard gate. Every imported user UUID and
`encrypted_password` value must match the fresh source snapshot exactly; hashes
must never be re-created or replaced with temporary passwords. Provider
identities, MFA records, sessions and refresh tokens belonging to retained UUIDs
must reconcile with zero unexplained missing or changed rows. An explicitly
approved identity merge may discard the superseded source session only when its
exact count is recorded and ordinary reauthentication is accepted. The current
known exception is the five approved Slunovrat identity merges; their source
sessions were intentionally not imported. Exercise password, OAuth and
refresh-token login canaries against the target before routing users. Any other
mismatch for one account is a no-go. Existing access-JWT continuity must be
tested independently because a
JWT signing-key change can invalidate an already-issued access token even when
the password hash and refresh token are preserved perfectly.

### Client release contract

The release source remains on the cloud endpoint until a separately reviewed
tenant configuration changes it. A self-hosted client release must set all four
values together in `automation/project.conf`:

- `SUPABASE_URL=https://api.festapp.net` (or the isolated rehearsal origin);
- the matching public `SUPABASE_ANON_KEY`;
- a non-empty, never-before-released `PUSH_APP_GENERATION` so Flutter clears
  legacy ID caches before reading the new canonical database;
- an explicit `SUPABASE_AUTH_STORAGE_KEY` retained from the previous release.
  The stable key is intentional: the web client exchanges the preserved refresh
  token against the new Auth service before any rights or business query, then
  stores the newly signed access token under the same namespace.

Run `automation/apply_config.sh` in a clean release worktree and then run:

```bash
FESTAPP_RELEASE_MANIFEST=/private/path/config.json \
FESTAPP_CANONICAL_CUTOVER_RELEASE=1 \
  node automation/release/client_cutover_preflight.mjs --require-canonical-cutover
```

For a product with both web and store lanes, one external schema-2 manifest
must own every platform. Keep that tenant-specific manifest outside this public
repository and prove the shared boundary with:

```bash
FESTAPP_RELEASE_MANIFEST=/private/path/config.json \
  node automation/release/release_lane_preflight.mjs --web
FESTAPP_RELEASE_MANIFEST=/private/path/config.json \
  node automation/release/release_lane_preflight.mjs --mobile
```

The mobile gate additionally binds both package identities, the production
branch and the read-only store preflight. A schema-1 evidence file is not a
publishing manifest. Store state, signing authority, reviewer data and
tenant-specific release evidence belong in the private release repository;
only generic validation contracts belong here.

For a self-hosted release, the private manifest must contain a `backend` object
with `mode: "self-hosted"`, `releaseIntent: "canonical-cutover"`,
`supabaseOrigin`, `anonKeySha256`, `installationGeneration`, and
`authStorageKey`, the post-merge `organizationId`, plus `authSiteUrl`, the exact browser-first
`authRedirectUrls`, and `allowedWebOrigins`. Only the public origins, key
digest, generation, and storage namespace are recorded; the public key itself
is not copied into evidence.
The same object must contain `sessionTransition` with the fixed
`refresh-or-reauth` strategy, rejection of legacy access tokens after cutover,
local sign-out on a terminal refresh failure, explicit permission for the
source-a cohort to reauthenticate normally, and the SHA-256 of a private
refresh-canary evidence file. This contract is necessary because the two legacy
cloud projects used different HS256 secrets and their old tokens have no `kid`;
one canonical GoTrue endpoint cannot verify both access-token families without
reintroducing a second trust path. Imported refresh tokens are exchanged first.
Only `refresh_token_not_found` or `refresh_token_already_used` clears the local
session; network failures remain retryable and preserve offline identity.
The organization ID is equally mandatory because deterministic merge allocation
can remap it; carrying the cloud ID into a target client returns a semantically
valid HTTP 200 with the wrong organization or a 404.
This applies independently to every tenant overlay. In the 2026-08-28
Slunovrat rehearsal, source organization `1` mapped to canonical organization
`19`; the legacy value must not be copied into web, iOS, or Android config.

The validated source-`a` organization mappings for the first web transition
wave are authoritative release inputs:

| Tenant | Legacy organization | Canonical organization |
| --- | ---: | ---: |
| CSM Ostrava | 9 | 12 |
| Člověk a víra | 3 | 6 |
| Hvězda Mořská | 4 | 7 |

The transition profile must compile both values and switch organization,
origin and public key atomically. A completed bundle is accepted only when it
contains the SHA-256 fingerprint of that complete canonical profile.

### Store release before the write cutover

A tenant that must publish mobile binaries before the production freeze uses
the one-way backend activation contract instead of shipping a dual writer. Its
pre-cutover `project.conf` keeps `SUPABASE_URL` and `SUPABASE_ANON_KEY` on the
legacy cloud and adds:

```text
BACKEND_ACTIVATION_TENANT_ID=<tenant-slug>
BACKEND_ACTIVATION_PHASE=legacy
BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL=https://api.festapp.net
BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY=<canonical-public-anon-key>
BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID=<mapped-target-organization-id>
```

`apply_config.sh` emits `backend-activation.json` and bakes the SHA-256 of the
exact future canonical document into Flutter and the vanilla web client. A
client can therefore select only its compiled legacy backend or its compiled
canonical backend profile (origin, public key and mapped organization ID); the
remote document cannot supply any of those values. Missing,
modified and legacy documents select legacy. Once the exact canonical document
is observed, a local monotonic marker prevents rollback to the old writer.
Every process resolves this choice before constructing Supabase, and Flutter
uses the explicit legacy `SUPABASE_AUTH_STORAGE_KEY` on both origins.

The corresponding private release manifest must record
`backend.activation.strategy: "pinned-one-way-manifest"`, the tenant, current
phase, manifest URL, canonical document and anon-key SHA-256 values, stable auth
storage key, canonical origin, and `finalRefreshTokenDeltaRequired: true`.
It must also record `canonicalOrganizationId`, proven from the final ID mapping.
The common release preflight compares this object with configuration, generated
clients and both emitted public manifest copies.

At the operational cutover, do not activate while the legacy source still
accepts uncontrolled writes. In one guarded sequence:

1. freeze legacy writes and prove the DML/write-authority gate;
2. export and import the final business, Auth session/refresh-token, and Storage
   delta, then pass the canonical refresh-session canary;
3. start and validate the canonical runtime internally, while public client
   routing still resolves to the frozen legacy backend;
4. open canonical write authority immediately before activation; this makes
   the target writable but does not itself route any public client;
5. keep the transition release's compiled `SUPABASE_URL`/key on legacy, change
   only `BACKEND_ACTIVATION_PHASE=canonical`, rerun `apply_config.sh`, and
   atomically deploy the web output containing the exact canonical activation
   document; the pinned resolver, not a second compiled default, owns this switch;
6. verify web/iOS/Android cold starts, writes and session refresh against only
   the canonical endpoint.

An already running native process cannot safely replace its Supabase singleton.
Once the legacy source is frozen its late write must fail, never be silently
lost. Backgrounding and foregrounding alone do not switch an existing process;
the app must be fully restarted, and only the next cold start resolves the
canonical activation. That cold start also runs a distinct canonical
installation generation before reading cached occasion IDs, because the
organization and occasion numeric IDs may have been remapped. Normal
installations retain their session because refresh
tokens and the storage namespace migrate unchanged. Only a token already
expired, revoked, terminally consumed, or belonging to an approved merged
identity follows ordinary reauthentication/local-sign-out policy.

The resolver remains a permanent architectural boundary, but not an arbitrary
remote multi-backend switch. This release permits only its compiled legacy
backend and one cryptographically pinned, monotonic canonical activation. After
decommission evidence passes, remove the legacy URL/key and rollback branch,
while retaining the resolver interface for a future versioned migration. Any
future endpoint generation requires a new client release that pins the new
origin, public-key digest, session policy and activation-document digest; a
remote document is never allowed to introduce an uncompiled endpoint or key.

Set `FESTAPP_CANONICAL_CUTOVER_RELEASE=1` for the web, Android and iOS release
builders. That flag accepts either a direct self-hosted manifest or the complete
pinned one-way transition contract; it rejects a plain legacy-cloud manifest.
The same preflight runs before compilation in all three builders. The completed web
bundle verifier additionally proves that the vanilla client, Flutter bundle,
and auth bridge contain the exact configured origin/key/namespace and no stale
Supabase Cloud origin.

For a signed iOS rehearsal artifact without an App Store mutation, run the
build-only path in a clean release worktree:

```bash
FESTAPP_RELEASE_MANIFEST=/private/path/config.json \
FESTAPP_IOS_SIGNING_DIR=/private/path/signing \
FESTAPP_CANONICAL_CUTOVER_RELEASE=1 \
  automation/release/ios_build_candidate.sh
```

It verifies bundle/version/certificate and artifact SHA-256 and contains no
upload implementation. Store upload and release remain separate approvals.

The native callback contract remains browser-first during this migration:
password recovery and transfer complete on the deployed HTTPS web origin.
Neither a Supabase hostname nor an unverified Android App Link is treated as a
native callback. Adding native Android/iOS callback routing is a separate public
contract requiring matching `assetlinks.json`, AASA, store builds, and device
proof; it is not silently enabled by the database cutover.

The public `send-reset-password-link` Function is deployed only after migration
`20260828090000_harden_password_reset_delivery.sql`. Its runtime must receive
`FESTAPP_ALLOWED_WEB_ORIGINS` equal to the manifest allowlist. The canonical
proxy must overwrite the client-IP forwarding headers and prevent direct-origin
bypass; the Function then enforces atomic 15-minute source and account limits,
returns non-enumerating responses, and writes reset tokens atomically.

## 2. Freshness gate

The encrypted exports produced during rehearsal are test inputs only and must
never be promoted as final production state.

1. Take fresh independent backups of every source registered in
   `automation/hetzner-supabase/merge/source-registry.json` (`default`, `a`, and
   `slunovrat` at the time of this runbook).
2. Freeze schema/config changes.
3. Start the approved maintenance freeze or record the source journal position.
4. Before acquiring the final Auth snapshot, freeze or route the old web/Auth
   refresh traffic so it cannot rotate a cloud refresh token. This gate must be
   active before snapshot acquisition starts and remain active until target
   activation or rollback.
5. Produce a new encrypted `default` export with source assertion and manifest.
6. Produce a new encrypted `a` snapshot at a recorded journal position.
7. Import using the exact twice-rehearsed immutable transformation version.
8. Replay `a` changes through the idempotent forwarder until the applied
   position equals the final source marker.
9. Under the final write freeze, verify zero journal lag, zero dead letters,
   zero old-owner transactions and matching table/tenant/business invariants.

If a journal is not complete for every writer, replace steps 3–9 with a full
write freeze lasting through both exports, import, validation and endpoint
activation. A best-effort delta query is not an acceptable substitute.

The mode is fail-closed and is recorded twice, before snapshot acquisition and
again at the final marker. Run
`automation/hetzner-supabase/merge/cutover-mode-gate.mjs` with a private,
fresh evidence file and `--phase=pre-snapshot`, then with
`--phase=final-marker`. `journal-hybrid` is accepted only from a global writer
inventory with 100% journal coverage; the existing Flutter-only seam report can
never authorize it. `full-freeze` requires application, Auth refresh, Storage,
Functions, cron, webhook and manual writer lanes to be blocked, zero active
mutating source sessions, target writes and external effects disabled, and the
snapshot timestamp after both write and Auth-refresh freezes. The final-marker
gate additionally requires both source markers and passing conflict/FK
validation. Decision files are append-only private evidence outside Git; the
gate itself performs no production mutation.

For this migration, `full-freeze` is the selected production mode unless a new
global writer inventory later proves the stricter hybrid contract. The final
marker cannot be generated honestly before the real production freeze; passing
the synthetic gate tests is tooling proof, not cutover authorization.

## 3. Activation order

### Runtime promotion boundary

The database-facing runtime has one production promotion entry point:
`automation/hetzner-supabase/runtime/promote-production-runtime.sh`. It is not
a client activation or write-authority command. It fails closed unless the
timestamped target contains exactly the `default`, `a` and `slunovrat` imports
from the installed immutable source registry, every validation row passes, and
the private inputs bind the exact source/reference registry digests to a
full-freeze final marker and matching encrypted backup/isolated-restore result.

Before the first production run on an existing host, install the current
runtime scripts and additively upgrade both registries:

```bash
FESTAPP_RUNTIME_UPGRADE_ACK=bootstrap-missing-production-runtime-registries \
  automation/hetzner-supabase/runtime/upgrade-installed-production-runtime.sh

# Subsequent registry/tooling updates:
FESTAPP_RUNTIME_UPGRADE_ACK=upgrade-installed-production-runtime-additively \
  automation/hetzner-supabase/runtime/upgrade-installed-production-runtime.sh
```

The bootstrap acknowledgement is accepted only when both installed registries
are absent. A mixed one-present/one-missing state is rejected. Subsequent runs
are idempotent, permit new source aliases/reference rules, reject mutation or
removal of an installed entry, verify all installed runtime dependencies, and
leave both installed JSON files root-owned and mode `0444`. Generate the
semantic digests recorded in the private production runtime config with:

```bash
node automation/hetzner-supabase/runtime/validate-production-promotion.mjs \
  --digest-json=/opt/festapp-supabase/docker/festapp-source-registry.json
node automation/hetzner-supabase/runtime/validate-production-promotion.mjs \
  --digest-json=/opt/festapp-supabase/docker/festapp-reference-registry.json
```

The mode-`0600` production runtime config must define the canonical
`api.festapp.net` external URLs, Auth site/origin/redirect allowlists, and
exactly one canary for every tenant in the source registry. Each tenant canary
pins its canonical organization and occasion plus the SHA-256 of the still-
legacy `backend-activation.json`. Promotion recreates only DB/API-facing
services, verifies their target database, checks Auth/REST/Storage/Realtime and
every tenant web/activation/occasion canary, and records a timestamped rollback
`.env`. It never publishes a canonical activation document, changes DNS, grants
database rights or opens external side effects. Those remain later, separately
approved steps in the activation order below.

1. Keep target side effects disabled during import and replay.
2. Verify Auth, rights, orders/tickets/QR, finance, Storage, Realtime, Functions,
   images and per-tenant isolation against the final data.
   Verify notification credentials are absent from organization JSON/admin RPC,
   present only behind the service-role delivery-config RPC, and backed by a
   completed provider rotation/revocation receipt.
3. Switch server-side writers, callbacks and workers to the canonical endpoint.
4. Activate the already-published client configuration/minimum version.
5. Switch the Cloudflare front door only after origin health and credentials
   pass; Cloudflare does not become the relational write path.
6. Enable target side effects and run synthetic plus real canaries with receipt
   checks.
7. Open writes only after the final marker, validation and canaries pass.

## 4. Stop and rollback boundary

Stop before activation on any non-zero lag, dead letter, unresolved conflict,
orphan FK, missing Storage object, Auth outage, unsupported active client,
duplicate external effect, capacity breach or unknown writer.

Before target writes open, rollback means restoring routing to the still-frozen
cloud source. After target writes open, the target remains the single owner and
recovery uses target restore/forward repair; cloud writes must not be reopened.
Both clouds remain read-only for the approved retention window. Nothing is
deleted without a later explicit destructive approval and completed deletion
ledger.
