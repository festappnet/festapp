# Rehearsal public origin — verified 2026-08-28

`https://rehearsal-api.festapp.net` is the isolated public compatibility endpoint
for the merged rehearsal database. It is not the production cutover hostname.

## Deployed path

```text
client
  -> Cloudflare proxied DNS/WAF (hostname-specific TLS Strict rule)
  -> Hetzner firewall (official Cloudflare IPv4/IPv6 ranges only)
  -> Caddy 2.11.4, pinned image digest
  -> 127.0.0.1:8000 Supabase gateway
```

Cloudflare Workers, Hyperdrive and D1 are not in the relational request or write
path. The rehearsal endpoint therefore adds no per-request Worker billing and no
second database interface. It uses the existing Cloudflare Free zone and the
existing EUR 7.8529/month Hetzner server.

The firewall retains the existing restricted SSH rule and ICMP diagnostics. It
accepts ports 80 and 443 only from the 15 IPv4 and seven IPv6 ranges published at
`https://www.cloudflare.com/ips-v4` and `https://www.cloudflare.com/ips-v6`,
checked on 2026-08-28. PostgreSQL, Studio, Supavisor and the gateway have no
public host binding. The gateway remains on `127.0.0.1:8000` and
`127.0.0.1:8443`.

Caddy obtained a publicly trusted Let's Encrypt certificate for the exact
rehearsal hostname. The Cloudflare configuration rule
`Rehearsal Supabase strict origin TLS` matches only
`rehearsal-api.festapp.net` and enforces `Strict`; the zone-wide mode and other
Festapp origins were not changed.

## Runtime evidence

After activation:

- all 11 Supabase services were healthy and `festapp-caddy` was running;
- Auth health and settings returned HTTP 200 with the rehearsal anon key;
- representative public REST tables returned HTTP 200;
- Realtime completed an HTTP 101 WebSocket upgrade;
- a real public Storage object returned HTTP 200 with 124,228 bytes;
- a direct `--resolve` connection to `46.224.187.4:443` from a non-Cloudflare
  source timed out, proving the origin bypass was closed;
- the presented origin certificate matched `rehearsal-api.festapp.net`, was
  issued by Let's Encrypt, and expires 2026-11-25.

The target generated a new anon key and signing secret. Password hashes are
preserved, but existing access-token continuity is not implied; login,
refresh-token and release adoption remain explicit cutover gates.

The refresh-token gate subsequently passed for both imported Auth cohorts on
the isolated second rehearsal database. One non-overlapping `default` session
and one non-overlapping `a` session each exchanged its imported refresh token
through the public rehearsal endpoint, rotated the token, received an HS256
`authenticated` access token for the same user UUID, and passed `/auth/v1/user`
with HTTP 200. Only those two isolated target tokens were rotated; neither
cloud source was mutated and no row was deleted. The private evidence file has
SHA-256 `4739f8fb3d1de54a6720cd8257b4d1c3950dc6ec1617635e35657744aedd9e82`.

Old access tokens from both cloud projects are deliberately not accepted as a
second trust path. GoTrue can hold multiple keyed verification keys, but these
legacy HS256 tokens have no `kid` and fall back to one configured secret. The
client contract is therefore refresh first, then normal reauthentication only
for terminal refresh failures. Web already performs that transition when the
backend origin marker changes; Flutter now persists a rotated refresh token and
clears only terminal `refresh_token_not_found` or
`refresh_token_already_used` sessions. Network errors preserve offline identity.

## Remaining production gates

The rotated-credential CSM web release and signed iOS candidate now pass against
this hostname from pushed overlay `ff89230cc73f2994a8b18e97653dc8f835255157`.
Password, refresh-token, rights and idempotent write canaries also pass; the
application's intentionally disabled Google provider is preserved as disabled.
The retained details are in `client-release-rehearsal-2026-08-28.md`.

1. Generate a new build-only Windows command only after the refreshed tenant
   overlay is final. Historical commands `1029` and `1030` have no retained
   result and must not be reused; Android remains deliberately deferred.
2. Prepare `api.festapp.net` with the same firewall, Caddy and strict-TLS
   contract, but do not activate it before the final freeze/journal gate.
3. Rewrite every retained registered legacy Storage URL only when the canonical
   production hostname is live and verified.

Client release tooling now accepts a custom HTTPS Supabase origin, preserves an
explicit browser auth-storage namespace across the hostname change, refreshes a
stored web session before the first rights query, and requires a non-empty
installation generation for self-hosted releases. Android and iOS builders run
the same fail-closed client preflight. These are readiness mechanisms, not proof
that a release has been built or adopted; the gate above remains open until the
actual web bundle and store artifacts pass against this endpoint.

The rehearsal runtime now explicitly uses
`https://festapp-rehearsal-client.pages.dev` as Auth `SITE_URL` and allows only
its two password-reset routes. Cross-origin callbacks remain rejected.

No cloud project, backup, restore database, Storage object or other retained
artifact was deleted during this activation.
