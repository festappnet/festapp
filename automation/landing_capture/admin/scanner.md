# Scanner reproduction

Use only a disposable local backend. The host imports the actual `ScanPage`
component, actual scanner frame decoder and allowlisted canonical scanner RPCs.
Its loopback SQL adapter is a test boundary, not a deployment/authentication test.
The camera is a synthetic QR MediaStream; decoded results and server state are
never injected or faked.

1. Load `database/tests/scanning/fixture.sql` into that local database, then
   run `select public.scanner_test_fixture(5)`. Save the returned object to
   `CAPTURE_PRIVATE_DIR/scanner-fixture.json` with mode0600. Never commit its
   scan_code. Save `supabase status --output env` privately as `local-env`.
2. Set `FESTAPP_REPO_ROOT`, `CAPTURE_PRIVATE_DIR`, a loopback
   `CAPTURE_DATABASE_URL` and `CAPTURE_LOCALE=cs` (or en for a fresh future take).
   Install the web_client dependencies using pnpm11.24.0, frozen lockfile.
   Run `node automation/landing_capture/admin/scanner-server.mjs`.
   API56831, DB56832 and scanner56843 are the reproducible local port contract.
3. Open localhost56843/scan through your explicit empty-config, headless, owned
   browser wrapper. Use a real430x900 narrow viewport. Set theme=light. The host
   opens a legitimate synthetic scanner session. Load camera.js using eval stdin,
   then start/retry the camera through the actual UI if the initial camera call
   had no device. The QR endpoint generates the second fixture ticket's symbol.
4. Start the product-demo-video CDP recorder in that exact owned tab.
   Run record-checkin-mobile.py with CAPTURE_OUTPUT and CAPTURE_BROWSER_WRAPPER.
   Sequence:0.6s blank camera, reveal QR,1.7s decoding,0.55s point at Confirm,
   click real Confirm,1.65s result, hide QR and click Next,0.7s pause, reveal
   the same QR,2.2s actual already-used result. This is one real admission and
   duplicate-scan warning. Use a fresh fixture on rerun.
5. Encode the430x900 raw mobile take with its original timestamp duration
   (current7.5667s). `frame_scanner.py source.mp4 output-dir` wraps that same
   narrow UI in a phone for both1200x800 and720x1000 outputs. It adds only a
   symbolic bezel/speaker/gesture bar. It never changes the captured UI.
6. Check valid/confirmed/already-used frames and every visible label. The current
   Czech source displays Ples pod hvězdami, Alexandra Novotná, Vstup do hlavního
   sálu; SCANNER-7-2 is an opaque synthetic ticket identifier, not English UI.

Retained source mapping: external `routing-capture/check-in-mobile-frames`,
`check-in-mobile-cue.json`, canonical scanner fixture and current phone exports.
For a longer YouTube version keep the entire camera/session setup as a separate
chapter; do not slow down the short clip or fabricate additional states.

## Current iPhone refinement

The flat rectangular bezel has been replaced by `iphone_scanner.html`: rounded
metal edge, rounded screen, safe-area status strip, Dynamic Island, side keys and
home indicator. This is an editorial phone composition, not physical-iPhone proof.
The original actual scanner recording is preserved unchanged inside the frame.

The refined cut uses the first4.1 seconds of the original timestamped mobile take:
blank input -> QR enters -> real valid result -> actual Confirm click -> canonical
RPC accepted -> real **Vstup potvrzen**. Source frames000313 and000330 visibly
prove acceptance. It stops before the duplicate-scan warning and holds that genuine
accepted frame. The large green caption outside the screen appears only at3.2s,
after the actual accepted state is visible; it is not injected into the app.

Reproduce from the original rawframe FFconcat manifest:

```
ffmpeg -v error -y -f concat -safe 0 -i "$RAW/check-in-mobile.ffconcat" \
  -t 4.1 -vf 'fps=30,format=yuv420p' -c:v libx264 -crf 18 -an \
  "$CAPTURE_OUTPUT/scanner-actual-source.mp4"
python3 automation/landing_capture/admin/build_iphone_review.py \
  "$CAPTURE_OUTPUT/scanner-actual-source.mp4" \
  "$CAPTURE_OUTPUT/iphone-scanner.html" --locale "$CAPTURE_LOCALE"
python3 automation/landing_capture/admin/record_iphone.py \
  "$CAPTURE_OUTPUT/iphone-scanner.html"
```

Use the capture.py environment variables from README. Encode the recorded desktop
composition1200x800 and mobile480x1000 with encode.py, preserving its cue duration
and holding the accepted frame. Export WebP posters from the final actual state.
For later English or another take, recapture the actual scanner UI in that locale,
set --confirmed-at to the first proven acceptance time, and use the matching
editorial caption translation. Do not merely translate the surrounding title.

Current external sources: `admin-refinement/scanner-actual-source.mp4`,
`iphone-scanner-desktop-1792670830`, `iphone-scanner-mobile-1792670889`.
These preserve all native intermediate frames and named cues for a longer cut.

The latest final revision supersedes the accepted-only crop above: see clarity.md final accepted/rejected section and final-takes.json. It captures both real outcomes with a paper ticket inside the camera stream and a compact Futura pill.
