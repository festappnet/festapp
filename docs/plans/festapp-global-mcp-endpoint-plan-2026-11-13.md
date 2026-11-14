# Jeden globální MCP endpoint Festapp

> Realizační zadání: [exekuční prompt](mcp-directory-registration-EXECUTION-PROMPT-2026-11-13.md)
> rozšiřuje tento návrh o vydání až do ověřeného produkčního výsledku. Vyžaduje
> kanonické opravy sdílené s produkční aplikací, migraci všech dotčených volajících,
> odstranění nahrazených větví a testy MCP i odpovídajících aplikačních cest.
> Rozsah realizace a oprávnění při jeho spuštění určuje toto novější zadání.

Datum: 2026-11-13  
Stav: Cílový návrh před realizací a registracemi  
Ověřování: standard - autentizace, autorizace, veřejný kontrakt

## Rozhodnutí a výsledek

Globální připojení ponese jméno **Festapp**. Pokryje funkce aplikace včetně
ticketingu **Festapp Tickets**, které se zpřístupní podle podporovaných nástrojů,
oprávnění účtu, klientského profilu a výslovného souhlasu. Festapp Tickets tím
neztrácí produktovou značku; nepotřebuje však další duplicitní MCP záznam.
Regionální připojení **vstupenky.online** zůstává samostatné, pod vydavatelem
Festapp. Tento návrh nahrazuje dřívější předpoklad registrace globálního
připojení výhradně jako Festapp Tickets.

Doporučená adresa je `https://mcp.festapp.net/mcp`. Jde o navržený cílový host,
nikoli dnes ověřenou dostupnou službu. Dřívější služba na tomto hostu byla
vyřazena s HTTP 410; nepřebírat její klíče, tokeny, audience ani staré souhlasy.
Případné znovupoužití domény bude explicitním uvedením nové globální služby,
po kontrole historie klientů a dopadu změny 410. Pokud to koliduje s reálnými
závazky, zastavit se u tohoto konkrétního konfliktu a upravit cílový host.

## Co je standard a co doporučení

