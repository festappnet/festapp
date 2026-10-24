# Glass tlačítka a typografická hierarchie - 2026-10-22

Lokální implementace po výslovné připomínce uživatele. Bez deploye, commitu a pushe.

## Skutečný produktový kontrakt

- Zdroj veřejných tlačítek: `web_client/src/components/users/user_header.css`, pravidla `.btn-sign-in`, `.btn-admin`, `.btn-add-event`.
- Ověřené computed hodnoty na živém veřejném katalogu: bílá 15 % opacity, blur 8 px, 1 px bílý okraj 10 %, radius 28 px, stín 0 2 8 px s černou 10 %. Tlačítko vytvoření akce má solidní světle modrou variantu téhož kontraktu.
- Další skutečný glass povrch: `web_client/src/components/blueprint/blueprint.css`, blur 16 px, saturate 140 %, translucent surface a opaque fallback.
- Read-only computed evidence: `/Users/miakh/Downloads/festapp-landing-review-2026-10-22/real-product-review/live-glass-contract.txt`.
- Browser byl vlastní izolovaný headless s prázdným configem a jedinou kartou; po čtení zavřený. Osobní Chrome nebyl používán.

## Implementace

`page.css` a `page.html` používají produktové role glass povrchů pro navigaci, CTA, ovládání médií, varianty, referenční carousel a QR callout. Zůstává Futura a původní navy/blue paleta. Hero rozlišuje kontext „Váš ples“ od dominantního nadpisu. Popisy a detaily mají zřetelně odstupňovanou velikost a řádkování. Šipkové dekorace se nevracejí.

Kontrast textu má přednost před průsvitností. Reduced-transparency má opaque fallback; reduced-motion zachovává stávající kontrakt animací. Mobilní header skrývá desktop CTA, aby vedle značky zůstalo místo pro Akce a Menu.

## Cílené ověření

- Generátor: `node --test --test-reporter=dot automation/tests/organizer_page.test.mjs`, 2/2 PASS.
- Skutečný náhled v headless Chrome: 320/390/768/1440 px, scrollWidth přesně odpovídá viewportu, jeden H1, computed CTA blur 8 px.
- Axe: 0 violations. První zachycené přetékání mobilního headeru bylo opraveno explicitním skrytím desktop CTA a oprava znovu potvrzena.
- Screenshoty a kontrolní JSON jsou v `real-product-review/style-proposal/`. Dokumentují typografii a ovládání před integrací následných výraznějších médií, nikoli konečný mediální výsledek.
- Nezávislý Astra koordinátor prohlédl desktop a mobil; bez nových blokujících stylových nálezů. Finální celostránková kontrola musí použít následný zmrazený manifest a média.
