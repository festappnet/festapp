# Česká produktová média a upravená landing - 2026-10-22

Tato iterace nahrazuje konfliktní závěry v product-design-refinement.md a
media-provenance.md. Zachován rozpracovaný strom, bez commitu, push či deploye.

## Výsledek

- Šest skutečných publikovaných plesů v menším ručním carouselu. Dvě budoucí
  akce, čtyři označené Archiv, skutečné intro obrázky a veřejné odkazy.
  Viz references-qr-implementation.md.
- Výrazný přínos QR bankovního převodu: transakční poplatek 0 Kč. Cena služby
  samostatně; platby kartou po kontaktování vstupenky.online. Obchodní fakta
  poskytl uživatel, nejde o tvrzení, že je celá služba zdarma.
- Osm českých produktových klipů, každý s desktopovou i mobilní variantou.
  Skutečná lokalizace editoru, formulářů, vstupenky, pickeru a scanneru;
  česká ukázková data. Žádné překryvné překlady ani kreslená pseudoaplikace.
- Formulář ukazuje textovou otázku, dvě možnosti výběru, checkbox, povinnost
  odpovědi a skutečně uložený veřejný výsledek. Historický asset ID form-style
  nyní znamená hotový formulář, nikoli změny písem/barvy.
- Vstupenka ukazuje nativní tažení názvu akce, jména hosta a QR kódu na červeném
  koncertním motivu. Návrh je skutečný canvas editoru, nikoli preset slideshow.
- Výběr míst je skutečný Festapp web klient nad místní syntetickou akcí:
  blueprint3/form7, dvě sedadla, 1 300 Kč, pokračování do skutečného formuláře.
  Původní anglický knihovní picker a text o demo cenách byly odstraněny.
- Scanner používá skutečný úzký mobilní záběr v rozpoznatelném telefonním rámu
  v obou variantách. JsQR dekóduje syntetický kamerový QR vstup, skutečné lokální
  RPC potvrdí první vstup a označí opakovaný. Přehled objednávek zůstal po auditu
  českých popisků a dat beze změny; export je skutečná tabulka vstupenek.

## Editor a reprodukce

Sestavení sálu: skutečný drag kulatého stolu z palety, jednotlivé přidání židlí,
Ctrl-drag kopie, celý sál. Vzhled: výběr dvou objektů se Shiftem, společná změna,
kino, divadlo a konferenční dispozice. Hero i galerie mají české názvy prvků.
Editor je nadále skutečný samostatný editorový example, označený „Ukázka
editoru“. Jeho moderní sál není vydáván za totožný dokument veřejného pickeru.
Picker používá vlastní konzistentní uložený Festapp blueprint po celý výběr.

Recepty: `automation/landing_capture/README.md`, podadresáře layout/admin/picker.
Obsahují locale parametr, přípravu fixture, UI kroky, skutečná gesta, cue časy,
cropy a encoder. Pořadí osmi kapitol je připravené pro pozdější YouTube sestřih,
který nyní nebyl požadovaný. Raw frames, cues a čisté master takes zůstávají v
`~/Downloads/festapp-landing-review-2026-10-22/` (layout-czech,
capture-czech-admin, real-picker a původní routing-capture).

Palette text resources připravuje existující kanonický kolektor a shaper,
nikoli náhradní geometrie glyphů. Capture host má read-only export skutečného
dokumentu pro diagnostiku. Při výměně fixtures je nutný čerstvý vlastní browser
profil: prostý reload zachovával starou HTTP cache. Nad skutečným exportovaným
dokumentem vrací compileScene issues=[]; čistý take neobsahuje chybové hlášení.

## Ověření a přesné hranice

16/16 MP4 plně dekódováno, délky odpovídají manifestu. Hash, rozměry a velikosti
jsou v real-product-media-validation.json. Každý klip je menší než 0,7 MB.
Finální české snímky a skutečná gesta prohlédnuté, Python capture recipes mají
ověřenou syntaxi. Finální společný batch: 20/20 cílených carousel/player/generator a client/Worker
SEO testů PASS. `pnpm 11.24.0` Vite build PASS (663 ms), výstup mimo checkout.
Aktuální skutečné desktop/mobile screenshoty, scroll záznamy a statická QA jsou
v lokální galerii real-product-review; jejich výsledky vlastní review JSON.

Uložení upravené vstupenky po záběru odmítl existující backend guard 42501
(vlastnictví pozadí). Klip proto dokládá skutečnou editaci a výsledný návrh,
nikoli uložení nebo následné PDF. Guard nebyl oslaben. Starší koncertní PDF a
náhled divadelní šablony zůstávají samostatnými pravdivými výstupy v galerii.
Skutečný admin blueprint3 při pokusu zůstal načítat; nebyl vyroben falešný
admin-to-picker handoff. Žádná skutečná platba ani produkční objednávka.

Mobilní autorské klipy jsou přerámované skutečné desktopové záběry. Picker,
hotový formulář a scanner mají skutečné úzké viewporty. Mobilní košík pickeru
částečně překrývá horní ovládání, což odpovídá aplikaci; footage to nemaskuje.
Konferenční stock layout má drobný překryv popisků ve zóně stání; geometrie
ani text nejsou retušované. To nejsou důkazy produkčního výkonu či konverze.

