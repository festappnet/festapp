# Image delivery without per-view Worker charges

Date: 2026-08-23
Status: Ready for gated execution
Verification: standard

## Outcome

Public Festapp images are served from project-specific, public-only R2 buckets through R2 custom domains and Cloudflare Cache, without invoking `festapp-image-worker` for every view. Authenticated upload, delete, private read and signing remain behind a small control-plane Worker on a separate hostname. The public URL contract remains `img.festapp.net` for the default project and `a.img.festapp.net` for project A, while responsive variants use a bounded Cloudflare Images URL contract.

The expected billing result is that ordinary image views stop contributing Worker Standard Requests and cached views stop contributing R2 Class B operations. Image transformations have a bounded variant cardinality and are measured against Cloudflare Images pricing before production enablement. As verified from official documentation on 2026-08-23, the Images Free plan allows 5,000 unique transformations per month and then rejects new variants rather than billing them; the Paid plan bills additional unique transformations at $0.50 per 1,000. Live account entitlement and the expected corpus-specific count remain Wave 0 gates.

## Scope

### In scope

- `workers/image-worker` routing, authentication, public/private bucket topology, upload, delete, signing and transformation behavior.
- Flutter and web image URL generation and upload/delete clients.
- R2 custom domains, Cache Rules, Smart Tiered Cache, Images transformations, zone WAF/source-origin restrictions and staged hostname cutover.
- Migration of any existing `private/` objects out of buckets that will become public.
- Compatibility gating for already-installed clients that still call `/upload` and `/delete` on `img.festapp.net`.
- Cost, privacy, cache-purge and rollback evidence.

### Out of scope

- Reworking unrelated sync Workers or Supabase image-table business semantics.
- Re-encoding the complete historical image corpus in advance.
- Changing visual design or image placement.
- Changing the existing project-wide `editor on any occasion` authorization semantics for generic `private/` objects; this plan isolates their storage and project routing but does not invent ownership metadata that does not exist today.
- Creating project B/C infrastructure unless a production inventory proves those projects exist and require it.

## Constraints

- Billing, authentication, privacy and production routing require standard verification.
- Production bucket creation, DNS/custom-domain changes, Cloudflare Images activation, deploys and data migration require separate operator authority.
- Existing unrelated worktree changes must be preserved.
- A Worker cache alone is not the target: Cloudflare documents that requests reaching Workers remain billed even when the Workers Cache API serves a hit.
- An R2 custom domain makes every object in its bucket publicly addressable. A bucket containing `private/` keys must never be attached to a public custom domain.
- No permanent V1/V2 control-plane compatibility implementation may remain after the client adoption gate closes.
- Paid Cloudflare Images activation or any change from Free to Paid requires explicit monetary approval; code must remain safe when the Free-plan unique-transformation limit is reached.
- Client helpers are not a cost-control boundary. URL transformations may be enabled only after a zone rule demonstrably rejects every noncanonical option set and disallowed source origin without invoking a user Worker.

## Current-state evidence

