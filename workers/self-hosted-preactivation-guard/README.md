# Self-hosted pre-activation Function guard

Temporary Cloudflare edge boundary for `api.festapp.net/functions/v1/*`.
It returns fail-closed `503` responses while the canonical Function bundle is
staged but not yet promoted. This prevents the older rehearsal runtime from
exposing obsolete or operator-only Function implementations on the future
production hostname.

The guard has no bindings, secrets, database access or public `workers.dev`
route. Remove its exact route only after the reviewed canonical Function bundle
is active and internally verified, immediately before the canonical external
Function canaries. Its removal is a production activation action and belongs in
the cutover receipt.

```sh
../self-hosted-monitor/node_modules/.bin/wrangler deploy --config wrangler.toml
```
