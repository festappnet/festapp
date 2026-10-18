# Organizace: místní implementace a ověření

Zdroj: `feat/occasion-setup-wizard-20261007`, výchozí HEAD `eb2304724`. Zachovány rozsáhlé původní rozpracované změny. Bez commitu, push, produkční migrace nebo nasazení.

## Začlenění do aktuálního main

Funkce byla pro publikaci izolována od ostatních rozpracovaných změn na základě
`5bc3addcc`. Přeneseny jsou jen právní profil, schvalování, veřejná projekce,
klienti a související testy/dokumentace. Zachovány jsou aktuální demo guardy,
platební údaje a nové osobní odkazy objednávek z main, i odpočet s informacemi.
Scoped migrace je znovu sestavena z těchto aktuálních kanonických SQL souborů.

Na tomto základu prošly všechny 3 SQL suites, skutečný dvousession test, všech
5 Flutter identity testů, startup regrese a celá JS sada (412 prošlo, 24 přeskočeno).
Architecture gate prošla. Cílený analyzer nemá chyby; existující upozornění mutability FormPage/MyApp a lint
info zůstávají. Celá testovací sada skončila na lokálních SQL testech
(173 prošlo, 50 selhalo), zejména kvůli chybějícím tabulkám abuse policy;
je zachována uživatelem povolená výjimka pro tento databázový stav prostředí.

Veřejný probe `https://vstupenky.online/version.json` stále vrací `0.20.260+744`.
Tato integrace neprovádí produkční migraci ani web release; další rollout musí
nejprve aplikovat novou scoped migraci a potom klienty pro vybraného tenanta.

## Výsledek

- Dvě samostatné tabulky, pět externích RPC a jeden interní veřejný projekční helper. Profil není v `units.data`, editovatelném formulářovém draftu ani obecném syncu. Write operace zamykají Unit a profil ve stejném pořadí; každá skutečná změna má novou revizi a audit ve stejné transakci.
- Právní údaje jsou podblok nastavení Unit s vlastním Form a ukládáním. Platform admin má chráněnou frontu pending/verified a detail konkrétní revize. Kontrolní součet IČO není schválením identity.
- JS a Flutter mají immutable read DTO, název s ikonou v page shellu a přístupný detail. Zahrnuty jsou redukované uzavřené odpovědi, waitlist a jeho terminal nabídka, přehled objednávky, rekapitulace a výsledek. JS detail používá nativní dialog.
- V průběhu implementace doplněn prokázaný zvláštní případ `get_waitlist_offer_form`: terminal nabídka vrací `form:null` a potřebuje identitu na kořeni po autorizaci. Doplněn také cold start administrace platformy bez výchozí události a zalamování 200znakového názvu bez mezer.

## Provedené kontroly

SQL testy byly spuštěny pouze s explicitním loopback URL pro disposable `supabase_db_festapp-db-tests-pg15`, port 55432, bez resetu existující databáze. Aplikována pouze nová lokální scoped migrace. Tři rollback suites `database/tests/organization_verification/*_test.sql` prošly: oprávnění, manager/editor/anon/cizí admin, demo, přímé granty, whitelist, draft/submit, audit, revize, retry po revokaci, přesun tenanta, delete_unit, veřejné open/closed/capability/overview projekce a terminal nabídka. Existující `get_form_for_edit_short_title_test.sql` prošel.

Skutečný dvousession test `automation/tests/organization_verification_concurrency.test.mjs` prošel: dva první save a save proti approve. Čekající write po uvolnění Unit zámku skončí 409, nevytvoří další audit ani neobnoví ověření. Test se bez explicitního `FESTAPP_VERIFICATION_TEST_DATABASE_URL` přeskočí a odmítá vzdálené hostname.

Klientské cílené kontroly: 33 JS testů prošlo (identity, page shell a dotčené form/loading/waitlist/overview větve); Flutter identity suite 5/5 včetně konfliktu, zachování draftu, read-only serializace a 200znakového názvu na 320 px; startup suite 15/15. Dodatečné modelové kontroly nullable `verifiedAt` prošly. Cílený analyzer nehlásil chyby; zůstává existující warning mutability `FormPage.formLink` a lint info.

Samostatná existující architecture gate (`cd packages/festapp_core && fvm dart run tool/check_architecture.dart ../..`) skončila čtyřmi problémy mimo tento úkol: neklasifikované `image_upload_contract_test.dart`, `price_wave_availability_test.dart`, `client_command_identity_test.dart` a chybějící `ticket_background_image_cases.dart`. Nový test root identity byl klasifikován. Tyto cizí rozpracované položky nebyly měněny.

## Skutečný browser průchod

Použity skilly `festapp-local-e2e` a `agent-browser`: samostatný headless browser s prázdnou konfigurací, žádný uživatelský Chrome. Nový disposable projekt `festapp-verification-e2e-20261018`, API 57521, DB 57522; nahrána produkční schema baseline, všechny následující migrace a syntetický seed. Žádná reálná identita nebyla schválena. Externí push SDK bylo stubováno existujícím lokálním E2E vstupem; produkční domény blokovány. Cloud sync/CDN a OAuth nebyly testovány.

V reálné Flutter aplikaci: načtení právního profilu v nastavení, žádost revize 1 -> pending 2; platform administrace -> fronta -> detail -> schválení se zdrojem -> verified 3. Skutečný JS FormPage přes lokální PostgREST zobrazil právě jednu patičku. Otevření a Escape zachovaly vyplněný input a vrátily focus. Ve Flutter veřejné stránce byl ověřen detail a patička ve stavu nedostupného formuláře. Následně ve Flutter frontě filtr verified -> odebrání s feedbackem -> revoked 4; audit obsahoval save,submit,approve,revoke a obě veřejná UI po reloadu patičku skryla.

Mobilní 320px a desktop screenshoty komponenty ověřily dlouhý název, světlé/tmavé vlastní barvy, řádek bez karty a minimální klikací výšku (naměřeno 49 px). Nativní dialog má Escape, pojmenování, modalitu a návrat focusu. Naivní okamžitá kontrola přítomnosti dialog elementu po Escape před close eventem není kontrolou otevření; po dokončení close eventu je odstraněn.

Limity průchodu: minimální syntetický formulář ve Flutteru skončil v existující větvi nedostupnosti po načtení identity; běžný otevřený Flutter formulář, rezervace sedadel a odeslání objednávky nebyly v tomto browser průchodu prokázány. Jejich integrace je pokryta read modelem a příslušnými widget/shell testy; browser nebyl plným release E2E všech form stavů. Lokální chybějící HTTPS sync endpoint není důkazem problému produkčního syncu.

Screenshoty: [mobilní patička](evidence/js-mobile.png), [mobilní detail](evidence/js-dialog-mobile.png), [tmavý desktop](evidence/js-dark-desktop.png), [skutečný JS formulář](evidence/js-live-mobile.png), [Flutter veřejný detail](evidence/flutter-public-dialog.png), [Flutter schvalování](evidence/flutter-review-dialog.png).

## Provozní hranice

Nasazení není provedeno ani autorizováno. Před produkční aktivací vybrat jeden tenant a postupovat podle release pravidel a [standardu ručního ověření](README.md). Přesun celé Unit mezi tenanty musí samostatná privilegovaná migrace spojit se zrušením ověření, revizí a auditem v téže transakci.
