# Capability a account evidence - 2026-11-06

Tato evidence neaktivuje prodeje ani marketplace. `unknown` není souhlas nebo
záruka protokolu. Uvedené zdroje jsou oficiální; indexovaný přehled API není
náhradou ověření konkrétního účtu nebo sandboxové transakce.

| Oblast | Stripe | Barion |
|---|---|---|
| Create retry | API v1 uchovává idempotentní odpověď nejméně 24 hodin; adaptér má konzervativní limit 23 hodin od založení pokusu | Oficiální obecné API dokumentuje GUID `Idempotency-Key`; retence a Start replay-result guarantee unknown. `PaymentRequestId` není idempotency guarantee |
| Ztracená odpověď | Stejný neměnný klíč v bezpečném okně; potom pouze čtení | unknown; bez ověřené recovery není dovoleno opakovat create |
| Lookup | Account-scoped seznam Checkout Sessions, fixní časové okno a ověřené stránkování v adaptéru | PaymentState v4 pro známé PaymentId je doložený; lookup podle ztraceného command ID a úplnost hledání unknown |
| Definitivní absence | Dokumentace list API nedokládá silnou konzistenci absence; prázdný seznam zůstává `unresolved` | unknown; nikdy nepředstírat absenci |
| Expirace | Adaptér ověřuje uloženou identitu, částku, měnu a remote session; rezervace inventáře je samostatná serverová politika | API expiry/account behavior unknown; neodvozovat ze Stripe |
| Callback | Raw-body podpis, účet, režim a aktuální provider reads jsou implementované a lokálně testované | Doložený POST callback s query paymentId; autentizované PaymentState čtení, nejméně 5 s mezi dotazy. Skutečná sandboxová platba 1 CZK, callback a autentizované Succeeded čtení ověřeny; viz navazující evidence |
| Refundy/spory | Existující ověřené Stripe facts, kurzory a SQL historie zachovány; společný owner aplikace důsledků | Externí partial/full refund ověřen přes skutečné API a common SQL owner. Neznámé/reversal/review stavy vytvářejí persistentní hold; úplný chargeback/release kontrakt blokuje aktivaci |
| Konkrétní účet/shop | Runtime/account způsobilost v této práci neověřována; žádná nová aktivace | Hlavní Chrome/Panerelay: shop Active (sandbox), schválení potvrzeno přes API, CZK účet založený. Klíč v lokální šifrované Klíčence; navazující payment evidence níže |
| Marketplace / E1 | unknown pro konkrétní účet; nezískává se tímto refaktorem | unknown; běžný merchant checkout neprokazuje marketplace |
| Provize / E2 | Collector se nezavádí; existující service-fee source zůstává jediná autorita | Totéž; žádné implicitní 4 % |

Oficiální zdroje ověřené 2026-11-06:

- [Stripe API v1 idempotency](https://docs.stripe.com/api/idempotent_requests).
- [Stripe Checkout Session list a stránkování](https://docs.stripe.com/api/checkout/sessions/list).
- [Barion PaymentState v4](https://docs.barion.com/Payment-PaymentState-v4),
  [responsive payment outline](https://docs.barion.com/Responsive_web_payment),
  [sandbox payment guide](https://docs.barion.com/Making_a_test_payment) a
  [marketplace example](https://docs.barion.com/Marketplace_Example).
  Oficiální stránky byly dohledány ve vyhledávacím indexu; přímé otevření
  dokumentace skončilo HTTP 403 / Cloudflare verification. Nejde o uzavřenou
  specifikaci pro bezpečnou implementaci druhého adaptéru.

## Sandbox a bezpečné uložení přístupů

Delegovaný Terra operátor použil BrowserOS Neo podle uživatelova pokynu.
[Sandbox login](https://secure.test.barion.com/) je v nové agentem založené kartě
65; žádost o lidské přihlášení zůstala `waiting`. Nalezené přístupy: žádné.
Vyhledání metadata internetového hesla pro `barion.com` v macOS Keychainu
nenašlo položku. Nepřítomnost této konkrétní položky není důkazem nepřítomnosti
jakýchkoliv jinak pojmenovaných hesel v iCloudu.

Žádné heslo ani API klíč nebyly vytvořeny, rotovány, vypsány nebo uloženy.
Uložení do Apple Passwords/iCloudu a ověření synchronizačních metadata nelze
potvrdit bez nalezení přístupu a podporovaného úložného mechanismu. Neexistuje
pracovní kopie přístupu pouze v `/tmp`. Dokumentační karta 66 byla zavřena.
Login karta neobsahovala přehrávaná média; její ztlumení se nepodařilo ověřit
před vyžádaným lidským přihlášením a čekající stránka nebyla dále ovládána.

Vlna 4 potřebuje přihlášení, identitu testovacího shopu, bezpečně zpřístupněný
sandboxový POSKey a ověřené protokolové i account-level podmínky. Teprve potom
lze dodat skutečný adaptér a redigovaný sandboxový acceptance receipt. Test
s alternativním lokálním úložištěm se za tento důkaz nepovažuje.


## Navazující stav přes Panerelay

Původní blokace chybějícími přístupy byla překonána. Podrobný aktuální stav,
ověřená dokumentace, bezpečné reference, přesná nejistota prvního Start a
skutečná account-level odpověď jsou v
[Barion protocol a account receipt](BARION-PROTOCOL-2026-11-06.md).
Původní BrowserOS záznam výše zůstává historickou evidencí. Schválení
sandboxového obchodu a CZK účet jsou nyní vyřešené. Aktuální výsledky jsou v
[navazující evidenci](BARION-APPROVAL-2026-11-06.md). Původní nejistý Start
zůstává nejistý; samostatné pojmenované testy jej nenahrazují ani automaticky
neopakují.

Aktuální implementace, validace a reálné finanční důkazy jsou v
[integračním receipt](BARION-INTEGRATION-RESULT-2026-11-06.md). Registrace Barionu
nepovoluje produkční prodeje. Původní timeout zůstává unresolved bez automatického
opakování; toto je správný recovery výsledek při chybějící záruce absence.
