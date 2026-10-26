# Realizace SEO vstupenky.online - 2026-10-15

Stav: lokálně implementováno a cíleně ověřeno. Nic nenasazeno, bez změny DNS, Cloudflare pravidel nebo produkčních dat, bez commitu a pushe. Uživatel autorizoval implementaci příkazem „docs/plans/vstupenky-seo-EXECUTION-PROMPT-2026-10-15.md realizuj“. Zákaz publikace z realizačního promptu zůstává platný.

## Výsledek T0-T5 a U1-U2

- T0: vybrán pouze tenant `festapptickets` / `vstupenky.online`. Read-only `origin/prod/festapptickets:automation/project.conf` uvádí canonical aktivaci, organizaci 3 a HTTPS apex; živý `backend-activation.json` potvrdil tenant `festapptickets`, generaci 1 a backend `canonical`. Místní `automation/project.conf` má organizaci 1 a prázdnou aktivační fázi. Nebyl přepsán produkční konfigurací. Místní Vite výstup proto není schválený produkční bundle.
- T1: jediný runtime router zůstává v `automation/cloudflare_build.sh`. Tenantový HTTPS origin se při generování razítkuje z `WEB_LINK`; přesné apex/www varianty dostávají 308 se zachováním cesty a query. Preview hostname se nepřesměrovává. HSTS začíná `max-age=300`, bez includeSubDomains/preload, na HTTPS odpovědích vybraných produkčních hostů včetně XML, 404, 503 a redirectů. HEAD nevrací tělo. Živý www před změnou stále vracel 200; provozní oprava dosud neproběhla.
- U1/U2, T2: Astra Medium (`gpt-6-astra`, medium) navrhla a implementovala tělo stránky a CSS, katalogový archiv, stavy a související přístupnost. Hlavní agent převzal rozhraní fragmentu `{{APP_NAME}}`, `{{CONTACT_EMAIL}}`, `{{PROVIDER_NAME}}`, `{{CTA_HREF}}`, `{{CTA_LABEL}}`, `{{CTA_NOTE}}` a integroval generátor, metadata, explicitní routu a sitemap. `/pro-poradatele` je český dokument s vlastním H1 i bez JS. Odkaz vedle hledání i stránka se generují jen pro vstupenky.online; při přechodu na jiný tenant se odstraní. Skrytý homepage úvod zůstal skrytý, původní logo zachováno.
- CTA `/?create=1` obnoví existující kontext práv, hostovi otevře stávající registrační modal, přihlášenému stávající správu akcí. Při vypnuté registraci zobrazí vysvětlení a kontakt. Nespotřebuje jiné query parametry ani auth fragment. Nezavádí novou registraci nebo oprávnění.
- T3: worker i klient používají `catalog.js` pro časovou klasifikaci a rozlišení validního prázdného výsledku od vadného RPC payloadu. Aktuální a budoucí akce před archivem, archiv je `details/summary` s počtem a při historické shodě hledání se otevře. Serverové odkazy zůstávají přístupné při čekání/chybě. Chybový text je bezpečně vkládán přes textContent, opakování a pozdní odpověď mají kontrolovaný lifecycle. Sitemap deduplikuje interní canonical destinace, vynechává cizí originy a nevymýšlí lastmod.
- Opraven související okrajový případ: veřejné záznamy s chybějícím/neplatným termínem zůstávají viditelné v sekci dalších akcí a karta nevytváří falešné datum ani nepadá na Intl RangeError. Zesílen textový překryv fotografie a zalamování dlouhých titulů podle konkrétního nálezu UI kontroly.
- T4: fontové požadavky existující aplikace beze změny. Není srovnatelný mobilní cold-load benchmark, který by doložil přínos jejich náhrady, proto se doporučená optimalizace neprovádí. Nová samostatná stránka používá existující kompilovaný tenantový CSS/fontový výstup a nepřebírá nepotřebné externí Google stylesheety. Generovaný zdroj `web/organizers-page` je deterministický; kompilovaný CSS odkaz se připojí až do cílového bundle přes `--built-index` a `--output`.

## Podklady a publikační kontrakt

Kontakt `info@festapp.net` a provozovatel Michael Bujnovský, IČO 06455361, pocházejí z `automation/release/legal/support.cs.md` a `terms.cs.md`. Cena je věcný odkaz na dotaz na tomto kontaktu; nejsou doplněny sazby, tvrzení o bezplatnosti ani reference. Funkce odpovídají existujícím formulářům, objednávkám a QR odbavení.

Stávající `get_available_occasions` vybírá ne-skryté a pro veřejný katalog propagované akce. RPC, SQL ani produkční publikace se neměnily. Název `(Copy)` se nikde nepoužívá jako filtr nebo důvod mazání. Soukromé/demo záznamy se touto změnou nezpřístupňují; zůstává odpovědností stávající publikační hranice. Případný úklid konkrétních kopií vyžaduje provozovatelovo rozhodnutí a samostatně autorizovanou datovou změnu.

## Ověření T5

Prošly cílené Node testy:

```sh
node --test automation/tests/public_seo.test.mjs automation/tests/organizer_page.test.mjs automation/tests/google_auth_hosting.test.mjs web_client/tests/services/seo_service.test.js web_client/tests/components/occasion_card_links.test.js web_client/tests/components/catalog.test.js web_client/tests/core/home_startup.test.js web_client/tests/core/organizer_intent.test.js web_client/tests/components/user_header_create_event.test.js
bash automation/tests/apply_config.test.sh
bash -n automation/cloudflare_build.sh automation/apply_config.sh automation/build_web_bundle.sh
npm --prefix web_client run build
```

