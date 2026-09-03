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
