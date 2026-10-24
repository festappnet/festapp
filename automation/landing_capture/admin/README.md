# Real admin footage

These recipes capture the real Festapp UI against a disposable synthetic tenant.
Never point them at production. Masters and frame journals belong outside Git.

## Reproduce

1. Follow `festapp-local-e2e` to bootstrap the disposable backend. The current
   landing fixture is organization/unit 1, occasion 6, form 7 and blueprint 3.
   Preserve the picker agent's authored blueprint and its spot IDs.
2. Run the guarded `test/browser/demo_full_app_e2e.dart` with a private define
   file for loopback API 56831. Respect the workstation's single Flutter slot.
   Serve the full local Edge Functions tree with bundled font/background assets.
3. Launch `agent-browser` using an empty config, explicit `--headed false`, and
   task-specific namespace/session on **every** command. Verify one owned
   headless Chrome tab. Never use personalChrome/Panerelay.
4. Set the actual application's persisted `flutter.locale` to `cs` before load.
   For another language, set that locale and translate synthetic fixture values
   as well. Do not replace rendered text using overlays.
5. Sign in using the local seed account. Open Ples pod hvězdami. Use the real
   Settings > Edit ticket dialog or Forms builder. Capture at 1440 x 1000.
6. Use product-demo-video's `capture-cdp.mjs` with the explicitly verified owned
   Chrome port and exact URL. Journal absolute timestamps and named chapter cues.
   Stop the recorder with SIGINT and preserve frames.json and cues.json.
7. Rehearse native drags via `gesture-cdp.mjs`. A preset selection or inspector
   field edit does not satisfy a drag. Compare before/after element positions.
   Flutter semantics may require a temporary pointer-events:none override on
   its semantics host and descendants; do not alter app state or rendering.
8. Export 30 fps H.264 MP4, yuv420p, CRF20, faststart. Hold the last painted
   frame until each cue boundary; use `option framerate 1000` for every FFconcat
   image including the final duplicate. Verify duration and inspect final frame.

## Chapters and reusable beats

- `ticket-design`: start with a real concert-stub preset (red border, generous
  title area). Show title drag, attendee-name drag and QR drag separately with
  0.8-1.2 seconds settling each, then 1.6 seconds final result. All displayed
  event/attendee data must match the requested locale. Desktop frames include
  controls; mobile landing edit is a close crop of the same desktop workflow,
  not a claim of native mobile authoring.
- `form-build`: show Add field > text (question `Poznámka pro pořadatele`), add a
  select (`Preferované menu`, options `Klasické` / `Vegetariánské`), then checkbox
  (`Souhlasím s podmínkami`) and Required, Save and the real public result. Keep
  style/theme controls outside this story. Translate all values for later en.
- `orders`: capture the actual orders table with synthetic Czech names/data;
  show filtering and a real order detail. Never send outbound tickets/emails.
- `scan`: actual scanner in a 390 x 844 browser viewport inside a symbolic phone
  frame for both landing aspect ratios. Show real QR input and real scan result.
  Record the camera source boundary in the take manifest (a synthetic ticket
  fixture is permitted, invented success UI is not).
- `blueprint-handoff`: open occasion6 Blueprint3 in actual Festapp admin, show
  editable tables and Czech stage, then connect to the same form7 public picker.

Each finalized clip must carry a manifest with locale, source revision, fixture
IDs, viewport, actual performed steps, cue timing, crop/export settings, source
frame directory, artifact paths and final-frame inspection. Keep source takes
and all cues so later English clips or a longer YouTube cut can reuse the
workflow without reverse engineering the short export. A longer cut is not
part of the current task.

## Current verification boundaries

Ticket drag take ends with the edited real preview. Attempted Save afterward was
rejected by the existing backend background ownership guard (42501); this footage
does not claim persisted ticket/PDF output. The actual admin blueprint3 screen
remained loading, so no fabricated admin-to-picker handoff was produced. Form7
save did succeed and its public result was fetched from the real local backend.

Capture-only input recovery: the initial owned Chrome tab stopped delivering
all native input while DOM UI handlers still worked. A fresh tab in that same
owned headless browser restored native pointer events; close the stale owned tab
and verify one target before recording. Never work around this with fake drags.

## Latest media refinement

Use scanner.md's iPhone composition and orders.md's report-first cut as the
current recipes; frame_scanner.py documents the superseded rectangular-frame
iteration. Current source takes are in the external admin-refinement directory.
The phone screen remains the recorded real scanner, with a green editorial
confirmation outside it only after real acceptance. Report values are actual
canonical synthetic data, never a claim of profit after costs.
