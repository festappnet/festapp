# Wizard UI QA - 2026-10-29

Výsledek: tři scénáře dokončeny přes skutečné UI, nalezeny tři chyby. Nejde o úplnou kombinatorickou ani platební certifikaci.

## Prostředí a rozsah

- Produktový kód: `2095a9ba49bf1a7cd3a76f9e5be98d8407e95825`, vydaný jako vstupenky.online `0.20.445+950`.
- Samostatný headless Chromium, `agent-browser`, skutečný Flutter a lokální Supabase Auth/REST/Functions. Hlavní pozdější scénáře B/C běžely v release sestavení.
- Izolovaný projekt `festapp-wizard-backend-qa-20261029`, API `127.0.0.1:56921`, DB `56922`, UI `56980`. Kanonický baseline, forward migrations a seed; žádné změny skutečných produkčních akcí.
- Všechny změny testovaných konceptů, vytvoření akcí, produktů a bankovního účtu proběhly přes UI. SQL sloužilo pro kontrolu výsledků a dodatečnou diagnostiku validátoru vzhledu.
- Cron byl vypnutý, e-mailová fronta pozastavená a bez worker URL. Při kontrole po vytvoření třetí akce obsahovala `email_messages` nula řádků.
- Externí OneSignal callbacky byly nahrazeny testovacím fixturem; externí backendové domény blokované. Reálné odeslání e-mailu, bankovní synchronizace, Stripe, doručení PDF a ověření organizace nejsou tímto testem prokázané.
- Příslušné tři funkce a obě signatury preview se shodují s živým kanonickým backendem podle `md5(pg_get_functiondef(...))`: viz [identity](wizard-ui-qa-2026-10-29/backend-identity.json). Produkční kontrola byla pouze read-only, bez testovacích RPC či zátěže.

## Dokončené scénáře

| Scénář | Provedeno přes UI | Ověřený uložený výsledek |
| --- | --- | --- |
| A - přihláška | Vypnutí vstupenek, nulová cena, vlastní Reply-to, změna adresy, tykání, úprava předmětu a těla šablony vložením proměnných, opuštění/obnovení konceptu, přidání spoluorganizátora bez potvrzení pozvánek, dokončení | Akce 2, formulář 2; vstupenky vypnuté, registrace v přípravě; Reply-to `qa-a-final@example.test`, tón `informal`; vlastní `TICKET_ORDER_CONFIRMATION` s upraveným předmětem a tělem; pozvánky neodeslány |
| B - placené vstupenky | Vzhled Gala, otevření/aplikování editoru vstupenky, produkt 175 Kč, limit 3, vlastní povinné textové pole, vytvoření účtu přes UI, číselná řada VS, splatnost 3 dny, připomínka 0.5 dne, vlastní Reply-to, okamžité otevření prodeje | Akce 5, formulář 5; ticket feature zapnutá, PDF režim; cena 175, `max_tickets=3`, pole `Odkud prijedete?` povinné, splatnost 259200 s, připomínka 43200 s, VS začíná 260001, formulář otevřený, Reply-to `qa-b@example.test` |
| C - kopie a změna voleb | Kopie formuláře B, přejmenování produktu, cena 0, návrat a vypnutí vstupenek, dočasný vlastní Reply-to a tykání, následné vymazání adresy a obnovení výchozího tónu, dokončení | Akce 7, formulář 7; cena 0, vstupenky vypnuté, `max_tickets=1`, žádný vlastní Reply-to ani explicitní tón, formulář v přípravě. Zdroj B nadále 175 Kč a vstupenky zapnuté |

Neplatný Reply-to zablokoval pokračování. Chybějící bankovní účet u placené varianty také zablokoval pokračování. Změna ceny na nulu odstranila kroky určené placenému prodeji.

## Chyby

### 1. Nabízené vzhledy nelze dokončit - vysoká priorita

Reprodukce: nový koncept, vzhled **Ocean**, vyplnit ostatní kroky, potvrdit kontrolu, vytvořit akci. UI zobrazí pouze obecné `Creation could not be confirmed. Retry the same request.` Backend vrátí `Unsupported shared font`.

