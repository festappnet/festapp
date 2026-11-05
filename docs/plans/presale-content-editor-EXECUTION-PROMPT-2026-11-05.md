# Provedení: jedna jednoduchá stránka před otevřením

Implementuj hotový návrh. Nezačínej dalším plánováním nebo novým výběrem UX variant; tento průzkum a review s Astrou Medium už proběhly.

## Vstup a pracovní kopie

Repozitář: `/Users/miakh/source/festapp`.

Autoritativní plán, který musíš přečíst celý:
`/private/tmp/festapp-presale-content-plan-20261105/docs/plans/presale-content-editor-plan-2026-11-05.md`

Interaktivní koncept:
`/private/tmp/festapp-presale-content-plan-20261105/docs/previews/presale-page-editor-2026-11-05.html`

Tyto dva soubory jsou zatím lokální artefakty, nikoli součást origin/main. Zkopíruj je do odpovídajících cest nového čistého implementačního worktree z aktuálního autoritativního mainu. Nepoužívej starší větev návrhu jako výchozí zdroj aplikace. Zachovej cizí rozpracované změny. Přečti platné AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md. Rozdíl oproti revizi plánu prověř jen v dotčených cestách; neopakuj celý architektonický průzkum.

## Závazný výsledek

- Výchozí pohled je jednoduchý a použitelný: návštěvnický náhled a jedna relevantní volba e-mailu. **Úpravy vzhledu a obsahu jsou ve výchozím stavu SBALENÉ.**
- Teprve „Upravit vzhled a obsah“ odhalí volné skládání textů, obrázků, odpočtu a e-mailu. Otevření/zavření úprav nevytváří dirty stav a nic nezapisuje.
- Jeden aktivní HTML dokument, stejný rodičovský draft a jediné Uložit formulář. Použij existující rich-text engine. Žádný paralelní block JSON, druhý HTML klíč nebo režim default/custom.
- Hlavička čte název a termín z jejich autoritativních zdrojů. Zapnutí e-mailu zachová vlastní obsah i pořadí, nevloží duplicitu a nevynutí otevření celého editoru.
- Odstranění funkčního bloku a jeho změna stavu jsou jedna vratná transakce; stejné Undo/Redo musí fungovat i pro klávesové mazání/Cut a textové úpravy.
- Skutečné veřejné renderery a náhled mají společná pravidla. Statický koncept je podklad pro interakce, nikoli implementace rendereru.
- Bezpečně převést staré dva dokumenty, zachovat soukromě skrytý obsah, zablokovat nebezpečné zápisy starších klientů a odstranit druhou aktivní autorskou/renderovací cestu podle plánu. Zachovat i původní hranici implicitního odpočtu před vedlejším obsahem.

## Rychlý pracovní postup

Postupuj po závislých vlnách plánu. Dělej souvislé změny před ověřením, netestuj po každém souboru. Hotový návrh znovu neotvírej, pokud konkrétní nový důkaz nemění jeho správnost. Takový důkaz promítni do plánu a příslušné vlny.

Ověřování je **standard** kvůli datům a veřejnému kontraktu. Použij cílené modelové, widgetové, HTML-history, webové a skutečné lokální SQL testy podle plánu. Pro finální vstupy spusť jednu smysluplnou validační dávku; úspěšné kontroly opakuj pouze při změně pokrytého kódu nebo novém problému. Na celém stroji smí běžet nejvýš jedna Flutter úloha; testy `--concurrency=1`.

Pro velikosti proveď plánovaný preflight před konverzí. Překročení limitů řeš explicitně; nic netruncuj, nezveřejňuj archiv a nepřeskakuj formuláře skrytým fallbackem. Připrav migraci, recovery i testy před žádostí o produkční krok. Použij stávající mediálního vlastníka, rodičovský writer a jeho verze/příkazové identity.

Po finálních změnách ovlivňujících generovanou MCP referenci spusť `pnpm --dir tools/festapp run docs:generate` a `pnpm --dir tools/festapp run docs:check`, aby se zastaralý digest neřešil až při releasu. Pravidla CI, tenant driftu a releasu neoslabuj. Browser a deployment deleguj podle AGENTS.md; další nezávislý návrhový audit automaticky nepřidávej.

## Dokončení a oprávnění

Dotáhni celou lokální implementaci, související migraci/ochrany, odstranění starých cest a ověření. Neodevzdej jen přejmenování obrazovky ani částečnou kompatibilní větev. Na konci stručně dolož dosažené invarianty, odstraněné cesty, kontroly a případnou přesnou datovou/provozní bránu.

Toto zadání samo neopravňuje produkční datovou migraci nebo nasazení. U publikace použij skutečné autorizace v dané session a platné repo instrukce; nevyžaduj znovu oprávnění, které už uživatel skutečně udělil. Pokud další produkční krok autorizovaný není, připrav jej nejprve do konkrétní, ověřené a reviewovatelné podoby.
