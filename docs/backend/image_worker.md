# Image delivery and control plane

Public image bytes and authenticated image operations are separate contracts.

## Checked-in routing and pending target

| Plane | Host | Checked-in route | Conditional target |
|---|---|---|---|
| Default public data | `img.festapp.net` | `festapp-image-worker` -> R2 `festapp-images` | Direct public R2 domain after P3 |
| Project A public data | `a.img.festapp.net` | `festapp-image-worker` -> R2 `festapp-images` | Direct public R2 domain after P3 |
| AKH public data | `akh.img.festapp.net` | `festapp-image-worker` -> R2 `festapp-images-akhweb` | No direct-domain completion claimed |
| Authenticated control | `image-api.festapp.net` | `festapp-image-worker` | Worker control plane |

`workers/image-worker/wrangler.toml` still declares all four Worker hosts.
The [open cutover item](../operations/work-items/open/image-delivery-cost-cutover-2026-08-24.md)
records the 2026-09-23 readback: public hosts remain on Worker and R2 custom
domains are absent. P3/P4 remain blocked by adoption/legacy-traffic gates.
This is checked-in routing plus dated evidence, not a fresh live readback.

The control request selects `projectId=default|a|akhweb|slunovrat`. The Worker registry owns the
Supabase origins, anon keys, public/private bucket bindings, bucket names and
public hostnames. Client-supplied credentials never select authority. During the
measured P1-P4 adoption window only, an exact registered `supabaseUrl` can alias
the project ID; its supplied `anonKey` is ignored.

Control routes are `/upload`, `/delete`, `/private/{key}` and `/presign/{key}`.
Public delete accepts stored `images.link` URLs, authorizes the complete batch
through `public.authorize_image_deletion`, deletes the public object, purges the
source URL (which Cloudflare applies to varied images), then removes the record.
Generic private delete accepts only a `private/` key and uses the selected private
bucket plus the existing project-wide editor contract.

AKH is a public-image-only registry entry. It validates the caller through the
AKH project's authenticated-only `get_can_manage_images()` RPC, accepts only
`images/`, `blog/` and `content/` keys, and deliberately skips Festapp's
`images`-table persistence RPCs. Private routes fail closed for this project.

Slunovrat uses its explicit canonical `https://api.festapp.net` configuration,
the Festapp public bucket `festapp-images` and `img.festapp.net` for new assets.
Old API Storage URLs are retired. Its public uploads retain the
owner-scoped `check_upload_permission` and `add_image_record` RPCs; private
operations are disabled. Both `slunovrat.festapp.net` and
`app.festivalslunovrat.cz` are exact allowed control origins. See the
[2026-10-12 recovery evidence](../operations/slunovrat-image-upload-recovery-2026-10-12.md).

## Required bindings and secrets

- R2: `IMAGES_BUCKET`, `IMAGES_BUCKET_AKHWEB`, `IMAGES_PRIVATE_BUCKET`.
  Default, A and Slunovrat share the canonical Festapp bucket pair; AKH remains separate.
