# Absolventsky Velehrad client release readiness — 2026-08-29

The active application is `app.absolventskyvelehrad.cz`; the informational
site at `absolventskyvelehrad.cz` is a separate deployment and must not be
replaced by the Flutter client.

## Canonical transition contract

- tenant overlay: `prod/absolventskyvelehrad` at
  `73e3706d390d7291c557cb8b0b8c56feec311068` over canonical main
  `0c6ae2ea53d5d28ad2a05b1730599f5ae6d3f750`;
- Flutter `3.47.2`, application version `0.19.93`;
- legacy source `https://lwfpdjxsdmkfyrzqbrlk.supabase.co`, organization `5`;
- pinned activation target `https://api.festapp.net`, canonical organization
  `8`, with the stable legacy Auth storage namespace and refresh-or-reauth
  session transition;
- iOS bundle `festapp.absolventskyvelehrad`, notification extension
  `festapp.absolventskyvelehrad.OneSignalNotificationServiceExtension`, team
  `8WKBB6L8LT`, App Group `group.festapp.festapp.onesignal`, and associated
  domain `app.absolventskyvelehrad.cz`;
- Android package `fstapp.AV25`; its signed build remains a Windows-workstation
  lane.

## Web production proof

Build `0.19.93+467` was deployed through the exact Cloudflare Pages project for
`app.absolventskyvelehrad.cz`. Three consecutive custom-domain probes passed.
A clean browser cold start reached `/av2025/event`, exposed the expected version,
initialized OneSignal and produced no console error. The activation document
returned JSON with `no-store` while remaining in the legacy phase. No DNS or
content change was made to the informational apex site.

## Signed iOS test candidate

Apple Developer capability readback identified the existing app and extension
bundle IDs. The notification extension was assigned only the existing
`group.festapp.festapp.onesignal` group, after which both App Store profiles
were regenerated using the existing distribution certificate. The exported
candidate is version `0.19.93`, build `467`, from source
`73e3706d390d7291c557cb8b0b8c56feec311068`.

Direct inspection of the exported IPA proved:

- production APNs entitlement on the Runner;
- the same expected App Group on Runner and notification extension;
- `applinks:app.absolventskyvelehrad.cz` on the Runner;
- exact Runner and extension application identifiers;
- no `OneSignalLocation.framework` in the application bundle.

The IPA, profiles and digest evidence are held only in private configuration
storage. No App Store version was created, no build was uploaded, and no
submission was made.

## Remaining gates

1. Install and exercise the candidate on a physical iPhone, including cold
   launch, login/session retention, push delivery and associated-link routing.
2. Read the live App Store listing/build state, then upload and release only
   through the separately confirmed store gate.
3. Build and inspect the Android transition artifact on the approved Windows
   workstation; do not substitute a local macOS build.
4. At the coordinated backend cutover, complete the production freeze, final
   Auth/write delta, canonical activation and full-process legacy-to-canonical
   session/write canaries.
