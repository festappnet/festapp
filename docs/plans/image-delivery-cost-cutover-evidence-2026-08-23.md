# Image delivery cutover evidence

Date: 2026-08-23
Status: P0 complete; P1 live; P2 infrastructure live and locally validated,
client adoption blocked on canonical release source

## Official product facts revalidated

- R2 buckets are private by default. Connecting a custom domain makes a public
  URL and enables Cloudflare Cache/WAF; `r2.dev` is not a production/cache path.
  Smart Tiered Cache reduces direct R2 fetches after lower-tier misses.
  Sources: <https://developers.cloudflare.com/r2/buckets/public-buckets/> and
  <https://developers.cloudflare.com/cache/interaction-cloudflare-products/r2/>.
- Worker cache hits still count as Worker requests (though they avoid CPU), so a
  Worker Cache API path cannot meet the no-per-view-Worker outcome.
  Source: <https://developers.cloudflare.com/workers/platform/pricing/>.
- Images Free includes 5,000 unique transformations/month, rejects new variants
  with error 9422 after that threshold and does not bill the excess. Images Paid
  includes the first 5,000 and charges $0.50/1,000 additional transformations.
  `onerror=redirect` can serve a same-domain original on the Free limit.
  Source: <https://developers.cloudflare.com/images/pricing/>.
- Source restrictions distinguish exact subdomains; adding a root does not
  implicitly allow its subdomains. Redirect targets are followed after only the
  initial URL is checked, so the checked-in WAF rule must also constrain the
  canonical initial source shape.
  Source: <https://developers.cloudflare.com/images/optimization/transformations/sources/>.
- Purging the original source URL purges all varied-image content for that URL.
  Source: <https://developers.cloudflare.com/cache/how-to/purge-cache/purge-varied-images/>.

## Live-account inventory and applied state

### P0 — completed 2026-08-23

- Cloudflare account `84b32318ac235bf6738bdf1c8caa0795`; `festapp.net` zone
  `02fd6ca8f4652d62e9b05f24a5e9d84f` on the Free zone plan.
- Pre-cutover Worker rollback version:
  `c16a8e31-2e40-4d62-bb7c-d9432ed9b8ca` (version 42). It had public
  `festapp-images`, `festapp-images-a`, empty `festapp-images-temp`, an Images
  binding, two public custom domains, and an enabled `workers.dev` route.
- Aggregate R2 inventory (no object names recorded):

  | bucket | all objects / bytes | `images/` | `private/` | other |
  |---|---:|---:|---:|---:|
  | `festapp-images` | 277 / 92,079,150 | 270 / 91,387,601 | 0 / 0 | 7 / 691,549 |
  | `festapp-images-a` | 664 / 187,091,477 | 659 / 186,538,587 | 0 / 0 | 5 / 552,890 |
  | `festapp-images-temp` | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

  All three had no custom R2 domains, disabled `r2.dev`, no CORS configuration,
  and only the default seven-day incomplete-multipart abort lifecycle rule.
- The databases identify `kjdpmixlnhntmxjedpxh` as the default project behind
  `img.festapp.net` and `lwfpdjxsdmkfyrzqbrlk` as project `a` behind
  `a.img.festapp.net`. Database aggregates contain 7 and 13 historical
  `private/` links respectively, but the corresponding public R2 prefix count is
  zero; no private objects were available to copy or delete.
- Image transformations were already enabled under the existing account PAYGO
  Images subscription. Dashboard usage was 174 unique transformations; the
  Free counter reported 0/5000. No plan or paid entitlement was activated or
  changed by this cutover. The 929 live `images/` objects imply a bounded
  three-preset upper bound of 2,787 unique source/preset pairs, below 5,000.
- Pre-state source policy was the entire `festapp.net` zone. No custom WAF
  entrypoint existed. Cache ruleset `e81c38494d8c4db3a89b2a9479f464b5`
  version 1 contained one unrelated CSM runtime-assets rule and was not changed.

### P1 — applied and validated

- Created empty private buckets `festapp-images-private` and
  `festapp-images-a-private`; both validated at 0 objects / 0 bytes. No source
  object copy or deletion was performed because both `private/` inventories were
  zero.
