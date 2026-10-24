# Stage drawing and subsequent hall refinement

This extends clean-stage.md with actual native drawing and a separate refinement chapter. Locale is selected by CAPTURE_LOCALE and prepare_brand_host.py --locale (cs now, en for later reproduction). All labels and resources for another language must be prepared before filming.

The capture-only host accepts `--resume-document PATH`: `?fixture=blank` starts from an actual empty document; `?fixture=resume` starts from the supplied saved document. This is initial fixture setup, not runtime UI mutation. It does not alter production routes or bypass validation.

`stage_and_refine.py` records:
- Blank canvas -> Rectangle tool -> slow pointer drawing of the stage. Actual inspector sets blue fill and font100 between editorial cues, then the actual Name field sets Pódium. Exact canonical text resources come from the saved native shape document.
- Four native Line drags surround the room. Search/filter controls remain outside the final crop. The real palette and canvas remain in continuous source coordinates.
- Existing clean_growth.py gestures build17tables/142seats inside the newly drawn outline. This take was recaptured to keep the actual outline present; no outline was composited over old footage.
- Shift-selection of three middle tables, actual Delete, native round-table drop, small real resize(+12 screenpx), two Add one seat actions (6->8), then real arc Curvature values -9 and +9.

The final refinement has15tables/132seats. Its round insertion resumes the exact saved middle-deleted.json after canonical resource preparation, at the same viewport. The first attempt at larger resize was discarded because it was too close to the next row and requested unprepared text. It is not included in the final video.

Actual intermediate resize documents were read back through the existing captureLayoutDocument property and processed by prepare_resources.py. A read-only property observer collected59 native snapshots; it never changed application state. The canonical collector produced12 additional resources. Always restore prepared assets after Flutter build and start a fresh isolated browser. For EN, translate the initial fixture labels, choose EN host/UI, and collect the resulting exact label/geometry requests with the same pipeline.

`encode_evolution.py ROOT` produces layout-build (intro+build) and layout-refine. Continuous crop1128x816@0,112, external matte#ebf1f6, desktop1140x828/mobile820x824. Stage drawing1.5x, name1.5x, surroundinglines4x; native table copies retain clean-stage.md's disclosed overlap-frame temporal trims. Refine selection/round gestures1.5x, chair and curvature actions1x. No fabricated ghost, no UI pixel replacement. Preserve original cue timings/source takes for later narration or a longer YouTube edit.

Update MP4/JPG/WebP together. Page story order: layout-build -> layout-refine -> layout-style. No new public order, payment, email or production operation occurs.

The round palette drag also crosses existing tables before reaching the empty middle. Seventeen transient overlap-warning frames in that named round-table cue are omitted editorially, preserving its actual insertion/result. `round-transition-cuts.json` records every omitted frame. No final placement overlaps; the first table drag and arc changes remain uncut. This is disclosed source editing, not a claim that intermediate native gestures never produce warnings.
