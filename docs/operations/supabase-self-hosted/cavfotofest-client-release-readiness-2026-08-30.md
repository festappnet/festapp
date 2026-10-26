# Clovek a vira client release readiness — 2026-08-30

## Canonical transition contract

- tenant overlay `prod/cavfotofest` at
  `c10a33dfd0f1e147be6e8674942b4b2d65df0754` over canonical main
  `cf80c7cafa2103d0ce26ea94d3868c0bec85a4c0`;
- Flutter `3.47.2`, application version `0.19.93`, web/iOS build `465`;
- production web origin and iOS associated domain
  `clovekavira.festapp.net`;
- legacy source `https://lwfpdjxsdmkfyrzqbrlk.supabase.co`, organization `3`;
- pinned canonical target `https://api.festapp.net`, organization `6`, with
  stable Auth storage and refresh-or-reauth session transition;
- iOS bundle `festapp.cavfotofest`, notification extension
  `festapp.cavfotofest.OneSignalNotificationServiceExtension`, and App Group
  `group.festapp.cavfotofest`;
- Android package `fstapp.cav`; its signed build remains a Windows-workstation
  lane.

## Apple signing correction and candidate

Read-only App Store Connect inspection found the existing app listing, Apple ID
`6471667352`, and a live maximum build of `222`; candidate `465` is monotonic.
The notification extension lacked App Groups, while the main Bundle ID retained
three historical group assignments. Apple Developer configuration was narrowed
to the single CAV group on both bundle IDs. No group was created.

Both App Store profiles were then regenerated with the existing distribution
certificate. Direct inspection of the exported, non-uploaded IPA proved
production APNs, the single CAV App Group on Runner and extension,
`applinks:clovekavira.festapp.net`, exact application identifiers, and absence
of `OneSignalLocation.framework`. Private configuration storage holds the IPA,
profiles and digest evidence. No App Store version, upload or submission was
created.

## Remaining gates

1. Physical-iPhone cold launch, retained-session, push and associated-link
   acceptance.
2. Separately confirmed App Store upload/release gate.
3. Android build and inspection on the approved Windows workstation.
4. Coordinated production freeze, final delta import, canonical activation and
   full-process legacy-to-canonical session/write canaries.
