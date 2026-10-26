# Embedded checkout - lokální ověření 2026-10-20

Lokální implementace dokončena v existujícím pracovním stromu na
`feat/occasion-setup-wizard-20261007`. Cizí rozpracované změny zachované.
Bez commitu, push, produkční migrace nebo nasazení. Produkční tenant nebyl vybrán.

## Automatické kontroly

- `npm test --prefix web_client`: 402 testů, 380 pass, 22 skip, 0 fail.
  Zahrnuje skutečný parent script v jsdom, child bridge, source/origin/instance,
  verzi, rozměry/scroll bounds, dvě instance, opakované vložení scriptu,
  ready/load, odebrání iframe, cleanup, offscreen RAF fallback, dialog/calendar
  measurement, zachování tab stops, veřejný bootstrap/routing/canonical slug,
  preview a identitu příkazu včetně blokovaného storage.
- `npm run build --prefix web_client`: pass. `dist/embed.js` existuje a `cmp`
  potvrzuje shodu s `public/embed.js`. `automation/build_web_bundle.sh` kopíruje
  celý `web_client/dist/.` do výsledného bundle; tooling nebylo nutné měnit.
- `fvm flutter test test/components/forms/public_link_settings_cases.dart --concurrency=1`:
  3 pass. Skutečně spuštěné případy: helper obou snippetů včetně escapování,
  saved/draft/new UI a zachování uložené adresy po neúspěšném přejmenování.
- `fvm dart analyze` na `form_embed_code.dart`, `form_public_link.dart`,
  `form_strings.dart` a příslušném testu: bez chyb a varování; existující info
  `non_constant_identifier_names` pro `typeHere_informal` ve FormStrings.
- JSON všech šesti jazyků obsahuje všech sedm nových neprázdných embed textů.
  Flutter úlohy proběhly jednotlivě, bez souběžného Flutter buildu/serveru.

## Skutečný prohlížeč a backend

Izolovaný lokální headless Chrome 151.0.0.0 na macOS, agent-browser s explicitním
prázdným configem a pojmenovanou session `festapp-embedded-checkout`.
Primárně accessibility snapshots a čerstvé refs. OOPIF introspekce, kliknutí na
sedadlo a simulace ztracené odpovědi použily CDP jen tohoto vlastního browseru;
nejde o Playwright gate nebo tvrzení o automatickém CI E2E pokrytí.

Host: `http://localhost:59801/tests/fixtures/embedded-checkout/host.html`.
Child: `http://127.0.0.1:59801/form/...`. Jde o rozdílné site, ne jen porty.
Backend: vlastní `festapp-embedded-e2e-20261020`, API 59821, DB 59822.
Kanonická baseline 20260805230000, novější migrace, seed a syntetická fixture.
Skutečný `send-ticket-order`, `waitlist-commands` a SQL finalizace, bez mocku
objednávkového backendu. Cron vypnutý, bez email workeru, provider credentials
nebo skutečných plateb. Waitlist používá vlastní náhodný lokální šifrovací klíč.

| Průchod | Důkaz |
| --- | --- |
| Dlouhý formulář v automatickém iframe | Přirozená výška se mění podle obsahu; při rekapitulaci se zmenší, při rozbalení platby zvětší. Desktop i 390 x 844 CSS px, bez horizontálního přetečení. |
| Nákup bez přihlášení | Skutečný lokální endpoint vytvořil objednávku; rekapitulace, potvrzení, 120 CZK, QR, download a návrat do formuláře. |
| Pevný iframe bez helperu | Výška zůstává 800 px, dlouhý obsah má interní scroll; validace zaměří chybný input; rekapitulace, Escape, dokončení a QR fungují. |
| Sedadla | Mobilní panel v automatickém iframe má ověřený host viewport 844 px. Zoom a výběr přes existující select_spot; nákup rezervovaného sedadla dokončen. Pevný iframe používá vlastní viewport 800 px, zoom a Escape dosažitelné. |
| Ztracená odpověď + blokovaný storage | Fetch wrapper po skutečném commitu zahodil odpověď; localStorage getter házel SecurityError. UI ukázalo chybu. Ruční návrat a opakování použily stejný commandId i clientId. DB počet před pokusem 1, po commitu 2, po opakování stále 2. Žádný automatický nákup/reload. |
| Dva iframe | Oba dostaly vlastní instance a přirozenou výšku. Po opravě offscreen RAF měření byly obě výšky stabilní přes 10 následných RAF vzorků (1561 px při tehdejším obsahu). |
| Host viewport update | Změna desktop/mobile viewportu se propsala do child `--embed-viewport` a mapy. |
| Odmítnutý handshake | Fixture `reject=1` poslala protocol 99: child nepřijal viewport, formulář zůstal použitelný v pevném 800px režimu. |
| Nedostupnost a kapacita | Uzavřený formulář zobrazuje odmítnutí a identitu. Po naplnění kapacity 1 přešel další skutečný load do waitlist režimu bez produktů/platby. |
| Waitlist a capability | Registrace proběhla přes skutečný endpoint, zobrazil se osobní přehled. Reload zachoval embed=1 i osobní fragment a znovu načetl přehled; token se neposílal rodiči. |
| Organizátor a kalendář | Native dialog dostupný i z finálního výsledku; měření zahrnulo jeho dolní okraj (frame 1490 px, dialog bottom 1489.16 px). Escape zavřel nejprve dialog a potom výsledek. Mobilní kalendář měl x=10, šířku 307.875 při child šířce 358, bez přetečení. |
| Existující session | Syntetická lokální session po reloadu zůstala stejným principalem; embed+preview=true měl formulář, skrytou hlavičku a žádný preview banner. Po doplnění odpovídajícího fixture user_info prošel i finální přihlášený nákup. |
| Samostatná stránka | Běžná /form URL zobrazila formulář i normální hlavičku, bez embed class. pageHost byl skutečně viditelný. |

Konečný stav syntetické DB: 5 ordered + 2 waitlisted objednávky. Předchozí
odmítnutí neúplné seat fixture a Auth-only fixture uživatele necommitovala nákup.
Fixture Auth uživatel pro session kontrolu musí mít rovněž odpovídající
`user_info` v lokálním tenantu. Testovací prostředí bylo po průchodu zastaveno.

Screenshoty obsahují pouze syntetické údaje:
[finální mobilní potvrzení/QR](mobile-payment-final.png),
[mobilní plánek](mobile-seats.png).

## Omezení

Safari/WebKit, Firefox, fyzický iOS/Android a konkrétní CMS nebyly testovány.
Storage denial byl v Chromiu simulován getterem, nikoli ověřen konkrétní
politikou Safari ITP nebo skutečným režimem blokování third-party cookies.
Paměťová identita při zakázaném storage nepřežije reload; exactly-once přes
reload se netvrdí. Waitlist nabídka/acceptance nebyla nově end-to-end proklikána;
capability načtení, běžná registrace a reload přehledu byly skutečné. Žádné
ověření reálného emailu, platební aplikace nebo produkčních HTTP hlaviček.
22 přeskočených Node testů nejsou součástí úspěšně provedeného pokrytí.

Provozní a veřejný integrační kontrakt je v
[průvodci vložením](../../../integrations/embedded-checkout.md).