- Registry: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_URL_A`,
  `SUPABASE_ANON_KEY_A`, `SUPABASE_URL_AKHWEB`, `SUPABASE_ANON_KEY_AKHWEB`.
- Slunovrat public canonical configuration: `SUPABASE_URL_SLUNOVRAT`,
  `SUPABASE_ANON_KEY_SLUNOVRAT` (the public anon key, not a service-role key).
- Signing: `CF_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` scoped to
  the two private buckets.
- Purge: `CF_ZONE_ID` and `CF_CACHE_PURGE_TOKEN`, with Cache Purge permission
  only for the `festapp.net` zone.
- Browser control CORS: `CONTROL_ALLOWED_ORIGINS`, an exact comma-separated list.

Private reads use only the selected private bucket. The disabled P1 migration
fallback and its configuration were removed from source on 2026-10-16; the
existing cutover receipts recorded zero private source objects. A missing private
object returns 404 and never reads the public bucket.

New Flutter image copies and uploads use the image control Worker and its SQL
admission. The production reference rewrite, canonical bucket pair and scoped
adapters are active; the old Storage runtime, source volume and redundant
buckets have been retired. Old API Storage URLs return 410; they are not a
fallback reader or writer. Existing canonical R2 `a` URLs translate at the Worker
boundary. AKH keeps its independent bucket/Auth/DB contract. Follow the current
[storage authority and cleanup receipts](../operations/supabase-self-hosted/storage-authority.md)
for production evidence rather than replaying the former copy/adoption gates.

## Canonical upload processing

All current Flutter image uploads send an `ImageUploadProfile` through
`DbImages.uploadImage` and `ImageControlClient`. Original bytes are processed
only by `src/upload-policy.ts` in this Worker. Purpose profiles are standard,
ticket-background, blueprint-background, portrait, thumbnail and banner. The
server owns edge, quality and output budget; clients cannot override a profile.
PNG alpha and GIF/WebP animation are preserved; print backgrounds use a still
JPEG/PNG. Failed modern processing returns an error before R2 or record writes,
rather than silently storing an oversized original. Input is bounded to 20 MB
including streamed multipart limits, dimensions to 40 MP, and outputs to their
profile budget. Images metadata/transform inputs use streams.

Already released clients and independent AKH consumers may still send numeric
maxEdge/maxBytes/quality fields without a profile. One resolver adapter maps
those fields into the same processor, retaining their former small-file and
failure behavior. Remove this adapter only after all active web/native/AKH
callers have adopted profile requests; this release updates Slunovrat web only.
Old stored Supabase images retain their read/copy/delete adapters. Native HEIC
format normalization remains a required adapter to the accepted raster input
formats; it does not choose upload dimensions, quality or output budgets.
Editor bitmap validation and in-memory previews decode within a 1200 px box,
retain original upload bytes, and perform no JPEG re-encoding. The existing
editor draft/input memory limits remain independent UI safety constraints.
Cloudflare binding limits and animation/format semantics are documented at
https://developers.cloudflare.com/images/get-started/limits/ and
https://developers.cloudflare.com/images/optimization/binding/.

## Public transform contract

The canonical machine contract is
`workers/image-worker/config/image-transform-contract.json`. Only widths 300,
600 and 1200 are valid, with fixed ordered options
`fit=scale-down,format=auto,quality=75,onerror=redirect`. The checked-in WAF
renderer is a deployment input, not permission to apply the rule. Transformations
must remain disabled until the source allowlist and negative P2 probes succeed.

## Validation and deployment gates

```bash
cd workers/image-worker
pnpm install --frozen-lockfile
./deploy.sh --check
```

`deploy.sh` does not create buckets, DNS, rules, paid products or releases. A
control deploy requires `--deploy-control` plus the checkpoint environment
variables described by the script. Public R2 custom-domain attachment and P4
route contraction are operator-run actions after their evidence gates.

Editor photos use a 1600 px maximum edge, JPEG quality 85 and a 1.5 MiB output budget. Ticket backgrounds use 1600 px, quality 90 and 2 MiB for print detail. The server keeps aspect ratio and never upscales; only an image that exceeds its byte budget receives additional downscaling. These storage dimensions are independent of the 1200 px in-memory preview bound.

HTML import uses the same 20 MB / 40 MP input contract as the shared uploader. It retains original upload bytes and decodes bounded previews; the former editor-only 10 MiB / 16 MP limits are removed.

## Occasion copy regression

`pnpm --dir workers/image-worker run test:lifecycle` runs the actual Worker entrypoint
in workerd with local R2 and canonical SQL on the disposable database at port 55432.
Set `IMAGE_LIFECYCLE_DATABASE_URL` for another disposable local database. The test
rolls back all SQL, checks object bytes and both image references, retries the same
job, and deletes the copy while preserving its source. RPC transport binds a test
actor locally; GoTrue/PostgREST and deployed Cloudflare configuration are outside
this test. The seat-checkout CI lane runs it together with
`database/tests/occasion_copy_lifecycle_test.sql`, including pending media deletion
copied scanner settings, and the existing order safety guard.