UI nabízí 18 předvoleb a rozšířený seznam fontů, ale `normalize_occasion_setup_appearance_internal` přijímá pouze Roboto, Roboto Slab a Russo One. Stejnou serverovou funkcí byly navíc read-only zkontrolovány všechny předvolby: 7 prošlo, 11 selhalo. Selhávají Ocean, Royal, Lavender, Citrus, Sunset, Terracotta, Forest, Graphite, Rose, Azure a Cream. Toto rozšíření je diagnostický SQL test, nikoli tvrzení o 18 samostatných průchodech UI.

Zdroje: `lib/components/occasion/setup/occasion_setup_appearance.dart`, `database/functions/occasion_setup/appearance.sql:16`.

Důkazy: [UI](wizard-ui-qa-2026-10-29/a-finalize-failed-ocean.png), [matice](wizard-ui-qa-2026-10-29/palette-validation.txt).

### 2. Chybějící počáteční číslo VS projde průvodcem až k neúspěšnému vytvoření - střední priorita

Reprodukce: placený formulář, zvolit **Variable Symbol Generation - Sequence**, nevyplnit Starting Number, pokračovat až na závěrečnou kontrolu a vytvořit. Průvodce dovolí pokračovat, ale finální transakce selže na `sequence requires starting number`; uživatel opět uvidí jen obecnou chybu. Po návratu, vyplnění 260001 a opakování vytvoření akce vznikla.

`OccasionSetupStory.paymentSetupReady` kontroluje metodu/účet, ale nikoli požadované číslo sekvence. Autoritativní SQL ve `database/functions/eshop_forms/form_settings.sql:133` je vyžaduje.

Důkazy: [UI](wizard-ui-qa-2026-10-29/b-sequence-finalize-failed.png), [finální stav](wizard-ui-qa-2026-10-29/b-final-state-compact.txt).

### 3. Konflikt revize při náhledech e-mailu způsobuje extrémní opakování na backendu - vysoká priorita, příčina ještě není plně izolovaná

Pozorováno v B při úpravách komunikace, načtení šablon a otevření **Ticket email preview**. Databáze opakovaně hlásila `Draft revision conflict` z `get_occasion_setup_email_preview`. Agregace lokálního logu za vybrané čtyřminutové okno obsahovala **439929** těchto chyb. Zavření stránky zastavilo aktivní požadavky.

Funkce používá pro nesouhlas aplikační revize SQLSTATE `40001` (`RAISE serialization_failure`, `database/functions/occasion_setup/email_preview.sql:28`). Je potřeba oddělit zastaralou aplikační revizi od skutečné tranzientní serializační chyby a určit, která vrstva požadavek opakuje. Počet databázových chyb není důkazem stejného počtu HTTP požadavků ani samostatných frontendových retry. Na produkci nebyla tato zátěž reprodukována. Relevantní preview funkce má ale shodnou definici.

Důkaz: [zachycené chyby](wizard-ui-qa-2026-10-29/captured-errors.txt).

## Limity a poznámky

- Richtextová pole nelze spolehlivě testovat pouhou změnou DOM hodnoty přístupnostního inputu. Ta může vypadat vyplněná bez změny modelu. Za úspěch byly počítány pouze změny potvrzené po uložení a v DB; úpravy šablony A byly provedeny skutečnými UI ovladači Insert information.
- Časová/datová pole otevírají picker a jsou read-only. Pokusy o přímé vyplnění jejich přístupnostních proxy nejsou započtené jako test datumového pickeru.
- Náhled doručení použil ilustrační částku 800 Kč; skutečná uložená cena 175 Kč byla ověřena zvlášť. [Snímek náhledu](wizard-ui-qa-2026-10-29/b-preview-wrong-price.png) sám neprokazuje cenu budoucího zákaznického e-mailu.
- Debug sestavení při Add Field zastavila diagnostická ListTile assertion; v release sestavení přidání vlastního pole prošlo. Tato assertion není zde vydávána za produkční chybu.
- Prohlížeč a vlastněný Flutter server byly uzavřeny. Pouze vlastní Supabase projekt byl zastaven s ponecháním lokálních dat pro následnou reprodukci. Ostatní běžící projekty nebyly měněny.
