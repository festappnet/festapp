# Make: dokončení review a sjednocení implementace

Datum: 2026-10-28. Stav: připomínky zpracované, odpověď odeslaná; následující architektonické úpravy připravené k implementaci. Verification: standard (OAuth, sdílené schéma, veřejný kontrakt).

Tento dokument nahrazuje původní přípravný plán na stejné cestě. Je jediným autoritativním plánem; [execution prompt](make-connector-EXECUTION-PROMPT-2026-10-28.md) na něj navazuje. Historické receipty se nepřepisují. Tato aktualizace je plán, nikoli důkaz provedení následujících změn.

## Výsledek a hranice

Zachovat funkční konektor vstupenky.online, dokončit existující review a odstranit doložené zdroje driftu. Doménová pravidla, oprávnění a projekce mají jednoho vlastníka; Make definuje transport, prezentaci a provozní nástroje. Nevytvářet nový konektor, REST backend, reportovací model ani generický integrační framework.

V rozsahu jsou schéma reportu, Make konfigurace/generátor, přesná inventura generated souborů, společná hranice Make SDK, neměnné důkazy a dokumentace. Mimo rozsah: Wix, účtování, změny SQL výpočtů, prodloužení souhlasů, další tenanty, Flutter buildy.

## Aktuální fakta a míra ověření

| Fakt | Důkaz | Důsledek |
| --- | --- | --- |
| Existuje app `vstupenky-online-buoz5u`, v1, EU1; Publish a review byly přijaty | `integrations/make/evidence/submission-20261028.json`, `execution-20261028.json` | Neopakovat registraci, Publish, review ani navazující formulář |
| AppBot feedback `1a18239723a8b8c6` přišel 28. 10. ve 12:15 Praha | Gmail; `review-response-20261028.json` | Není to dosud nevyřízený nový seznam oprav |
| Stejné Gmail vlákno obsahuje odpověď `1a18258af1b4ad0b` s labelem SENT | Aktuální Gmail readback; `review/RESPONSE-20261028.md` | Platné připomínky opravené, odchylky vysvětlené; neposílat duplicitní odpověď |
| V aktuálním hledání `from:make.com newer_than:2d` není další věcná odpověď | Gmail kontrola při aktualizaci plánu | Lidské schválení ani vydání nejsou doložené |
| Po opravách zaznamenána shoda 34 SDK sekcí, pět modulů, dva konzumenty mapování a šest hraničních případů | `source-readback-review-20261028.json`, `review-qualification-20261028.json` | Historický výsledek konkrétního digestu, nikoli nové ověření worktree |
| Backend receipt uvádí 45/45 cílených testů bez skipu | `server-tests-20261028.json` | Po změně backendu znovu ověřit; širší write fixture měla samostatné `ORDER_CHANGE_REJECTED` |
| Doménu obsluhuje `Operations.invoke`, společné scopes a `DelegatedOwner` | `tools/festapp/src/operations/catalog.mjs`, `packages/festapp_contracts/mcp-permissions.mjs`, `tools/festapp/src/remote/delegation.mjs` | Zachovat kanonické vlastníky |

Historické revize: backend `903145af65e4a3c1944464078c472bee26400ae9`, opravené definice `1967445f97bb6a91b256672ec346eac06e9796c3`. Manifest SHA256 `9a46cc151a1808cfdaa68f03fc772e5c2ced2b3450f7d82d5ce3e0a5e985ef2d`. Jde o údaje z receiptů, nikoli čerstvý live probe.

Aktuální checkout při průzkumu: `main`, HEAD `d2ed02f81`, mnoho jiných rozpracovaných změn a Make soubory jako untracked. Historickou revizi nezaměňovat za místní obsah. Před implementací izolovat vlastní soubory; před publikací určit přesný čistý source revision a digests. Necommitovat celý dirty worktree.

## Vypořádání všech 21 bodů AppBotu

Číslování odpovídá mailu. Opraveno znamená potvrzené zdrojem a existujícím receiptem; přijetí reviewerem je externí krok.

