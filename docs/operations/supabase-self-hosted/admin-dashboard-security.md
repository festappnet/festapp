# Supabase administrator dashboard boundary

The Cloudflare control-plane tunnel `festapp-supabase-admin`
(`40e1a9a2-d1d5-4789-a691-20818d648b95`) was provisioned on 2026-09-10 with
the exact loopback ingress and a `404` catch-all. It remains inactive and has no
public DNS route until the Access and origin gates below pass.

## Target state

- `api.festapp.net` remains the canonical application endpoint. Only the
  established Auth, REST, Storage, Realtime, Functions, and GraphQL path
  families reach the Supabase gateway.
- `supabase.festapp.net` is the only browser administration endpoint. It is
  published through the dedicated `festapp-supabase-admin` Cloudflare Tunnel;
  the origin listener remains `http://127.0.0.1:8999` and receives no inbound
  Internet traffic.
- Cloudflare Access protects the entire administrator hostname before traffic
  reaches the origin. Its allow policy contains only `bujnmi@gmail.com` and
  `vichapavel@gmail.com`; no domain-wide, country-wide, bypass, or
  service-token rule grants interactive access.
- Administrators authenticate through Google and Cloudflare independent MFA.
  The Access application requires MFA and uses a one-hour maximum session.
  After Access succeeds, the loopback-only Caddy proxy supplies the existing
  Supabase HTTP Basic credential to the upstream gateway; the credential is
  never sent to the browser, so the user proceeds directly to Studio.
- Cloudflare Access logs identify the person. Runtime access logs and PostgreSQL
  audit logs remain encrypted off-host for 30 days. Studio still uses one
  database role, so durable SQL changes belong in reviewed repository
  migrations; dashboard SQL is an emergency/diagnostic path.

## Ordered activation

1. Enable Cloudflare Zero Trust for the existing account and configure the
   approved MFA-capable identity provider.
2. Create a self-hosted Access application for the exact administrator
   hostname. Add only approved email identities and require MFA. Verify an
   anonymous request is intercepted by the Cloudflare Access login endpoint.
3. Route `supabase.festapp.net` only to Cloudflare Tunnel
   `40e1a9a2-d1d5-4789-a691-20818d648b95`; never point it at the server IP.
   The tunnel has one ingress rule to `http://127.0.0.1:8999` and a mandatory
   `http_status:404` catch-all. Do not change the `api.festapp.net` record.
4. Install the root-only tunnel token and the candidate Caddy and Compose files with
   `upgrade-installed-production-runtime.sh`. This step does not restart the
   runtime and leaves the administrator listener on loopback. The pinned,
   capability-free, read-only `cloudflared` container is disabled behind the
   `admin-dashboard` Compose profile until activation. It runs as container
   root only because Compose preserves the host's root-only `0600` permissions
   for file-backed secrets; it has no Linux capabilities or writable root
   filesystem.
5. Run `activate-admin-dashboard.sh` with its exact acknowledgement. The script
   proves the Access interception, validates that the token belongs to the
   approved tunnel, records baseline API canaries, starts Caddy plus the tunnel,
   and then proves a live tunnel, an authenticated local Studio redirect plus
   an unauthenticated `401` from the upstream gateway, Auth `200`, REST
   `200`, Storage `200`, Realtime `101`, plus `404` for Studio and postgres-meta
   on the public API hostname.
6. Complete a login through Access, open Studio, and run only
   `select current_user;` for the first authenticated check. Confirm the Access
   event contains the expected administrator identity.

The activation script preserves the prior environment, Caddy configuration,
and Compose override and restores them automatically if any post-change API or
exposure check fails. It does not change the database, API credentials, Auth
configuration, client configuration, or any tenant branch.

## Non-negotiable gates

- Do not activate while Access is disabled or only an email OTP identity is
  available without the retained second authentication layer.
- Do not enable One-time PIN as an alternate Access login method. Require the
  MFA claim from the selected IdP; prefer a passkey or hardware security key.
- Enable Access denied-login alerting and tunnel disconnect alerting before
  adding the second administrator.
- Do not add `supabase.festapp.net` to application CORS or Auth redirect lists.
- Do not expose ports 3000, 5432, 6543, 8000, or 8443 publicly.
- Do not share the existing administrator identity as a substitute for adding
  a named Access user.
