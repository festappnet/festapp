# Client sync v1 current status — updated 2026-08-05

The filename remains for stable links and supersedes its pre-activation
snapshot. Production occasion `csmostrava2026` (organization 9, occasion 643)
uses protocol 1. The component registry is ready and the canonical engine owns
public catalog/live and identity-scoped private projections.

Repository hardening now includes Cache API serving, one publisher with
authenticated five-second wake-up and minute recovery, failed-claim release,
complete event projections, bounded local generations/blob cache, guarded
occasion lifecycle, dry-run-first retention and read-only health gates. See
[client-sync-v1.md](client-sync-v1.md).

Production rollout recorded at 2026-08-05T13:40:00Z:

- Forward migrations `20260805233000`, `20260805235000` and `20260806100000`
  are applied to project `lwfpdjxsdmkfyrzqbrlk`. The rollout repair reduced
  event projection drift from 10 rows to zero.
- `festapp-sync-worker` version
  `b12e6778-a5f1-4a49-b46c-a7da6557c778` serves `sync.festapp.net`.
- `festapp-sync-publisher` version
  `586d6db5-5897-4c40-b0fa-2cfaa7b20b66` serves the authenticated wake endpoint.
  Vault and Cloudflare bearer secrets are present and cron job 18 is active at
  five seconds. The minute recovery and daily retention dry-run remain active;
  `SYNC_RETENTION_APPLY=false` prevents deletion.
- Edge functions `confirm-account-deletion`, `request-account-deletion`,
  `send-reset-password-link` and `send-sign-in-code` were deployed to the same
  project.
- Cloudflare Pages deployment `68782574` serves web release `0.19.84+380` on
  `csmostrava.festapp.net`; three consecutive manifest/root probes returned the
  expected version and HTTP 200.
- Post-scheduler publication lag was 4.26 seconds. Current dirty work, revision
  lag and projection drift are zero; the public head returns 200/304 and its
  artifact hashes verify. The 24-hour health window still contains old
  minute-fallback samples, so its historical p95 remains above the new SLO.

Still pending: complete the 24-hour observation, run the authorized 5k load
gate, and separately approve the first R2 deletion and first receipt
compaction. Retention must remain disabled until those gates are recorded.
