# Stable-version policy

Festapp uses the newest stable versions available at the start of a rehearsed
release, with one compatibility boundary: Supabase services and PostgreSQL are
selected as the newest **tested self-hosted Supabase release bundle**, not as an
untested collection of individually newest container tags.

The 2026-08-27 cutover candidate is Supabase `self-hosted/v0.8.0` at commit
`241bb11c0627f2981746d37033f57dbfa81d29b0`. It contains PostgreSQL
`17.6.1.136`, matching the canonical source's PostgreSQL 17 major. Source `a`
on PostgreSQL 15 is logically exported into staging and transformed; its data
directory is never opened by PostgreSQL 17.

PostgreSQL 18.6 is the newest upstream stable version, but the selected stable
Supabase bundle does not support it as its tested default. Moving the canonical
database to PostgreSQL 18 is therefore a separate post-cutover release with its
own backup, restore rehearsal and rollback gate. This preserves both user goals:
no knowingly stale production software and no database-major change hidden
inside the data consolidation.

All container references are pinned by human-readable tag and `linux/arm64`
digest in `runtime/pins.json`. Before the first rehearsal and again immediately
before production cutover, refresh stable-version research from primary
sources, resolve new digests, inspect breaking/security changes, run the full
restore suite and commit the updated manifest. A newer release is adopted only
as a complete tested bundle. Mutable `latest` tags are prohibited.

Run `node runtime/verify-pins.mjs --online` to compare release pins with primary
upstreams. Before production cutover, authenticate to Docker Hub and run
`node runtime/verify-pins.mjs --online --registry` to re-resolve every declared
container digest for `linux/arm64` without relying on anonymous pull quotas.

Terraform is pinned to stable `1.16.1`, published on 2026-09-02 and verified as
non-prerelease through GitHub Releases. It is a patch release containing CLI,
test, import and state bug fixes; `required_version = "~> 1.16.0"` already
accepts it. The Hetzner provider remains pinned to stable `1.68.0`.

No update workflow may invoke Supabase `reset.sh`, `docker compose down -v`,
volume pruning or any equivalent deletion command. Cloud sources remain intact
and writable/read-only according to the current migration wave until a separate
explicit destructive approval is recorded.