| Bod | Stav | Řešení / důkaz |
| --- | --- | --- |
| 1 Univerzální modul | Opraveno a vysvětleno | `scripts/build.mjs`: relativní URL, metoda, bezpečné headers, qs, JSON body, body/headers/statusCode; API má pět POST read operací |
| 2 RPC limit | Opraveno | Generated RPC limit 500, bez vymyšlené serverové pagination |
| 3 Get pole mode edit | Opraveno | Generátor nastavuje `mode: edit` u RPC-backed Get vstupů |
| 4 Popisy modulů | Opraveno | `catalog-draft.json`: Make prezentace oddělená od MCP instrukcí |
| 5 Scénáře | Provedeno | `review-qualification-20261028.json`, dvě existující inactive/on-demand scénáře |
| 6 Expirace a refresh | Opraveno a vysvětleno | `src/connection.json`: fallback refresh tokenu; sedmidenní serverová delegace se neprodlužuje |
| 7 Pagination akcí | Vysvětleno | `access.inspect` vrací úplný consent-filtered seznam, nemá kurzor |
| 8 Prázdný detail | Vysvětleno | `validateMakePage`: před úspěchem právě jeden matching event/order řádek; chybějící/cizí detail selže |
| 9 Pagination headers | Vysvětleno | `make-transport.mjs`: completion guard, nikoli autorizační vstupy |
| 10 Chybové zprávy | Opraveno | Společné status/code/message pro base a connection test |
| 11 State select | Vysvětleno | Kanonický input je stored-state string bez enumu; neinventovat neúplný seznam |
| 12 Output interfaces | Opraveno a vysvětleno | Date parse/declaration, skutečný dotted-key konzument; text report ID a money reprezentace zachované |
| 13 Labels | Opraveno | Sentence case, ID, Event v prezentaci; machine keys nepřejmenované |
| 14 Module action | Opraveno | CRUD read metadata |
| 15 Groups | Opraveno | Events / Orders / Other |
| 16 Limit | Vysvětleno a upravená nápověda | Chybějící klíč = 10, explicitně prázdné pole = všechny do technické meze; ověřeno skutečnými blueprinty |
| 17 Pagination body | Návrh vědomě nepřevzat | Make body nahrazuje původní body; event/filtry/limit se musí zopakovat |
| 18 Connection | Opraveno a vysvětleno | Common client ID, čitelná chyba, uživatelský label; privacy projection nerozšířená o identitu účtu |
| 19 Validace a typy | Opraveno | Bez neúčinného max na selectu; nullable strings jsou text |
| 20 Scopes | Opraveno | Univerzální modul má oba read scopes, server kontroluje grant |
| 21 Samples | Ověřeno | List moduly samples mají; zahrnuté v SDK readbacku |

