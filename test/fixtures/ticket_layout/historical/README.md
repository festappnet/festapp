# Historical ball ticket references

The local editor opens with an internal picker for three distinct landscape image
references from the canonical festapptickets organization (3), inspected on
2026-10-01: AKH 2025 (cream), Skautský ples 2026 (forest green), and Farní ples
2026 (black and white). `catalog.json` records their occasion IDs, source URLs,
original dimensions, text colors, and generated layout geometry.

These are original backgrounds with historical titles/dates embedded in their
pixels. They are local reference fixtures, not a global cross-tenant template
catalog or ready-to-publish artwork for another event. QR/order fields remain
synthetic. Images are stored locally so the preview does not depend on live
image hosts or administrative authentication.

All three are 1600 x 900 pixels, printed at approximately 189 x 106.3 mm on A4.
The selected references have space for ticket details below the artwork.
The 1600 x 533 and 1600 x 636 banner references were not selected because their
artwork already fills the available space; they need a separately designed
information area before being reusable editor defaults.

Regenerate their ordinary wide layouts from the production geometry function:

```sh
deno run --allow-read --allow-write test/fixtures/ticket_layout/historical/build.ts
```

The script validates each layout. QR stays dark with the editor's white quiet
zone; only text inherits each event's original text color. The preview keeps the applied layout and selected artwork together. Selecting a
reference is one undoable edit. Cancel leaves the previously applied draft unchanged.

The forest picker now uses `forest-clean.png`, a clean AI-redrawn version of the
historical reference (1672 x 941 px). `forest.jpg` remains the untouched original;
its source URL identifies the historical reference, not the redrawn file. Titles
and dates still describe the historical event and are not generic event defaults.
