# Security release - 2026-10-09

The reviewed security package is merged and its backend and shared image-worker changes are deployed. The selected frontend tenant is `festapp` only. Final frontend evidence is recorded below. This release does not claim retirement of old mobile contracts or completion of a full penetration test.

## Source and deployment

- [PR 352](https://github.com/festappnet/festapp/pull/352), main `721ee4622cf12fd9802491b22d985f338dcabaf3`: SQL/XSS/RPC fixes, compatible code/count transitions and dependency remediation. The user explicitly authorized administrator merge despite the one-review rule; repository protection settings were not weakened.
- [PR 353](https://github.com/festappnet/festapp/pull/353), main `e441a2341823cc4477c12d4e32cfe3b0c704cc8e`: code exchange receives the unprefixed mailbox; ordinary password Auth retains its tenant-prefixed identity. The first frontend workflow was cancelled before build/deploy after this compatibility issue was found.
- [PR 354](https://github.com/festappnet/festapp/pull/354), main `991be7c35e42830c18e6f35773b8dd736e6af899`: advanced-mode Cloudflare Pages Worker now injects CSP/nosniff into final responses. The initial `_headers` files were removed by the build, as live verification revealed.

### Canonical backend

Activation, organization, hostname and runtime database identity were checked before writes. Four exact canonical migrations were applied in one transaction together with their ledger rows:

- `20261009120000_security_rpc_authorization.sql`
- `20261009131500_secure_email_template_writes.sql`
- `20261009133000_event_attendance_summary.sql`
- `20261009143000_expiring_sign_in_code_protocol.sql`

Source SQL digests, the transaction, previous function definitions/owners/ACLs and operation logs are retained in the protected host evidence directory `security-release-20261009-721ee4622`. Post-commit readback confirmed all four ledger entries, restricted anonymous grants and NULL guards. Read-only checks returned 403 for absent attendance identity and an empty aggregate for an empty request.

The canonical Edge bundle from `721ee4622` was installed with its verified digest and previous directory retained. The existing Compose configuration recreated only the functions service. The public invalid-proof exchange returns 200 with empty JSON; registration/invitation preflights return 200. No production test users, customer mutations, email sends or fake orders were used for validation.

### Shared image control worker

New version `684241fa-7bfb-433d-aa9b-ccb0d42821c6`; rollback version `63e8aab7-74fa-48e3-9d59-18bafaa9258c`. The unchanged deploy script passed typecheck, 34 unit tests and dry-run. Its localhost guard skipped 27 remote integration tests that would create a real backend account.

Live domains, routes, bindings and variables match their prestate. Unauthenticated private access and an invalid presign method return expected 401/405. DNS/ruleset/cache-rule read access returned 403; those resources were outside this code-only release and were not changed. This is not evidence of a completed image-routing/cost cutover.

### Festapp frontend

Version **0.20.144+628**, tenant commit `e571e348f1b74c2df3f7cc7cb98e6351907f804e`, canonical main `991be7c35e42830c18e6f35773b8dd736e6af899`. [Release workflow](https://github.com/festappnet/festapp/actions/runs/37866589074) succeeded with coherent live version, assets and legal-page checks. Live `/`, `/form/`, `/login`, `/backend-activation.json` (200) and `/flutter` (301) all returned `Content-Security-Policy: base-uri 'self'; object-src 'none'` and `X-Content-Type-Options: nosniff`. Only `prod/festapp` was released.

## Validation and audit state

The package passed 28 scan/attendance checks, 11 isolated SQL suites, 40 frontend tests/build, 14 Deno tests, worker/tooling checks, and four focused Dart authentication tests. Generated Pages worker tests cover response bodies, policy headers, redirects, activation CORS and OAuth cache/referrer controls. Deployment workflows supply their own drift, legal, build and coherent live-version/assets/legal gates.

All 53 recorded Dependabot alerts and one additional high NanoID advisory were addressed with supported dependency versions. Seven affected npm projects audited at zero, including development dependencies. GitHub returned zero open Dependabot alerts after merge; no alerts were dismissed. The [alert reconciliation](github-security-alerts-2026-10-09.md) preserves IDs and versions.

GitHub secret scanning, push protection and automatic Dependabot security updates remain disabled. Code scanning returned no available analysis. These coverage gaps were not represented as clean scans, and repository security settings were not changed.

## Preserved compatibility and remaining gates

- Older installed clients still require their existing attendance reads. Current Flutter uses aggregate counts/own-state; removing the raw UUID policy requires the documented [client cutover](event-attendance-privacy-cutover-2026-10-09.md).
- Updated registration opts into expiring, attempt-limited, one-use code v2. Legacy invitations and historical weak passwords are not automatically revoked; recipients need a compatible client/recovery transition.
- Project-wide editor file sharing remains intentional. Narrower access requires authoritative owner/classification metadata, not assumptions from old paths.
- Deployed CSP is the compatible `base-uri 'self'; object-src 'none'` baseline, not a strict script policy.

Prefer a scoped forward fix if a legitimate path fails. Do not roll back by restoring anonymous privileged RPC access or NULL authorization bypasses. The temporary integration database and browser sessions were stopped; the unrelated original working tree was preserved.