Po finálních opravách byly opakovány pouze dotčené testy/build: katalogový payload a skutečný startup shell, karta s neplatným datem, sitemap/generátor a výstupní cesta. Nezměněné passing kontroly se neopakovaly. Finální routing/generátor: 12/12; finální katalog/startup v cíleném balíku: passing; test apex metadat: 2/2. Vite build prošel na finálních JS/CSS vstupech. Nespouštěl se Flutter build ani produkční release gates.

Testy skutečného workerového kódu pokrývají host/protokol matici, cestu/query OAuth a formuláře, preview, HSTS na různých statusech, HEAD, HTML bez JS, metadata, interní/externí odkazy a deduplikaci. Test generátoru provádí i skutečný Python stamping z build skriptu, tenantový přechod, idempotenci a zachování deterministického zdroje při připojení kompilovaného CSS. Klientské testy pokrývají chybu se zachováním SSR, bezpečný text, opakování, archiv/hledání v cs/en, likvidaci pozdní odpovědi a CTA pro hosta/přihlášeného/zavřenou registraci. Auth a backend jsou zde simulované; nebyly odeslány registrace ani objednávky.

Astra Medium převzala výsledné vygenerované HTML s přesným kompilovaným CSS a fonty: světlo/tma při 320, 390 a 1280 px bez horizontálního přetékání, jeden H1, axe WCAG A/AA bez nalezených porušení, nativní FAQ/archiv přes Enter a viditelný fokus. Dlouhý český název katalogové karty se nezkracuje. 200% CSS zoom prošel; nativní browser zoom nebyl testován. Poslední nález zmizel po scoped podtržení odkazů v odstavcích; finální integrovaná kontrola potvrdila opravu. Izolovaný prohlížeč byl uzavřen.

Náhled: [přesný integrovaný statický náhled](vstupenky-seo-preview-2026-10-15.html). Funguje přímo přes file://, obsahuje vložené logo, CSS a fonty. Banner označuje nenasazený náhled; navigace v náhledu používá veřejné absolutní odkazy. Produkční HTML tento banner nemá.

## Oddělení od cizích změn

Výchozí branch `feat/occasion-setup-wizard-20261007`, HEAD `eb23047248d59bf86345b9e0b79db4a988275231`. Read-only lokální upstream reference: main `b256384d654011b9aefdd625b973a106e75f185d`, prod/festapptickets `959d4100c736d324c7dc37010d5f5623783065a8`. Nebyl proveden fetch pro publikaci, protože se nic nepublikuje.

Samostatný `vstupenky-seo-implementation-2026-10-15.patch` obsahuje jen změny tohoto běhu vůči zachycenému místnímu výchozímu stavu a nové implementační soubory. Souběžný JSON manifest uvádí předchozí a nové SHA-256. Náhled a tento protokol jsou samostatné review artefakty. Původní kopie vybraných souborů a stav jsou v `/tmp/festapp-seo-baseline-20261015`; logy kontrol v `/tmp/festapp-seo-*.log`.

Patch není samostatný release nad čistým main: navazuje na již existující místní SEO/router/link a startup změny. Například `occasion_link.js` a předchozí úpravy workeru/karet/registračního vstupu nejsou novou prací tohoto běhu. Před vydáním musí být potřebné předpoklady integrovány a ověřeny na canonical main; rozsáhlý celý pracovní diff se nesmí zveřejnit jako SEO release.

## Přesně zbývající provozní kroky

1. Ukázat/převzít vzhled náhledu před publikací a získat pokyn k vydání pouze `vstupenky.online`. Na čistém canonical main integrovat tento rozsah a jeho ověřené předpoklady, poté jediný produkční overlay `festapptickets` s organizací 3 a canonical aktivací. Před publikací fetch autoritativního upstreamu, kontrola ancestry/drift a release gates.
2. Před případnou změnou hrany zkontrolovat aktuální Cloudflare redirect/HTTPS pravidla a TLS www. Worker je jediným implementovaným zdrojem redirectu; nezakládat souběžné dashboard pravidlo. Vnější HTTP->HTTPS pravidlo může běžet před workerem a počet živých skoků se musí ověřit provozně.
3. Lokální Flutter + web build a `automation/deploy_direct.sh`, po vydání coherent live-version probes, matice HTTP/HTTPS apex/www s cestou/query, HSTS na 200/404/XML, HTML nové stránky bez JS, sitemap a host/přihlášení/formulář bez odesílání dat. HSTS zvýšit na rok až po provozním ověření. Samotné lokální testy nedokazují změnu živého hostu.
4. O2: účet Search Console nebyl otevřen. Ověřit/schválit sitemap submission a baseline indexace + nebrandové dotazy/CTR; po vydání porovnat 28 dní před/po s ohledem na sezonnost. Žádný nový tracker nebyl přidán.
5. M1: samostatně doložit skutečné From/MAIL FROM, SES a další poskytovatele před návrhem SPF/DMARC. DNS pošty, ads.txt ani GA nebyly změněny. Fontovou větev otevřít pouze se srovnatelným měřením, pokud bude požadována.
