# PR #749 - výsledek místní implementace

Stav: místní implementace a požadované lokální ověření dokončeny. Bez publikace, push, merge do main či produkčních zásahů.

- Worktree: `/Users/miakh/source/festapp-pr749`, větev `fix/mcp-pr749-lifecycle`.
- Fetch ověřil původní PR `0aa0654b0069ee2773bf00f880c5d026fd566187` a main `7e9a8ec6c21fa0a56dc985bb65479fd3acebe320`.
- PR je lokálně přebázovaný na tento main; rebased commit je `f23ed15bcb20726f423998a88fcff355c9c07681`. Následná implementace zůstává jako necommitnutý diff. Změny #750 a opravy cash RPC jsou zachované. Jediný rebase konflikt byl v referenci, která byla regenerována ze zdrojů.
- Původní checkout a jeho dva uživatelské soubory plánu zůstaly beze změn; jejich kopie jsou i zde.

## Výsledek

Nové consent záznamy jsou pending do úspěšné serverové výměny kódu. Jedna synchronní SQLite transakce ověří aktuální cíl, aktivuje nástupce, povýší TTL a odvolá původní backend i provider grant. První commit vyhrává. SQLite chyba vrací OAuth error bez tokenů, rollback obnoví původní stav. Ani tokenové řádky ponechané při chybě cleanup neopravňují pending připojení.

Jedna sdílená policy vlastní aktivitu, absolutní konec, 30denní neaktivitu a délky 7/30/90/365 dní. Oba consent vstupy zobrazují limit, datum konce a omezení backend session. Historické záznamy normalizuje jednorázová transakční migrace; nepoužité legacy nemá automatický replacement default. Refresh replay odvolává rodinu i Delegation. Browserem nalezená chyba Origin byla opravena změnou Referrer-Policy na same-origin při zachování přesné CSRF kontroly originu.

## Provedené checks

Pnpm 11.24.0; instalace `pnpm --dir tools/festapp install --frozen-lockfile` a `pnpm --dir web_client install --frozen-lockfile`.

Na původním PR byl nový HTTP test aktivace červený: při selhání aktivace vrátil 200 místo požadovaného 500. Po opravě prochází. Finální ověření:

```sh
./automation/test_ci.sh server-policy
```

Canonical lane skutečně vykonala worker typecheck/unit checks a následující kontrakt, připnutým Node 22.23.3:

```sh
pnpm --dir tools/festapp exec node --test --test-concurrency=1 test/connection-choice.test.mjs test/remote.test.mjs test/forms.test.mjs
pnpm --dir web_client exec node --test --test-concurrency=1 tests/components/mcp_connection_page.test.js tests/components/account_connections_page.test.js
deno test --frozen --lock=supabase/functions/deno.lock --allow-env --allow-net --allow-read supabase/functions/mcp-session-exchange/
pnpm --dir tools/festapp run docs:check
```

Výsledek: 100/100 Node, 51/51 web, 15/15 Deno, bez skipů. Lane prošla za 8,4 s. Vývojový dirty receipt je v [CI záznamu](mcp-connection-pr749-ci-2026-11-07.json); není release attestací.

Navíc:

- `automation/ci/test_contract.py` přes cached Python prostředí s PyYAML: 6/6 prošlo. Přímý systémový Python nejprve postrádal yaml; podporované cached prostředí prošlo.
- `git diff --check`: prošlo.
- `pnpm --dir tools/festapp exec node --check test/browser-oauth-fixture.mjs`: prošlo.
- `FESTAPP_AUTHORIZATION_DATABASE_URL=<task-owned-loopback-db> FESTAPP_LOCAL_DB_PORT=62422 FESTAPP_LOCAL_DB_PROJECT_ID=festapp-pr749-oauth-local node --test tools/festapp/test/mcp-tree-postgres.test.mjs`: 1/1, bez skipů. Skutečné canonical SQL ověřilo i odebrání živých práv.
- Skutečný izolovaný muted headless browser přes Terra: consent, callback, token exchange, MCP tools/list, refresh, druhé nové roční připojení, opuštěná náhrada a browser revoke. Finální runtime znovu ověřen kompletním flow včetně odvolání. Podrobnosti a příkazy jsou v [browser evidence](../../tools/festapp/test/browser-oauth-evidence.md).

Nové HTTP testy pokrývají souběh v obou pořadích, skutečné SQLite fault injection ve třech fázích, rollback a restart, nefunkční cleanup, ztracenou HTTP odpověď po commit, ruční revokaci, hranice všech čtyř délek a neaktivity, native refresh replay, pending deadline a idempotentní migraci včetně native refresh existující šifrované session.

## Deletion ledger

| Nahrazená cesta | Uzavření |
|---|---|
| Best-effort installConnectionReplacement | Odstraněn; synchronní installConnectionActivation propaguje commit chyby. |
| Active candidates bez issuance | Nahrazeny společným connectionActive; pending se nenabízí ani nelistuje. |
| Autocommit storage.revoke | Nahrazen transakcí se soukromým společným revokeRecords. |
| Roční backend TTL po consentu | Pending zůstává v původním interaction deadline; promotion pouze v activateConnection. |
| Test vyžadující HTTP 200 při cleanup failure | Nahrazen skutečným HTTP error kontraktem, SQLite rollback testy a důkazem odmítnutí ponechaných tokenů. |
| Kopie duration/idle výpočtů | Společný contracts modul používají issuer, čtenáři, management a oba consent adaptéry. |
| Zastaralá reference | Regenerována, docs:check prošlo; measurement/cash změny zachované. |
| Fallback podle chybějící issuance | Pouze jednorázová startup normalizace verze 1; explicitní legacy zachovává původní deadline. Nové zápisy mají pending marker. |

## Hranice důkazu a samostatné vydání

V lokálním browser testu byl simulován pouze aktivační manifest; GoTrue, PostgREST a SQL byly skutečné. Browser prošel standalone consent, tenant bridge je pokryt skutečným HTTP/OIDC a Deno/component testy. Externí poskytovatelé přihlášení ani produkční session timeouty nebyly prověřovány. Fixture po posledním reálném průchodu dostala pouze explicitní vstup pro privátní adresář a dodatečné disposable/email-fence assertions; issuer se nezměnil a syntax fixture prošla.

Požadované místní ověření nezůstává otevřené. Task-owned browser, issuer, Supabase kontejnery, volumes a dočasné credentials byly uklizeny. Cizí stacky ani produkční účty nebyly použity.

Před samostatně autorizovaným vydáním nadále zjistit případná dřívější nasazení nekanonického PR a skutečné produkční GoTrue limity, zopakovat upstream/publication gate a vyžadovat všechny canonical release gates. Tyto produkční kroky nebyly součástí tohoto zadání.
