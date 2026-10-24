# vstupenky.online a Festapp Tickets pro WordPress

Dva samostatné pluginy 1.0.0 sestavené z `shared/` a explicitních identit v `products.json`. Každý přidává nativní Gutenberg blok a shortcode. Účet pořadatele, objednávky, platby, kapacita, emaily, PDF a odbavení zůstávají ve službě. Výsledky a limity: [READINESS.md](READINESS.md). Veřejné kroky: [SUBMISSION.md](SUBMISSION.md).

| Plugin | Blok | Shortcode | Povolený produkční origin |
| --- | --- | --- | --- |
| vstupenky-online | vstupenky-online/ticket-form | vstupenky_online | https://vstupenky.online |
| festapp-tickets | festapp-tickets/ticket-form | festapp_tickets | https://tickets.festapp.net |

Ve službě vytvořte účet, akci a formulář, uložte jej a zkopírujte veřejné `/form/<slug>` URL. Pro placený prodej dokončete obchodní/platební nastavení. Vložte URL do bloku nebo například `[festapp_tickets url="https://tickets.festapp.net/form/ulozeny-slug"]`. Nevkládejte administrační ani soukromé odkazy. V editoru je bezpečný náhled nastavení; služba se načte až na veřejné stránce. Ve WordPressu se neukládají servisní hesla ani objednávky. Automatická výška používá servisní `/embed.js`, fixed režim ji nepotřebuje; veřejný odkaz zůstává dostupný.

Aktuální podání se připravuje pouze pro **vstupenky.online**. Globální distribuce
zůstává mimo rozsah. Před odesláním musí projít
`python3 scripts/verify-submission.py --product vstupenky-online --submit-ready`;
aktuálně jej blokuje rozdíl produkční služby popsaný v READINESS.md.

## První použití po instalaci

V seznamu pluginů zvolte **Začít**, případně otevřete **Nastavení → vstupenky.online**
(nebo **Festapp Tickets**). Tři kroky vás provedou přípravou veřejného formuláře
v účtu pořadatele, vložením bloku do stránky a náhledem/publikací. Automatická
výška a převzetí vzhledu jsou výchozí. Účet pořadatele je samostatný od WordPressu.
Skutečné obrazovky: [obrázkový průchod](preview/onboarding/index.html).

## Převzetí vzhledu webu

Blok má ve výchozím stavu zapnutou volbu **Převzít styl stránky**; totéž platí pro shortcode.
`inherit_style="false"` ji vypíná. Sdílený servisní `/embed.js` předává skutečnou computed
`font-family`, dostupné definice fontů a barvy okolní stránky přes stejný ověřený
embed protokol. Fonty se načítají také v iframe a potřebují CORS na svém serveru.
Nepřístupné stylesheety/fonty ponechají fallback ze stejné font-family. Plánek
zachovává původní vzhled služby. Pevná výška zůstává pevná i s helperem.
WordPress pouze deklaruje volbu; nenese druhý renderer ani vlastní theme bridge.
Změna vyžaduje nasazení aktualizovaného web clientu i `/embed.js` služby.

## Sestavení a lokální WordPress

Ověřený tooling: macOS/arm64, pnpm **11.24.0**, Node 26.8.1, Docker/Colima, @wordpress/env 12.0.0, Supabase CLI 2.111.0. WP **7.1.3/PHP 8.5.12** na 59811 a minimum **6.6.4/PHP 7.4.33** na 59812. Core a obrazy jsou připnuté v `.wp-env.json` a `docker-images.json`; aktualizace a cron vypnuté. Wrapper váže WordPress/MySQL na loopback. Nepoužívejte neobalené `wp-env start`. Docker CLI plugin cesta ve wrapperu je lokální konfigurace, na jiné stanici ji upravte.

Z tohoto adresáře:

```sh
pnpm install --frozen-lockfile
pnpm run package
pnpm run start
node scripts/environment.mjs run cli wp plugin install /var/www/html/wp-content/vo-artifacts/vstupenky-online-1.0.0.zip --force --activate
node scripts/environment.mjs run cli wp plugin install /var/www/html/wp-content/vo-artifacts/festapp-tickets-1.0.0.zip --force --activate
node scripts/environment.mjs run tests-cli wp plugin install /var/www/html/wp-content/vo-artifacts/vstupenky-online-1.0.0.zip --force --activate
node scripts/environment.mjs run tests-cli wp plugin install /var/www/html/wp-content/vo-artifacts/festapp-tickets-1.0.0.zip --force --activate
pnpm run seed
node scripts/environment.mjs run tests-cli wp eval-file /var/www/html/wp-content/plugins/vstupenky-online-tests/seed.php
node scripts/environment.mjs run cli wp eval-file /var/www/html/wp-content/plugins/vstupenky-online-tests/dual-seed.php
node scripts/environment.mjs run tests-cli wp eval-file /var/www/html/wp-content/plugins/vstupenky-online-tests/dual-seed.php
```

