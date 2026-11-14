# Implementovat schválené rozložení C editoru formuláře

Pracujte v `/Users/miakh/source/festapp`. Nejdříve přečtěte platné AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md, potom celý autoritativní plán:

`docs/plans/form-editor-layout-c-plan-2026-11-11.md`

Výsledek: textově pojmenované akce, přidání pole přímo u polí a navigační osnova pouze na široké obrazovce. Celý současný blok dostupnosti, kapacity/náhradníků, rozvrhu a obsahu mimo prodej MUSÍ zůstat nahoře v původní podobě. Úvodní HTML editor a souvislý seznam všech polí zůstávají pod ním. Čtyři hlavní záložky a současní vlastníci ukládání se nemění.

HTML `docs/previews/form-editor-variants/variant-c.html` je vizuální reference, nikoli implementace pravidel. Znovu použijte původní Flutter komponenty. Žádné placeholdery, druhé kopie konceptu nebo obchodních pravidel, privátní State průchody, feature flag pro paralelní V2 ani automatické ukládání. Splňte matici zachování a odstraňte pouze nahrazené UI cesty uvedené v plánu.

Samotné UI delegujte podle výslovného pokynu uživatele na `gpt-6-astra`, reasoning `medium`, `fork_turns="none"`. Předejte stručné zadání s tímto plánem, relevantním UI/UX skillem, konkrétními soubory a výhradním vlastnictvím změn. Astra implementuje schválené UI bez nového návrhového průzkumu a dalších subagentů; hlavní agent integruje, doplní behaviorální testy a provede jednu závěrečnou kontrolní dávku. Nekopírujte celou konverzaci, neopakujte hotový průzkum ani kontroly. Dodržte sekci Delegace a tokenová efektivita v plánu.

Ověřování low-risk: dokončete ucelenou změnu a spusťte jednu přiměřenou finální dávku podle plánu. Flutter vždy přes fvm, jediná úloha na workstation, testy s --concurrency=1 a prokazatelně vybranými případy. Browser kontrolu delegujte Terra subagentovi, izolovaně a ve světlém režimu; řiďte se festapp-local-e2e. Mimo předepsané Astra UI a Terra browser role nespouštějte další nezávislý audit nebo jiné subagenty bez dalšího oprávnění.

Respektujte existující rozpracované změny a větev. Pokud aktuální kód vyvrací faktický předpoklad, opravte autoritativní plán a přizpůsobte dotčený krok bez změny schváleného výsledku.

Tento soubor je zadání pro budoucí autorizovanou implementaci, nikoli pokyn k jejímu automatickému spuštění. Bez dalšího zadání neprovádějte implementaci, commit, push, tenant overlay, migraci ani nasazení. Případná později autorizovaná publikace musí nejprve splnit dotčené automation/test_ci.sh lanes.

Při předání stručně uveďte změny rozložení, zachované původní komponenty, odstraněné staré UI, výsledek ověření a konkrétní zbývající rizika či blokery.
