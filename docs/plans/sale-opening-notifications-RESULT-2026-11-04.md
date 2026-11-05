# Upozornění na spuštění prodeje - výsledek 2026-11-04

Aktuální zadání po localhost náhledu: pouze pole E-mail a vedle tlačítko
„Upozornit“. Kliknutí ihned aktivuje odběr. Neodesílá se potvrzovací e-mail,
neexistuje čekání na ověření. Jediná zpráva je oznámení skutečného otevření.
Toto rozhodnutí nahrazuje původní double opt-in v plánu a execution promptu.

## Dokončené chování

- Nastavení ve stávajícím agregátu formuláře, výchozí stav vypnuto,
  přehled zájemců s existujícími kontaktními oprávněními.
- Oba veřejné klienty používají kompaktní odběrový blok. Odpočet se zapíná
  nezávisle; při vypnutí se nezobrazuje ani automaticky vložené datum.
  Uložený dokument nadále určuje pořadí a vlastní okolní obsah.
- Odběr se ukládá rovnou jako `active`; vytváří se pouze šifrovaný zdroj
  odhlášení. Přihlášení ani opakované přihlášení nevytváří e-mail.
  Opětovné přihlášení po odhlášení revokuje starou capability.
- Oznámení používá ordinary limity, stávající frontu a finální send gate,
  živou dostupnost prodeje, jediné launch ID a původní 24hodinové okno.
  Ruční uzavření, plná kapacita a waitlist nejsou otevřený prodej.
- Jedna e-mailová šablona `sale_opening_opened`, současný wrapper a editor,
  šest jazyků, vypnuté sledování, odhlášení přes explicitní POST.
  Zdroj kontaktu a tokenů se odstraní 30 dní po uzavření odběru.
- Společná atomická obálka HTML bloků zůstává i pro countdown a e-mailové
  proměnné. Formáty HTML slotů a `{{code}}` zůstávají zachované.

## Kontroly aktuální single opt-in verze

| Oblast | Výsledek |
| --- | --- |
| SQL | 7 doménových testů prošlo na disposable DB port 55432. Dodatečný případ opětovného přihlášení a revokace starého tokenu prošel. |
| Regrese SQL | 4 existující testy: canonical email queue, occasion setup sales, waitlist lifecycle a Stripe form availability. |
| Souběh | Skutečná oddělená PostgreSQL spojení: save/subscribe, souběžný fanout a send/unsubscribe. |
| JS | 41 testů: dostupnost, kompaktní odběr, samostatný odběr bez data/odpočtu, přímý úspěch, překlady, odkazy a chyby. |
| Edge | 12 testů handleru a rendereru, včetně šifrovaného zdroje pouze pro odhlášení a šesti jazyků. |
| Flutter | 6 widgetových/modelových testů, včetně mobilního řádku, draftu, chyby e-mailu a samostatného odběru bez odpočtu/data. `--concurrency=1`. |
| Generované zdroje | Freshness migrace, canonical source contract, 66 e-mailových preview scénářů a `git diff --check` prošly. |

Původní společná HTML/email regrese 137 testů proběhla před úpravou na
single opt-in. Není vydávána za nové ověření aktuálního odběrového procesu.

## Artefakt a provozní hranice

Migrace: `supabase/migrations/20261104130000_sale_opening_notifications.sql`.
SHA-256: `08d1231e9778399872d4d050e6ee446fd53f39d79564182c570d0bdb795bd05e`.
Skládá ji `automation/assemble-sale-opening-notifications-migration.py` pouze
z kanonických vlastníků SQL. Případné staré nepotvrzené lokální odběry uzavírá,
neaktivuje je zpětně; staré potvrzovací zprávy nesmí projít send gate.

Změny jsou lokální, bez commitu, push nebo produkčního nasazení. Disposable
preview nemá skutečného poskytovatele, fronta je pozastavena a cron vypnutý.

## Aktuální localhost náhled

- Bez odpočtu: http://127.0.0.1:58380/form/ples-upozorneni-bez-odpoctu
- S odpočtem: http://127.0.0.1:58380/form/podzimni-ples-vstupenky
- Flutter editor běží na portu 58381.

Izolovaný browser ověřil desktop i šířku 375 px. Skutečné přihlášení ihned
vytvořilo aktivní odběr a zobrazilo „Upozornění uloženo.“. Počet zpráv před
přihlášením i po něm byl 1 (žádná nová zpráva). Existují jen capabilities
pro odhlášení. Fronta zůstala pozastavena, worker URL prázdná a cron vypnutý.
Náhledy zůstávají spuštěné. Screenshoty jsou v lokálním workspace
`/Users/miakh/source/festapp-sale-opening-e2e-20261104/single-*-{desktop,mobile}.png`.

## Následná ochrana proti botům 2026-11-05

Tlačítko má podle poslední úpravy uživatele text „Upozornit mě na začátek přihlašování“.
Oba veřejné webové klienty před přihlášením získávají Turnstile proof; server
vyžaduje skutečné ověření, správný hostname, účel a vazbu na formulář/adresu.
Samostatný Managed widget je připraven a lokálně nakonfigurován; produkční
backend se neměnil. Jedenáct Edge testů, 38 JS testů, šest Flutter testů a cílený
Dart analyzer prošly. Reálný headless browser dostal interaktivní challenge;
pozitivní dokončení u skutečného poskytovatele nebylo prokázáno. Negativní testy
podvrženého/chybějícího tokenu prošly bez zápisu kontaktů či zpráv, při výpadku
skriptu zůstal e-mail zachovaný a tlačítko umožnilo opakování. Podrobnosti a
omezení: [ochrana odběru](../backend/sale-opening-bot-protection.md).
