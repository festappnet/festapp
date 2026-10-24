# Image delivery and control plane

Public image bytes and authenticated image operations are separate contracts.

## Checked-in routing and pending target

| Plane | Host | Checked-in route | Conditional target |
|---|---|---|---|
| Default public data | `img.festapp.net` | `festapp-image-worker` -> R2 `festapp-images` | Direct public R2 domain after P3 |
| Project A public data | `a.img.festapp.net` | `festapp-image-worker` -> R2 `festapp-images-a` | Direct public R2 domain after P3 |
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
Existing canonical Storage URLs are unchanged. Its public uploads retain the
owner-scoped `check_upload_permission` and `add_image_record` RPCs; private
operations are disabled. Both `slunovrat.festapp.net` and
`app.festivalslunovrat.cz` are exact allowed control origins. See the
[2026-10-12 recovery evidence](../operations/slunovrat-image-upload-recovery-2026-10-12.md).

## Required bindings and secrets

- R2: `IMAGES_BUCKET`, `IMAGES_BUCKET_A`, `IMAGES_BUCKET_AKHWEB`, `IMAGES_PRIVATE_BUCKET`,
  `IMAGES_PRIVATE_BUCKET_A`.
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

All new Flutter image copies download the existing public URL and upload through
the same control Worker as ordinary uploads, including its SQL admission. This
also migrates an individual historical Storage image when copied. There is no
Storage copy writer. Restrictive Storage INSERT/UPDATE policies also close the
old public-files, images-temp and editor-files API writers. Listing and deleting
legacy public-files metadata requires the existing image ownership authorizer;
public image bytes remain readable at their existing URL. `add_image_record`
requires one authorized owner and central rolling/occupancy/URL limits; direct
images INSERT/UPDATE grants are removed. Existing installed writers must migrate
to the control API before this prepared server cutover is activated. Reading and deleting existing Storage images remains an
explicit compatibility boundary: the October 12 Slunovrat readback still found
224 Storage image records. Remove that boundary only after a current canonical
database inventory proves no remaining references and released clients permit it.

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
