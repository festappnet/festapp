# Vykonání plánu sjednocení administrace a MCP

Repozitář: `/Users/miakh/source/festapp`. Připravené dokumenty jsou v checkoutu
`/private/tmp/festapp-mcp-recovery-20261022`; zachovejte cizí rozpracované soubory
v hlavním checkoutu. Změny sdíleného kódu nakonec patří do canonical main.
Před prací načtěte aktuální autoritativní `origin/main` z GitHubu; místní `main`
a remote ref nezávislého klonu s lokálním originem nemusí být aktuální.
Pracujte v čistém izolovaném checkoutu, nepřesouvejte hlavní checkout jiné relace.

Poslední potvrzený základ: `4cfc9b7bc66f48c2d6e42155f08e905dde112d0d`.
MCP protokol `2026-07-28`, server SDK 2.3.1 a Node adaptér 2.1.1 jsou nasazeny.
Oficiální legacy hranice obsluhuje stejný katalog. Všech 74 MCP testů prošlo
s reálnou disposable PostgreSQL, bez skipů; tento výsledek není náhradou
za ověření nově změněných cest. Upgrade transportu neopakujte.

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
a ověření; jinak pokračujte postupně. Nezastavujte po první etapě pouze kvůli získání
potvrzení k další již zadané práci. Neúplnou etapu neoznačujte za hotovou.
Při přerušení uložte přesný checkpoint, zdrojovou revizi, výsledky kontrol
a nejbližší další krok tak, aby další relace neopakovala hotovou práci.

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

Uživatel již zadal implementaci i nasazení a požaduje zachování čisté
architektury. Pokračujte v tomto rozsahu bez opakovaných žádostí o totéž
povolení: sdílený kód do autoritativního main podle pravidel repozitáře,
produkční rollout pouze `festapptickets` / `vstupenky.online`, organizace 3,
canonical backend `api.festapp.net`. Produkční migrace patří do samostatného
ověřeného kroku s přesnými zdrojovými digesty, kontrolou cíle, zálohou a recovery.
Nevytvářejte produkční testovací objednávky, skutečné platby ani zákaznické
e-maily. Jiné tenanty nevydávejte. Autorizovaný web release má lokální build
a přímý deploy; backend-only změna nevyžaduje nesouvisející web build.
Rutinní release delegujte levnějšímu agentovi podle AGENTS, s frozen source
a přesnými gates. Každý release vázejte na konkrétní ověřenou revizi;
nevydávejte cizí rozpracované změny bez jejich validace.

Po každém řezu aktualizujte checkpoint, mapu administrace a zdrojový JSON
statického katalogu, potom přegenerujte HTML pomocí
`node automation/reports/generate_admin_capabilities.mjs`. Při předání stručně
uveďte hotové operace, sjednocené volající, odstraněné cesty, výsledky kontrol,
skutečný stav publikace/nasazení a přesný další krok či blokující podmínku.