| Claim | Evidence | Consequence |
|---|---|---|
| The Jul 17-Aug 16 invoice rose to $23.09 from the prior $5 base. It contains 43.73M Worker requests (33.73M billable, $10.20), 26.58M R2 Class B operations (16.58M billable, $6.12), 96.5 GB-month R2 storage ($1.31 billed) and $0.46 CPU. | Cloudflare invoice `IN-75620995` and account usage inspected 2026-08-23 | Request volume, not CPU, is the main avoidable charge. |
| `festapp-image-worker` produced 23,924,500 requests in the measured Jul 17-Aug 17 interval. | Cloudflare Workers GraphQL account aggregate inspected 2026-08-23 | Image delivery is the largest identified Worker request source. |
| A public `HEAD` performs one R2 `head`; a normal public `GET` performs one R2 `get`, and a failed transform fallback can perform a second `get`. No Cache API lookup exists. | `workers/image-worker/src/serve-public.ts: handleServePublic` | Repeated views invoke a Worker and at least one Class B operation even for immutable objects. |
| Browser cache headers are long-lived, but they do not create an account-level edge cache shared across users. | `workers/image-worker/src/serve-public.ts: handlePublicServe` response construction | Client caching cannot prevent cold devices and crawlers from repeating Worker/R2 work. |
| Uploads create unique timestamp/random keys under `images/{occasionId}` or `images/unit-{unitId}` and store the returned absolute hostname in `public.images.link`. | `workers/image-worker/src/upload.ts: handleUpload`; `database/functions/others/add_image_record.sql` | Public images are naturally immutable and suitable for cache-forever delivery; retaining hostnames avoids a DB rewrite. |
| Public and explicit `private/` objects currently use the same resolved project bucket. | `workers/image-worker/src/upload.ts`; `workers/image-worker/src/serve-private.ts`; `workers/image-worker/src/delete.ts` | Direct-public R2 cutover is blocked until private objects are separated and proven absent. |
| `img.festapp.net` maps to `IMAGES_BUCKET` / `festapp-images`; `a.img.festapp.net` maps to `IMAGES_BUCKET_A` / `festapp-images-a`. Both run the same Worker code. | `workers/image-worker/src/bucket.ts: projects`; `workers/image-worker/wrangler.toml` | The hostnames separate Supabase projects and data buckets; they are not size or transformation variants. |
| Upload/delete routing trusts caller-supplied `supabaseUrl` and `anonKey`; an unknown project silently falls back to the default bucket. | `workers/image-worker/src/auth.ts: resolveSupabaseAuth`; `workers/image-worker/src/bucket.ts: resolveBucket` | Control-plane project identity must be allowlisted and unknown routing must fail closed. |
| Presigning hardcodes the `festapp-images` bucket. | `workers/image-worker/src/presigned.ts: handlePresign` | Private URLs for project A cannot be correct under the intended per-project topology. |
| The Worker owns `/upload`, `/delete`, `/private/*`, `/presign/*` and all public GETs on the same hostnames. | `workers/image-worker/src/index.ts` | The public and authenticated planes cannot be switched independently today. |
| Flutter uses `AppConfig.imageWorkerUrl` for upload/delete and stored public URLs for display; transform helpers append arbitrary `w/f/q` query parameters. | `lib/app_config.dart`; `lib/components/images/db_images.dart`; `lib/components/images/image_url_helper.dart` | A new control origin and a canonical bounded transform builder must ship before hostname cutover. |
| Web uses the same query-style transform contract. | `web_client/src/utils/image_url_helper.js`; `web_client/src/components/occasion/occasion_card.js` | Both clients must migrate together and old helper syntax must be deleted. |
| Wrangler declares B/C bindings in types/routing code but provisions only default/A routes and bindings. | `workers/image-worker/src/types.ts`; `workers/image-worker/src/bucket.ts`; `workers/image-worker/wrangler.toml` | Phantom projects and default fallback make misrouting possible and must be reconciled. |
| `imageWorkerUrl` is hard-coded in Flutter and is not propagated from `automation/project.conf`; `automation/apply_config.sh` and its fixture test know nothing about an image control origin or project ID. | `lib/app_config.dart`; `automation/apply_config.sh`; `automation/tests/apply_config.test.sh`; `automation/tests/fixtures/project.conf` | `IMAGE_API_URL` and `IMAGE_PROJECT_ID` must become canonical tenant config and their propagation must be tested before a client release. |
| Current delete authorization is inferred from the caller-supplied key path and generic private deletes use project-wide editor access; the authoritative image rows are deleted later by `remove_image_records`. | `workers/image-worker/src/delete.ts: handleDelete`; `public.remove_image_records` in `database/functions/others/add_image_record.sql` | Public batch delete must pre-authorize exact stored links against `public.images`; private objects retain their explicitly bounded project-wide authorization contract. |
| Current upload records an R2 object before calling `add_image_record`, but `addImageRecord` logs and suppresses RPC failure, so the request can return success with an orphaned object. | `workers/image-worker/src/upload.ts: handleUpload/addImageRecord` | Upload needs compensation and must not return success unless persistence completes. |
| Current CORS is `*` and deployment documentation/scripts still configure an unused `SUPABASE_SERVICE_ROLE_KEY`. | `workers/image-worker/src/cors.ts`; `workers/image-worker/deploy.sh`; `docs/backend/image_worker.md` | Control-plane origins and least-privilege secret manifests are part of the cutover, not optional documentation cleanup. |
| Direct R2 delivery will not inherit the one-year `Cache-Control` header currently added only by Worker response code; uploaded R2 metadata contains only content type. | `workers/image-worker/src/serve-public.ts: handlePublicServe`; `workers/image-worker/src/upload.ts: bucket.put` | The public domain needs an explicit edge TTL and response/browser cache-header policy that also covers existing objects. |
| `npm run test:integration` excludes `workers/image-worker/tests/unit/`, including the current bucket fallback tests. | `workers/image-worker/package.json`; `workers/image-worker/tests/unit/bucket-routing.test.ts` | The plan must add or invoke a full Worker test command before claiming routing proof. |
| `IMAGES_TEMP` / `festapp-images-temp` is provisioned and documented but has no production code consumer. | `workers/image-worker/src/types.ts`; `workers/image-worker/wrangler.toml`; `workers/image-worker/deploy.sh`; repository search for `IMAGES_TEMP` | Treat it as drift and remove it unless Wave 0 finds an external operational consumer. |

Representative current flow:

```text
image widget -> https://img.festapp.net/images/...?... -> image Worker
  -> R2 GET -> optional Images binding -> response

HEAD probe -> image Worker -> R2 HEAD -> response

editor upload/delete -> same img.festapp.net Worker
  -> caller-selected Supabase URL/key -> permission RPC -> shared R2 bucket
```

## Target architecture and invariants

### Canonical owner and contract

