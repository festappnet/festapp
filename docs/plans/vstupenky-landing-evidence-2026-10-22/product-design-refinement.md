> Novější česká iterace a skutečný Festapp picker: [real-product-refinement.md](real-product-refinement.md). Níže je historická evidence.

# Produktový design - nové uživatelské zadání 2026-10-22

Předchozí ivory/ink/wine nebylo schváleno. Tato iterace nahrazuje jeho vizuální
rozhodnutí. Žádný deploy, commit, push ani produkční mutace.

## Doložený jazyk produktu

- Skutečný veřejný katalog ve světlém režimu: Futura, body rgb(235,241,246)
  (#ebf1f6), header rgb(25,36,59) (#19243b). Izolovaný read-only browser,
  přepnutí vzhledu vlastním UI. `/events` na live stále vede na původní `/`;
  toto je source/live rozdíl před lokálním release, nikoli nový routing zásah.
- `web_client/src/theme_config.css`: seed1 #253759, seed2 #80bdf2,
  seed3 #4465a6, bílý surface, radius10/15px. Landing používá stejné seed
  proměnné s fallbackem pro samostatný render; nepřidává druhou brand paletu.
- `lib/theme_config.dart`: Futura, lllPrimary=seed1, stejné tři seed barvy,
  appBarColor odvozený ze seed3. Admin má vlastní #e3e2d3 scaffold; pro
  veřejnou landing je záměrně použit veřejný #ebf1f6, ne směs dvou scaffoldů.
- Odstraněny dekorativní šipky, rotace screenshotů a archový dekorativní tvar.
  Scan část používá skutečný tmavý chrome a modrý brand akcent.

Důkazy mimo Git: `~/Downloads/festapp-landing-review-2026-10-22/product-refinement/`:
`live-public.png`, `live-public-light.png`, `design-hero.png`.
Browser: explicit task-owned empty config, --headed false, namespace
landing-product-20261022/session design; daemon96013, vlastní Chrome96014
(--headless=new, task temp profile), pouze1tab. Osobní Chrome nepoužit.

## Obsah a hranice

Skutečné Country bál a Ples AKH obrázky a live formulářové URL zůstávají.
Galerie dispozic ukazuje skutečné Cinema, Theatre a Conference/reception
výstupy. Kombinovaný sál je označen jako koncertní použití sezení a stání;
nejde o tvrzení, že existuje samostatný koncertní preset. Galerie vstupenek ukazuje skutečné ball_silk, concert_stub a
theatre_program. Detailní capture a validační výsledky doplní závěrečný handoff.

## Skutečná média a kritika výsledku

Nový hero je samotný Contemporary ball sál: 6 hranatých a 4 kulaté stoly,
mátový vzhled, pódium, recepce a parket. Je shodný s finálním dokumentem
nového layout-build. Kritika původního jednoduchého 12stolového hero byla
zapracována; vedlejší telefon byl odstraněn, aby neimplikoval nedoložený nový
handoff. Minimal compiled editor nemá export/persist UI. Samostatný seat-select
zachovává svůj původní ověřený čtyřstolový dokument a je takto popsaný.

Nový layout-build 15,87s: skutečné Ctrl-drag kopie dvou kulatých stolů,
přidávání židlí, odstup na plný sál. layout-style 15,03s: původní doložená
hromadná úprava vzhledu + nové skutečné Cinema/Theatre/Conference dispozice.
Všechny čtyři encody plně dekódovány a reprezentativní snímky prohlédnuty.
Master evidence: `layout-capture/PROVENANCE.md` a `verification.json` v lokální
galerii. Mobilní editorové encody jsou portrétní výřezy desktopového editoru,
nikoli tvrzení o mobilním editoru.

Vstupenky ukazují ball_silk (skutečný PDF render), concert_stub (skutečný PDF
render) a theatre_program (skutečný editorový canvas). Divadelní PDF není
prohlášeno za ověřené: lokální Edge preview opakovaně narazil na CPU soft limit.
Náhled v editoru je úplný a přímo dokládá třetí šablonu. Fixture název byl
upraven běžným UI na Ples pod hvězdami, bez přípony kopie.

## Závěrečná lokální kontrola

5/5 cílených generator/player tests PASS. 320/390/768/1440px bez horizontálního
přetoku, 1H1, žádné dekorativní šipky v odkazech. Všech9obrázků se skutečně
načetlo. Axe0violations; ruční posouzení částečně oříznuté posuvné reference
a titulků němých videí zůstává uvedeno v raw reportu. Reduced motion: match=true,
0pending a0playing. Všech16variant má délku shodnou s manifestem;6nahrazených
MP4 odpovídá hashům plně dekódovaných a vizuálně posouzených capture výstupů.

Po nezávislé kritice upravené pořadí navazujícího příběhu koncert/kino/divadlo
a mobilní natural aspect vstupenek. Hero mřížka zůstává skutečnou součástí
editoru, bez raster retuše. Žádný browser ani capture server neběží; Flutter,
Edge a disposable backend zastavené jejich vlastníkem.

Aktuální statický preview: `~/Downloads/festapp-landing-review-2026-10-22/landing.html`.
Aktuální review galerie: `product-refinement/index.html` v témže adresáři;
obsahuje nové desktop/mobile screenshoty, oba plné scroll záznamy, všech8klipů
a mobilní varianty, srovnání s odmítnutým návrhem a odkazy na důkazy.
Starší galerie odkazují na tuto aktuální iteraci. Validation summary vlastní
`product-design-validation.json`; předchozí routing/PWA evidence zůstává
platná pro nezměněné routovací kódy. Žádné nasazení.
