# Blueprint verified image resources - local evidence

Only the isolated B worktree and owned disposable backend59521/59522 were used.
No cloud, production, provider, email, deployment, commit or push operation ran.

Forward migration `20261019110000_blueprint_verified_image_assets.sql` SHA256:
`961880db9fa1f8992bb3f775c80f8123a6ab0630e80f03dd6db7e65c292cc898`.
The prior191000 aggregate/finance migration is unchanged by this work.

The existing Image Worker processes all backgrounds. The same native Images
binding rasterizes safe SVG to PNG; output bytes determine SHA256, dimensions,
MIME and length. JWT geometry scope plus a one-purpose HMAC records readiness in
one occasion/unit-scoped registry. Existing quota/gallery owners remain single
owners. Public projection contains safe referenced metadata, without proof,
private owner details, credentials or source SVG. The canonical layout save
rejects missing/foreign readiness and mismatched hash/dimensions atomically.

## Actual validation

From `workers/image-worker`, `npm run typecheck --silent` passed and
`npm run test:unit -- --reporter=dot` passed12 files /110 tests. The focused
concurrent duplicate test lets one request register successfully while another
same-key acknowledgement fails, proving ready bytes survive failure cleanup.
It also checks separated occasion/unit attestation scope and unsafe SVG inputs.
These boundary tests are mocks; the following pipeline proof uses actual IO.

The owned bridge ran with:

```sh
node workers/image-worker/scripts/blueprint_local_bridge.mjs \
  --env-file /Users/miakh/source/festapp-blueprint-b-e2e-20261019/private-worker.env \
  --api http://127.0.0.1:59521 --port 59525 \
  --state-dir /tmp/festapp-blueprint-image-local
```

The mode0600 env file contains local anon configuration and the dedicated HMAC
key matching local vault `blueprint_image_processing_v1`. No key was copied into
this evidence. The bridge allows only canonical RPC requests rewritten to the
owned API; all other outbound network is rejected. `/health` identifies
`festapp-blueprint-b-image-local` and `remote:false`.

```sh
BLUEPRINT_WORKER_ENV=/Users/miakh/source/festapp-blueprint-b-e2e-20261019/private-worker.env \
BLUEPRINT_OCCASION_LINK=bp-fixture-9f5c97e9-2364-418b-b8a5-27767f6bb442 \
node workers/image-worker/scripts/blueprint_local_images.mjs
```

Actual results: occasion PNG320x180/1928 bytes, occasion SVG rasterized to
PNG320x180/3804 bytes, unit PNG320x180/1928 bytes. Every public R2 response matched
manifest SHA256, raster signature, dimensions and byte length. Existing receipt
save, persisted read and remove passed. An SVG containing script was rejected.
Fixtures are `workers/image-worker/tests/fixtures/blueprint-raster.png` and
`blueprint-safe.svg`. This was actual Miniflare5 Images with native Sharp/libvips,
not a mock or remote Cloudflare call.

The local SQL command was:

```sh
psql 'postgresql://supabase_admin:postgres@127.0.0.1:59522/postgres?sslmode=disable' \
  -Xq -v ON_ERROR_STOP=1 -f database/tests/blueprint/image_resources_test.sql
```

One rollback scenario passed forged/stale HMAC rejection, foreign asset save
rejection, unchanged revision/bindings on rejected saves, hash/dimension/crop
rejection, safe public form projection, protected immutable deletion, actual
existing occasion copy with scoped ready resources and no holds/tickets, unit
wizard resource association, foreign-unit rejection and restricted grants.
It requires previously processed real registry assets and does not fabricate
readiness or hash claims. Fresh DDL was also proven in one guarded transaction:
owned marker checked, task asset table dropped, entire forward applied, two
scoped unique indexes checked, rollback restored all live fixture state.
The final forward was applied and marked in the owned migration ledger.

## Limits

The local Images emulator supports a subset of remote transform features; no
production service activation or remote provider execution was attempted.
Ambiguous registration failures retain bounded immutable blobs (800 KiB and
existing storage admission), because deleting a shared hash may destroy another
request's successful resource. Automatic orphan reconciliation is not implemented.
Full UI/wizard/browser evidence is coordinator-owned. This report proves actual
backend processing/persistence, not the coordinator's rendered UI checks.

Focused static-artwork proof: `BLUEPRINT_ANIMATED_ONLY=1` with the same local
script processed real two-frame GIF and animated WebP fixtures through actual
Images/R2/SQL. They returned single-frame PNG2x2 (95 and98 bytes), with exact
manifest hashes and raster metadata. Blueprint already shared the ticket
static-artwork policy; focused unit assertions now explicitly cover both source
formats. Targeted upload-policy suite:15 passed; typecheck passed. No SQL changed.