`image-api.festapp.net` is the authenticated control-plane owner. Its project registry is a fail-closed server-side mapping from a stable project ID (`default`, `a`, plus only inventory-proven additions) to that project's canonical Supabase URL, server-owned anon key (`SUPABASE_ANON_KEY`, `SUPABASE_ANON_KEY_A`), public bucket, private bucket, public hostname and presign bucket name. The Worker also owns a zone-scoped `CF_ZONE_ID` and least-privilege `CF_CACHE_PURGE_TOKEN` used only for `festapp.net` cache purge. Clients identify the project with that stable ID, but may not supply a Supabase origin, credential, bucket, hostname, zone or purge credential that changes the authority boundary.

`img.festapp.net` and `a.img.festapp.net` are public data-plane owners backed by the corresponding public-only R2 buckets. Original-object URLs retain the current shape. One documented URL contract, mirrored by Dart and JavaScript helpers and parity fixtures, builds transformed URLs with exactly the ordered options `width={300|600|1200},fit=scale-down,format=auto,quality=75,onerror=redirect`; it strips source query/fragment data and accepts only canonical `https` source URLs on the exact registered public hosts. A zone WAF rule blocks every other `/cdn-cgi/image/` option/source shape, any outer query, percent-encoded source path or dot segment before Images processing, and the Images source allowlist contains only those public hosts.

Control-plane outputs are structured JSON with stable error codes. Upload is idempotent at the object-key/DB-record boundary or compensates by deleting the object if DB insertion fails. Public delete accepts canonical stored URLs, pre-authorizes their owning occasion/unit through a narrow SQL RPC over `public.images`, deletes only registry-matching R2 keys, purges the original source URL using Cloudflare's varied-image purge semantics, and only then removes successful records through `public.remove_image_records`. Keeping the DB record until R2 and purge succeed preserves authorization and retry state. Generic private deletion remains separately project-scoped and permissioned by the existing `get_is_editor_on_any_occasion` contract.

### Invariants

1. No object requiring authentication exists in a bucket attached to a public custom domain.
2. A normal public image GET does not execute a user Worker.
3. Each production hostname resolves to exactly one explicit project and bucket; unknown host/project input fails closed.
4. The client cannot select an arbitrary Supabase origin, anon key, bucket, public hostname, Cloudflare zone or purge credential.
5. Public object keys are immutable and never overwritten in place.
6. Variant cardinality is bounded to at most three declared presets per source per month; raw `w`, `q` and `f` query parameters are not a public contract.
7. Public delete success means the R2 object is absent, its image record is absent and Cloudflare accepted a purge that covers the original and varied images; otherwise the response reports an idempotently retryable partial result without claiming full deletion.
8. Installed clients no longer need control routes on public image hostnames before those hostnames leave the Worker.
9. Project A data can never fall back into the default project bucket.
10. Public delivery and control-plane costs have separate metrics and budgets.
11. Handcrafted `/cdn-cgi/image/` URLs cannot create a fourth option set, use a query-distinct source or fetch an unregistered origin; client code is not relied on to enforce this invariant.

### Entry points and forbidden bypasses

- Public originals: `https://img.festapp.net/images/...` and `https://a.img.festapp.net/images/...` -> direct R2 custom domains.
- Public variants: for example `https://img.festapp.net/cdn-cgi/image/width=300,fit=scale-down,format=auto,quality=75,onerror=redirect/https://img.festapp.net/images/42/photo.jpg`; only the three exact width presets and registered source hosts pass the zone rule.
- Control: `https://image-api.festapp.net/{upload,delete,presign,private/...}` -> Worker with an allowlisted stable project ID.
- Forbidden: `/upload`, `/delete`, `/private`, `/presign` on public R2 hostnames after cutover; direct access to private buckets; arbitrary client-provided Supabase origins/keys; silent default-bucket fallback; permanent workers.dev client URLs.

## Decisions, assumptions, and blockers

### Decisions

- **D1:** Move public GETs outside the Worker. Cache API may be used only as a temporary rollback mitigation because it reduces R2/CPU, not Worker request charges.
- **D2:** Reuse `img.festapp.net` and `a.img.festapp.net` for public originals after control clients migrate. This preserves stored DB URLs and external links.
- **D3:** Split private objects into per-project private buckets before attaching public custom domains.
- **D4:** Use one separate control hostname and one explicit project registry rather than duplicating Workers per hostname.
- **D5:** Use Cloudflare Images URL transformations only for three responsive presets with fixed `quality=75` and `onerror=redirect`. Do not allow arbitrary quality/width combinations that can create unbounded billable unique transformations or make the Free-plan limit a broken-image failure.
- **D6:** Keep generic authenticated/user data uncached; only immutable public image bytes use the public cache.
- **D7:** Treat B/C as configuration drift: provision them only if inventory proves live ownership; otherwise delete their dead types/tests/routes.
- **D8:** Authorize public deletion from exact stored `public.images.link` ownership, not from a caller-supplied R2 key. Preserve the existing project-wide private-file permission contract as an explicit boundary.
- **D9:** Use a response-header rule for the one-year immutable browser policy on `images/*` plus Cache Rules for edge TTL, so historical objects do not require a metadata rewrite merely to gain direct-delivery cache headers. New uploads also write equivalent `cacheControl` R2 HTTP metadata.
- **D10:** Enforce the three transformation presets at the zone edge with one fail-closed WAF custom rule plus an exact Images source-origin allowlist. Do not replace this with a preset Worker because Worker cache hits would reintroduce per-view Worker request charges.

