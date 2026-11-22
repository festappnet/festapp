# Dokončení Make review a přechod vstupenky.online na jednotné API

Datum: 2026-11-19  
Ověřování: standard  
Rozsah: existující aplikace Make `vstupenky-online-buoz5u`, verze 1, EU1, ticket #2351677, a regionální integrace vstupenky.online.

## Výsledek

Make schválí existující integraci s regionálním OpenAPI `https://api.vstupenky.online/integrations/v1` s issuerem `https://mcp.festapp.net`. Uživatel ji najde v katalogu, projde produkčním OAuth přihlášením a spustí všech pět modulů. Po migraci konzumentů skončí obsluha `/make/v1` včetně vlastních OAuth vazeb a stránkovacích hlaviček.

## Výchozí stav

- [Make, 18. listopadu](https://mail.google.com/mail/u/?authuser=bujnmi%40gmail.com#all/1a1eefd4c6133674) uzavřel většinu říjnových bodů. Zbývá jeden povinný bod kolem univerzálního modulu, dvě otázky k OAuth a dvě drobnosti kolem data a loga. Logo je výslovně nepovinné pro schválení.
- [Zmrazený říjnový stav](../../integrations/make/evidence/review-freeze-20261028.json) odpovídá digestu `9a46cc151a1808cfdaa68f03fc772e5c2ced2b3450f7d82d5ce3e0a5e985ef2d` v revizi `df4cbed07`. Pět modulů, dvě downstream mapování a šest hraničních případů prošly. Starší e-maily o neplatném tokenu a neplatném typu výstupu předcházejí těmto úspěšným běhům. Platnost dnešního reviewer připojení určí nový readback a reautorizace podle potřeby.
- [SDK inventář z 13. listopadu](festapp-unified-api-evidence-2026-11-13/make-consumers.json) našel posuzovanou definici na regionálním issueru, reviewer připojení a dva neaktivní scénáře. Aktuální generátor na main už připravuje nové API. Jeho plošný sync by během review změnil route i OAuth resource. Říjnové receipty zůstanou historickým důkazem.
- [Registrace posuzované verze](../../integrations/make/evidence/oauth-registration-20261028.json) eviduje veřejný klient `festapp-make`, PKCE S256, bez client secretu, a přesný callback `https://www.make.com/oauth/cb/app`. Dynamická registrace je vypnutá. Unifikovaný server navíc pro Make vyžaduje přesný seznam s jediným callbackem v `normalizeClient`.
- Uživatel 19. listopadu výslovně přidal přímý přechod na jednotné API k opravám review. Tato aktualizace nahrazuje původní pořadí z [plánu z 13. listopadu](festapp-unified-api-plan-2026-11-13.md) pro změnu definice a testovací připojení. Zachovat stejný app záznam, stejný ticket, stabilní identifikátory modulů a read-only profil. Původní trasu lze odebrat po prokázaném přesunu konzumentů a potvrzení, že Make nebude potřebovat původní definici.
- Živý SDK readback 19. listopadu potvrdil `public=true`, `approved=false`, původní API call a date IML a dva neaktivní on-demand scénáře. Připojení 12447881 má v Make expiraci 4. listopadu. Nový reviewer consent je součástí přechodu.
- Shoda s říjnovou definicí platí pro 33 z 34 SDK sekcí. Živé rozhraní sales reportu má novější schéma plateb a sum. Porovnání podle cest a datových typů potvrdilo, že odpovídá i novému generátoru. Přesný živý stav této sekce a hashe všech sekcí jsou v chráněných receiptech `review-before-cutover` a `review-interface-diff` pod `~/.festapp/make-runs/`.
- Živá reference jednotného API vrací HTTP 200. Autorizační požadavek pro `festapp-make` s kanonickým resource a vývojovým callbackem prošel do interakce (HTTP 303). Oba uvažované produkční slugy zatím vracejí `invalid_redirect_uri`. Dokončený OAuth tok a přesný produkční callback zůstávají k ověření.
- Make dostal [dotaz ve stejném ticketu](https://mail.google.com/mail/u/?authuser=bujnmi%40gmail.com#all/1a1f1d6a40554ca3) na podporovaný postup a přesný callback. Text prošel nezávislou kontrolou. Před zápisem do stávající verze čekáme na potvrzení aktualizačního postupu, protože SDK změna může okamžitě ovlivnit instalace ze stávajícího veřejného odkazu.

## 1. Připravit opravy review a potvrdit callback

1. Bez zápisu přečíst SDK metadata aplikace, moduly API call a sales report, jméno connection a stav review. Porovnat s říjnovým digestem. Při rozdílu vycházet z ověřeného živého stavu a uložit sanitizovaný výchozí readback. Původní sekce uložit jako doklad a zdroj pro obnovu před dokončením cutoveru. Opravu implementovat jednou v generátoru přímo pro kanonické API.
2. Univerzální modul složí URL z pevného HTTPS originu a zadané relativní cesty. Platné cesty prochází beze změny včetně neznámé operace, aby konkrétní chybu vrátil server. Odstranit seznam pěti cest i interní přesměrování na `/operations/forbidden`. Zachovat metodu, headers, query, tělo a výstupy body/headers/statusCode. Make musí garantovat pevnou autoritu požadavku a vlastní OAuth Authorization i při konfliktu velikosti písmen. Ověřit chování v reálném runtime, včetně odmítnutí absolutní cesty, změny originu a cross-origin redirectu. Běžné vlastní hlavičky projdou. Pokud SDK předá i transportní hlavičky schopné změnit cíl nebo identitu requestu, použít nejmenší nutnou ochranu a popsat ji Make. Server dál vynucuje klienta, scopes, živá práva, souhlas k události, povolené operace a summary profil.
3. V `orders.report` dát `parseDate` explicitní formát. SQL `get_report_ws.sql` vrací UTC s mikrosekundami a koncovým Z. Ověřit skutečný vzorek `2026-10-28T09:43:58.688416Z` a downstream formátování v Make. Pokud Make čte jen milisekundy, normalizovat zlomek výhradně při převodu v konektoru a výslovně ověřit stejný okamžik. Schema reportu zůstává společné.
4. Make vysvětlit, že tato integrace používá jediný registrovaný veřejný OAuth klient a zákazník si vlastní klient pro ni nezaregistruje. Ověřit skutečný produkční callback podle existujícího connection a Make. Reviewer očekává `https://www.make.com/oauth/cb/vstupenky-online`, zatímco interní jméno connection v `app.json` má suffix `-buoz5u`. Rozhodující je hodnota skutečně vyslaná Make nebo potvrzená Make pro tento connection. Registrovat oba potřebné callbacky jako přesné HTTPS adresy v relevantních issuerech podle fáze, bez wildcardu. Upravit konfiguraci i `normalizeClient` pro explicitní množinu. Pokrýt povolené exact match a odmítnutí cizích variant na authorize/token hranici. Stávající `/oauth/cb/app` zachovat, dokud ho Make pro vývoj skutečně potřebuje.
5. Připravit transparentní tmavý PNG se samotnou ikonou vstupenky. Zdroj Make loga oddělit od loga ChatGPT, ověřit v nativním barevném náhledu Make a uložit hash zdroje i renderu. Logo lze zveřejnit samostatně v rámci stejného review, pokud jeho příprava jinak zdrží schválení.

**Brána:** jednotný generátor a změna proti živému readbacku mají lokální důkaz. Produkční callback má zjištěnou skutečnou hodnotu, nebo je otevřená konkrétní otázka pro Make. Nové API může být připravené v kódu.

## 2. Nabídnout jednotné API ve stejném review

- Ověřit regionální summary OpenAPI, callback na kanonickém issueru a scope/audience `https://api.vstupenky.online/integrations`. Výstup generátoru použije veřejné OpenAPI, stejnou sadu modulů a RFC 9457 chyby. Počáteční readiness ověřit s callbackem `/oauth/cb/app`. Produkční exact-match nastavit až po potvrzení slug Make.
- Ověřit v Make nativní stav a podporovanou aktualizaci rozpracovaného review. Před přepsáním definice pořídit sanitizovaný readback změněných SDK sekcí a inventuru instalací, scénářů a připnutých verzí. Pokud aktualizace přepíše definici i existujícím konzumentům, vyžaduje koordinovaný přechod přímo v tom okně. Pokud Make vyžaduje podporovanou novou verzi v rámci stejného app záznamu, postupovat v tomto rámci a udržet stejný ticket.
- Pro autorizovaný přechod použít SDK synchronizaci pouze na správnou app/verzi s ověřenými vstupy nebo konkrétní nativní workflow požadované Make. Po nejednoznačném zápisu nejdřív readback a teprve potom případná oprava. Ověřit přesný issuer, resource a REST modul. Připojit testovacího uživatele novým OAuth consentem a ověřit připojení podle jeho ID a resource. Syntetická data zůstávají ze stávající fixture.
- Použít dva existující on-demand scénáře 8226665/8228261. Ověřit všech pět modulů, 52 objednávek přes dvě stránky, prázdný a vynechaný Limit, explicitní stránkovací chybu na stropu, mapování timestampu a capability, průchod vlastní hlavičky, 401/403/429 a reautorizaci při expiraci nebo revokaci. Readbackem ověřit, že scénáře po testech zůstaly neaktivní. Uložit revizi, ověřené sekce, výsledky, ID běhů a případný rollback.
- Po autorizaci odpovědět ve vlákně #2351677. Popsat opravy, nový issuer a resource, testy, veřejného klienta a skutečně ověřené callbacky. Případný nejasný produkční callback potvrdit s Make před jeho aktivací. Použít stávající Free organizaci bez nákupu, nové aplikace nebo duplicitního review.

**Brána:** Make eviduje jednotnou definici v existujícím review, proběhlo reálné nové OAuth a testy všech modulů a scénáře zůstaly neaktivní.

## 3. Ověřit katalog a přechod konzumentů

- Doložit schválení a katalogový listing stejného záznamu a produkční OAuth z dalšího autorizovaného připojení. Ověřit skutečný consent a jeho pevný limit.
- Ověřit instalace, připnuté verze, aktuální spojení a sanitizovanou serverovou telemetrii. Připojení migrovat novým OAuth consentem se samostatnou audience. Spotřebitele po ověřené migraci evidovat po ID, bez tokenů či osobních údajů. U každého dočasného konzumenta určit vlastníka a konec migrace. Případné `Deprecation` a `Sunset` zveřejnit až po znalosti konzumentů.
- Dokud existují závislosti, původní adaptér je dočasná provozní pojistka s doloženým koncem. Po odstranění obnovovat opravenou verzi jednotného API.

**Brána:** katalog ukazuje schválenou verzi, produkční OAuth a všech pět modulů čtou přes jednotné API, inventura a telemetrie potvrzují přesun či ukončení všech starých konzumentů.

## 4. Odstranit starou cestu

- Po inventuře a potvrzeném přechodu odebrat v `server.mjs` registrace `/make/v1`, transport `legacy-make`, jeho validační a error větve a legacy Make consent/resource vazby. Odstranit `make-transport.mjs`, Make stránkovací hlavičky, obsolete části `make-contract.mjs`, proxy upstream, staré config příklady, pomocné rollout skripty a zvláštní fixtures/testy po přesunu obecného pokrytí. Historické receipty ponechat. Prověřit širší [deletion ledger](festapp-unified-api-DELETION-LEDGER-2026-11-13.md) a uzavřít [otevřený úkol](../operations/work-items/open/make-route-canonical-cutover-2026-11-13.md).
- Revokovat pouze nahrazené Make granty, podle ověřené vazby na původní audience a klienta. Regionální MCP a ostatní OAuth klienty zachovat. Případný proxy HTTP 410 je statická odpověď bez OAuth a bez přesměrování na nové API. Ověřit, že stará cesta nemůže vykonat operaci a běžné MCP vstupy dál fungují.

## Ověření a doklad o dokončení

- Generátor `pnpm --dir tools/festapp exec node ../../integrations/make/scripts/build.mjs --check`; cílené Node testy `make-connector`, `api-transport`, `client-policy` a do odstranění `make-transport`. Zkontrolovat skutečný běh dotčených testů v `automation/ci/checks.json`; při přidání nebo přesunu testu spustit `python3 automation/ci/run.py inventory`.
- Při živém běhu potvrdit z request logu, že `X-Festapp-Make-Qualification` skutečně prošla do požadavku. Vlastní response `X-Request-Id` vydává server a tuto zkoušku nenahrazuje.
- Pro živé změny použít ověřené provozní vstupy a příslušné CI a release gates. V závěrečném receiptu uvést schválení, katalogovou verzi, použitý callback, ověřené běhy po migraci, výsledek inventury a HTTP chování odstraněné cesty. U neuzavřené fáze uvést konkrétní chybějící důkaz či autorizaci.