[MCP Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#streamable-http)
požaduje protokol endpointu, nikoli konkrétní subdoménu nebo rozdělení podle
produktů. `mcp.` je praktická konvence, kterou používají například
[Notion](https://developers.notion.com/guides/mcp/get-started-with-mcp)
(`https://mcp.notion.com/mcp`) a [Stripe](https://docs.stripe.com/mcp)
(`https://mcp.stripe.com`). Výhoda pro Festapp: stabilní adresa nezávislá na
hostingu frontendů, samostatné provozní nastavení a jedno srozumitelné připojení.
Subdoména sama neposkytuje tenantovou izolaci.

[MCP authorization](https://modelcontextprotocol.io/specification/latest/basic/authorization)
vyžaduje správné resource metadata a validaci token audience. Přesměrování
regionálního endpointu proto není řešení globální identity. Zachovat
`https://mcp.vstupenky.online/mcp` a existující schválené regionální klienty.

## Současné technické hranice

- `tools/festapp/src/context/profile.mjs`: profil obsahuje právě jeden tenantId,
  organizationId a ověřený backend activation binding.
- `tools/festapp/src/remote/config.mjs`: konfigurace obsahuje právě jeden profil,
  issuer a volitelný tenantOrigin. Pouhé vynechání regionalPortal nezavádí globální
  přístup přes organizace.
- `tools/festapp/src/remote/delegation.mjs`: grant je vázán na profileBinding,
  clientId, uživatele a audience; delegatedContext používá organizaci konfigurace.
- `tools/festapp/src/operations/access.mjs`: discovery zjišťuje přístup uvnitř
  organizace profilu; výběr více pořadatelů není totéž co více organizací platformy.
- `tools/festapp/src/remote/tenant-bridge.mjs` a
  `supabase/functions/mcp-session-exchange/config.ts`: first-party broker ověřuje
  explicitní tenant/origin/organization vazbu. Volba z těla požadavku ji nesmí obejít.
- `tools/festapp/Caddyfile.remote` a `remote-compose.yml`: regionální sidecar
  používá vlastní host a loopback port 3399. Druhá služba nesmí kolidovat portem,
  stavovým adresářem, signing keys nebo konfigurací.

## Pořadí práce

1. **Uzavřít rozsah globálního připojení.** Z existujících backendových membership
   a authorization funkcí zjistit, jak bezpečně nabídnout dostupné organizace.
   Cílově jedna veřejná adresa, při připojení explicitní výběr kontextu a jeho
   organizace, pořadatelů/akcí a oprávnění. Stejný uživatel může mít více pojmenovaných
   připojení pro různé kontexty. První implementace nemusí agregovat více tenantů
   do jednoho grantu; případná agregace je samostatné rozšíření, nikoli automatické
   právo globálního endpointu. Ověřit, že tato vazba pokryje skutečné globální
   účty, ne pouze organizaci globálního ticketingového portálu.
2. **Navrhnout a implementovat binding na připojení.** Global issuer má explicitní
   důvěryhodný seznam podporovaných tenantových profilů. Vybraný a backendově
   ověřený profil se neměnně váže na OAuth flow, grant, session a každý nástrojový
   požadavek. Zachovat kontrolu aktuálních práv SQL, consent narrowing, client
   ceiling, dataProfile, aud a revokaci. Nepoužít organizationId=null, wildcard
   ani přepínat organizaci podle libovolného tool argumentu. Změna kontextu
   vyžaduje nové připojení nebo explicitní reconsent, nesmí přepsat starý grant.
   Regionální konfigurace zůstane vázaná na regionální profil.
3. **Připravit globální identitu a discovery.** Festapp jako název připojení,
   pravdivé katalogové popisy jednotlivých schopností, globální consent a správa
   připojení, odpovídající privacy/terms/support a přesné registrace klientů.
   Reuse `Operations.catalog` a existujících permissions; nekopírovat doménovou
   logiku podle produktových značek. V katalogu neslibovat všechny funkce, které
   nejsou skutečně dostupné. Statické OAuth registrace neobcházet plošným DCR.
4. **Ověřit skutečné bezpečnostní hranice.** Cílené existující remote a broker
   testy rozšířit o dva profily, stejného uživatele s různými právy, nepovolený
   profil, podvržený tenant/origin/organization, nesprávnou audience, nesoulad
   session/grantu, revokaci, změnu práv po souhlasu a souběžná připojení bez
   přenosu kontextu. Použít disposable PostgreSQL pro skutečné membership/SQL
   hranice. Prokázat ticketingový i neticketingový nástroj v deklarovaných scopes;
   regionální klient nadále nesmí vidět globální organizaci. Ověřit skutečný
   OAuth průchod s oddělenými syntetickými účty a absenci soukromých dat v logu.
5. **Uvést samostatnou globální službu.** Nejdříve uzavřít konkrétní dopad na
   sdílený backend a regionální klienty, kanonické CI lanes a release gates podle
   pravidel repozitáře. Nasadit immutable image, oddělený port, chráněnou
   konfiguraci, state a keys; globální DNS/TLS/discovery ověřit až po lokálním
   health a OAuth ověření. Neměnit Supabase compose ani restartovat regionální
   službu jako vedlejší efekt. Produkční rollout a přesné hosty uvést v release
   zadání; rutinní deploy delegovat dle AGENTS.md. Nové tokeny musí mít globální
   resource, staré regionální tokeny se nepřijímají. Při selhání odpojit novou
   službu; nepřesměrovat regionální tokeny a neodstranit regionální připojení.
6. **Teprve potom registrovat.** Do plánovaných registrů uvést vstupenky.online
   a Festapp pod vydavatelem Festapp. Preferovaný globální namespace
   `net.festapp/festapp`, pokud je dostupný a ověřitelný. Festapp Tickets uvést
   v popisu podporovaného ticketingového produktu, ne jako duplicitní server
   se stejným účelem a stejným endpointem. Licenční a kvalitativní podmínky
   registračního plánu nadále platí.

## Dokončení a meze tohoto dokumentu

Hotovo je ověřený veřejný globální endpoint Festapp se skutečným OAuth připojením,
správně vázaným kontextem a fungujícím ticketingovým i neticketingovým scénářem,
při zachované regionální funkčnosti a izolaci. URL, resource, source/image SHA,
provedené testy a omezení mají sanitizovanou provozní evidenci. Dokument sám
není nasazení ani hotový implementační kontrakt změny tenantového bindingu;
ten musí vlna 1-2 uzavřít proti skutečnému backendu před změnou autorizace.

Veřejné podání ani produkční změny v rámci tohoto návrhu neproběhly. Základní
otevřená otázka implementace je výběr bezpečného globálního first-party login a
consent originu, protože dosavadní tenantOrigin je pevně svázaný s jedním
tenantem. Tento origin se nesmí odvozovat z nedůvěryhodného URL parametru.