`package` generuje oba zdrojové adresáře i deterministické ZIPy. Upravujte sdílené šablony, nikoli generované kopie. Každý ZIP je plně samostatný; při instalaci není potřeba Python ani generátor. `evidence/shared-build.json` a produktové manifesty zaznamenají zdroje a soubory. `stage-submission.py` připraví dva offline SVN návrhy bez externího zápisu.

Seed používá standardní `wp_upgrade()` pro sladění testovací DB s připnutým core. Vytváří jen syntetické stránky, správce a subscriber. Heslo správce uloží do `.private/wordpress-auth.json` (0600). Start wp-env může obnovit heslo i odstranit ručně instalované pluginy/nástroje; následně znovu instalujte oba ZIPy a seed. Pluginy nejsou mountované ze zdrojů.

## Disposable služba

Pouze vlastní projekt `festapp-vo-wordpress-20261023` s `Test Organization`, nikdy produkce. Zkontrolujte volné porty 59801-59804, 59811/59812 a 59820-59829. Nezasahujte do ostatních Supabase projektů.

```sh
pnpm run backend:setup
pnpm run backend:start > .private/backend-start.log 2>&1
pnpm run backend:seed > .private/backend-seed.log 2>&1
pnpm run backend:serve > .private/edge.log 2>&1
```

Poslední příkaz běží v samostatném terminálu. Setup kopíruje aktuální Edge zdroje do soukromého snapshotu, připraví guardované capture/sink funkce a CORS pouze lokálních originů. Seed odmítá neprázdný backend. Používá kanonickou baseline, upgrade engine, seed a existující embedded-checkout fixture; `tests/fixture-fixes.sql` doplňuje syntetickou akci, bankovní popis a kapacitu. Žádné provider credentials, cron ani nehlídaný email worker. Backend CLI používá Docker bind; nevystavovat jej mimo vlastní testovací stanici.

```sh
pnpm run web:start
FESTAPP_EMBED_PRODUCT=festapp-tickets pnpm run web:start
```

Tyto příkazy běží odděleně: Czech 127.0.0.1:59801, global 127.0.0.1:59804; oba skutečně používají tentýž disposable backend 59821. Nejde o živý globální tenant. `.wp-env.json` povoluje oba originy pouze dvojitou branou local/development + konkrétní DEV konstanta. Produkční gate prokazuje jejich odmítnutí v produkci.

Pro nový účet použijte `tests/onboarding-fixture.sql` v tomto disposable DB: nastaví syntetické šablony, kvótu a HTTPS návratovou URL, **nevytváří pořadatele**. Guardovaný `tests/onboarding-email-sink.ts` zpracuje kanonickou frontu/sender přes lokální transport pouze pro Test Organization a @example.invalid. Spuštění drain funkce vyžaduje privátní proof z `.private/edge.env`; nikdy jej nevypisujte. Není to SES ani důkaz doručitelnosti. Reset URL lze otevřít na nativním Vite HTTPS 59803 pomocí `FESTAPP_EMBED_TLS_CERT` a `FESTAPP_EMBED_TLS_KEY` se soukromým lokálním certifikátem; fixture config určí HTTPS port automaticky. Nikdy pro tento test neměňte produkční návratové URL.

Skutečná Flutter administrace používá `tests/organizer_e2e.dart`, backend guard na 59821 a pouze externí push callback stub. Po `node scripts/prepare-organizer.mjs` a ověření volného jediného Flutter slotu z kořene repozitáře:

```sh
fvm flutter run -d web-server --target integrations/wordpress/tests/organizer_e2e.dart --dart-define-from-file integrations/wordpress/.private/flutter-defines.json --web-hostname 127.0.0.1 --web-port 59802
```

Nového uživatele registrujte skutečným veřejným UI, zachyťte počáteční přihlašovací heslo lokálním sinkem a vytvořte vlastní akci/formulář přes UI. Nepřidávejte mu role přes SQL. Produkční veřejné URL ze servisní administrace pro lokální WP explicitně převeďte na správný lokální origin, zachovejte uložený slug. První vlastní jednotka ještě vyžaduje platební/právní aktivaci. Nákupní fixture používá připravenou syntetickou jednotku.

