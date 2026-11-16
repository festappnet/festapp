# Exekuční zadání: globální MCP Festapp až do ověřeného vydání

Pracuj v `/Users/miakh/source/festapp`. Toto je zadání k realizaci, ne k dalšímu
sepsání plánu. Dotáhni implementaci, opravy, testy, publikaci zdrojů, produkční
nasazení a veřejné registrace až k ověřenému výsledku.

## Autoritativní vstupy a rozsah

Přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md, CONTRIBUTING.md,
docs/architecture/mcp-design-practices.md a oba plány v plném znění:
- docs/plans/festapp-global-mcp-endpoint-plan-2026-11-13.md
- docs/plans/mcp-directory-registration-plan-2026-11-13.md

Toto zadání nahrazuje starší omezení plánů na pouhou přípravu a požadavky na
nové potvrzení rutinního vydání. Je autorizována práce na main, globální MCP
službě, potřebných kanonických backendových změnách, DNS/TLS pro
mcp.festapp.net a bezplatných veřejných registracích popsaných níže. Regionální
vstupenky.online zachovej funkční; jeho first-party web nasaď pouze tehdy,
pokud je změna nezbytná pro společný autentizační/consent tok, jako jediný
vybraný existující tenant. Nedělej rollout ostatních tenantů ani celého
globálního ticketingového portálu. Placené služby, skutečné platby/refundy,
nevratné mazání produkčních dat a korespondence třetím stranám nejsou součástí
zadání. Běžné vratné technické volby a opravy rozhoduj samostatně.

Použij focused-development, canonical-cutover a příslušné projektové backendové
či release dovednosti. Ověřování: standard pro vývoj a všechny povinné release
brány při vydání. Historická tvrzení ověř proti současnému zdroji a runtime;
při změně premis aktualizuj plány bez tiché změny cíle.

## Cílová architektura

Globální připojení se jmenuje **Festapp**, cílová adresa je
`https://mcp.festapp.net/mcp`. Pokrývá podporované funkce celé aplikace včetně
Festapp Tickets. Regionální **vstupenky.online** zůstává na
`https://mcp.vstupenky.online/mcp`. Vydavatel obou je Festapp. Nezakládej třetí
duplicitní MCP záznam Festapp Tickets. Dřívější 410 host globálně zprovozni jako
novou službu po kontrole historie klientů, s odděleným state a klíči; staré ani
regionální tokeny a souhlasy nepřebírej jako globální oprávnění.

Nejprve uzavři bezpečný first-party login/consent origin a výběr kontextu podle
existujících membership/SQL pravidel. Jedna veřejná adresa neznamená přístup ke
všem organizacím. Jedno připojení váže jeden ověřený tenantový profil a výslovně
vybrané pořadatele/akce a oprávnění; účet může mít více pojmenovaných připojení.
Globální endpoint nesmí být jen přeznačená jediná ticketingová organizace.
Vazba kontextu musí být neměnná od OAuth flow přes grant a session až po každý
request. Kontext neměň argumentem nástroje, wildcardem ani organizationId=null.
Zachovej SQL kontrolu aktuálních práv, audience, PKCE, consent, client scope
ceiling, dataProfile, revokaci a přesné callbacky. Kvůli katalogovému skeneru
nezapínej plošné DCR, neobcházej autentizaci a nerozšiřuj oprávnění.

## Kanonické opravy sdílené s produkční aplikací

Před změnou každého dotčeného toku dohledat jeho skutečného doménového vlastníka,
kontrakt a všechny relevantní volající: SQL/RPC, Edge/API, Flutter, web, MCP/CLI
a navazující integrace či joby. Produkční aplikace i MCP musí používat stejné
kanonické operace, výpočty, autorizaci a hranice vedlejších účinků. MCP je tenký
transportní adaptér; jeho scopes a consent přístup pouze dále zužují.

Každý nalezený problém MCP, který ovlivňuje vydávaný kontrakt, bezpečnost,
připojení nebo správnost sdílených operací, reprodukuj a oprav v kanonické vrstvě.
Nevytvářej MCP-only obcházení chyby produkce, duplicitní business engine,
paralelní V1/V2, fallbacky nebo kopie SQL. Převeď všechny dotčené volající a
odstraň nahrazené implementace, runtime registrace, flagy a zavádějící testy/docs.
Podporované veřejné protokoly neporušuj; potřebný compatibility adaptér má být
tenký, nad týmž vlastníkem a s popsaným důvodem zachování. Zachovej command ID,
receipty, idempotenci a obnovu po nejistém výsledku zápisu. Nesouvisející nález
zaznamenej odděleně; release blokující nález musí být vyřešen, ne jen popsán.

## Testy a průkaznost

Použij skutečné discovery a příkazy aktuálního repozitáře. Testy mají ověřovat
chování a bezpečnostní hranice, ne opisovat implementaci. Pro každou opravenou
chybu přidej regresní případ a dolož reprodukci před opravou, je-li proveditelná.
Povinně pokryj:
- dvě tenantové organizace, různá práva stejného uživatele, nepovolený kontext,
  podvržený origin/tenant/organization a nesoulad session, grantu či audience;
- OAuth/PKCE od začátku do konce, consent, refresh, expiraci, revokaci, změnu
  práv po udělení souhlasu a souběžná připojení bez přenosu kontextu;
- skutečné moderní i podporované legacy MCP klienty podle aktuálních zásad,
  HTTP transport, metadata a skutečně vyjednanou verzi protokolu;
- alespoň jeden ticketingový a jeden neticketingový scénář a stejný doménový
  výsledek odpovídající cestou produkční aplikace; zápisy, retry a odmítnutí
  neoprávněných akcí tam, kde se dotýkají změn;