### Assumptions

- **A1:** Existing public keys are not overwritten; impact if false: immutable cache can serve stale bytes; resolve by: inventory write sites and R2 object-version history before Wave 5.
- **A2:** Old clients that append query parameters still receive an acceptable original from direct R2; impact if false: image rendering breaks at cutover; resolve by: staging custom-domain probe with representative legacy URLs.
- **A3:** The live account and `festapp.net` zone permit URL transformations from both selected R2 custom domains and varied-image purge behaves as documented; impact if false: serve originals and stop before variant activation/delete cutover; resolve by: read-only account preflight plus staging transform and purge probe.
- **A4:** Existing installed-client adoption can be measured or enforced; impact if false: public-host cutover would break legacy upload/delete; resolve by: inventory release telemetry/minimum-version controls in Wave 0.
- **A5:** No external producer writes stable public keys in place; impact if false: immutable caching can retain stale bytes; resolve by: repository and account inventory before setting the cache rule.
- **A6:** The live zone has a free WAF custom-rule slot and string operators can block noncanonical `/cdn-cgi/image/` requests before Images billing; impact if false: bounded URL transformations cannot be enabled under this design and clients must serve originals; resolve by: account inventory and staging requests for valid, invalid-width, reordered-option, query-bearing and foreign-source URLs.
- **A7:** Failed transformations for nonexistent canonical-looking R2 keys do not consume billable unique-transform usage; impact if false: a caller could create cost with random source paths even though option cardinality is fixed; resolve by: official product confirmation or an isolated usage-meter experiment before selecting a Paid plan.

### Blockers

- **B1:** Production inventory must prove zero private objects remain in every bucket before that bucket becomes public.
- **B2:** Production route/domain changes, bucket creation/migration, Images activation and deploy require explicit authority.
- **B3:** Public hostname cutover is blocked until old-client control traffic is zero for the agreed observation window or a minimum-version gate is active.
- **B4:** Cloudflare's current Images and cache pricing/entitlement must be accepted after the preflight; transformation activation may create a new billed product.
- **B5:** Production URL transformations are blocked until server-side rejection of noncanonical variants is proven; helper-only cardinality is not sufficient.
- **B6:** Paid transformations are blocked if nonexistent-source attempts are billable and the account cannot enforce a hard acceptable spend ceiling; the safe fallback is originals or the Free plan's non-billing 5,000 limit.

## Deletion ledger

| Artifact | Current role | Final action | Removal proof |
|---|---|---|---|
| `handleServePublic` and catch-all public routing | Serves every public image through Worker | Delete after R2 custom-domain cutover | `rg "handleServePublic|serve-public" workers/image-worker` is empty |
| Query transform contract `?w=&f=&q=` | Creates Worker-side variants | Replace with bounded `/cdn-cgi/image/...` builder, then delete parser/tests | Search contains no production query builder/parser |
| Unrestricted public `/cdn-cgi/image/` parameter surface | Lets callers bypass helper presets and create billable variants | Install exact source allowlist and fail-closed WAF rule generated from the canonical contract | Negative probes are blocked before Images and ruleset/topology guard matches the three presets |
| Caller-provided `anonKey` and arbitrary `supabaseUrl` authority | Selects permission origin and routing | Remove; use server allowlist/config | Contract tests reject unregistered projects and supplied keys |
| Default bucket fallback in `resolveBucket`/`resolvePublicOrigin` | Masks routing errors | Delete; return typed unknown-project/host error | Unit tests prove fail-closed behavior |
| Same-bucket `private/` storage | Private object convention | Migrate to private bindings/buckets and remove fallback reads | Inventory reports zero private keys in public buckets |
| Hardcoded presign bucket | Signs only default bucket path | Replace with project registry's private bucket name | Project A signing contract test |
| Per-object cleanup delete loop and key-derived public authorization | N control requests and path-based authorization | Replace with bounded URL-based batch delete pre-authorized from `public.images` | Search/call test proves one bounded request and rejects a mismatched/unowned URL |
| B/C phantom bindings and fallback tests | Unprovisioned routing surface | Delete unless Wave 0 proves live projects | Wrangler/types/project-registry parity check |
| Unused `IMAGES_TEMP` binding/bucket setup | Provisioned but unreferenced storage surface | Remove types/binding/deploy/docs unless Wave 0 proves an external owner | Registry/Wrangler/deploy parity search and authorized bucket-retention decision |
| Public custom-domain Worker routes | Mixed plane | Remove after adoption gate; retain only `image-api.festapp.net` Worker route | Wrangler dry-run plus production routing evidence |
| Stale deploy secrets/comments (`SUPABASE_SERVICE_ROLE_KEY`) | Misstates authority | Replace with the actual per-project anon secrets plus zone-scoped purge credential/config; retain R2 signing credentials only if presign remains | Secret/config manifest check |
| Hard-coded `AppConfig.imageWorkerUrl` and missing propagation | Mixed-origin client configuration | Add `IMAGE_API_URL` and `IMAGE_PROJECT_ID` to `automation/project.conf`, both generated app configs and `automation/tests/apply_config.test.sh`, then remove the old name | Config fixture test and `rg "imageWorkerUrl" lib automation` is empty |
| Wildcard control-plane CORS | Allows any browser origin to invoke authenticated endpoints | Replace with exact deployed-origin allowlist and correct `Vary: Origin` behavior | Preflight/response tests for allowed and denied origins |
| Stale mixed-plane deployment guide and script | Recreates old topology and secrets | Rewrite `docs/backend/image_worker.md` and `workers/image-worker/deploy.sh` around the split topology and explicit production gates | Search and dry-run inspection contain no old host/control instructions or service-role secret |

