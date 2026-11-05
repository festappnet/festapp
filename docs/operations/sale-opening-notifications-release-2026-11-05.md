# Sale opening notifications - production release 2026-11-05

Released only the vstupenky.online web tenant (`prod/festapptickets`), organization 3.

- Shared source: `ef1c1bcc78f8b8ad7f9d6e206602f03ce9c8e3c2`.
- Tenant revision: `69c6eb41d664a888a4be7ac2c4dd4504dcd3e3d1`.
- Version: `0.20.501+1008`.
- Direct local Cloudflare deployment: https://e825cc48.vstupenkyonline.pages.dev
- Live target: https://vstupenky.online

Canonical source was isolated from the original dirty checkout, integrated onto
current main, validated and published. The selected tenant retained its previous
production tip as a merge parent, used the main-owned overlay policy and passed
drift checks. Both authoritative refs were fetched before publication. The local
build used the existing protected approved release manifest without modification;
no GitHub production build/workflow was dispatched. Live coherence verification
passed three consecutive probes.

The block is positioned near the top and horizontally centered. The local JS
visual check measured zero center offset at 1280px and 375px with no horizontal
overflow. The independent live browser smoke found no browser errors, confirmed
the deployed helper asset is JavaScript, both public/browser shells reference it,
and confirmed current Czech label and success template with `{email}`.
Existing forms remain default-off; owners enable collection in their form settings.
The countdown remains independent.

## Backend execution

The verified canonical host, database and activation identified festapptickets
organization 3. Migration `20261104130000` and its ledger record were applied
atomically from canonical SQL with SHA-256
`08d1231e9778399872d4d050e6ee446fd53f39d79564182c570d0bdb795bd05e`.
There was no production contact/campaign backfill or test enrollment.

The official full Functions bundle was built from clean canonical main and installed
through the existing verified installer. Bundle digest:
`97182ddf94e6aaf74129ae0a5f9d14ad5ba176b8ad19189c75418fadde79acef`.
The writer-policy change added only the new endpoint and its proof contract.
The reviewed configuration migration preserved the complete six-overlay model,
added exactly three Turnstile inputs, retained protected rollback evidence and
scoped them to the owning worker. Production hostname validation permits only
vstupenky.online. The guarded Functions restart and worker authorization probe passed.
The public protection operation returned 200 and the expected public sitekey;
invalid proof returned 400 without enrollment.

This installation hosts pg_cron in the control-plane postgres database rather than
the app database. The single new named job
`festapp_canonical_sale_opening_notifications` was created inactive there using
`cron.schedule_in_database`, targeting only the verified application database, then
enabled after probes. Its every-minute command is
`SELECT public.maintain_sale_opening_notifications(100)` and a real run succeeded.
Other cron jobs were not activated or reconfigured.

Email was paused/drained for the runtime changes and restored to its prior
unpaused state afterward. Final health: no alerts, producer access valid, fresh
heartbeat and no sends in flight. No synthetic production email was sent.

## Validation and limits

Final isolated-source checks: 118 Flutter tests, 46 JS tests, 24 Edge tests,
11 SQL tests plus real PostgreSQL concurrency, six CSP tests and two bounded
runtime-configuration tests. The later safe-diagnostic adapter check passed five
tests. A user-reported local successful real-provider signup correlated with the
new active row and guarded Edge request, sole current unsubscribe capability and
unchanged email count. Automated real-provider challenge reproduction returned
600010; it was not bypassed. Production smoke was read-only, not an enrollment
or a test of actual provider email delivery.

Native Flutter has no Turnstile WebView adapter; this web release supports the
public JS and Flutter web clients. No Android/iOS or other tenant web release was
performed.
