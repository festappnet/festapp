# Implementuj: typy akcí, společný vzhled a klikací navigaci

Pracuj v `/Users/miakh/source/festapp`. Nejdřív přečti `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/archive/plans/occasion-setup-types-appearance-plan-2026-10-22.md`

Tento prompt je zadání k implementaci plánu, nikoli k dalšímu plánovacímu kolu. Pro nedořečené kosmetické detaily použij výchozí návrhy v plánu. Pracuj až do dokončení lokálně ověřitelného výsledku; nezastavuj na návrhu ani po první vlně.

Výsledek: Název / Termín / Typ / Vzhled; tři typy akcí a podmíněné další otázky; kopírování pouze s dostupnými oprávněnými zdroji; automatický název formuláře; kompaktní odkaz; společné barvy/gradient a font v reálném formuláři i vstupence. Horní navigace pojmenovává aktuální část a dovoluje přímé přepínání na jednotlivé aktivní otázky klikem i klávesnicí. Dokončení zahrnuje dynamický progress, resume konceptu, serverovou validaci a odstranění nahrazených pravidel v plánu.

Povinně zapoj UI/UX subagenta `gpt-6-astra` s reasoning `medium`, `fork_turns="none"` a skillem `/Users/miakh/.codex/skills/ux-designer/SKILL.md`. Dej mu tento plán a vlastnictví `occasion_setup_story_shell.dart`, nových prezentačních komponent vzhledu a souvisejících widget testů. Hlavní agent vlastní tok, `occasion_setup_page.dart`, persistence/SQL a integraci. Nejprve dohodněte callbacky a vstupní modely; subagent nemá kopírovat doménovou logiku ani souběžně upravovat soubory hlavního agenta. Bez dalších subagentových auditů a variantních redesignů.

Postupuj efektivně: jeden cílený průzkum aktuálních rozdílů, pak implementační vlny podle plánu. UI lze připravovat souběžně s doménovou logikou po dohodnutí rozhraní. Testy seskup po souvislé integraci; nespouštěj je po každém souboru. Zachovej cílené standardní kontroly SQL, oprávnění a skutečného PDF/veřejného formuláře, jednu závěrečnou lokální headless kontrolu mobil/desktop. Nerozšiřuj ověřování na nesouvisející části a neopakuj úspěšné kontroly bez změny jejich kódu.

Zachovej existující necommitnuté změny a jediný nynější draft/finalizační mechanismus. Pokud důkaz vyvrátí předpoklad plánu, oprav plán a dotčenou vlnu. Nezaváděj paralelní kopii, skryté rozšíření oprávnění, placeholder renderer ani tichý fallback fontu. Flutter jen jeden proces na stanici, včetně subagenta, a testy `--concurrency=1`; slot řídí hlavní agent. JS pnpm 11.24.0. Bez dalšího zadání žádný commit, push, živá migrace ani nasazení.

Na konci stručně uveď dokončené chování, provedené kontroly a přesný případný blokující bod. Rozliš místní implementaci od živého nasazení. Nedeklaruj shodu designu jen podle náhledu, pokud není ověřen skutečný formulář a export vstupenky.