Po obnově disposable databáze mohou ve WordPressu zůstat odkazy na smazané
formuláře. Pro samotný veřejný náhled `/prvni-formular-noveho-poradatele/`
lze obnovit syntetickou kopii pod původním slugem:

```sh
docker exec -i supabase_db_festapp-vo-wordpress-20261023 psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 -q < tests/onboarding-preview-fixture.sql
```

Tato obnova neobnovuje účet původního pořadatele a neprokazuje registraci.
Pro nový průchod onboardingem použijte skutečné UI popsané výše. Veřejné
náhledy vyžadují běžící oba procesy `web:start` (59801 a 59804).

## Cílené ověření

Rozšířená veřejná ukázka `/podrobny-formular/` přidává firmu, adresu, více
voleb a samostatné údaje každého návštěvníka. V existujícím disposable backendu
ji lze obnovit bez změny základního formuláře:

```sh
docker exec -i supabase_db_festapp-vo-wordpress-20261023 psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 -q < tests/rich-purchase-fixture.sql
node scripts/environment.mjs run cli wp eval-file /var/www/html/wp-content/plugins/vstupenky-online-tests/rich-purchase-preview.php
```

Pro každou sestavu spusťte tři nezávislé kontrakty (39 + 37 + 40 assertions):

```sh
node scripts/environment.mjs run cli wp eval-file /var/www/html/wp-content/plugins/vstupenky-online-tests/contract.php
node scripts/environment.mjs run cli wp eval-file /var/www/html/wp-content/plugins/vstupenky-online-tests/tester-contract.php
node scripts/environment.mjs run cli wp eval-file /var/www/html/wp-content/plugins/vstupenky-online-tests/dual-products.php
```

Zopakujte s `tests-cli` místo `cli`. Dále `dual-translations.php`, `dual-lifecycle.php`, `node scripts/check-production.mjs`, WPCS 3.4.1 a Plugin Check 2.1.0 pro oba slugy s runtime bootstrapem `--require=/var/www/html/wp-content/plugins/plugin-check/cli.php`. Zaznamenaný výsledek Plugin Check je 0 errors a 1 odůvodněný warning na produkt, viz READINESS.

`python3 tests/dual-browser.py` provede pět headless případů; spusťte na klasické i blokové šabloně, pak obnovte Twenty Twenty-Five. Používá task-specific izolovaný agent-browser a `.private/stable-browser.json`; nevstupuje do uživatelova Chrome. Ověřený skutečný Chrome 155.0.8059.86. Další smluvní testy: `tests/dual-uninstall.py`, `tests/verify-onboarding.py`.

`python3 tests/scroll-browser.py` ověřuje scroll rekapitulace a přesný návrat
na desktopu i mobilu, validaci, cenový přehled, zavření plánku a pevnou výšku
s helperem i bez něj. Potřebuje běžící WordPress, oba storefronty a existující
disposable backend; nevytváří objednávky ani rezervace. Každý příkaz používá
explicitní lokální browser config, aby globální provider nemohl připojit
uživatelův prohlížeč.

`tests/dual-purchases.py` vytváří skutečné syntetické objednávky pouze na prázdné fixture a ukládá privátní HAR. Nespouštějte jej opakovaně na již nakoupených datech. `VO_ACCEPTANCE_HAR=shared-czech-order.har VO_ACCEPTANCE_RECEIPT=shared-service-receipt.json python3 tests/verify-service.py` ověřuje reálný příkaz, replay, ruční potvrzení, frontu, PDF a scanner. Nejde o skutečnou bankovní platbu ani o externí odeslání emailu. Native Safari důkazy a omezení jsou v READINESS; testovací simulator byl po průchodu smazán.

Lokální opravy služby mají 8 cílených Node testů a rollback-only SQL regresní test `database/tests/users/password_reset_retry_validation_test.sql`. `evidence/service-onboarding-fixes.patch` odděluje naše změny od cizí práce. Před nasazením jej sladit s aktuálním main; žádný produkční release nebyl proveden.

## Ukončení

Zavřete pouze vlastní pojmenované browser sessions; ukončete vlastní Vite, Edge serve, lokální sink/PDF procesy a Flutter `q` (uvolněte sdílený slot). Poté:

```sh
pnpm run stop
pnpm run backend:stop
```

`backend:stop --no-backup` odstraní vlastní disposable data. ZIPy a veřejné důkazy zůstávají. HAR, přihlašovací údaje, capability a raw queue capture patří pouze do ignorované `.private/` s režimem 0600, nikdy do ZIP/SVN. Nepoužívejte globální Docker stop/prune ani globální browser close. Stav úklidu: `evidence/cleanup.json`.
