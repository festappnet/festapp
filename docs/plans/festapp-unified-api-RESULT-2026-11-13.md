# Společné API Festapp - produkční výsledek

API i oba MCP vstupy jsou nasazené ze společného zdroje
`d9f0e34cd5fc53e1873a63762017c952ad44cfb2`. Používají jeden katalog
`DELEGATED_OPERATIONS`, stejný executor `Operations`, vstupní/výstupní schémata,
doménové vlastníky a SQL oprávnění. Oprava v této cestě platí pro oba adaptéry.
API nabízí 174 Bearer / 196 DPoP operací; summary profil má pět operací.
Zvláštní transportní požadavky 22 citlivých operací jsou DPoP, PAR a skutečné
GoTrue AAL2 ne starší než 300 sekund. Nevznikla druhá doménová implementace.

Oba MCP runtimy používají shodný immutable image
`sha256:0979040896ab82d05431183fbb3c7281f40f003449d3944d453e720d8810a6a9`.
Osm veřejných manifestů odpovídá zapečetěným projekcím. API audience jsou oddělené
od MCP i navzájem. Nevznikl další API proces, auth databáze ani dokumentační server.
[Produkční receipt](festapp-unified-api-evidence-2026-11-13/production-operator-d9.json)
a [veřejné manifesty](festapp-unified-api-evidence-2026-11-13/operator-public-manifests.json)
obsahují přesné identity a výsledky.

## Dokumentace dostupná z nápovědy

Zdroj `4a373ff3dfd8b5bd7a056d999918cd096ffd57da` přidává výrazný odkaz
**Nápověda > Integrace > API dokumentace**, anglicky
**Help > Integrations > API documentation**. Vyhledávání najde API také přes
OpenAPI a Swagger. Odkaz na úplnou DPoP referenci a OpenAPI JSON se odvozuje
z generovaného manifestu správného regionálního/globálního profilu, nikoli
z druhého ručně udržovaného seznamu endpointů.