Oficiální podklady znovu přečtené při plánování: [REST universal module](https://developers.make.com/custom-apps-documentation/app-components/modules/universal-module/rest), [RPC pravidla](https://developers.make.com/custom-apps-documentation/best-practices/remote-procedure-calls), [pagination a nahrazování body](https://developers.make.com/custom-apps-documentation/component-blocks/api/pagination#body). AI feedback není autorita pro změnu oprávnění nebo účetních dat. Podrobné zkušenosti vlastní `integrations/make/review/REVIEW-LESSONS.md`.

## Doložené architektonické nedostatky

1. `orders.mjs: orderDataSchemas['orders.report']` deklaruje jen malou část reportu a používá passthrough. `build.mjs: inferred/field` doplňuje další pole a typy ze sample, datum podle názvu `generated_at`. Make interface tak částečně vlastní fixture a OpenAPI schéma je neúplné. Toto je hlavní sjednocovací práce.
2. Transport vlastní `MAKE_CLIENT_ID` a allowlist, generátor klienta znovu hardcoduje; `catalog-draft.json` opakuje scopes/client ID a odvozené stavy. OpenAPI znovu vypisuje scope keys. Groups a moduly mají více seznamů.
3. Limity jsou rozházené: backend stránka 50, serverový guard 50 stránek, Make total input/fallback 3200, default 10, RPC 500. Jsou to odlišné pojmy. 3200 není příslib úplného exportu 3200 objednávek; při pokračování na stránce 50 současný guard skončí explicitní chybou.
4. `build.mjs --check` kontroluje očekávané soubory, ne nadbytečné generated soubory. Odstraněný modul může zůstat na disku mimo manifest.
5. `sync.mjs`, `verify.mjs`, `qualify.mjs` opakují SDK HTTP/token/rate-limit kód. Token file permissions kontroluje jen sync. Qualify hardcoduje connection/version a spolu s verify přepisuje datované historické důkazy.
6. Původní plán/prompt tvrdily, že účet/OAuth nejsou ověřené. Aktuální status již vlastní `execution-20261028.json`; dokumentace musí odlišit status, historický receipt, místní zdroj a runtime.

## Cílová architektura a invarianty

Tok zůstává: Make definice -> `/make/v1/operations/:operation` -> společná autentizace a `DelegatedOwner` -> `Operations.invoke` -> existující operation adapter -> SQL -> veřejná projekce -> Make bundle.

| Vlastník | Odpovědnost |
| --- | --- |
| `database/functions/eshop/get_report_ws.sql` | Jediné reportové výpočty |
| `database/functions/eshop_orders/operator_orders.sql: get_operator_order_report_v1` | Scoped obálka nad existujícím reportem |
| `orderDataSchemas`, `publicOrderPage` | Jediný machine data contract; žádné Make schema kopie |
| Nový `tools/festapp/src/operations/order-report-schema.mjs`, pokud oddělení pomůže | Jediná deklarace reportu importovaná do `orders.mjs`; ne druhá implementace |
| Nový `tools/festapp/src/remote/make-contract.mjs` | Make client ID, read allowlist a pojmenované transportní limity; scopes odvozené přes `scopesForOperation` |
| Nový `integrations/make/src/catalog.json` | Jediná Make prezentace: stable module key, label, description, group, operation vazba |
| `app.json`, `src/connection.json` | Existující SDK app identity a OAuth IML definice; nepřenášet sem doménová pravidla |
| Nový `scripts/lib/make-sdk.mjs` | Malá sdílená SDK hranice pro existující příkazy |

Invarianty:

- Generátor promítá schémata a Make metadata. Samples jsou validované příklady, nikdy zdroj typů. Manifest odpovídá přesně celému vlastněnému generated stromu.
- Zachovat machine names, module keys, operace, connection identity, `/make/v1`, scopes, report `schema_version`, text event ID a původní money typy. Event label neznamená rename `occasionId`.
- Zachovat client isolation, order-summary privacy, event consent, fixed origin, server allowlist, header ochrany, revokaci a pevnou sedmidenní expiraci. Jsou to záměrné hranice, ne duplicita doménových pravidel.
- Zachovat omitted/blank limit rozdíl, descending cursor a explicitní incomplete-export error. `access.inspect` nadále nemá serverovou pagination; state zůstává free-text stored value.
- SQL počty/peníze nepřepočítávat v JS. Přes Make nesmí nově unikat kontakty, poznámky, odpovědi ani QR obsah.

## Rozhodnutí, předpoklady a závislosti

**D1:** Připomínky znovu neimplementovat. Nová práce opravuje doložený drift a zachovává kvalifikované chování.

**D2:** Žádná plošná REST migrace ani přestavba OAuth. Jediný HTTP adapter existuje; neobnovovat pilotní MCP cestu jako alternativní backend.

**D3:** Report schéma rozšířit o fakticky známá pole podle SQL a konzumentů; zachovat extension compatibility. Optional/null/union typy odpovídají doloženým SQL variantám. Nezpřísňovat podle jediné fixture ani uzavřeným strict objektem zahodit dříve platná rozšíření.

**D4:** V tomto refaktoru zachovat veřejný vstupní strop 3200 i současnou completion mez. Pojmenovat je odděleně a odvozovat page size z canonical schema. Změna stropu nebo hlavičkového protokolu je samostatná veřejná změna.

**A1:** SQL v repozitáři popisuje zamýšlený report. Před posílením schématu porovnat `get_report_ws`, `get_operator_order_report_v1`, samples a `reporting.mjs: reports.export`. Nesoulad řešit podle doložených variant, nikoli úpravou peněz nebo SQL pro Make.

**A2:** Existující app stále čeká na lidskou kontrolu. Před případným sync jednou načíst stav. Již schválenou app neměnit cestou pro unapproved review update.

Externí závislost: lidské posouzení Make a katalogové vydání. Lokální architekturu neblokuje. Reautorizace reviewer účtu po expiraci nesmí rozšířit consent scope ani opakovat provisioner.

## Mazací a migrační seznam

| Artefakt | Akce | Důkaz |
| --- | --- | --- |
| `catalog-draft.json` | Migrovat prezentaci do `src/catalog.json`, odstranit starý soubor a odvozená runtime/status/tool pole | Žádné aktivní odkazy na starý soubor |
| Sample inference pro známý report a name-only date heuristika | Nahradit canonical schema | Změna sample hodnot nemění interface; datum deklarované schématem |
| Kopie client ID/scopes/transportních limitů | Použít `make-contract.mjs` a shared scope owner | Runtime, OpenAPI i generátor odvozují stejné údaje |
| Paralelní groups/module seznamy | Odvodit z jediné Make prezentace | Každý modul právě jednou, známá read-only operation |
| Obsolete `src/generated/` soubory | Odstranit pouze ve vlastněném stromu, check odmítá extra soubory | Přesná file-set shoda s manifestem včetně manifestu samého |
| Tři kopie SDK token/HTTP/rate kódu | Nahradit jednou SDK hranicí; mutation guardy ponechat u příkazů | Jeden protected loader a request implementation |
| Hardcoded qualification connection/version | Reviewer kontext v jednom ne-secret configu, verze z `app.json` | Konzistentní fixture/identity kontrola |
| Přepis historických receiptů | Nové run-specific soubory, status pouze pointer | Původní freeze/qualification/readback digesty nezměněné |
| Zastaralé tvrzení o neexistujícím účtu a nezvoleném transportu | Odstraněné touto aktualizací plánu/promptu | Jediný aktuální execution status |
| Server allowlist/header guardy, veřejná v1 jména, historické receipty | Záměrně ponechat | Testy kontraktu, doložené boundary/history |

## Implementační vlny

### 1. Jediné faktické schéma reportu

**Změny:** zmapovat pouze `get_report_ws.sql` -> `operator_orders.sql` -> `orders.mjs` -> `catalog.mjs` a `reporting.mjs: reports.export`. Popsat známá pole jedním schématem: ISO timestamp, text ID, numeric/decimal-text money varianty a podmíněné bloky. Zachovat passthrough pro rozšíření; nepřidat osobní údaje.

`build.mjs: concrete/field` musí používat schema včetně nullable/union/array/object pravidel a date metadata. U nevyjádřitelného unionu explicitní podporované mapování, ne výběr podle sample. Odstranit sample-owned report typing a name-only date heuristiku. Dynamický record má schema-owned value type, ne seznam fixture keys.

**Kompatibilita:** stejné hodnoty i rozšíření; žádná SQL změna/migrace ani konverze peněz/ID. Posílení validace nesmí odmítat dosud podporovanou variantu pouze kvůli neúplnému vzorku.

**Validace/exit:** contract testy různých report variant, skutečný SQL výstup přes `make-orders-postgres.test.mjs` a sdílený export přes `reporting-postgres.test.mjs`. Porovnat generated interface a OpenAPI s baseline. Známá report pole mají jednoho vlastníka, změna sample hodnot nemění interface.

### 2. Jeden Make kontrakt a přesný generátor

**Změny:** zavést `make-contract.mjs`, přesměrovat importy serveru/transportu/generátoru; prezentaci přestěhovat do `src/catalog.json`. Scope union odvozovat z allowlistu a `mcp-permissions.mjs`; vazby ověřit proti `Operations.catalog` a `domainReadOnly`. Common client ID ze stejné konstanty. OpenAPI scope keys odvodit, popisy mohou zůstat prezentační.

Pojmenovat zvlášť backend page size, max pages, total input cap, default total a RPC sample limit. Page size vycházející ze schema použít v generated body i completion aritmetice. Zachovat úplné pagination body. Groups odvodit z modulových metadat.

Oddělit čisté sestavení mapy souborů od CLI zápisu. `--check` porovnává obsah i přesný file set. Regenerace odstraní obsolete artefakty pouze pod vlastním `src/generated/`, bez symlink escape a bez mazání ručních zdrojů. Schema-only artefakty nesynchronizovat jako SDK komponenty.

**Mazání/kompatibilita:** odstranit draft/kopie/seznamy a obsolete outputs; zachovat veřejné názvy, parametry, limity a auth chování.

**Validace/exit:** generator testy dokazují schema/sample nezávislost, detekci extra souboru, zrušený modul, scopes/groups, blank/default logiku. Finální `build.mjs --check`, `make-transport.test.mjs`, `remote.test.mjs`. Jediný Make kontrakt a prezentace, žádný aktivní draft odkaz nebo extra generated artefakt.

### 3. Jediná SDK hranice a důvěryhodné důkazy

**Změny:** `scripts/lib/make-sdk.mjs` sjednotí protected token loader (regular file, bez symlinku, bez group/other permissions), pevný SDK origin z ověřené app identity, paced requests a sanitizované chyby. Žádné automatické retry mutace s neznámým výsledkem. Sync/verify/qualify zachovají účely a guardy; sync nesmí automaticky mazat neznámé remote komponenty.

Reviewer kontext (connection `12447881`, scénáře `8226665`/`8228261`, fixture marker) bude mít jeden ne-secret config. Verze z `app.json`. Před mutací ověřit team, vlastníka, fixture a inactive/on-demand stav. V `finally` ukončit scénáře jako inactive; stop failure zaznamenat i při původní chybě. Žádná nová fixture/provisioner.

Nové důkazy ukládat pod jedinečným run ID s digesty a odkazy na původní freeze. `execution-20261028.json` je stručný mutable status/pointer; původní datované readback/qualification/freeze se nemění. Žádné tokeny nebo celé privátní logy.

**Validace/exit:** fake HTTP testy SDK hranice (403/429/timeout, žádné implicitní mutation retry, token file protections), failure cleanup a immutable evidence writer. Tři příkazy sdílejí klienta; neúspěšný běh má pravdivý status a nezměněnou historii.

### 4. Kontrakce dokumentace a podmíněný review update

**Změny:** aktualizovat `README.md`, `SETUP.md`, `API.md` a review handoff jen podle skutečné změny kontraktu/workflow. Stav odkazuje na execution receipt. Již odeslanou odpověď a historické receipty needitovat. Výsledek implementace doplnit do tohoto plánu, žádný paralelní plán.

Nejprve porovnat finální generated manifest s odeslaným digestem. Pokud se publikované definice nezměnily, žádný sync ani živé scénáře jen kvůli refaktoru tooling. Pokud se změnily, po lokálních checks a readbacku současného review stavu aktualizovat stejnou unapproved app přes `sync.mjs --apply --review-update`, ověřit SDK a jednou spustit dotčené existující scénáře přes `qualify.mjs --apply`. Žádný nový Publish/review. Nový mail není součástí tohoto plánovacího kola; odpověď již odešla. Další konkrétní komunikaci řešit pouze v autorizovaném rozsahu.

Případný server deploy je zvláštní krok s přesnou revizí/cílem podle provozních pravidel a skillu `festapp-backend-access`. Rutinní autorizovaný deploy delegovat levnějšímu subagentovi. Žádný deploy z dirty worktree ani vedlejší tenant. Exit lokální části: deletion ledger uzavřený, dotčené gates passing, dohledatelný nový digest/status. Externí review může stále čekat.

## Ověření, rollout a rollback

Plánování testy nespouští. Při implementaci změny dávkovat a provést cílenou závěrečnou sadu; opakovat jen dotčené kontroly po opravě. Node 24, pnpm 11.24.0, z `tools/festapp/`:

```sh
pnpm exec node ../../integrations/make/scripts/build.mjs --check
pnpm exec node --test --test-concurrency=1 test/make-connector.test.mjs test/make-transport.test.mjs test/remote.test.mjs test/make-orders-postgres.test.mjs test/reporting-postgres.test.mjs
```

Nový `test/make-connector.test.mjs` ověřuje stabilní schema/generator/SDK kontrakty, nikoli přesné znění UI copy. SQL testy vyžadují `FESTAPP_MCP_TEST_DATABASE_URL` na marker-ověřené disposable lokální DB, paused email kapacitu, null worker URL a rollback. Neexportovat produkční `.env.local`, nehádat DB podle starého portu. Chybějící DB/skip = INCOMPLETE, nikoli PASS. Při změně shared schématu zahrnout skutečné konzumenty; širší známou write fixture neoznačovat za passing.

Před externí změnou: izolovaný známý commit, aktuální authoritative main fetch/porovnání, cílené tests, manifest freeze, kontrola review state, server před klientem pouze pokud je serverová změna nutná, pak sync/readback a relevantní scénáře. Před push platí repository publication pravidla. Při pouhé reorganizaci nezasahovat do issueru/callbacků.

Rollback tvoří koherentní vrácení zdrojů a generated definic při zachování klientské identity. Nevracet pilot, fallback backend ani paralelní schéma. Schválený katalogový kontrakt neměnit rollbackem přes unapproved review cestu. Historie zůstává zachovaná.

Původní rozsah projektu již obsahoval účet `info@festapp.net`, bezplatné vydání, cílené nasazení Make a řešení review. Tato plánovací aktualizace neuděluje nové širší oprávnění. Případné provozní kroky realizovat pouze v doloženém existujícím rozsahu. Pevný poplatek, předplatné, automatický nákup kreditů ani změny jiných produktů nejsou autorizované.

## Definice dokončení a zbytková rizika

- [ ] Všech 21 bodů má opravu nebo doložené vysvětlení; žádný duplicitní review/mail.
- [ ] Report schéma vlastní operation vrstva; samples nedefinují známá report pole.
- [ ] Runtime/OpenAPI/Make používají společný transportní kontrakt a scope owner; doména zůstává v Operations/SQL.
- [ ] Prezentace a SDK mají po jednom vlastníkovi, obsolete zdroje i outputs odstraněné.
- [ ] Generated file set přesně sedí, historie nepřepsaná, aktuální status dohledatelný.
- [ ] Passing cílené testy včetně skutečné lokální SQL; sync/deploy ověřené, nebo výslovně neprovedené.
- [ ] Lokální dokončení je oddělené od schválení Make. Katalogové dokončení vyžaduje skutečné approval/release a discovery + OAuth z jiného již autorizovaného účtu; nezakládat další účet jen kvůli testu.

Rizika: podmíněná report pole a union money typy mohou vyžadovat explicitní Make projekci typu bez změny hodnot. Server a checkout mohou být na jiných revizích. Make může při lidské kontrole vyžádat další doloženou úpravu. Veřejná cost evidence není písemná garance Make. Sedmidenní reautorizace a omezený ne-snapshot export zůstávají produktové limity.

## Implementace 2026-10-28: lokální kontrakce

Změny jsou izolované nad existující Make větví `42917b9e1` v `/tmp/festapp-make-contract-20261028` (`refactor/make-contract-20261028`). Dirty main není zdroj pro provozní zápis. Původní obsah dotčených souborů je pro oddělení vlastního diffu zachovaný v `/tmp/festapp-make-baseline-20261028`.

- Vlna 1: `order-report-schema.mjs` je jediná deklarace známého SQL reportu, importovaná do `orderDataSchemas`; `reports.export` používá stejný executor. Podmíněné bloky jsou optional, objekty passthrough, SQL se nemění. Make pro mixed scalar union používá `any` bez konverze; dynamic collection nemá fixture-owned keys, value schema zůstává canonical JSON Schema. Toto je explicitní mez Make projekce, nikoli další schéma.
- Vlna 2: identitu, allowlist, scope union a pojmenované limity vlastní `make-contract.mjs`; scopes dál počítá `scopesForOperation`. `src/catalog.json` vlastní pouze prezentaci a groups. `assemble` sestaví mapu; generátor kontroluje přesný file set a odmítá symlinky i u kořenové cesty s koncovým lomítkem. Regenerace maže obsolete soubory pouze ve vlastním stromu.
- Vlna 3: `scripts/lib/make-sdk.mjs` je jediný token/HTTP/pacing/evidence owner. `src/reviewer.json` vlastní existující reviewer kontext; qualification ověřuje team, autora connection/scénářů, fixture a on-demand/inactive stav. Mutace vyžadují čistý source commit a generated shodu. Evidence vzniká s exclusive create mimo source checkout, každý checkpoint samostatně; cleanup selhání zůstává v receiptu.
- Vlna 4: README/API/review handoff odlišují historické receipty od místního zdroje. SETUP neměníme: uživatelský/OAuth postup zůstává stejný a jeho native README digest je zachovaný. Existující odpověď ani historické důkazy se nemění.

Deletion ledger: odstraněn `catalog-draft.json`, sample inference a name-only datumová heuristika, kopie klienta/scopes/limitů a paralelní groups seznam; tři SDK request/token implementace nahrazené jednou; hardcoded qualification IDs/verze nahrazené kontextem/app identity; přepis historických receiptů odstraněn. Baseline neobsahoval obsolete generated soubory; test vytváří extra soubor a retiruje modul, ověřuje jejich odstranění a přesnou shodu zbývajícího stromu. Aktivní draft odkazy nejsou. Záměrně zachovány public machine keys, fixed-origin/read/header/consent hranice a historické důkazy.

Lokální ověření: Node 24.20.0, pnpm 11.24.0, cílená sada plánu 61/61 PASS, 0 skip. SQL použilo marker `festapp-authz-20261020` na explicitním loopback 61022, cron off, paused email a null worker URL; fixture transakce se rollbackují. `build.mjs --check` potvrzuje všech 42 souborů. První testovací běh zachytil root symlink s trailing slash; opraveno a konečná sada je passing. Širší write fixture se nespouštěla a tento výsledek ji neoznačuje za passing.

Nový manifest SHA256: `7c33fb6636d5cc85109c228b0acd62facb452f085374e5d45e0884719e93fdd0`. Proti review freeze se mění pouze `schemas.json`, salesReport interface a manifest; jediné změněné publikované SDK tělo je salesReport interface. Čerstvý omezený SDK read vrátil app v1/public, `approved=false`, `inReview=true`; connection/team a positive scenario owner/on-demand/inactive pole odpovídají reviewer kontextu. Podmíněný update stejné app bude zaznamenaný samostatným immutable receiptem po source freeze. Server deploy není potřebný pro doplnění SDK interface: skutečný SQL výstup již obsahuje tato pole, values/transport se nemění.

Externí závislost zůstává: lidské review, approval/release a následně discovery/OAuth jiného již autorizovaného účtu. Žádný nový Publish, review, mail, účet, provisioner, placený závazek nebo jiný tenant není součástí této implementace.

### Provozní průběh a doložená korekce předpokladu

Čistý freeze `eb02a9c2a62e8b37280beb27411f7616ee6fb681` aktualizoval stejnou unapproved app a SDK readback potvrdil 34/34 sekcí. První qualification invocation skončila lokálně před SDK voláním nebo změnou scénářů: soukromý provision receipt má u objednávek navíc canary metadata `hostileNote`, zatímco veřejný `review/demo-data.json` má jen identity. Plná rovnost řádků tedy není platný fixture invariant. Guard nově porovnává marker, unit/event IDs a set stabilních order identit (id, occasionId, symbol, state); nerozšiřuje consent ani fixture. Preflight rejection je zaznamenaný samostatným immutable receiptem a neprovedl žádný scenario run.

Tooling follow-up navíc odmítá URL-encoded/fragment/query názvy cest ještě před mazáním generated souborů. Cílené contract testy po těchto změnách: 12/12 PASS, 0 skip; generated check opět PASS a manifest je beze změny. Sync a readback se neopakují pro totožné SDK definice. Qualification se provede z nového čistého source revision, poprvé skutečně spustí existující scénáře. Historické freeze zůstávají zachované.
