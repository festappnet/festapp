---
target_identity: "file:/Users/miakh/source/festapp/web_client/public/embed.js"
target_fingerprint: "sha256:d53aade3f73fa314936a68e1a586eace5cab908713613c2c1bedc8fbc7373d73"
target_path: /Users/miakh/source/festapp/web_client/public/embed.js
timestamp: 2026-11-05T20-14-47Z
slug: web-client-public-embed-js
---
# Kontrola iframe embedu před širším vydáním

Metoda: dvě nezávislá posouzení - embed_visual_review (prohlížeč) a embed_code_review (zdrojový kód a detektor). Živý cíl: https://vstupenky.online/form/hwnsne2t?embed=1 a /embed.js?v=appearance-1. Světlý a tmavý syntetický HTTP host, desktop a mobil 390 px. Konkrétní hostitelský web zatím neexistuje.

## Výsledek

Základ funguje: převzetí barev a písma, čitelné CTA v testovaných paletách, automatická výška a mobilní zalomení. Před širším vydáním doporučujeme krátké dotažení.

- P2, potvrzeno vizuálně: na desktopu je dole v iframe přibližně 22px tmavý pruh při celkové výšce 240px. Ruší světlé i tmavé pozadí. Příčina v DOM zatím nebyla určena. Snímky: /tmp/fest-embed-host-desktop.png a /tmp/fest-embed-dark-desktop.png.
- P1, riziko z aktuálního lokálního kódu: web_client/public/embed.js:83 kombinuje WordPress primary proměnnou s barvou textu jiného tlačítka. Chybí ověření kontrastu. Barvy tlačítka vybírat jako pár s čitelným fallbackem.
- P2, riziko z lokálního kódu: poloprůhledné pozadí předka se přenese bez složení s pozadím pod ním (embed.js:70). Na cílovém webu se může vykreslit jinak.
- P2, riziko z lokálního kódu: .surcharge-info má vlastní pevnou barvu a není zahrnuta mezi zděděné popisky v embed.css. Ověřit vysvětlivky příplatků na obou paletách.
- P2, kontext: živý formulář teď ukazuje jen e-mail a upozornění na začátek přihlašování. Bez okolního textu hostitele chybí název akce a vysvětlení. Řešit podle toho, kde bude kontext vlastnit hostitelská stránka.

## Omezení a stav

appearance-1 je URL parametr assetu; v lokální nové implementaci řídí přebírání vzhledu uložené nastavení formuláře a starý data-festapp-style už není autoritou. Živý helper explicitní atribut ještě podporuje. Před vydáním sjednotit dokumentovaný a nasazený kontrakt.

Prohlídka neověřila nákup, plánek, rekapitulaci ani platbu, protože živý cíl aktuálně nabízí pouze upozornění. Nebyla vytvořena objednávka, rezervace ani odběr upozornění. Pro úplné Nielsen skóre není dost důkazů; nebylo přiděleno.

Detektor proběhl jednou nad relevantním JS/CSS: 0 nálezů; toto neověřuje kontrast a runtime chování. Ignore soubor nebyl přítomen. Uživatelská okna nebyla dotčena, overlay nebyl vkládán. Izolovaný browser i dočasný HTTP server byly ukončeny. Zdrojové soubory nebyly změněny. Otázky přeskočeny: uživatel upřesnil, že cílový web zatím neexistuje.