- [Regionální nápověda](https://vstupenky.online/napoveda/integrace/#api)
- [Globální nápověda](https://tickets.festapp.net/help/integrations/#api)
- [Úplná regionální API reference](https://api.vstupenky.online/integrations/v1/proofs/dpop/docs/)
- [Úplná globální API reference](https://api.festapp.net/integrations/v1/proofs/dpop/docs/)

[CI evidence nápovědy](festapp-unified-api-evidence-2026-11-13/api-help-ci.json)
zachycuje všech osm lokálních lanes a dotčenou opakovanou kontrolu po opravě
veřejné URL reference. Také [všech osm GitHub jobs na přesném Help SHA](festapp-unified-api-evidence-2026-11-13/api-help-github-source.json) prošlo. Help změna nemění backend, kontrakty ani Functions.

Oba weby jsou živě na verzi **0.20.605+1130**, z kanonického main SHA `4a373ff3dfd8b5bd7a056d999918cd096ffd57da`:

| Tenant | Produkční větev / SHA | Přímé nasazení |
| --- | --- | --- |
| vstupenky.online | `prod/festapptickets` / `1ef56dce0619ce8e9be9be9e917d1aae469d34e2` | [Pages deployment](https://9132847f.vstupenkyonline.pages.dev) |
| Festapp Tickets | `prod/festappticketsglobal` / `3f001b230cc9fb4f4e8c01165077fd12fc877983` | [Pages deployment](https://0e731d10.festappticketsglobal.pages.dev) |

Lokální kanonické buildy a kontrola zapečetěných artifact receipts prošly.
Každý web potvrdily tři po sobě jdoucí koherentní live-version probes.
[Produkční Help receipt](festapp-unified-api-evidence-2026-11-13/api-help-production-605.json)
obsahuje tenant SHA a artifact digests.
[Browser ověření obou jazyků](festapp-unified-api-evidence-2026-11-13/api-help-browser-605.json)
potvrdilo vyhledávání Swagger/OpenAPI, navigaci a proklik správné reference i JSON.
Izolovaná browser relace je uzavřená.

## Nasazené změny a ověření

- Všech osm lokálních lanes a všech osm
  [GitHub jobs na přesném backend SHA](festapp-unified-api-evidence-2026-11-13/operator-github-source.json)
  prošlo. Parity test porovnává všech 196 operací přes skutečné OAuth/HTTP a MCP
  SDK. Účinky pokrývá 270 testů nad skutečným PostgreSQL; nejde o tvrzení,
  že všech 196 mutací proběhlo v produkci. Finální image prošel 23 disposable
  ingress kontrolami.
- Migrace `20261113160000_shared_bank_writer_acl.sql` je aplikovaná a zapsaná
  v ledgeru. ACL bankovního writeru žije u jeho kanonické deklarace; živá
  dvourolová autorizace a payment policy zůstávají uvnitř SQL funkce.
- Kanonický úplný Functions bundle ze zdroje
  `f961bacff3d201f0311267a0687b652e1a5ed8b4` je nainstalovaný. Jeho dotčený
  obsah je shodný na D9 i Help zdroji. Samostatné vydávání session podporuje MFA
  bez převzetí browser refresh tokenu. Worker probe prošel, email health má nula
  alertů, producer access je v pořádku a fronta je nepozastavená.
- Přesná shoda JWT issueru odpovídá produkčnímu GoTrue root originu
  `https://api.festapp.net`. `/auth/v1` není přijatý issuer alias. Pozitivní MFA,
  nezávislá session a nepřenášení čerstvosti MFA refreshem prošly se skutečným
  produkčně připnutým GoTrue v disposable prostředí.
- [Skutečné živé OAuth průchody](festapp-unified-api-evidence-2026-11-13/operator-live-probes.json)
  prošly na obou API a globálním MCP: čtení a refresh HTTP 200, chybná audience
  a Bearer downgrade HTTP 401, revokace a další přístup HTTP 401. API bez MFA
  odmítá citlivou operaci před dispatch s odpovídající AAL2 challenge.
  Granty byly odvolány, vlastní Auth session odhlášena a izolovaný browser uzavřen.
  Živé ověření neprovedlo business mutace. Použilo fixture org3; org25 má ověřenou
  aktivaci/registry a web release, nikoli úspěšný uživatelský grant v této evidenci.

Nový native operator klient je pouze aditivní; žádné service identities ani
`client_credentials` nebyly aktivované. Má strop 83 permission groups a 85 scopes;
živý occasion-only souhlas správně udělil 84 bez scope pro vytvoření akce.
Původních 10 globálních a 16 regionálních grantů zůstalo s totožnou efektivní
identitou, oprávněními a expirací. Doplnění explicitních regionálních defaultů
nemění jejich význam. Klíče a původní klientské politiky zůstaly zachované.

Kontrolovaný benchmark finálního image měl MCP p95 22,53 ms proti 25,19 ms
baseline, idle RSS +3,52 MiB, kontejnerový peak 198,98 MiB, bez OOM.
Je to diagnostický vzorek se stejnou fixture, nikoli důkaz rychlejší produkce;
RSS procesu a kontejnerové memory.peak jsou v receiptu uvedeny odděleně.
Limity zůstávají 384 MiB / 0,5 CPU / heap 192 MiB.

## Make zůstává před přepnutím

**Make cutover je povolený teprve po přijetí stávající aplikace v review.**
Původní regionální `/make/v1` vrací HTTP 200 a zůstává tenkým adaptérem společného
runneru. Jeho issuer/resource, konfigurace, klíče a klientská politika se nezměnily;
samotný regionální runtime už používá stejný nový image jako globální MCP.
Nebyl publikovaný nový konektor, provedený reconsent, změněný native README ani
volané existující scénáře. Audit uložených grantů neobsahoval Make grant,
a proto není vydáván za ověření skutečného Make připojení/scénáře.

Automatický kalendářní cutoff je odstraněný. Připravená migrace zůstává v
[API-AFTER-REVIEW.md](../../integrations/make/API-AFTER-REVIEW.md);
[deletion ledger](festapp-unified-api-DELETION-LEDGER-2026-11-13.md)
uvádí přesnou podmínku budoucího odstranění adaptéru.
Starší receipt `production-rollout-97.json`, refresh-year a rekey evidence
zůstávají historickými výsledky prvního vydání, nikoli popisem aktuálního image.
