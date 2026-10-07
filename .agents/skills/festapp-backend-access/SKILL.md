---
name: festapp-backend-access
description: Use the persisted, protected SSH tunnel to the canonical self-hosted Festapp Supabase backend for authorized diagnostics, SQL migrations, Edge Functions or backend configuration. Avoid repeated human Cloudflare MFA, direct public SSH and former cloud projects.
---

# Festapp backend access

Use `ssh festapp-backend-agent` first. The workstation's SSH alias uses a dedicated
Cloudflare Access Service Auth application plus its existing SSH private key.
The machine service token is scoped to that one SSH application, expires after
one year and lives only in macOS Keychain. Studio keeps human MFA unchanged.

## Resolve and verify the target

Read the Festapp repository's `CLAUDE.md`, `docs/architecture/ai_context.md` and
applicable agent rules. Resolve the requested tenant from its project.conf and
live backend-activation.json, including generation and canonical organization.
Authorization for one tenant does not authorize other tenant writes or releases.

Read the private connection's non-secret target assertions:

```sh
python3 <this-skill-directory>/scripts/target.py
ssh festapp-backend-agent hostname -s
```

On this workstation the skill directory is
`~/.codex/skills/festapp-backend-access`. Target assertions must match the SSH
hostname, active `FESTAPP_RUNTIME_DATABASE` in `/opt/festapp-supabase/docker/.env`,
`current_database()` and requested tenant organization before querying data or
writing. Do not print the runtime .env, credentials or private connection data
into public artifacts. Stop on a mismatch rather than trying another backend.

## Persisted machine authentication

The local SSH alias and known-host identity are in `~/.ssh/config` and
`~/.ssh/known_hosts`; do not overwrite other entries or disable host-key checks.
Its ProxyCommand runs this skill's `scripts/proxy.py`. The proxy reads Keychain
service `festapp-backend-ssh`, account `festapp-workstation`, and supplies service
credentials to cloudflared through child environment variables, not command
arguments or logs. It refuses missing, invalid or expired credentials.

There is no public direct SSH rule and no retained Hetzner administration token.
The temporary bootstrap token was revoked and removed from Keychain. Do not
recreate it, expose port 22, grant a machine token access to Studio, export
credentials or open a human browser login while the persisted alias works.

The connection is privileged server administration using the existing SSH key;
it is **not** a restricted SQL role. An authenticated machine does not authorize
arbitrary shell commands, production writes or other tenants. Default database
diagnostics to an explicit read-only transaction and prefer fixed catalog/identity
queries over customer rows. A compromised workstation/SSH key requires revocation;
a public explanation of the method does not supply either authentication secret.

If a credential is expired/revoked or the alias/host-key assertion is missing,
report the specific blocker. Provisioning, rotation and recovery require appropriate
task authorization. Revoke the dedicated Cloudflare service token to disable this
route; Studio and unrelated applications need no policy changes.

## Authorized backend releases

Use SSH and `docker exec -i supabase-db psql -X -U postgres -d <verified-database>
-v ON_ERROR_STOP=1`, following the repository's approved release workflow. Do not
retrieve postgres passwords or Supabase service-role keys. Use exact canonical
repository SQL from verified authoritative main, verify its digest and migration
ledger, preserve required rollback evidence, apply SQL and ledger atomically,
notify PostgREST when required and verify the result. Preserve required review
and production-write gates. Never run production fixtures/tests or touch other
sessions' worktrees.

The named-user `automation/hetzner-supabase/runtime/access-sql.py` remains a
recovery fallback, not the default path. The proposed bounded SQL diagnostics
broker is **not enabled**: inherited PUBLIC grants prevent its planned role
isolation. The active SSH tunnel is a separate administrative transport; do not
represent the broker prototype in Festapp PR #252 as an active restricted channel.

This skill is project-scoped to the Festapp repository under
`.agents/skills/festapp-backend-access`. Do not install it globally or apply it to
unrelated projects. Credentials are protected workstation provisioning inputs
and never repository content. Never commit private target metadata.
