# Self-hosted client release rehearsal — 2026-08-28

The corrected client rehearsal used an isolated post-merge CSM overlay over
shared source commit `521cebfd3dfbd996e0ff8e59c2198a565963e6c6`. It preserved the production
mobile identities (`fstapp.jm2025` and `festapp.jm2025`) while pointing only to
`https://rehearsal-api.festapp.net`. Production DNS and store state were not
changed.

The final browser audit caught and corrected one release-contract gap: source
organization `9` is target organization `12`. The client preflight now binds
`ORGANIZATION_ID` to `backend.organizationId`, so an old cloud numeric ID cannot
survive a deterministic merge unnoticed. Web and mobile rehearsal candidates
must be rebuilt from that corrected contract; the earlier organization-9
artifacts are invalid evidence.

## Web

The corrected CSM web profile `0.19.92+450` was assembled at pushed isolated
overlay commit `ff89230cc73f2994a8b18e97653dc8f835255157` with organization `12`. It
passed the canonical-cutover preflight, Flutter
release build, vanilla-client build, completed-bundle verifier and deployment
verifier. It is deployed only to the isolated Cloudflare Pages project at
`https://festapp-rehearsal-client.pages.dev`; the verifier passed three
consecutive probes. A clean Chromium canary on the actual Flutter occasion route
`/csmostrava2026` reached application-ready state with zero startup errors and
used only the Pages, rehearsal API, Festapp image and OneSignal CDN/API origins.
Its private mode-0600 HAR has SHA-256
`8b6967b5de6025acd6b9a7717a756b12d283cac0b7218ab1bec6f30d1e1487cc`.
The production CSM Pages project was not changed.

## iOS

`automation/release/ios_build_candidate.sh` provides a build-only release path:
it has no Fastlane, Transporter or App Store Connect call. The signed App Store
organization-12 IPA for `festapp.jm2025`, version `0.19.92 (450)`, was built at
isolated overlay commit `ff89230cc73f2994a8b18e97653dc8f835255157` and passed
bundle/version and distribution-certificate inspection. The retained private
artifact is 43,420,446 bytes with SHA-256
`2b4f5b210fad1d0e0204fc3dcf1bcb596d09c317c305a5c4fa730cc0d7d5b3ea`.
Its mode-0600 evidence has SHA-256
`35ef0c395480b0f63c7447a0e16ecafa50fa85105a74a687ecdba36efb3810d4`.
All earlier organization-9 and pre-credential-rotation IPA candidates are
superseded and must never be uploaded. App Store Connect was not mutated.

## Auth, rights and idempotent write

The existing review account password was read from macOS Keychain and never
written to evidence. Against the public rehearsal origin, password login,
`/auth/v1/user`, and the rights RPC returned HTTP 200. An existing saved-program
row was sent through the public write RPC in idempotent `join` mode; the exact
before/after aggregate digest matched and zero target rows changed. The current
application is email-only: target Auth settings expose e-mail and keep Google
OAuth disabled, and the disabled-provider request was rejected with HTTP 400.

This auth/rights/write evidence is independent of the superseded IPA. It is
mode 0600 and has SHA-256
`d594aca5b2d6213bda4cd242cb65ab57496b5ca2c3225618ee18ad79014fc73c`.
Cloud sources, production DNS and external provider accounts were not mutated;
no row was deleted.

## Android

Control-channel commands `1029` and `1030` are historical and have no retained
result. They target superseded source/build state and must not be reused. After
the refreshed tenant overlay is final, issue a new build-only command pinned to
that exact source and manifest. Android remains deliberately deferred to the
paired Windows workstation; no Play mutation is authorized.

## Rehearsal runtime credential rotation

The rehearsal PostgreSQL password, JWT secret, anon key and service-role key
were rotated under a Caddy maintenance gate after an encrypted recovery point.
Seven database logins and both database JWT settings passed, all services
returned healthy, the new anon/service-role credentials returned HTTP 200 and
both old public tokens returned HTTP 401. Persistent Vault, Realtime, S3,
dashboard and provider credentials were deliberately left unchanged. No
production target or DNS record was mutated. The web and iOS evidence is pinned
to the new public anon-key digest; a future Android command must derive the same
digest from its final manifest rather than historical command state.

## Notification delivery credential

The rehearsal audit found that the OneSignal REST credential historically lived
inside `organizations.data` and could therefore cross the admin-client DTO/RPC
boundary. Migration `20260828110000_move_onesignal_credentials_server_side.sql`
now extracts it into a no-direct-grants, RLS-enabled server-only table. The
admin RPC scrubs the legacy key, the admin update rejects attempts to restore
it, Flutter no longer models or edits it, and both delivery Functions use the
service-role-only configuration RPC. An isolated copy migrated 10/10 values,
left zero legacy JSON keys, and passed the SQL and Edge tests. The active
four-argument admin RPC is also hardened and the obsolete three-argument
overload is absent, preventing a released client from bypassing the guard.

The provider credential itself must still be rotated through an authorized
OneSignal/private-configuration session. Production activation remains blocked until the
replacement is provisioned, notification and account-deletion canaries pass,
and the historical key is rejected. No secret value is recorded in this
repository.

The final production release still requires a fresh post-merge tenant overlay,
the production `api.festapp.net` manifest, store approval/adoption evidence and
the production full-freeze/final-marker gate.
