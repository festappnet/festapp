# Grid seating and pacing refinement

The new native grid story adds12chairs through actual seat-increase controls, copies the real grid table with Ctrl-drag, then selects both tables and applies the copied wooden preset to both. The multi-selection UI does not offer preset cards; actual Copy style / Paste style is used, with no invented bulk-preset UI. Readback verifies2grid tables and24seat nodes, both table and child-seat materials wood.

Actual source/frame proof: external `layout-grid/seating-final.json` and `.png`, raw `grid-seating-*` and `grid-seating-edges-*` takes. The original transparent stage/build/refinement sources remain. A separate real backdrop shape is added after the two-table result and sent behind it; no old no-chair backdrop scene is presented as the new result.

Pacing removes0.8s of trailing idle from recorded1.6s holds, retaining visible action-result. Repeated chair addition is2×, second-table copy and shared-style steps1.5×; native edge adjustments1×. First slow table drag stays1× in the original build. Build now30.033008s; refinement14s. Final grid duration is read from synchronized manifest/proof after export.

Media-only validation: actual readback, representative encoded frames and successful decode for changed MP4 variants. No new product code or Flutter build is required for this revision. Source recipes retain locale and raw timings for later English recording or longer edits. Hash receipt: `grid-seating-final-proof.json`.
