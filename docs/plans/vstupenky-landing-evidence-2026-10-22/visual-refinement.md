> Historická iterace před novou uživatelskou připomínkou. Aktuální design a nahrazené layout/ticket klipy viz [product-design-refinement.md](product-design-refinement.md). Předchozí ivory/ink/wine nebylo schváleno.

# Vizuální dotažení 2026-10-22

Lokálně implementováno, bez commitu, push nebo deploye.

- Paleta: slonová kost, téměř černý text, jeden vínový akcent; silnější hero, kratší vizuální hierarchie, přímá navigace šesti ukázkami. Odstraněny opakované tagy a duplicitní archivní case study.
- Reference: Country bál 14.11.2026 a Ples AKH 20.11.2026, jejich skutečné cover obrázky a veřejné formuláře. Read-only inventura pořadatele 22.10.2026, žádná testovací objednávka. Datum není tvrzením o garantované kapacitě.
- Motion: oddělené vrstvy sálu a telefonu v hero, postupný nástup textu/produktu/detailu, jednorázová linka, přehrávání po ustálení sekce. Zachováno nejvýše jedno video a ruční pauza. Focus odhalí skrytou sekci.
- Kontroly: 5/5 generator/player testů; viewport 320/390/768 bez horizontálního přetoku, skutečně načtené obrázky; reduced motion potvrzený matchMedia, 0 pending sekcí a 0 autoplay. Axe 0 violations; manuální omezení silent video captions a částečně zakrytých prvků v posuvné řadě uvedené v JSON.
- Browser: task-owned empty config, --headed false, vlastní namespace/session, headless Chrome child procesu a pouze 1 tab. Statické file://, žádný server.

Lokální galerie a plný scroll: /Users/miakh/Downloads/festapp-landing-review-2026-10-22/refinement.html. Test log refined-tests.log, axe refined-a11y.json, skutečné screenshoty refined-*.png, scroll refined-scroll.webm. Pro zdrojové kontrakty a předchozí runtime/media kontrolu platí původní evidence; tato vlna netvrdí produkční nasazení.