- Applied migration `20260823190000_authorize_image_deletion` to both Festapp
  Supabase projects. Both definitions have MD5
  `6506a2c6f76ba69a5f42017481368e60`, `SECURITY DEFINER`, fixed
  `search_path = public, extensions`, authenticated execute and no anon execute.
  The project-A pgTAP file passed and rolled back its test data. The default
  project could not run that unchanged pgTAP file because its older database
  lacks `create_user_for_test(text,text)`; definition/privilege validation there
  passed.
- Created a least-privilege Cache Purge token limited to the `festapp.net` zone
  and stored it only as Worker secret `CF_CACHE_PURGE_TOKEN`. Added the
  project-A anon secret from Supabase without recording either value. The live
  manifest now contains the eight expected secret names. An interim token whose
  value appeared in automation output was revoked immediately; a final
  inventory confirmed exactly one active token with this name and no token
  value in the repository.
- Deployed Worker version `4369e694-9b6b-4705-a67a-7397770ff21a` with the two
  private bindings, fail-closed project registry, exact CORS origins
  `https://csmostrava.festapp.net` and `https://vstupenky.online`, disabled
  private fallback, disabled `workers.dev`, and transitional custom domains
  `img.festapp.net`, `a.img.festapp.net`, `image-api.festapp.net`.
- Live smoke: both original public hosts returned 200; unknown control route 404
  JSON; unauthenticated upload 401 JSON; allowlisted CORS 204 with exact origin
  and `Vary: Origin`; denied CORS 403; cross-project host 400; `workers.dev` 404.
  Source bucket object counts remained 277 and 664.

### P2 — infrastructure applied; client gate remains open

- Source allowlist is now exactly
  `img.festapp.net/images/,a.img.festapp.net/images/` (modified
  `2026-08-23T19:32:04Z`).
- Created custom WAF ruleset `b9abeff61b454e0a870da4bbe5b1153b`, version 2,
  rule `b7bdd5d823704830b3da13f8eaa1eda7`. The checked-in renderer uses the raw URI
  path so nested source URLs, percent encoding and dot segments are evaluated
  before normalization.
- Live probes: canonical width-300 variants on both hosts returned 200 images;
  invalid width, reordered options, foreign source, cross-project source, outer
  query, encoded source and dot segment all returned 403. Dashboard usage still
  displayed 174 after the probes.
- No client build or release was produced. The checkout is detached at
  `84c1d5de5277d4388c25d07235700a93668345c4`, behind
  `origin/prod/csmostrava2026` at `dbd06e0fffb7e905885de7724873ab632cbb310c`,
  and contains unrelated dirty user work. Android signing configuration and a
  Google Play credential are absent. Under the release contract this is a hard
  stop before build or Play mutation.
- Recheck on 2026-08-24 found the clean local unified cutover source at
  `92fbd6e3b15040ca25dd9c7e43abc089616d2693` (`0.19.89+439`), while
  `origin/prod/csmostrava2026` still remained at
  `dbd06e0fffb7e905885de7724873ab632cbb310c`. The clean `+439` source does not
  contain `IMAGE_API_URL`/`IMAGE_PROJECT_ID` or the new image control client;
  the image cutover changes exist only in the mixed dirty checkout and therefore
  are not eligible release input.
- The 2026-08-24 local cutover validation passed: Worker TypeScript typecheck and
  full unit/integration suite (15 passed, 30 explicitly skipped), config
  propagation fixture, targeted Flutter image/control tests plus the affected
  speaker command tests (10 passed), and the web client test suite including the
  bounded image helper contract (160 passed).
- A clean release candidate was then assembled on 2026-08-24 in branch
  `release/image-delivery-cutover` on top of unified source
  `92fbd6e3b15040ca25dd9c7e43abc089616d2693`, with canonical version
  `0.19.90+440`. Only the image cutover, its direct call sites, generated version
  outputs and the pre-existing broken config fixture asset references were
  included; unrelated dirty speaker, occasion-save, ticket and sync changes were
  excluded. In this clean candidate the Worker typecheck/full suite passed, as
  did config propagation, targeted Flutter image/control tests and the web suite.
  Per operator instruction no Android bundle was built on the Mac; signed AAB
  production is owned exclusively by the Windows release workstation after the
  candidate becomes the clean remote canonical source.
