# Image delivery and control plane

Public image bytes and authenticated image operations are separate contracts.

| Plane | Host | Owner |
|---|---|---|
| Default public data | `img.festapp.net` | public-only R2 bucket `festapp-images` after P3 |
| Project A public data | `a.img.festapp.net` | public-only R2 bucket `festapp-images-a` after P3 |
| AKH public data | `akh.img.festapp.net` | R2 bucket `festapp-images-akhweb` |
| Authenticated control | `image-api.festapp.net` | `festapp-image-worker` |

The control request selects `projectId=default|a|akhweb`. The Worker registry owns the
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

## Required bindings and secrets

- R2: `IMAGES_BUCKET`, `IMAGES_BUCKET_A`, `IMAGES_BUCKET_AKHWEB`, `IMAGES_PRIVATE_BUCKET`,
  `IMAGES_PRIVATE_BUCKET_A`.
- Registry: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_URL_A`,
  `SUPABASE_ANON_KEY_A`, `SUPABASE_URL_AKHWEB`, `SUPABASE_ANON_KEY_AKHWEB`.
- Signing: `CF_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` scoped to
  the two private buckets.
- Purge: `CF_ZONE_ID` and `CF_CACHE_PURGE_TOKEN`, with Cache Purge permission
  only for the `festapp.net` zone.
- Browser control CORS: `CONTROL_ALLOWED_ORIGINS`, an exact comma-separated list.

`PRIVATE_MIGRATION_FALLBACK=enabled` is a temporary P1 reader only. It reads the
new private bucket first and instruments an old-public-bucket fallback. Remove it
after copy parity and zero-source proof.

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
npm run typecheck
npm test
./deploy.sh --check
```

`deploy.sh` does not create buckets, DNS, rules, paid products or releases. A
control deploy requires `--deploy-control` plus the checkpoint environment
variables described by the script. Public R2 custom-domain attachment and P4
route contraction are operator-run actions after their evidence gates.

Editor photos use a 1600 px maximum edge, JPEG quality 85 and a 1.5 MiB output budget. Ticket backgrounds use 1600 px, quality 90 and 2 MiB for print detail. The server keeps aspect ratio and never upscales; only an image that exceeds its byte budget receives additional downscaling. These storage dimensions are independent of the 1200 px in-memory preview bound.
