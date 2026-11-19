# Obnova objednávky při změně Meta souhlasu

PR #929 má zachovat stejný příkaz pro rozpracovaný nákup i po obnovení stránky, když zákazník souhlas udělí, odvolá nebo se jeho dřívější souhlas nedá načíst. Regresní test na revizi `4010c35aa` opakuje tentýž košík bez původního souhlasu a dostane dva příkazy.

## Smlouva

- Identitu nákupu určuje objednávka, prodejní endpoint a stávající vazba na kupujícího. Celé `metaPurchaseConsent` je volitelný podklad pro měření. Browser i databáze ho vynechají z hashe příkazu.
- Prvotní uložení může zachytit pouze právě autorizovaný souhlas. Databázová obnova vrací původní výsledek a měření znovu nezachytává. Stejný příkaz s jiným košíkem nebo kupujícím se odmítne.
- Starý čekající příkaz se stále obnoví, pokud jeho původní hash odpovídá dodanému obsahu. Neznámý obsah starých hashů nelze zpětně odvodit. Pokud na stejném webu zůstane neprůkazný starý pokus stejného kupujícího, prohlížeč zastaví nový pokus a zobrazí výzvu k obnově. Stav obsahuje jen ID příkazu, identitu kupujícího a dosavadní důkaz původu.

## Provedení a ověření

1. Uprav `ticket_order_identity.js` a `browser_storage.js`. Ověř zachování ID po obnovení se změněným souhlasem i obnovu starého přesně odpovídajícího záznamu. Otestuj bezpečné zastavení při nejasném starém pokusu.
2. Uprav `create_ticket_order_command_internal`. Ponech původní ověření identity serverové účtenky, včetně platnosti kupujícího a vazby na akci. Starý hash použij jen pro už existující účtenku se stejnou identitou a obsahem. Ověř, že změněný nebo chybějící souhlas po ztrátě odpovědi vrátí původní objednávku a že obnovený grant nepřidá měření zpětně.
3. Přegeneruj otevřenou migraci `20261118200000_meta_purchase_matching.sql` a kontrolu shody SQL. Ověř cílené testy v oddělené databázi a v klientu, aktualizuj #929 a počkej na CI přesné revize.

Kontrola rozsahu zahrnuje obě vstupní cesty do stejného SQL příkazu, obnovu starých účtenek a existující vazbu původu checkoutu. Produkční migrace a aktivace pilotu vyžadují samostatné nasazení.
