# Produkční evidence product type cutoveru

Datum: 2026-10-13. Pouze čtení, každá SQL dávka v `BEGIN READ ONLY`; žádné produkční zápisy, nasazení ani zákaznické zprávy.

Tenant profil z `prod/festapptickets:automation/project.conf` a živé `https://vstupenky.online/backend-activation.json` se shodují: tenant `festapptickets`, canonical backend, generation 1, organization 3. Hostname a runtime DB souhlasí s chráněnými connection assertions. SQL identity potvrzuje organization 3 jako `vstupenky.online`. Výchozí metadata připojení uvádějí tenant `festapp` / organization 1; nejsou výběrem tenantu tohoto dotazu. Organization 3 je ověřena samostatně podle produkčního profilu a DB.

SSH alias měl starou cestu k již přesunutému proxy skriptu. Použit jednorázový `ProxyCommand` s aktuálním `.agents/skills/festapp-backend-access/scripts/proxy.py`; stejný chráněný Cloudflare transport, Keychain a SSH klíč. Nebyla měněna SSH konfigurace, autentizace ani backend.

## Výsledek

- Organization 3: 77 akcí, 73 ticket features, 21 enabled; 15 uložených layoutů (11 schema 1, 4 schema 2), 58 implicitních konfigurací.
- Uložené layouty obsahují 14 food polí a jeden named layout bez food. Čtyři food pole mají konkrétní food typ použitý ve formuláři; deset nemá food typ a nyní je prázdných.
- Osm food typů, čtyři taxi typy. Každý má vazbu na formulář stejné akce; žádná akce nemá více food typů. Nevyžaduje se ruční výběr kandidáta pro současný inventář.
- Žádné uložené taxi/odvoz bindingy; odvoz se používá jako formulářový produkt, ale dnešní tisk ho nemá jako vlastní pole. Není co převádět ve starém tiskovém layoutu. Nový editor jej umožní přidat jako libovolný konkrétní product type.
- Zavřené formuláře i skrytá pole mají zakoupené produkty: nesmějí být vyloučeny z historické migrace. Například food 8 má skryté form field a 263 product vazeb.
- Kontrola integrity: 0 cross-occasion form references, 0 cross-occasion ticket product references. Všech 669 zdánlivě chybějících product references má `product IS NULL` a ticket state `storno`; žádný chybějící nenulový product ID. Canonical renderer musí takové cancelled vazby ignorovat a nepovažovat za rozbitý aktivní produkt.
- Dalších 11 organizací má ticket features: 60 features celkem, 59 implicitních layoutů a jeden schema-1 layout. To potvrzuje potřebu vymezit společný backend cutover; inventura není oprávnění k jejich zápisu nebo rolloutům.

## Konkrétní formulářové vazby

| Akce ID | Product type ID | Typ | Form ID | Field hidden | Form open | Product vazby |
|---|---|---|---|---|---|---|
| 13 | 1 | food | 1 | False | True | 247 |
| 13 | 2 | taxi | 1 | False | True | 246 |
| 19 | 4 | food | 2 | False | False | 270 |
| 25 | 8 | food | 4 | True | False | 263 |
| 82 | 104 | food | 59 | False | False | 233 |
| 82 | 105 | taxi | 59 | False | False | 199 |
| 97 | 119 | food | 71 | False | True | 253 |
| 111 | 135 | food | 84 | False | True | 182 |
| 11438 | 388 | food | 188 | False | False | 0 |
| 11438 | 389 | taxi | 188 | False | False | 0 |
| 32316 | 651 | food | 464 | False | True | 27 |
| 32316 | 653 | taxi | 464 | True | True | 2 |

Přímé mapování uložených food polí: `82 -> 104`, `97 -> 119`, `111 -> 135`, `32316 -> 651`. ID 13/19/25/11438 mají food typ ve formuláři, ale ticket konfigurace je implicitní; materializaci řídit skutečným starým ticket režimem a geometrií.

Nevyužitá uložená food pole: occasion IDs `81, 83, 92, 99, 100, 101, 9245, 9246, 1072585, 1072589`. Odstranit element a jeho flow reference; nejprve materializovat původní pozice zbývajících flow elementů, aby se prázdný řádek neobjevil zpět. Named layout `934571` nemá food pole.

## Podklady a omezení

`summary.json` obsahuje konfigurační ID, minimální form metadata, layout bindingy a agregované počty bez zákaznických jmen, emailů, poznámek či QR symbolů. SQL soubory vedle něj reprodukují read-only inventuru. Data jsou časový snapshot, nikoli apply manifest s expected layout digests; před zápisem znovu ověřit konfigurace a verze.

Live RPC inspection potvrzuje `food` v SQL layout validátoru a `short_title` v product katalogu. Produkční products mají i sloupec `title_short`, ale aktuální RPC čte `data.short_title`; cutover zachová dnešní prioritu názvů. Nebyl ověřen digest nasazeného Edge balíčku, obsah čekající email fronty ani úplná dostupnost všech historických artwork/font resources. Tyto release gates zůstávají.


## Doplňující UI a efektivita revize

Přezkoumány skutečné callers `features/feature_form.dart`, `occasion/setup/occasion_setup_page.dart`, `TicketSettings` a editor/controller/canvas. Existující desktop má sidebar prvků (200 px), mobil pod 900 px používá `showMobilePanel` s tabs Prvky/Vlastnosti. Produkční flow nepřenáší konkrétní form ID, proto plán nevyžaduje nový per-form runtime API.

Zjištěné mezery jsou opravené přímo v autoritativním plánu: bezpečné umístění nového elementu; dynamická data namísto statického `resources.scenarios`; grouped label history; selection po remove/undo; reset stylu konkrétního product pole; vysvětlená výměna předlohy; schema guard v TicketSettings; draft source-preview nemůže používat katalog cizí akce jako svůj vlastní. Rozšíření nevyžaduje nové UI frameworky, implicitní PDF requests ani generický migration systém.

Doplňující read-only `ui-drafts.sql` skončil přesnou chybou `relation public.occasion_setup_drafts does not exist` v již ověřené canonical DB. Není to počet 0 návrhů; draft persistence z checkoutu není v tomto runtime nasazená. Dotaz nic nezapsal. Před případným rolloutem tohoto produceru znovu vymezit jeho storage/identity map a nenahrávat nesouvisející pending migrace při ticket cutoveru.

Revize je kódová a návrhová. Picker pro nový kontrakt zatím není implementován ani vizuálně otestován; plán nyní vyžaduje konkrétní interaction tests a jeden krátký isolated headless browser smoke při implementaci.
