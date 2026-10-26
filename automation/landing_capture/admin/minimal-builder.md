# Current Czech builder and minimal scanner

Pending builder retake: follow [the 2026-10-23 scenario](../scenario-revision-2026-10-23.md)
for four priced dinners followed continuously by a text question. The recipes
below describe existing footage, not completion of that retake.

Locale: cs. For en/other locales, use genuine app localization and translated local fixture values, then rerun the same actions; do not translate baked pixels. Longer YouTube versions should retain complete raw action timing and explain each field before the same final builder hold.

Runtime inputs: CAPTURE_OUTPUT (outside Git), CAPTURE_BROWSER_WRAPPER (isolated empty-config headless session), PRODUCT_DEMO_SKILL. Raw masters for this run: Downloads/festapp-landing-review-2026-10-22/admin-minimal. No secrets belong in recipes.

## Builder

Use disposable occasion6/form9 (slug ca4txqrp). Preserve base email/ticket/product fields. Reset only prior demonstration fields, never another form. At 1000x850, scroll to Add field. Add Jedna možnost, click new card, enter Večeře, enter Kuřecí then Vegetariánské (Tab/Enter commits each option). Add Více možností, enter Podmínky účasti and Souhlasím s podmínkami, then click actual Povinné checkbox. Save. Saving scrolls to top: scroll back to the authored cards before recording the final 3-second builder hold. Never navigate to public filling.

Raw takes: form-meal-final-cs-1792682219 and form-meal-result-cs-1792682290 (resolve the latter by glob). Cues in each take are authoritative. `assemble_form_builder.py "$CAPTURE_OUTPUT"` cuts actual add/type/required actions and builder hold. Desktop crop 1000x670 at0,180 ->1200x804; mobile700x620 at150,180 ->720x638. No fabricated UI. JPG and WebP posters use final builder cards.

## Minimal scanner

This is an explicitly editorial presentation of actual recorded camera pixels and backend-confirmed outcomes, not a redesigned app UI. Approved source `admin-final/scanner-screen.mp4`, actual camera crop398x160 at16,113. Preserve camera motion and QR/paper. `minimal_scanner.html` uses local Futura, direct SVG and navy19243b, with only camera, Alexandra Novotná / SCANNER-10-2 and Ano/Ne. Reduced motion disables shake. Accepted at2.650028s, rejected5.093097s, matching actual backend/DOM receipts from scanner-accept-reject-cs-1792675426. Receipts remain admin-final/scanner-accepted-receipt.json and scanner-final-state.txt.

Replace template __SOURCE__ with local cropped video URI and __FUTURA__ with local bundled font URI; record via record_iphone.py for8.5s. Export via encode.py with end=cueStart+8.5, scale=iw:ih. Accepted poster at3.3s. Desktop1200x800, actual mobile500x1000. Sources: iphone-scanner-desktop-cs-1792681879 and iphone-scanner-mobile-cs-1792681890. No backend recapture or injected scan state for this composition pass.

Final footer-free revision: original cached takes, desktop crop1000x610 at0,180, mobile700x600 at150,180. Scale proportionally within1176x780 /696x614 and center-pad#ebf1f6 to1200x804 /720x638. Native save/discard footer excluded. Actual actions and21.7s duration unchanged.

Square scanner revision: minimal_scanner.html now renders the original camera.js paper fixture on640x640 canvas, retaining460x210 paper,174x174 QR, rotation and700ms approach. Generate __QR__ using installed web_client qrcode.toDataURL('SCANNER-10-2',{width:320,margin:4}); __SOURCE__ remains the cached camera video as timing clock only. Full square background uses the original fixture gradient; no stretching/cropping of paper or QR and no letterbox. This is authorized editorial camera-scene recomposition, not new backend detection. Actual accepted2.650028s/rejected5.093097s evidence remains unchanged. Desktop camera280x280; mobile350x350. Final masters scanner-square/final, MP4s8.5s1200x800 /500x1000, accepted posters3.3s. All six canonical scanner assets replaced; no app or backend change.

Final camera guides: copy genuine .scan-viewfinder corners (62% square,28px corners,3px white border) and .scan-camera-live/.scan-dot styling from web_client/src/components/scan/scan.css into editorial composition. Same Czech Živý obraz label as scan_page.js. Only positioning/display is adapted to square container; no extra toolbar. Record and run encode_scanner_composition.py OUTPUT; accepted posters3.3s, trim8.5s. Current guides masters are scanner-square/guides.

## Paid dinner revision (supersedes generic dinner)

Actual form9 ticket group now owns field52/product_type8; products14 Kuřecí večeře180CZK and15 Vegetariánská večeře160CZK. Remove only prior demonstration select_one field50. In actual editor select Vstupenka, scroll, click Přidat typ produktu, enter Večeře, Přidat produkt, fill Název and Cena for each product, save, and physically reload. Existing required Podmínky účasti remains unchanged. No orders/payments/email. SQL readback and saved/reloaded images prove real persisted prices, not generic options or overlays.

Raw form-priced/form-priced-cs-1792691174; price-entry.png shows actual editable Cena inputs. Run `assemble_form_priced.py "$CAPTURE_OUTPUT"` to export17.3s builder-only clips, desktop1200x804/mobile720x638, footer-free crops and#ebf1f6 padding. No generic dinner take reused. Finalposters show actual product names/prices plus required field. Readback proof form-priced/proof.json. For another locale use actual app locale and localized fixture titles; retain the complete raw action sequence for longer YouTube. Existing source runtime closed after capture.