Task-owned editor browser/server, admin Flutter/browser/Edge, picker Vite a
Supabase byly ukončeny. Backend data zachována. Review je statické file://.

## Další dokončená vizuální revize

Následující výsledky nahrazují odpovídající záběry výše:

- Skutečný editor: odstraněný vzor podlahy přes ovládání, modré a jantarové
  zóny stolů, navy sedadla a pódium. Sestavení ukazuje palette drag, přidání
  židlí a Ctrl-drag kopii. Barevná varianta ukazuje skutečnou změnu vybrané
  skupiny. Hero je pouze čistý výřez papíru skutečného výsledku 860x690.
- Skutečný veřejný Festapp: bohatší lokální syntetický sál s různými stoly,
  parketem a pódiem, skutečný zoom 2 kroky desktop / 4 mobil, posun, výběr
  dvou míst za 1 300 Kč a návazný formulář. Zoom je vpravo dole skutečnou
  opravou produktového CSS, nikoli přesunutou video vrstvou.
- Odbavení: reálné načtení QR a potvrzení vstupu uvnitř rozpoznatelného
  iPhone rámu. Zelený redakční indikátor mimo telefon se objeví až po
  skutečném potvrzení. Není to statický výsledek bez předchozí akce.
- Report začíná skutečnými syntetickými příjmy 124 950 Kč (95 objednávek,
  260 vstupenek), poté objednávky a export. Nejde o tvrzení o zisku firmy.
- Glass a typografie vycházejí z ověřeného veřejného produktu. Dolní
  technická sekce odkazuje na veřejný MIT repozitář, vlastní hosting a
  skutečný návod lokálního MCP propojení s AI agentem.

Surové záběry: `vivid-layout/`, `real-picker/v2/`, `admin-refinement/` pod
externím review adresářem. Reprodukce: `automation/landing_capture/`;
nový editor `layout/vivid.py`, export `layout/finish_vivid.py`, skutečný
anonymní dokument `layout/fixtures/vivid-document.cs.json`. Kanonické
prostředky Stůl 9/10 se připravují přes `prepare_resources.py --document`;
po doplnění je nutný nový vlastní profil prohlížeče. Finální dokument
prošel skutečným compileScene bez resource chyb, video neukrývá banner.
Budoucí angličtina vyžaduje nový capture skutečně lokalizovaného UI;
existující české záběry se nepřekládají překryvem. Zdrojové takes a pořadí
kapitol jsou zachované pro případný budoucí delší sestřih.

Finální cílená kontrola této revize: 26 Node testů PASS
(player, carousel, blueprint loading/viewport, generator, public SEO),
pnpm 11.24.0 Vite build PASS (690 ms), 16/16 videí plně dekódováno a délky
souhlasí s manifestem (`media-validation-vivid.json`). Python capture recipes
prošly AST parse. Vlastní browser a editor server55907 ukončené; Vite56841 a
lokální Supabase56831 zastavené se zachováním dat. Ostatní stacky nedotčené.
Finální statická galerie a screenshoty celé stránky jsou v `real-product-review/`.

## Konečná statická kontrola po glass úpravě a technické sekci

- Aktuální přímý náhled: `/Users/miakh/Downloads/festapp-landing-review-2026-10-22/landing.html`.
- Aktuální galerie: `real-product-review/index.html` ve stejném kořenovém adresáři. Obsahuje finální screenshoty včetně spodní technické sekce, všechny aktuální klipy a dva celé scroll záznamy.
- Skutečný izolovaný headless Chrome: 320/390/768/1440 px bez přetečení a bez rozbitých obrázků, 6 referenčních karet, jeden H1, žádné dekorativní šipky; tlačítko carouselu skutečně posunulo pás. Axe: 0 violations.
- Desktopový scroll 1440×1000: nejvýše jedno přehrávání, 17 vzorků; mobilní 390×844: nejvýše jedno přehrávání, 27 vzorků. Celá videa se dekódují bez chyb.
- Reduced-motion ověřeno odděleně od záznamu: skutečně `matches=true`, žádný automatický playback napříč sekcemi a žádná skrytá čekající sekce.
- Capture poznatek uložen do přenosného skriptu: změna viewportu, emulace nebo reload po `record start` může záznam zahodit. Recording nyní provádí pouze čtení a posun stránky; emulace se ověřuje samostatně. Nejde o tiché vydávání běžného videa za reduced-motion důkaz.
- Přesné otisky finálního HTML/manifestu a browser výsledky: `real-product-review/final-review.json`, `results.json`, `a11y.json`. Přenosné generování a kontrola: `automation/landing_capture/review/`.
- Detail glass původu: `glass-typography-refinement.md`; veřejné technické odkazy a MCP skutečný rozsah: `technical-options.md`.
- Výsledkem není vytvořený delší YouTube film. Zdrojové takes a recepty jsou zachované pro pozdější sestřih a jazykové varianty. Žádný commit, push, deploy ani skutečná platba.
