# Retired Storage routes

This terminal Worker returns 410 for canonical `/storage/v1` requests before
Cloudflare can serve a previously cached Storage object. Origin-only retirement
cannot invalidate those cached URLs immediately; measured legacy responses had
`Cache-Control: max-age=14400`.

It has no secrets, buckets, service bindings or origin fetches. Its two routes
cover only retired paths on `api.festapp.net`; live Auth/REST/Functions and the
independent AKH application remain outside them. Keep Caddy's origin rejection
and the contracted Compose runtime as the other boundaries.

Validate with `node --test workers/storage-retirement/test.mjs`. Deploy only from
verified main with Wrangler using `workers/storage-retirement/wrangler.json`,
then prove an original Storage URL returns 410 without a cache-busting query.