## Implementation waves

### Wave 0 — Measured feasibility and cutover gates

**Goal**

Resolve every fact that can make direct-public delivery unsafe or unexpectedly billable.

**Changes**

- Add `docs/plans/image-delivery-cost-cutover-evidence-2026-08-23.md` recording current Worker/R2/Images pricing, Free-versus-Paid behavior, live subscription, domain feasibility, purge capability, WAF rule capacity/evaluation order, presign token bucket scope and the exact pre-change Cloudflare resource IDs/versions. Never put credentials or user/object identifiers in it.
- Inventory each configured R2 bucket by prefix, object count and bytes, specifically `private/`, non-`images/` keys, overwrites/versioning, CORS and lifecycle rules. Record aggregates, never object names containing user data.
- Inventory production callers by app version and endpoint class (`public_get`, `upload`, `delete`, `private`, `presign`) without logging paths, JWTs or user identity.
- Reconcile default/A/B/C projects against live Supabase projects, secrets, bucket bindings and hostnames.
- Prove a staging R2 custom domain serves original and legacy-query URLs with expected content type, Range/HEAD behavior, ETag and cache key. Prove one allowlisted Images transformation and `onerror=redirect`, one source-URL purge that invalidates all varied images, and pre-Images rejection of invalid width, reordered/extra options, source query, percent encoding, dot segments, foreign source and unregistered public host. Establish from official support or isolated metering whether nonexistent-source failures count toward unique usage.

**Migration/deletion**

- None; this wave is read-only except for an explicitly authorized isolated staging hostname/resource.

**Failure and compatibility**

- If public/private separation cannot be proven, stop before public-domain attachment.
- If legacy query URLs fail, retain the Worker route until a client/minimum-version gate eliminates those readers.

**Validation**

- The evidence file has no unknown project/bucket/domain mapping, identifies how client-version/control-endpoint adoption will be gated, and contains a corpus-derived estimate for `active source images x at most 3 presets` against the 5,000-free and Paid-plan thresholds.

**Exit condition**

- B1-B6 have either bounded resolutions or an explicit operator stop; no production mutation has occurred.

### Wave 1 — Fail-closed control-plane core

**Goal**

Make project, auth and bucket selection an explicit deep module before moving data.

**Changes**

- Replace `workers/image-worker/src/bucket.ts` with a typed project registry containing canonical Supabase URL, public/private bindings, bucket names, public hostname and only inventory-proven temporary storage.
- Make hostname/project resolution return a typed error and never default.
- Make `projectId` the target request field and obtain Supabase URL/anon key from bindings/secrets. During the measured old-client window only, accept a canonical allowlisted legacy `supabaseUrl` as an alias to `projectId` and ignore the supplied `anonKey`; unknown URLs fail closed. Delete this parser in Wave 6.
- Tighten CORS to deployed Festapp origins for control routes; public image GET CORS belongs to R2 bucket configuration.
- Correct presigning to the resolved private bucket and validate key prefix, expiry and project.
- Add `CF_ZONE_ID` config and a `CF_CACHE_PURGE_TOKEN` secret scoped only to Cache Purge for the `festapp.net` zone; centralize purge requests with typed rate-limit/upstream errors and never accept zone/token input from a request.
- Define stable JSON error codes and request-size/key-count bounds.
- Add a `test` script that runs both `tests/unit/` and `tests/integration/`; keep narrower scripts only as optional developer shortcuts.

**Migration/deletion**

- Delete phantom B/C and unused `IMAGES_TEMP` configuration unless Wave 0 proves live ownership; otherwise provision and document them completely in the same change.

**Failure and compatibility**

- Unknown projects, missing bindings and mismatched hostname/project combinations return 400/403/500 as appropriate without touching R2 or Supabase.

