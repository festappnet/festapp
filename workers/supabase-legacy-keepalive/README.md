# Legacy Supabase keep-alive

Cloudflare Worker that performs one small authenticated database query against
each cloud Supabase source every day. Its purpose is to retain the cloud sources
as rollback archives while Festapp runs on self-hosted Supabase.

This is an intentional read-only retention boundary, not an application writer
or rollback path. It uses only legacy anon keys, sends `GET`, has no public HTTP
route, and must be removed when the approved cloud-retention period ends.

The target list mirrors `automation/hetzner-supabase/merge/source-registry.json`.
When that registry changes, update the list and tests together.

The `SUPABASE_LEGACY_ANON_KEYS` Worker secret is a JSON object keyed by project
ref. Values are the corresponding legacy anon keys. Deploying requires an
authenticated Wrangler session:

```sh
npm install
printf '%s' "$SUPABASE_LEGACY_ANON_KEYS" | npx wrangler secret put SUPABASE_LEGACY_ANON_KEYS
npm run deploy
```

The Cron Trigger runs at 04:17 UTC. Failures are recorded in Cloudflare Workers
observability; the Worker deliberately has no public HTTP endpoint.
