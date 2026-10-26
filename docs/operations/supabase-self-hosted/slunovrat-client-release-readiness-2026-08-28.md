# Slunovrat client release readiness — 2026-08-28

Slunovrat client releases must be generated from current canonical `main` plus
the narrow `festivalslunovrat` tenant overlay. The old
`origin/prod/festivalslunovrat` branch is a historical data/config reference,
not a merge source for shared application code.

Verified configuration inputs:

- canonical backend origin: `https://api.festapp.net` (activate only at final
  cutover);
- mapped organization: `19`, not legacy source ID `1`;
- web origin and associated domain: `app.festivalslunovrat.cz`;
- iOS bundle ID `festapp.festivalslunovrat`, team `8WKBB6L8LT`, and app group
  `group.festapp.festivalslunovrat`, verified in renewed App Store profiles and
  in the signed candidate;
- Android application ID `fstapp.slunovratopava` as configuration only; the
  signed build remains deferred to the independent Windows workstation;
- languages `cs,en,pl`, brand colors `#53707f`, `#f8c04f`, `#de703e`,
  `#e9dabb`, and font `Agrandir-Narrow`;
- a unique auth-storage namespace retaining the old project-ref suffix and a
  new push-app generation.

The main-owned overlay schema, path allowlist, config generator and matrix tests
now recognize `festivalslunovrat`. A production overlay must be created only
after these changes land on canonical `main`, recording that exact main SHA.
It must include a private canonical release manifest with the public-key digest,
organization `19`, Auth/reset/CORS origins, session-transition evidence and
deployment generation.

Completed after the initial readiness inventory:

- the canonical public-key digest is recorded in the private tenant release
  manifest; no secret key is committed;
- canonical Auth, reset and Edge Function allowlists include the Slunovrat
  production origin with constrained callback paths;
- all 259 current client RPC names, 14 invoked Edge Functions and 48 directly
  used relations are present on the canonical target;
- the version-93 Cloudflare candidate is deployed at
  `festivalslunovrat.pages.dev`; Program, event detail, in-app back navigation,
  Map and canonical REST/RPC reads were exercised successfully;
- the existing OneSignal application retained the production
  `app.festivalslunovrat.cz` web origin, and a zero-recipient provider canary
  succeeded without sending a notification;
- compact offline-map schema 3 is implemented on canonical `main` without
  changing the existing schema-2 dual-renderer contract. Immutable Slunovrat
  `festivalslunovrat/v2` is publicly verified with 12 assets / 29,783,342 bytes
  (28.4 MiB), down from 79,999,911 bytes. It contains PMTiles plus Latin,
  Latin-Extended and General-Punctuation glyphs, no duplicate MBTiles payload,
  and has manifest SHA-256
  `95f8ceec864f1b2464ea4c414f9a8c3cc5c785f9de2a9ef14f22e590d556456f`;
- encrypted canonical backup and isolated restore verification passed.

The version-93 Cloudflare candidate was rebuilt from canonical `main` as
`0.19.93+471` and deployed to `festivalslunovrat.pages.dev` in legacy-backend
mode. A clean browser profile selected organization `1`, loaded occasion
`2025-copy-98cf835a`, and rendered the complete public program. This replaces
the old production web client's indefinite splash-screen behavior without
changing the externally controlled Slunovrat DNS.

The legacy cloud also contained a partial inventory migration: the pool,
context and resource tables and their RPCs were present, but `eshop.spots`
lacked the nullable columns referenced by those RPCs. Migration
`database/migrations_legacy/0.19.93.sql` completed that table shape
transactionally. The affected inventory tables and `eshop.spots` contained
zero rows before and after the change; four nullable columns and three
`ON DELETE SET NULL` foreign keys were added, and an authenticated
`get_user_inventory()` verification completed without PostgreSQL `42703`.
No occasion, user, ticket, order or Storage data was changed.

An iOS build-only pass then produced an unsigned 304.4 MB Xcode archive for
`festapp.festivalslunovrat`, version `0.19.93` build `471`, display name
`Slunovrat 2026`, with the notification service extension embedded. No IPA was
uploaded or submitted. App Store Connect readback matched Apple ID
`6481703402`, app name `Festival Slunovrat`, team `8WKBB6L8LT`, the main bundle
ID and the extension bundle ID. Both App IDs have App Groups enabled; the main
ID additionally has Push Notifications and Associated Domains.

The two stale local App Store profiles were replaced with uniquely named
build-candidate profiles using the sole valid distribution certificate. Both
new profiles expire on 2027-08-04 and remain owner-only in the private
`festappseed` signing directory. The notification extension App ID was corrected
in Apple Developer to share `group.festapp.festivalslunovrat` with the main app,
and both profiles were refreshed afterward.

The guarded signed build-only lane then produced
`Slunovrat.ipa` from source `a5ec993b52d1beeef43532c69d539384f8b27d8a`,
version `0.19.93` build `471`, with 43,481,704 bytes and SHA-256
`a648ed3595500cf00449e13f386db430dd0f11a919f97a15181ce830042a788d`.
The embedded Runner signature uses production push, the expected associated
domain and `group.festapp.festivalslunovrat`; the notification extension has
the same group. `OneSignalLocation.framework` is absent. The build used the
private backend/session-transition contract and a dedicated private signing
keychain. App Store Connect was not mutated and the IPA was not uploaded or
submitted.

Remaining external/final-cutover gates:

1. point `app.festivalslunovrat.cz` at the prepared Cloudflare Pages project and
   verify TLS, OneSignal service-worker scope and provider delivery on that real
   origin;
2. point the build-only Slunovrat candidate at the verified offline-map v2
   manifest and complete native cold-start/airplane-mode acceptance before
   setting `forceOfflineMap=true`; the manifest is published but intentionally
   not yet activated for older installed clients;
3. install and smoke-test the validated signed iOS candidate on a physical
   device against the legacy backend and the real production origin; do not
   submit the final App Store release yet;
4. prepare the Android configuration, but defer the signed build to the
   independent Windows workstation;
5. perform the production write freeze, final delta import and zero-lag audit,
   then publish the backend activation generation and verify session continuity;
6. only after those gates, authorize custom-domain production activation and
   later the mobile store releases.

No App Store upload, Google Play upload, Android build, production freeze,
production write-authority switch or global backend activation was performed by
this rehearsal.
