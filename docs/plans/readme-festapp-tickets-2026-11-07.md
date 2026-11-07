# Festapp repository presentation

## Intended result

An English repository homepage named **Festapp**, explaining the shared platform,
its ticketing products and branded festival apps. Show actual native iPhone
simulator screenshots of the **summer Slunovrat 2026 festival, June 18-21**, plus
English ticketing screens. Provide a standalone GitHub-style HTML preview.

The owner's latest instructions replace the earlier Festapp Tickets-first title
and Winter Edition mobile web gallery. English translations are local only.

## Plan

1. Preserve unrelated work and bring the documentation branch up to date with
   canonical main before publication.
2. Explain the relationships with a source-controlled vector diagram: Festapp
   as the shared platform, ticketing through Festapp Tickets and vstupenky.online,
   and branded event apps such as Festival Slunovrat on iOS, Android and web.
3. Use the verified public summer occasion 1072558, not the current winter landing
   page or identifiers from historical rehearsal databases. Preserve artist,
   venue, image and date facts; translate visible editorial text only locally.
4. Build the real iOS app in an isolated checkout with Slunovrat's public branding.
   Install Apple's simulator runtime, launch a task-owned headless iPhone in light
   mode, and capture native program, map and artist-detail screens with simctl.
   Keep push disabled and guard backend transport against live mutations.
5. Put the native app gallery before ticketing so the app is immediately visible.
   Keep the English local seat-selection and order-administration screenshots.
   Remove superseded mobile captures from the final gallery and asset directory.
6. Rebuild the self-contained static HTML preview with embedded assets, phone
   frames and the relationship diagram. Open it directly from disk, without a
   preview server or disturbance to existing browser tabs.
7. Validate the final local Markdown/image targets, PNGs, SVG and whitespace;
   inspect the native screens and the static preview. No main-checkout application
   source changes or tenant deployment are part of this documentation task.
8. Update the existing PR #755 and GitHub description/homepage. Main requires
   one approving review; do not bypass that protection.

## Evidence and boundaries

- Shared capture source: `1080cadc1`; public Slunovrat configuration/branding:
  `f89359611d4ffab7175e74a179ec956e33941bf6`.
- Summer source: `https://slunovrat.festapp.net/2025-copy-98cf835a/event`,
  occasion 1072558, organization 19, canonical tenant `festivalslunovrat`.
- The historical rehearsal's 1072557 is Winter 2025 in live production and must
  not be used to identify the summer event.
- Local translation is applied to decoded display models in the isolated capture
  checkout. Public sync asset integrity and live event content remain intact.
- Local app clock selects June 18; simulator status-bar time is normalized for
  presentation. Artist photos, names, times and venues come from public data.
- The order-administration screen retains its original fixture provenance.
  The gala seating capture uses the newer local round-table fixture below.
- Final screenshot details and native capture commands are recorded beside the
  images in `docs/images/readme/README.md`.

## Execution result

- Installed iOS 26.5 and built the native app for arm64; captured three clean
  1206 x 2622 PNGs directly with simctl. The task-owned simulator was shut down
  and deleted after capture. The runtime remains installed for future work.
- Restored the Festapp title, repository description and homepage; added the
  relationship diagram and replaced all superseded mobile examples.
- Checked 27 local README targets, decoded all five PNGs with valid CRCs and
  dimensions, parsed the SVG, and verified whitespace. Browser inspection
  confirmed six embedded images, three aligned native phone frames, a legible
  diagram, and no page overflow at 1440px or 390px.
- Fetched upstream main at `db00d5c7b`. Its intervening measurement-protocol
  changes do not touch the captured native UI, images or README. Merged
  that main revision before updating PR #755; no capture checks were invalidated.

### Round-table gallery refinement

The organizer screenshot now shows the complete Grand Gala plan: 12 round tables,
96 seats, a stage, a central dance floor, and local VIP/standard ticket products.
The real public picker captured one selected VIP seat at CZK 650. Capture source
is `307b61405`; the PNG is 1440 x 900. The README caption and media provenance
are updated with the same local-only fixture boundary.
