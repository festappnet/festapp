# Vykonání plánu sjednocení administrace a MCP

Repozitář: `/Users/miakh/source/festapp`. Připravené dokumenty jsou v checkoutu
`/private/tmp/festapp-mcp-recovery-20261022`; zachovejte cizí rozpracované soubory
v hlavním checkoutu. Změny sdíleného kódu nakonec patří do canonical main.

Přečtěte celé autoritativní zadání:

[admin-mcp-canonical-plan-2026-10-23.md](admin-mcp-canonical-plan-2026-10-23.md)

Respektujte AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a ověřování
`standard`. Výsledkem mají být skutečné operace běžné administrace přes MCP
na stejných doménových vlastnících jako UI, bez driftu a paralelních implementací.
Jeden související databázový záměr má jeden transakční příkaz a jednu vlastněnou
receipt hranici. Pouhá obálka nad třemi nezávislými příkazy tento cíl nesplňuje.

Postupujte po vertikálních řezech v pořadí plánu. Začněte novým checkpointem
etapy 0: serverové stránkování produktového read owneru a odstranění přenosu
celého katalogu při každé MCP stránce. Doloženou baseline uchovejte a porovnejte
s novou evidencí na stejných fixture. Potom sjednoťte nový i existující cíl cenové
vlny na existující receipted příkaz v etapě 1. Produkty a objednávky znovu celé
neimplementujte. Pokud uživatel omezí běh na určitou etapu, dokončete její ledger
a ověření; jinak pokračujte postupně.

Součástí každého řezu je povinná datová, SQL a síťová kontrola z plánu: agregáty,
null/default semantics, duplicity, execution plan při podezření na výkon, pořadí
zámků, počet requestů a skutečný objem dat. Opravy patří do společných vlastníků.
Nepřidávejte indexy ani další abstrakce bez konkrétního důvodu a evidence.

Každý řez nejdřív ohraničte ownerem, kontraktem, volajícími a nejmenším smysluplným
ověřovacím batchem. Znovu neprocházejte celý projekt. Existující doménové moduly,
transport, permission registry a disposable SQL harness rozšiřujte pouze tam,
kde je to pro konkrétní operaci potřeba. Nepřidávejte obecný CRUD framework,
placeholders, spekulativní fallbacky ani duplicitní ACL a výpočty v MCP.

Oprávnění, atomicitu, retry a souběh ověřte na skutečné disposable PostgreSQL.
Testy nepouštějte po každé editaci; ověřte hotový koherentní řez. Zachovejte
passing výsledky pro nezměněné vstupy. Nejvýše jeden Flutter task na stroji,
testy s `--concurrency=1`, JavaScript přes pnpm 11.24.0. Browser použijte pouze
pro skutečně změněný UI tok, izolovaně a headless.

Přečtěte také [zásady MCP](../architecture/mcp-design-practices.md) a konkrétní
katalog operací odkazovaný z plánu. Protokolová pravidla vztahujte ke skutečně
vyjednané verzi; novější příklady nejsou automatický důvod měnit SDK. Provozní blokace
míst, dočasné rezervace a zakoupené vstupenky mají oddělené příkazy (řez 2B).
Starší PDF ticket-layout readiness neblokuje všechny operace nad plánkem.

Neaktuální fakt opravte přímo v plánu s konkrétní evidencí a upravte zasaženou
etapu. Každou odstraněnou cestu uzavřete v ledgeru; vydané veřejné klienty
neodpojujte bez doloženého upgrade gate. Staré granty nerozšiřujte automaticky.
Známý starší readiness problém layoutu neobcházejte regenerací hashe.

Tento prompt sám neautorizuje commit, push, produkční migraci, nasazení ani
skutečné e-maily/platby. Použijte výslovnou autorizaci aktuálního vykonávacího
zadání nebo již platnou autorizaci v jeho kontextu; jednou udělenou žádost
neopakujte. Při autorizovaném releasu jen vybraný tenant `festapptickets`,
canonical backend, lokální web build a přímý deploy. Rutinní release delegujte
levnějšímu agentovi podle AGENTS, s frozen source a přesnými gates.

Po každém řezu aktualizujte checkpoint, mapu administrace a zdrojový JSON
statického katalogu, potom přegenerujte HTML pomocí
`node automation/reports/generate_admin_capabilities.mjs`. Při předání stručně
uveďte hotové operace, sjednocené volající, odstraněné cesty, výsledky kontrol,
skutečný stav publikace/nasazení a přesný další krok či blokující podmínku.
