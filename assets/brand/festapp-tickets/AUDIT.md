# Uploaded asymmetric logo audit

Input: `source/Festapp_Tickets_asymmetric.svg`. Reference: the approved `../vstupenky-online/vstupenky-online-symbol.svg` and its Roboto Bold source. The uploaded file is retained unchanged.

| Property | Uploaded SVG | Canonical reference / normalized global output |
| --- | --- | --- |
| Ticket bounds before its placement transform | x 190-684, y 117-361 | x 196-828, y 254-563 |
| Width / height | 494 / 244 = 2.02459 | 632 / 309 = 2.04531 |
| Left corner extent / ticket width | 47 / 494 = 9.51% | 54 / 632 = 8.54% |
| Right corner extent / ticket width | 49 / 494 = 9.92% | 54 / 632 = 8.54% |
| Side-notch depth / ticket width | 48 / 494 = 9.72% | 60 / 632 = 9.49% |
| Side-notch height / ticket height | 96 / 244 = 39.34% | 118 / 309 = 38.19% |
| Font contours | 0 of 14 glyphs exactly match the canonical font; raw contour XOR area is roughly 0.40-2.03% of each reference glyph area | Rebuilt from the exact canonical Roboto Bold file |
| Lettering structure | Separate transformed glyph paths | One boolean-unioned, flattened path per word row |
| Interior design | Asymmetric stepped separation | Preserved; mapped from uploaded ticket bounds into the canonical envelope |

Raw coordinate differences alone are not evidence of a mismatch because the two source drawings use different scales. The normalized ratios above establish the geometric differences. Font comparison uses the untransformed glyph contours in their common 2048-unit coordinate system; it establishes a contour mismatch, not a diagnosis of which alternative font/version produced the upload.

The final global halves are intersected with the canonical envelope. The envelope is recovered from the actual regional mirrored paths and an interior rectangle which stays clear of the deepest notch points. The generator compares the final logo's complete exterior edge bands against the regional halves themselves, rather than against a separately redrawn approximation. The measured XOR area must be below 0.01 square source units; the result is recorded in `vector-verification.json`.

The global separator and two-colour ticket are deliberate identity differences. An assertion that the entire global symbol is identical to the regional V mark would be incorrect. Corner curves, side notches, palette and the font source are shared; the new asymmetric interior is retained.
