# Blueprint v2: nejprve samostatný balíček a demo

Implementuj pouze **etapu A** v `/Users/miakh/source/venue_seat_picker`. Přečti applicable instructions repozitáře a celý autoritativní plán:

`/Users/miakh/source/festapp/docs/plans/blueprint-v2-plan-2026-10-18.md`

Festapp je v A pouze read-only reference. Neprováděj integraci, úpravy jeho runtime/pinů/font služby/Ticket Editoru, SQL, objednávek ani setupu. Etapa B vyžaduje nové zadání po vyzkoušení dema. Tento prompt není příkaz provést všechny budoucí vlny plánu. Použij `verification: standard`, zachovej cizí rozpracované změny a neupravuj pub cache.

Začni G0 (Dart core -> JS export, font paths, hit test, scene parity, způsob spuštění dema), pokračuj 1-6 -> 10A. Nejprve zprovozni jeden vertikální průchod stůl + text + save/reopen + Flutter/JS, potom rozšiř všechny nástroje a šablony. Při vyvrácení technologického předpokladu aktualizuj plán s důkazem; žádný druhý geometrický engine ani tichý fallback. Samostatné core je `packages/venue_layout_core`, obecný editor a viewer jsou ve veřejném balíčku.

Použij plánované subagenty s konkrétním vlastnictvím souborů a exit kritérii. UI/UX zadávej **`gpt-6-astra` s `reasoning_effort: medium` a `fork_turns: none`**; dej mu samostatný handoff včetně relevantních rozhodnutí, veřejných rozhraní a UX skills. Core/runtime a demo/templates svěř samostatným coding subagentům s výchozím modelem. Nejvýše 3 pracovní subagenti současně vedle koordinátora; QA využije uvolněný slot. Koordinátor vlastní společné kontrakty/manifests a finální sloučené ověření. UI se nepíše nad vymyšleným API, agenti neupravují stejné soubory a nespouštějí souběžné full buildy. Nedostupnost Astra Medium oznam, nenahrazuj ji potichu.

Dodej 9 editovatelných šablon podle tabulky plánu: klasický ples, kulaté stoly, smíšený ples, členitý sál s balkónem, lounge/stání, řadový sál, autobus, dva vlakové vozy a prázdný plánek. Všech 9 šablon je součástí veřejného balíčku a galerie samostatného editoru, dostupných bez demo hosta přes public API. Demo používá tutéž knihovnu, nikoli kopie; pouze připojuje ukázkové ceny a stavy. Ověř jejich přibalení a otevření v čistém consumeru. Klasický ples je default. Jeden společný plánek, schematické měřítko bez metrů, pokročilé nastavení až na vyžádání. Text/fonty/barvy, tvary a vlastní presets, rotace/pivoty, podklady/crop/registrace, auto-expanze, fitting a automatické přidávání židlí jsou skutečně funkční s preview, stabilními IDs a jedním undo krokem na gesto. Neodevzdávej pouze maketu nebo omezený generátor.

Rozšiř existující `example/` o editor a Flutter zákaznický náhled; `web/demo/` je samostatný JS consumer téhož exportu a společného kernelu. Demo bez loginu/backendu používá licencované lokální font/asset fixtures a obecné providery. Nezakládej produkční fontový katalog: budoucí Festapp adaptér bude používat jediný existující Ticket katalog/picker/resource pipeline. Soukromé snapshoty a originální grafiku nebal do veřejných artefaktů.

Syntetický host ukáže ceny/dědění, nedělitelný gauč, volbu počtu stání a kontrolované failure/conflict/timeout stavy. UI jasně uvádí ukázková data. Žádný nový účetní/rezervační engine: mock nedokazuje serverové zámky, oprávnění ani atomitu. Export/import zahrne použité lokální resources a oddělená demo metadata; čistý geometry export nezahrnuje ceny či obsazenost. Autosave/reload, neplatný import, storage failure, font race a reset nesmí poškodit draft.

Připrav plánované package vstupy `tool/demo.sh build|check|open|stop`, README a `build/demo/` kit s manifestem. Jejich přesnou realizaci ověř proti SDK a package instructions. Preferuj file-open artefakt; případnou nezbytnost loopback HTTP pro Flutter loader dolož v G0, launcher musí mít jasný životní cyklus a cleanup. Pro automatické testy pouze izolovaný headless browser. Statický výsledkový report funguje z `file://`; neotvírej ani neměň uživatelův browser. Již sestavené základní demo funguje bez sítě, build prerequisites jsou dokumentované zvlášť.

Dokončení A vyžaduje DA01-DA08, package části AC01-AC29 podle explicitního mapování v plánu, cílené core/widget/browser/parity testy, výkonový report a čistý consumer smoke ze skutečně zabaleného artefaktu. Nespouštěj Festapp/SQL testy pro standalone fázi. Testuj ucelené změny a jednou finální integrovaný batch; passing checks neopakuj bez změny pokrytého kódu. Výsledky uveď poctivě jako package pass / simulace / odloženo B. Budoucí SQL, migration kit a odstranění Festapp legacy cest nejsou podmínkou dokončení A ani autorizovanou prací v této etapě.

Tento prompt neautorizuje publikaci na pub.dev/npm, deployment dema, produkční data, commit ani push. Po DA gate předej funkční demo k vyzkoušení a zastav se na hranici A; nezačínej automaticky B. Stručné předání obsahuje cestu a příkaz spuštění, šablony, export/reset, report ověření, skutečné technické limity a přesný seznam simulací.

## Povinný vstup pro integraci B (2026-10-19)

Před integrací načti [funkční paritu V1 → V2](blueprint-v2-v1-functional-parity-2026-10-19.md).
Všechny její požadavky jsou součástí integračního rozsahu; neomezuj práci na
produkty/ceny, objednávku a swap. U každého splněného řádku doplň skutečný důkaz.
Neoznačuj demo nebo samotný balíček jako hotové napojení Festappu.