**Validation**

- `cd workers/image-worker && npm run typecheck && npm test` — project routing, auth, CORS, signing, legacy-alias behavior and fail-closed behavior across unit and integration suites.

**Exit condition**

- Every control request resolves exactly one registered project and cannot influence credentials or another project's bucket.

### Wave 2 — Private storage isolation

**Goal**

No authenticated object remains in a future public bucket.

**Changes**

- Add `festapp-images-private` and `festapp-images-a-private` (plus only inventory-proven projects) and their Worker bindings; new `private/` writes go only to the selected private bucket.
- Implement an idempotent, resumable migration tool with source/destination checksum or size+ETag evidence, bounded batches and a durable progress ledger outside `supabase/migrations`.
- During migration, read private objects from the new bucket first and the old bucket only as a temporary, instrumented fallback.
- Migrate existing private keys, verify parity, then delete the old copies only after authorized confirmation.
- Keep migration tooling code-ready without assuming live buckets exist; bucket creation, dual-write/reader deployment, copying and source deletion are distinct authorized operational checkpoints.

**Migration/deletion**

- Remove the temporary fallback and migration code after zero-source proof. Do not retain dual reads.

**Failure and compatibility**

- A copy failure leaves the source intact. Deletion is a separate authorized phase. Private URLs continue through the control Worker throughout.

**Validation**

- Integration tests cover default/A private isolation and cross-project denial; production aggregate inventory proves destination parity and zero private keys in public buckets.

**Exit condition**

- Public-candidate buckets contain only explicitly public prefixes and the dual-reader is gone.

### Wave 3 — Dedicated control hostname and transactional behavior

**Goal**

All supported clients use `image-api.festapp.net` for authenticated operations.

**Changes**

- Make the Worker reject catch-all public reads on `image-api.festapp.net`, while temporarily retaining public GET and legacy control routes on the old hosts until Wave 5/6. Add the new control hostname in staging, then production under separate authority.
- Add `IMAGE_API_URL=https://image-api.festapp.net` and tenant-specific `IMAGE_PROJECT_ID` (`default` or `a`) to `automation/project.conf` and its fixture; propagate them through `automation/apply_config.sh` to `lib/app_config.dart` and `web_client/src/app_config.js` as `imageApiUrl` and `imageProjectId`; cover both in `automation/tests/apply_config.test.sh`.
- Migrate Flutter upload/delete/private/presign calls to `imageApiUrl` plus `projectId`; remove the public hostname and Supabase credential overrides from the production client API while retaining only explicit endpoint injection for tests.
- Make upload compensate R2 write when `add_image_record` fails; return success only when both object and DB record exist.
- Add `public.authorize_image_deletion(p_links text[])` in `database/functions/others/authorize_image_deletion.sql` plus a timestamped `supabase/migrations/` deployment artifact. It is a narrow `SECURITY DEFINER` RPC that returns the exact existing authorized links without mutation, checks every owning occasion/unit, sets `search_path = public, extensions`, and grants only `authenticated`; cover mixed-owner/all-or-nothing and unauthorized cases in a targeted SQL test.
- Add bounded URL-based batch delete so cleanup performs one permission-aware request. Reject URLs whose exact host/path do not match the selected registry project. Pre-authorize the whole batch, delete R2 objects, purge each successfully deleted original source URL using varied-image purge, then remove only fully purged records through `public.remove_image_records`. A retry must converge after any partial failure.
- Record low-cardinality operation/status metrics, not object paths or identities.

**Migration/deletion**

- Remove client control calls to `AppConfig.imageWorkerUrl`; retain public URLs only as image data.

**Failure and compatibility**

- There is no cross-system transaction. Auth failure mutates nothing; an R2 or purge failure leaves its DB record as the ownership/retry anchor; a DB failure occurs only after R2 deletion and purge and still leaves the same record for an authorized retry. Every partial result is per-URL and idempotently retryable. Purge failure does not claim privacy-complete deletion.

**Validation**

- Worker full suite, targeted SQL permission tests, `./automation/tests/apply_config.test.sh`, and targeted Flutter tests for upload, copy, single delete and cleanup batch behavior.

**Exit condition**

- Released clients perform no authenticated operation against `img.festapp.net` or `a.img.festapp.net`.

### Wave 4 — Bounded responsive image contract

**Goal**

Clients request only useful, predictable variants without executing the image Worker.

**Changes**