- The Windows control channel was healthy and paired. Its last completed Play
  readback confirmed production version `438` at full distribution from source
  `dbd06e0fffb7e905885de7724873ab632cbb310c`; that version predates the image
  control-origin migration and cannot satisfy the adoption gate.
- Consequently the zero-legacy observation window/minimum-version gate has not
  begun. P3 public R2 domain cutover and P4 compatibility contraction were not
  performed.

## Authorized production checkpoints

### P0 — feasibility

- Target: approved isolated staging resources only.
- Pre-state to record: account/zone, Worker version/routes, R2 aggregate inventories,
  Images entitlement/usage, WAF/ruleset/cache versions and client endpoint metrics.
- Rollback identifier: staging resource IDs and pre-test ruleset versions.
- Expected cost: $0 on Images Free up to 5,000 unique monthly transformations;
  Paid activation is forbidden without separate monetary approval.
- Validation query/probes: bucket prefix aggregates; valid transform plus invalid
  width/order/query/encoding/dot-segment/foreign-source probes; source purge;
  HEAD/Range/ETag/cache behavior; post-probe transformation-usage delta.

### P1 — private/control preparation

- Target: `festapp-images-private`, `festapp-images-a-private`, and
  `image-api.festapp.net` -> `festapp-image-worker`.
- Pre-state: exact deployed Worker version/routes/bindings/secrets manifest and
  source `private/` count+bytes for both public buckets.
- Rollback: recorded Worker version and route/ruleset version; copied sources are
  retained until separately confirmed deletion.
- Expected cost: normal R2 Class A copy/write and control Worker requests; no
  paid Images activation.
- Validation: migration ledger parity, destination HEAD size/ETag evidence,
  default/A cross-project denial and new-write isolation. Source deletion remains
  a distinct authorized command.

### P2 — client adoption and bounded transforms

- Target: exact `img.festapp.net`/`a.img.festapp.net` source allowlist, generated
  fail-closed WAF rule, zone transformations and client release.
- Pre-state: ruleset version, Images entitlement/usage, active source count and
  current endpoint traffic by installed version.
- Rollback: prior ruleset version; disable transformations and release/control
  clients continue to use originals.
- Expected cost: Free behavior above, or `(unique-5000)/1000 × $0.50` only after
  explicit Paid approval.
- Validation: all negative probes rejected before Images; helper/rule contract
  parity; zero legacy control traffic for the agreed window or minimum-version gate.

### P3 — public R2 cutover

- Target: `img.festapp.net` -> `festapp-images` and `a.img.festapp.net` ->
  `festapp-images-a`, plus scoped CORS/cache/header/Smart Tiered Cache rules.
- Pre-state: zero `private/` and zero nonpublic-prefix objects in each target,
  exact Worker route/version and DNS/custom-domain/cache-rule versions.
- Rollback: recorded Worker version/routes only; private storage and server-owned
  auth are not rolled back.
- Expected cost: no public-view Worker requests; R2 Class B only on cache misses;
  Images cost remains the accepted P2 entitlement.
- Validation: original/legacy-query/variant MISS->HIT probes on both hosts,
  Range/HEAD/ETag/content type, delete+purge 404, and zero Worker invocation delta.

### P4 — contraction

- Target: remove old public Worker routes, legacy URL alias, fallback reader,
  unused Images binding (if upload compression no longer needs it), and stale secrets.
- Pre-state: accepted P3 metrics and zero legacy control traffic.
- Rollback: release policy/minimum version, not restoration of mixed auth routing.
- Expected cost: no new product cost.
- Validation: topology guard and absence searches, then 7-day/full-cycle Worker,
  R2 Class B and unique-transformation metrics against the recorded baseline.


## Current readback - 2026-10-07

The [read-only production report](../operations/image-delivery-readback-2026-10-07.md)
supersedes historical runtime/client assumptions above. Public domains still
map to the Worker, R2 custom domains are absent, 104 objects outside the
registry's public prefixes require classification, and the deployed Slunovrat
client selects an unregistered project. All 11 web bundles contain the control
origin; native adoption remains unverified. P3/P4 are not complete.
