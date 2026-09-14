# BISCUP client release readiness — 2026-08-30

## Canonical transition contract

- tenant overlay `prod/doobiscup` at
  `72d5a399272b7ac2dcdada1f298a9d486a0d779e` over canonical main
  `5236099ff3f6b7a5f29a2ab21ea37e27dc6abbbb`;
- Flutter `3.47.2`, application version `0.19.93`, web/iOS build `472`;
- production web origin and iOS associated domain `biscup.festapp.net`;
- legacy source `https://lwfpdjxsdmkfyrzqbrlk.supabase.co`, organization `2`;
- pinned canonical target `https://api.festapp.net`, organization `5`, with
  stable Auth storage and refresh-or-reauth session transition;
- iOS bundle `festapp.doobiscup`, notification extension
  `festapp.doobiscup.OneSignalNotificationServiceExtension`, and App Group
  `group.vkhcr.doobiscup.onesignal`;
- Android package `fstapp.diecezkodoo`; its signed build remains a separate
  Windows-workstation lane.

Organization `2→5` is a deterministic primary-key remap of the same BISCUP
tenant, not a change of business organization. The activation document couples
the endpoint and organization ID, so the client cannot use a legacy endpoint
with canonical ID `5` or a canonical endpoint with legacy ID `2`.

## Production web and legacy-origin retirement

Cloudflare Pages serves production build `0.19.93+472` at
`https://biscup.festapp.net`. A cold browser start loaded the BISCUP 2025
program in the legacy phase without application errors. The saved OneSignal web
origin was changed from `https://biscup.netlify.app` to the canonical domain;
a new browser session then completed notification initialization without the
previous origin rejection. The OneSignal app and Safari Web IDs were preserved.

The old Netlify origin is now a redirect-only compatibility surface. It returns
HTTP 301 for deep paths while preserving the path and query, and retains the
retirement service worker plus the OneSignal worker endpoint so an installed
legacy PWA is not left on a broken origin. Browser push subscriptions are
origin-bound and therefore require opt-in on the new domain; this does not
affect mobile push or require account reauthentication.

## Apple signing and test candidate

Read-only App Store Connect inspection found the existing BISCUP listing, Apple
ID `6472435824`; candidate build `472` is monotonic over the observed live build
`223`. Apple Developer configuration now assigns only the existing BISCUP App
Group to both the main Bundle ID and notification extension. Regenerated App
Store profiles were used with the existing distribution certificate.

Direct inspection of the signed, non-uploaded IPA proved production APNs, the
single BISCUP App Group on Runner and extension,
`applinks:biscup.festapp.net`, exact application identifiers, version
`0.19.93 (472)`, and absence of `OneSignalLocation.framework`. The IPA,
profiles and digest evidence are held only in private configuration storage. No
App Store version, upload or submission was created.

## Remaining gates

1. Physical-iPhone cold launch, retained-session, push and associated-link
   acceptance.
2. Separately confirmed App Store upload/release gate.
3. Android build and inspection on the approved Windows workstation.
4. Coordinated production freeze, final delta import, canonical activation and
   full-process legacy-to-canonical session/write canaries.