- Add one checked-in machine-readable transform contract fixture used by Worker rule tests and mirrored Dart/JavaScript tests. Its only option strings are the ordered `width={300|600|1200},fit=scale-down,format=auto,quality=75,onerror=redirect` presets and its only hosts are the registry's inventory-proven public hosts.
- Replace Dart and JavaScript helpers with mirrored implementations of that contract. Emit Cloudflare Images URL syntax only for canonical `https` originals with an unencoded, dot-segment-free `images/` path on exact allowlisted public hosts (`img.festapp.net`, `a.img.festapp.net` and any inventory-proven additions); strip query/fragment data, do not use substring matching, and return historical noncanonical paths, non-image, already-transformed or unrecognized URLs unchanged as originals.
- Add a checked-in rule renderer/topology check for the Images source allowlist and one fail-closed zone WAF rule that permits only the exact preset prefixes, exact source hosts, empty request query, unencoded source paths and no dot segments. Applying the rule remains a production action requiring separate authority.
- Update all Flutter/web call sites; remove unused web helper code if the final consumer search proves it dead.
- Add tests for encoding, project A hostname, source query/fragment stripping, non-image URLs, already-transformed URLs, exact option ordering and exact preset cardinality. Negative rule tests cover reordered/extra options, a fourth width, foreign source, unregistered host, request query, percent encoding and dot segments.
- Establish a monthly unique-transformation budget and alert threshold from Wave 0 evidence.

**Migration/deletion**

- Delete arbitrary query options and Worker transformation tests.

**Failure and compatibility**

- Do not release a client that emits `/cdn-cgi/image/...` until zone transformations and the fixed `onerror=redirect` behavior pass staging/production smoke under separate authority. Before the R2 hostname cutover, the existing Worker may temporarily remain the transformation source origin; after cutover the source is direct R2. A failed transformation falls back to the immutable original and must never use the old `?w/f/q` Worker contract.

**Validation**

- Targeted Dart and web helper/call-site tests plus Worker/ruleset contract tests; staging proves valid dimensions/content type/cache behavior and rejects every negative probe before it increments Images usage.

**Exit condition**

- All production call sites use only the three presets or originals and no public request depends on Worker transform parsing.

### Wave 5 — Public R2 custom-domain cutover

**Goal**

Public views bypass the Worker with no URL/DB rewrite.

**Changes**

- After the installed-client gate, detach `img.festapp.net` and `a.img.festapp.net` from Worker custom-domain routes and attach each to its exact public R2 bucket.
- Configure R2 CORS, a Cache Rule with explicit edge TTL, Smart Tiered Cache and a response-header transform rule that emits `Cache-Control: public, max-age=31536000, immutable` for immutable `images/*`. New uploads write equivalent R2 HTTP metadata; this rule covers historical objects without rewriting the corpus.
- Ignore irrelevant legacy query parameters in the `images/*` cache key only after staging proves old `?w=&f=&q=` clients receive the original. Do not apply that cache key to control, private or presigned paths.
- Preserve content type, ETag, HEAD and Range semantics.
- Purge test objects and verify MISS->HIT behavior, R2 Class B reduction and zero `festapp-image-worker` public GET invocations.

**Migration/deletion**

- No DB URL rewrite. Stored `img`/`a.img` links remain canonical.

**Failure and compatibility**

- Roll back domain routing to the exact pre-cutover Worker version if public reads fail. This rollback is time-bounded and does not cancel private separation or client control migration.

**Validation**

- Cache-busted and repeated original/variant probes on both domains, including headers and purge-after-delete; Cloudflare aggregate metrics; representative app browser QA after explicit approval.

**Exit condition**

- Repeated public reads are edge hits, invoke no user Worker, and the corresponding buckets contain no private objects.

### Wave 6 — Contract and legacy contraction

**Goal**

Only the final split-plane architecture remains.

**Changes**

- Delete `serve-public.ts`, public catch-all routing, the legacy `supabaseUrl` alias parser, Images binding from the control Worker if upload compression no longer needs it, obsolete route tests and mixed-origin config.
- Remove public Worker custom-domain routes, workers.dev client assumptions, temporary migration readers, compatibility flags and stale deployment docs/secrets.
- Add a topology guard asserting public host->R2 bucket and control host->Worker, project registry/Wrangler parity, private-public bucket disjointness and no public Worker GET route.
- Record post-cutover 7-day and full billing-cycle metrics against baseline.

**Migration/deletion**

- Complete every deletion-ledger entry; no permanent fallback remains.

**Failure and compatibility**

- If an unknown legacy client appears, handle it through explicit release policy, not by silently restoring mixed routing.

**Validation**

- `rg` absence proofs, Worker typecheck/integration tests, relevant Flutter/web tests, config/topology guard and authorized production metrics.

**Exit condition**

- The Worker receives only authenticated control operations; ordinary image views cannot reach it.

## Rollout and rollback

Waves describe dependency order, not permission to mutate production. Code and tests for Waves 1-4, including migration tooling, can become code-ready locally; their production effects are held behind these explicit checkpoints:

