# One original storyboard, two real UI recordings

`storyboard.json` is the shared recording authority on main. It pins the Czech
publication source and hashes every original video and poster. It records
fixture identity/counts/prices, ordered beats, native gestures where retained,
viewport, device scale, light theme, crop, presentation and both exports.
`text.cs.json` and `text.en.json` may change text only. They cannot contain
locale-specific coordinates, prices, object counts, cuts or camera settings.

The reference is the fetched `prod/festapptickets` commit that owns the intended
published Czech set, not an arbitrary newer working-tree experiment. The isolated browser verified all 32 public video/poster file hashes against
that revision; `reference-live.json` records the actual current-page readback.
A bare HTTP client was rejected, so the read-only browser was used. Historical source references remain immutable. A new approved Czech
revision updates the shared storyboard/reference once for BOTH locales.

## Record an update

1. Restore the exact named fixture through the canonical local backend/host.
   Preserve its geometry, IDs, inventory, amounts and prices. Localize labels and
   cast text through the locale text files. Never repair reservations by deleting
   committed orders. Keep actual before/after readbacks with the take.
2. Save a fixture input containing `fixture`, `geometry`, `data` and `before`.
   The latter fields must satisfy the storyboard's numeric preconditions. Record
   the common source-tree SHA-256 separately from locale build artifact hashes.
   This is source identity supplied by the real build record, not remote build
   attestation; keep the archived build and actual served-artifact readback.
3. Generate the job, then use the same recipe with the other locale:

   ```sh
   python3 automation/landing_capture/scenario_contract.py prepare layout-build \
     --locale cs --fixture /private/fixture.json \
     --source-sha256 ACTUAL_COMMON_SOURCE_SHA256 --output /private/job.cs.json
   CAPTURE_SCENARIO_JOB=/private/job.cs.json CAPTURE_LOCALE=cs \
     python3 automation/landing_capture/layout/row_ready.py
   ```

   Keep the existing isolated browser/capture environment variables. Start from
   the storyboard viewport; the recorder checks rather than silently resizing or
   moving the camera to compensate for a locale. `story_beat()` records each beat
   in order. A missing/reordered beat produces a rejected receipt, never a match.
4. `row_ready.py` and `continuous_form.py` are shared executable original recipes.
   The former English row entrypoint is only an alias, with no second geometry.
   Encode their take with `encode_revision.py`: a scenario receipt locks crop,
   content scale and desktop/mobile dimensions. Conflicting CLI overrides fail.
5. The other six chapters retain their original storyboard and asset references,
   but their historical multi-take/phone composers have not yet been consolidated
   into this runner. Their existing English convenience scripts are historical
   capture adapters, NOT evidence of original-scenario parity. The generic
   encoder refuses to substitute a letterbox for their original composition.
   Reconstruct their native recipe/composer from retained masters and the named
   beats before certifying a pair. In particular: round-table/arc refinement,
   painted multi-table grid, original red ticket, six-seat pinch selection,
   repeated-scan rejection and report-first sales fixture must not be replaced
   by simpler interactions with the same marketing description.
6. Review the real first/middle/final frames, actual canonical after state, full
   decode and full playback. Extend each recorded receipt with actual `after`,
   `exports`, storyboard `edit`, immutable `takeSha256`, actual `exportSha256` for desktop/mobile files, `checks` booleans
   (`actualReadback`, `firstMiddleLastFrames`, `fullDecode`, `fullPlayback`) and
   `status: reviewed`. This is explicit review evidence, not generated approval.
7. Compare independently recorded CS and EN receipts:

   ```sh
   python3 automation/landing_capture/scenario_contract.py compare \
     /private/take.cs/scenario-receipt.json /private/take.en/scenario-receipt.json \
     --output /private/matched-pair.json
   ```

   Different source, geometry, numeric data, beats, edit plan or framing fail.
   Identical raw take hashes also fail: Czech footage cannot be relabeled English.
   A match proves equal reviewed inputs/outcomes; localized pixels are expected
   to differ. It never replaces real UI recording or human visual inspection.

## Existing media

The existing English files remain actual English recordings with their original
provenance. They were not recorded with this common contract and are NOT
retroactively certified 1:1. `scenario_contract.py audit --output FILE` exposes
framing mismatches and missing pair evidence without changing any footage.
The Global release manifest requires matched receipts for all rendered chapters
before claiming the original-scenario requirement complete. Locale verification
and decode success alone do not satisfy that gate.

Raw frames, PDFs, credentials and recordings stay outside Git. Scripts, fixture
contracts, locale text, common editorial settings and evidence conventions belong
to main and are forbidden tenant-branch differences. No deployment or recording
of paid provider operations is performed by these tools.

For a complete publication gate, use the same verifier with paired receipts:

```sh
python3 automation/landing_capture/verify_media.py --locale en --required-only \
  --scenario-pairs /private/reviewed-receipts --output /private/media-proof.json
```

The directory contains `CLIP.cs.json` and `CLIP.en.json` for every rendered clip.
This checks actual published file hashes against reviewed export hashes, not
just matching dimensions or copied receipt labels. Missing or divergent pairs
fail. The historical default decode-only mode explicitly reports that scenario
parity was not checked.
