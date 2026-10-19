# Runtime version policy

Use a tested self-hosted Supabase bundle with exact container tags and ARM64
digests. A database major upgrade needs its own backup, restore rehearsal and
rollback plan. Do not assemble a release by independently advancing individual
service tags or using mutable `latest` images.

The selected repository inputs are
[`runtime/pins.json`](../../../automation/hetzner-supabase/runtime/pins.json),
the Festapp Compose overlays and the host bootstrap. They describe the proposed
source configuration, not proof of what is installed on a live host. Verify the
installed versions and artifact identities during a scoped release.

## Check the pins

Run from the repository root:

```bash
node automation/hetzner-supabase/runtime/verify-pins.mjs
```

This checks local version/digest/source formats. For an authorized dependency
review, `--online` compares selected versions with primary upstream release
information and checks the selected upstream Compose bundle:

```bash
node automation/hetzner-supabase/runtime/verify-pins.mjs --online
```

With an authenticated Docker registry session, add `--registry` to check the
`linux/arm64` image digests. A newer upstream version can make this comparison
fail; that is a review finding, not authority to update or restart production.
Commit a rehearsed pin/Compose change before its release.

Terraform's repository constraint is `~> 1.16.0`; the hcloud provider is pinned
to `1.68.0` in `terraform/versions.tf`. The recorded 2026 cutover selected
Supabase `self-hosted/v0.8.0` at revision
`241bb11c0627f2981746d37033f57dbfa81d29b0`, including PostgreSQL `17.6.1.136`.
Earlier statements about the newest upstream PostgreSQL/Terraform version were
point-in-time research, not a current availability claim.

## Data and retention boundaries

An ordinary runtime update must not invoke Supabase `reset.sh`,
`docker compose down -v`, volume pruning or equivalent deletion. Former cloud
sources remain retained history/reconciliation targets; routine migrations and
writes must not reopen them. Their disposition follows the
[retention record](../work-items/completed/legacy-supabase-decommission-2026-09-23.md),
not the old migration-wave state. A restore or destructive recovery requires
its own exact target and authority.