1. **P0 — feasibility authority:** create only approved staging resources and record the Wave 0 evidence.
2. **P1 — private/control preparation:** create private buckets; deploy the fail-closed registry while the old public hosts still serve reads and allowlisted legacy control requests; enable new private writes; copy and verify private data; attach `image-api.festapp.net` to the Worker.
3. **P2 — client adoption:** after monetary/entitlement approval, apply the exact source allowlist and fail-closed WAF rule, prove invalid variants are rejected, then enable the bounded zone transformations while the old Worker can still serve source originals. Release clients using `image-api.festapp.net`, `projectId` and the new helper. Observe endpoint traffic until the agreed zero-legacy window or enforce the approved minimum version. If transformations or the server-side rule are not approved/proven, release only a control-origin migration build whose image helper returns originals and keep Wave 4 incomplete.
4. **P3 — public cutover:** prove zero private keys in public buckets; attach the public hostnames to their exact R2 buckets; enable cache/header rules and Smart Tiered Cache while retaining the bounded zone transformations; verify metrics and delete/purge behavior.
5. **P4 — contraction:** remove old public/control routes, aliases, migration fallbacks and obsolete secrets/docs only after P3 evidence is accepted.

Before each deploy, record the exact Worker version, routes, DNS/custom-domain ownership, bucket bindings, ruleset versions and cache rules. Rollback of Wave 5 restores public routing to that exact Worker version only; it must not move private objects back or reintroduce caller-selected auth. Cache purge is required when rolling between representations. A pricing/entitlement failure leaves URL transformations disabled (or relies on fixed `onerror=redirect`) and serves originals while public direct delivery remains.

## Verification strategy

| Risk or invariant | Verification seam | Command/observation |
|---|---|---|
| Project isolation | Registry and handlers | Image Worker unit/integration suite with default/A and unknown project |
| Private exposure | R2 inventories/topology guard | Zero `private/` keys and no nonpublic prefix in public buckets |
| Auth origin injection | Request contract tests | Supplied foreign URL/key cannot cause outbound call or bucket write |
| Upload consistency | Handler failure injection | DB failure removes newly written object and returns failure |
| Delete ownership and convergence | SQL + handler failure injection | Unowned/mismatched URLs mutate nothing; retry completes any R2/DB/purge partial state |
| Delete edge-cache visibility | R2 + varied-image purge probe | Deleted original/variants return 404 at Cloudflare after successful response; already-downloaded browser copies remain a documented external boundary |
| Variant cost bound | Helper tests and metrics | Only 3 preset keys per source; monthly unique transforms within budget |
| Variant bypass resistance | WAF/source allowlist and negative probes | Fourth/reordered/query-bearing/foreign variants are rejected before Images; checked-in contract and deployed rule agree |
| Legacy compatibility | Staging old-client URLs and endpoint metrics | Render succeeds; old control traffic reaches zero/gate |
| Worker request elimination | Cloudflare aggregate metrics | Public GET sample causes no `festapp-image-worker` invocation |
| R2 cache effectiveness | Repeated request headers/metrics | Immutable browser header is present, first edge request misses then repeated request hits, and Class B rate falls materially |
| Registry/config integrity | Worker and config tests | `npm test` includes unit+integration; `apply_config` fixture emits the correct `imageApiUrl`/project ID |
| Repository integrity | Targeted checks and searches | One final standard validation batch; no unrelated files changed |

## Definition of complete

- [ ] Every intended control entry point reaches the fail-closed project registry.
- [ ] Public and private data are physically separated for every configured project.
- [ ] Public image GETs use direct R2 custom domains and no user Worker.
- [ ] All clients use the dedicated control origin and bounded transform presets.
- [ ] The deployed source allowlist and zone rule reject noncanonical transformation requests before Images processing.
- [ ] Stored `img` and `a.img` URLs continue to resolve without a DB rewrite.
- [ ] Delete includes cache invalidation with honest partial-failure semantics.
- [ ] Public deletion is authorized from stored image ownership, not a caller-claimed key path.
- [ ] Deletion-ledger items are removed or intentionally bounded by an explicit blocker.
- [ ] Production route/bucket/client adoption evidence is recorded.
- [ ] Targeted validation passes at standard level.
- [ ] Post-cutover request/Class B/transformation costs are measured against baseline.

## Residual risks

- Cloudflare product pricing and entitlements can change; Wave 0 must revalidate them immediately before execution using official documentation and the live account.
- Installed-client adoption is not currently proven in repository evidence and may lengthen the compatibility window.
- Browser caches can retain already-downloaded immutable content after an edge purge; the deletion contract guarantees R2/database removal and Cloudflare varied-image purge, not revocation of bytes already held by a client.

## External references

- [R2 public buckets and custom domains](https://developers.cloudflare.com/r2/buckets/public-buckets/)
- [R2 cache and Smart Tiered Cache](https://developers.cloudflare.com/cache/interaction-cloudflare-products/r2/)
- [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/)
- [Cloudflare Images pricing](https://developers.cloudflare.com/images/pricing/)
- [Images URL transformations](https://developers.cloudflare.com/images/optimization/transformations/overview/)
- [Images source-origin restrictions](https://developers.cloudflare.com/images/optimization/transformations/sources/)
- [WAF custom-rule availability](https://developers.cloudflare.com/waf/custom-rules/)
- [Purge varied images](https://developers.cloudflare.com/cache/how-to/purge-cache/purge-varied-images/)
