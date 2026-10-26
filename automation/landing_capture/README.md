# Organizer product recordings

Use `product-demo-video` and its isolated agent-browser capture observer. The
shared clip schema is `automation/release/organizers/clips.json`; the English
content manifest is `clips.en.json`. Section clip IDs define the required set.
A locale never substitutes another locale's video or poster.

`admin/capture.py` owns recording, absolute frame timestamps and cue manifests.
`admin/continuous_form.py` and `layout/row_ready.py` demonstrate the form and
seating-plan scenarios. `encode_revision.py` preserves native timing and emits
desktop/mobile MP4 files and posters. Masters live outside Git in an owned take
directory. Use synthetic English events, products and people for English takes.

`render_organizer_page.mjs --preview` permits an explicitly incomplete local
preview. Normal generation refuses an English release until every referenced
clip is verified. A pending manifest entry is not a recording or an acceptance
result. Never mark an entry verified without inspecting actual English UI,
full decoding and playing both exported variants.

## Shared original-scenario authority

Use [scenarios/storyboard.json](scenarios/storyboard.json) and the
[recording/pair-verification workflow](scenarios/README.md) for new CS/EN takes.
The original publication source is pinned by revision and media hashes. Both
languages share scene data, beat order, camera and export rules; only text is
localized. `CAPTURE_SCENARIO_JOB` enables fail-closed viewport/locale checks and
ordered beat receipts in the existing capture helper. Row and form recipes are
shared executable entrypoints. Historical English-only convenience scripts do
not establish 1:1 parity and must not silently replace the common storyboard.

Decoding a video and verifying its language do not prove scenario identity.
Existing EN clips keep their original evidence, but paired scenario acceptance
is pending. No raw footage was overwritten or relabeled by this tooling change.
