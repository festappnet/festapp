# Architektonický styl a čistší produktová kompozice

Reakce na uživatelskou kritiku16:14-16:22.

Použité skills: UI/UX Pro Max a Product Demo Video. Konkrétní line-drawing efekt nebyl nalezen v lokální databázi motion skillu. Primární technická reference: https://github.com/maxwellito/vivus a jeho README (stroke offset postupně odhaluje skutečné SVG obrysy). Implementace používá vlastní SVG kontury s pathLength=1 a normalizovaným dashoffset, žádný další runtime balíček ani konkurenční asset.

Pozadí obsahuje stěny, pódium, dveřní oblouk, stoly, samostatné židle a kótovací linky. Každý obrys má vlastní fázi kreslení;24s cyklus obsahuje klidovou část a fade, při reduced-motion je výkres statický. Uživatel vybral titulek „Vstupenky pro Vaši akci.“; doprovodná věta je „Vlastní plánek. Přímé platby. Vstup přes QR.“.

Platební video i jeho syntetický bankovní QR byly odstraněny z aktuální stránky a aktuální galerie. Místo nich je statická kompozice Host/bankovní aplikace → Účet pořadatele. Marketing neobsahuje živý platební kód pro omylem provedenou platbu. Skutečný produkt generuje QR podle konkrétní objednávky a účtu pořadatele; starý lokální QR master není použitelným bankovním účtem. Žádná skutečná platba se neprovádí. Text říká přímý převod bez platební brány,0Kč transakční poplatek oddělený od ceny služby. Okamžitý převod je podmíněn podporou obou bank.

Karta podpory nyní jasně říká „Máte nad akcí plnou kontrolu.“ a vysvětluje ceny, místa, podmínky a správu objednávek. Média se upravují prostřednictvím skutečného stylu plánku/formuláře a reprodukovatelných receptů, nikoli přemalováním renderovaného produktu.

## Nejnovější pokyn: video bez hranice

Videa nemají vnější card border/shadow/roundedframe ani bílý letterbox. Světlé sekce používají #ebf1f6, scanner #19243b; kompoziční matte exportů má stejné zadané barvy. Reálné aplikační UI se nepřemalovává, jsou měněné pouze okolní kompoziční plochy. Drobná odchylka dekódovaného YUV420 RGB je ztrátová komprese; zadané i změřené barvy se zaznamenají. Zařízení má nadále vlastní bezel, aby zůstalo jasné, že jde o telefon.

## Finální ověření

8 cílených Node testů prošlo, Vite build prošel. 18archivních i aktivníchMP4 plně dekódováno podle mediálního freeze. 7aktivních klipů a9skutečnýchmasonry karet. StaticQA PASS na320/390/768/1440px: žádné přetékání, rozbité obrázky či vnější video rámečky,1H1,axe0nálezů. SVG nativní timeline normalizovaného strokeoffset1→0 ověřená. Žádné platební video/platební QR obrázek ani tab hotového formuláře v aktuálnímobsahu. Ručnípauza, native loop, nejvýše1aktivnívideo a skutečné reduced-motion0přehrávanýchvideí/0skrytýchsekcí PASS. Oba scrollzáznamy plně dekódované; galerie obsahuje desktop/mobil srovnání a finálníSHA receipt. Náhled `Downloads/festapp-landing-review-2026-10-22/landing.html`, evidence `blueprint-review/index.html`. Vlastní procesy uzavřené, žádný deploy/commit/push.
