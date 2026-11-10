# Souhlas podle skutečných práv uživatele

Upřesnění uživatele nahrazuje návrh funkčních checkboxů z předchozího plánu. Obecné MCP má v odsouhlasených akcích/pořadatelích vykonávat úkony podle aktuálních uživatelských práv. Uživatel nemá sestavovat další matici funkcí.

1. Odstranit seznam a přepínače jednotlivých funkcí i samostatné povolování vytvoření akce z běžné tenantové i samostatné issuerové souhlasové stránky. Zachovat výběr akcí/pořadatele, dobu a správu připojení.
2. Interně potvrdit klientem požadované OAuth scopes jedním souhlasem. Obecní klienti nadále podporují celý katalog. Výběr pořadatele zahrnuje i vytváření, pokud jej žádá klient a aktuální práva uživatele jej dovolují. Technické scope kontrakty, strop specifického klienta a živé SQL predikáty dál brání rozšíření práv. Existující granty se nezvětšují automaticky; staré rozpracované užší souhlasy se respektují.
3. Regresními testy ověřit absenci další role-matice v UI, kompletní obecný katalog, úzký klientský request, cizí akci, změnu aktuálních práv a platnost již vydaných grantů. Zachovat opravu členství při vytvoření a jediného SQL vlastníka doménových příkazů.
4. Spustit dotčené canonical CI lanes, publikovat main a po osmi GitHub gates nasadit MCP issuer a web pouze pro festapptickets. Bez SQL migrace, nových rolí nebo změn veřejného omezeného ChatGPT klienta.
5. Ověřit přes UI jednoduchý souhlas a funkční obecný MCP přístup, zákaz cizího rozsahu, následně odvolat vlastní granty. Pořídit skutečný světlý snímek souhlasu bez přepínačů funkcí a osobních údajů.
