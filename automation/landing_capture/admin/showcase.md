# Offline genuine template showcase

Run from the repository root:

```
deno run --cached-only --allow-read --allow-write --allow-env automation/landing_capture/admin/render_showcase.ts "$CAPTURE_OUTPUT"
swift automation/landing_capture/admin/raster_showcase.swift "$CAPTURE_OUTPUT"
cwebp -q 91 "$CAPTURE_OUTPUT/boarding_pass.png" -o web/organizers-media/ticket-showcase-boarding-pass.webp
```

Repeat WebP conversion for cinema_strip, gallery_square and sports_arena. No network permission, Flutter build, backend or browser is needed. Deno uses cached packages only; if missing, stop rather than fetch. Env permission is required by cached Node compatibility dependencies. The real production ticketGallery and generateTicketPdf modules supply geometry, typography, bundled fonts/backgrounds and QR. PDFKit rasterizes exactly the page box at1200px longest edge. No rendered UI or artwork is invented or edited.

Synthetic Czech data: occasion6/org1, Ples pod hvězdami, Kulturní dům,20.-21.2.2027,19:00,Jana Nováková,Stůl12. These are genuine preview sample outputs, not claims of paid issued tickets. Current PDFs/PNGmasters and provenance.json are outsideGit in the ticket-masonry review directory. Final manifest suggestions are showcase-items.json; clips.json is coordinator-owned.

All four selected outputs were visually inspected for complete Czech title/data and clean page-only crops. The batch also renders festival_poster and workshop_card for reproducibility; they are not published. Festival's title wraps mid-word for this long sample title, so it was excluded rather than altered. Existing Gala/Klub/Divadlo crops remain unchanged, giving seven distinct showcase variants total. For another locale supply translated synthetic event/name/date data in the renderer and rerender genuine PDFs; do not translate image pixels. Longer YouTube use should show selecting these same presets in the actual editor, then the preserved native text/QR drag capture.

The next revision publishes two further canonical cards, yielding nine total. festival_poster now uses the shorter genuine synthetic event title `Letní festival`; workshop_card uses `Tvůrčí dílna`. This fixes sample-title wrapping through actual renderer input, without pixel editing or template geometry changes. Both newly rendered pages were visually checked. Paths and dimensions are in showcase-extra-items.json: festival771x1200, workshop1200x851. Their PDF/PNG masters remain in the same external ticket-masonry directory.

## Gala safe inset correction

Render only this preset with `deno run --cached-only --allow-read --allow-write --allow-env automation/landing_capture/admin/render_showcase.ts "$CAPTURE_OUTPUT" gala_invitation`, rasterize that dedicated output directory, then convert gala_invitation.png to the existing ticket-ball.jpg. This fixture keeps the prior empty venue. Canonical ticketGallery geometry now places the 24mm QR at y122mm and symbol at y148mm in a4mm box; both fit inside the lower decorative frame on the160mm page. No QR alteration or pixel retouching. Current clean page is525x1200. PDF/PNG/provenance are preserved in external gala-safe-inset; visual review of final JPG confirms the complete symbol above both border lines. Other cards and videos are unchanged.
