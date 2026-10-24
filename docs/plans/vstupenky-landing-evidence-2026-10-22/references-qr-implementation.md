# Kompaktní reference a QR platba - 2026-10-22

Pouze lokální realizace; bez deploye, commitu, pushe a produkčních zápisů.

## Reference

Šest skutečně zveřejněných plesů, vlastní původní cover obrázky a přímé odkazy. Country bál a Ples AKH jsou nadcházející; Skautský ples, Sportovní ples Větřkovice, Ples obce Větřkovice a Farní ples mají jasné označení Archiv a skutečné datum.

Metadata: `automation/release/organizers/content.json`. Podklady veřejné read-only inventury: `/Users/miakh/Downloads/festapp-landing-review-2026-10-22/reference-inventory/`, včetně `carousel-references.json`, původních coverů a výpisů formulářů. Formuláře archivních akcí mohou být stále dostupné, jejich datum je přesto v minulosti; popisek Archiv nepředstírá stav dnešního prodeje.

Karty mají přibližně třetinovou šířku desktopového obsahu a 82 % mobilního obsahu. Ruční posuvný pás používá nativní scroll a scroll-snap, Předchozí/Další, klávesy na soustředěném pásu a dotyk. Žádné automatické přejíždění. Šipkové klávesy nejsou přebírány, když je fokus na odkazu akce. Při reduced-motion se posuv provede okamžitě; bez JavaScriptu zůstává nativní posouvání a přímé odkazy.

## QR platba

Obchodní tvrzení pochází z výslovného upřesnění uživatele: QR bankovní převod má nulový transakční poplatek; platební karty lze zpřístupnit po kontaktování vstupenky.online. Hero na tuto výhodu odkazuje a samostatná sekce ukazuje 0 Kč. Cena služby je uvedena samostatně jako předmět domluvy; stránka neslibuje celou službu zdarma. Žádná platební operace nebyla provedena.

## Ověření

- `node --test --test-reporter=dot web_client/tests/components/reference_carousel.test.js web_client/tests/components/landing_demo_player.test.js automation/tests/organizer_page.test.mjs`: 6/6 PASS.
- Skutečný headless browser nad samostatným file:// výřezem skutečného rendereru/CSS/JS: 1440 px, 6 karet, všechny obrázky načtené, přibližně 339 px na kartu, bez vodorovného přetečení stránky.
- Skutečné tlačítko Další posunulo pás až na konec a deaktivovalo Další. Mobil 390 px: karta přibližně 284 px v pásu 350 px, bez přetečení stránky.
- Browser session ověřená vlastním headless Chrome potomkem a jedinou kartou; po kontrole zavřena.
- Screenshoty samostatné kontrolní výseče jsou v reference-inventory/carousel-desktop.png a carousel-mobile.png. Tyto výseče nenahrazují celostránkové finální ověření integrátora. Po změně viewportu se čítač synchronizuje po scroll debounce; finální screenshot pořizovat po ustálení.

Nový přehrávač referencí je `web_client/src/marketing/reference_carousel.js`, inicializovaný z existujícího marketingového vstupu `landing.js`. Generátor, obsah a CSS zůstávají jediným zdrojovým vlastníkem stránky.