- skutečný disposable PostgreSQL pro sdílené SQL/RPC a membership hranice,
  cílené Flutter/web testy podle dotčených volajících a regresi regionálního
  připojení. Produkce není testovací fixture.

Použij existující remote, broker, connection UI a PostgreSQL testovací seam.
Před publikací spusť dotčené kanonické lanes přes automation/test_ci.sh;
ručně vybrané testy je nenahrazují. Z automation/ci/checks.json odvoď aktuální
MCP auth a související lanes, nekopíruj zastaralý seznam příkazů. Zaznamenej
příkazy, skutečně provedené testy, výsledky a přesné zdrojové revize. Neopakuj
úspěšné kontroly beze změny pokrytých vstupů. Používej pnpm 11.24.0 a frozen
lockfiles. Nejvýše jedna Flutter úloha, testy --concurrency=1.

## Publikace a produkční nasazení

Chraň cizí rozpracované změny čistým worktree; nepřidávej je do svých commitů.
Před publikací fetchni main, vyřeš posun upstreamu a znovu ověř postižené vstupy.
Preferuj přímé vydání do authoritative main, pokud pravidla nevyžadují PR.
Před rolloutem vyžaduj úspěšné kanonické GitHub CI na přesném source/baseMainSha
přes automation/ci/release_gate.py. Chybějící, pending, skipped nebo failed
kontrolu neobcházej; potřebné regression workflow můžeš spustit, nikoli
GitHub Deploy. Vyřeš chyby sdílené s tímto vydáním, včetně relevantní baseline.

Backend řeš přes projektový festapp-backend-access a ověřený canonical target;
SQL změny jako forward migrace kanonického zdroje s atomickým ledgerem.
Functions reload jen schváleným restart-production-functions.py se správným
pause/drain a následnou kontrolou email workeru; neregeneruj Supabase compose.
Nový MCP sidecar musí mít oddělený loopback port, state, keys, resource a
chráněnou konfiguraci. Ověř immutable image a konfiguraci před DNS/proxy cutover.
Pokud je nezbytný first-party web release, použij kanonický tenant overlay,
ancestry/drift gates, lokální build a automation/deploy_direct.sh pouze pro
vybraný tenant. Nezakládej vedlejší webserver ani nenasazuj jiné prod větve.

Browser práci deleguj na gpt-6.1-terra, routine deploy/monitoring na gpt-6-luna
s přesným předáním revizí, scope, příkazů a gates podle AGENTS.md. Po předání
zmraz vstupy. Používej vlastní tiché browser relace a syntetická data. Před
žádostí o heslo prověř předepsaná chráněná úložiště; nové credentials bezpečně
ulož a nikdy je netiskni ani necommituj. Nepřidávej další review/delegační fáze
bez potřeby nebo explicitního pravidla.

Po nasazení prokaž DNS/TLS, discovery, globální audience a autentizované SDK
volání, skutečný OAuth průchod a deklarované scénáře. Ověř regionální regresi,
izolaci tenantů, health a sanitizované logy; HTTP 200 nebo nástrojový scan není
sám důkaz funkčního připojení. Při selhání použij připravený rollback nové služby,
bez obnovení duplicitního business owneru nebo rozšíření cizích oprávnění.

## Registry, licence a vydání

Po živém ověření zveřejni **Festapp** a **vstupenky.online** pod jedním vydavatelem
Festapp v Official MCP Registry a Glama. Použij existující identitu, pokud už
existuje; retry nesmí tvořit duplikáty. Ověř namespace/doménu, skutečné endpointy,
aktuální schémata, Glama claim a healthy/indexovaný stav. Prověř aktuální
PulseMCP a bezplatné MCP.so; nedostupnost nebo neexistenci bezplatné cesty dolož.
Aktualizuj neaktuální fakta podle primárních pravidel registrů.

Ověř MIT LICENCE a rozsah jejího použití, licence přesných runtime závislostí
a přibalených aktiv, povinná oznámení, podpůrné/právní URL a oprávnění ke značce.
Zachovej historické copyrighty; podmínky hostované služby nejsou licence kódu.
Doplň chybějící pravdivá metadata, CS/EN dokumentaci, schválená loga, konkrétní
příklady, autentizaci, cenu účtu a omezení. Optimalizuj vhodné kategorie a
relevantní hledané výrazy bez spamových duplicit a slibů pořadí. Neuváděj
schválení ChatGPT ani jiný odznak bez ověření; jeho nová samostatná submission
není součástí tohoto zadání.

## Definice hotovo

Nezastavuj se u plánu, lokálních testů, commitu, uploadu nebo podání formuláře.
Hotovo znamená živý a ověřený globální MCP Festapp, zachovanou regionální službu,
kanonické opravy ve všech dotčených volajících, odstraněné nahrazené větve,
prošlé povinné kontroly a ověřené veřejné katalogové záznamy.

V docs/operations/releases/ ulož sanitizovanou evidenci: source/image SHA,
případné migrace a tenant revize, testy, live probes, release/rollback stav,
namespace/ID a veřejné URL registrací. Čekající externí moderaci označ pending,
nikoli hotovo; pokračuj ve zbývající nezávislé práci a po dostupném schválení
dokonči publikaci v autorizovaném rozsahu. Nevymýšlej datum schválení ani
nezakládej automatické plánované kontroly. Narazíš-li na skutečnou externí
překážku, uveď přesnou akci, důvod, dokončené části a minimální potřebný vstup.
Nevyžaduj opakovanou autorizaci pro již schválené rutinní vydání.

Závěrečná odpověď stručně: co je živě, veřejné URL, společný kanonický owner,
opravené problémy, důkaz testů a případné konkrétní nehotové externí položky.
