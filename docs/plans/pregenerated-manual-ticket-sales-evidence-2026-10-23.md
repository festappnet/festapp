# Předgenerované vstupenky: realizační evidence

Datum: 2026-10-23. Implementace v pracovním stromu, ověřování standard.
Bez commitu, push, nasazení nebo změn produkčních dat v rámci této realizace.

## Architektura

- Běžný checkout a tvorba zásoby sdílejí `materialize_ticket_products_internal_v1`.
  Dávka vlastní zásobní objednávku a audit; každá položka od začátku používá
  stávající ticket, QR, OPT, sedadlo a alokace. Prodej přesouvá existující OPT
  do prodejní objednávky a používá společný cash/pairing primitive.
- Create/sell/void jsou atomické serverové příkazy s durable command identity,
  receipt replay a kontrolou práv před zveřejněním výsledku. UI nepotřebuje
  skládat finanční RPC ani vytvářet náhradní identity.
- Stock nemá finance a není vstupenkou použitelnou pro admission. Kapacitu
  blokuje od vytvoření; prodej ji znovu nealokuje. Běžné mutace a mazání jsou
  chráněny společnými serverovými guardy. `allowedActions` mají společného vlastníka.
- PDF používá společný renderer a jednou zapečetěný snapshot včetně fontů,
  grafiky, cen a digestů. Privátní objekty jsou neměnné, práce má lease fencing,
  adaptivní velikost tiskových částí a skutečné výstupní limity. Download a email
  používají stejné uložené jednotlivé PDF.
- Nový forward source manifest a deterministický assembler zachovávají historické
  migrace. Pozdější notification hooky vlastní migrace `20261023210000`;
  jejich definice se nepřenášejí zpět do dřívější ticket-batch migrace.

## Provedené kontroly

| Kontrola | Výsledek |
| --- | --- |
| `database/tests/eshop/ticket_batches/foundation_test.sql`, `lifecycle_test.sql` | PASS: reálný checkout, zásoba, prodej, storno, cash, identity, práva, replay, report, Fakturoid, email intent a rollback po injektované chybě |
| `database/tests/eshop/ticket_batches/concurrency.test.mjs` | 4 PASS: dva DB klienti, sale/sale, sale/void, sale/scan a Blueprint identity/guardy |
| Existující SQL regrese | 9 PASS: checkout, seating, waitlist ticket identity včetně partial flow, kapacita, manuální platba bez VS, pairing, report, admission a scan snapshot |
| Edge/Deno cílená sada | 66 PASS: dokumenty, renderer data, delivery a entrypoint kontrakty |
| Flutter batch commands a print downloads | 4 PASS: stejné command ID při serializačním retry, durable obnova, validace emailu před persistencí intentu, mobilní nabídka 10 PDF částí |
| Cílený Dart analyzer | Bez nálezů v batch UI, commands, document DTO/menu, order modelu a obou testech |
| Forward assembler, efektivní canonical source contract | `--check` PASS; pozdější notification source parity ověřena vlastníkem navazující změny |
| Canonical operation sources a Edge coverage registry | 9 PASS |

## Reálný lokální průchod

Izolovaný lokální Supabase, syntetický tenant a headless browser. Žádná produkční
data ani uživatelův browser. V aplikaci vytvořena dávka 200 kusů za 100 CZK:

- 200 jednotlivých PDF a 10 tiskových částí; celkem 400 uložených stran
  (jednotlivé a tiskové varianty), 19 372 184 bytů.
- Prodej dvou kusů vytvořil jednu prodejní objednávku a jednu cash úhradu 200 CZK.
  Storno jednoho neprodaného kusu dalo stav 197 zásoba / 2 prodané / 1 stornovaný,
  obsazenost 199, hodnotu zásoby 19 700 CZK a tržbu 200 CZK.
- Stažené tiskové PDF: HTTP 200, 20 stran, 952 474 bytů; SHA-256 odpovídá
  uloženému digestu `419352df5beefd036059e32536f423b205c5af1ba5b86cd96a38912041b765fc`.
- Změna živé ceny/názvu produktu, názvu akce a vzhledu po vytvoření nezměnila
  jednotlivé PDF: 49 256 bytů, SHA-256
  `79a73ddfc3657b19efb3835d4e7f9f79a5161dfe54523e5773c872c7238d57c4`.
- Ověřen studený deep link do dávky, návrat ze sekce Vstupenky přes browser Back,
  zobrazení původu/stavu a výběr konkrétních kusů. Mobilní overflow tiskových
  tlačítek vyřešen jednou nabídkou a ověřen widget testem při šířce 390 px.
  Následné rozšíření této nabídky na celé A4 PDF / ZIP popisuje doplnění níže.

## Hranice ověření a release

- Produkční konfigurace, migrace a rollout nebyly provedeny. Před aktivací grants
  musí být připraven odpovídající Edge runtime. Produkční ověření patří release.
- Fyzický browser reload po konkrétním prodeji není samostatně doložen; durable
  obnova je ověřena testem a studené otevření existující dávky reálnou aplikací.
- Starší `create_ticket_order_errors_test.sql` selhal na nesouvisejícím setupu
  formuláře s `form editor required`; nejde o passing evidence této realizace.
- Celorepozitářová architektonická kontrola souběžné práce hlásila nesouvisející
  nezařazené soubory a chybějící fixture. Nebyl proveden celý release gate.
- Úmyslně bez Fakturoid prodeje, Stripe/terminálu, offline prodeje a povinných
  jmenných údajů. Zvláštní kompatibilita starých klientů byla uživatelem vyřazena.

## Doplnění: celé tiskové PDF nebo ZIP

Uživatelský požadavek ze stejné relace: místo jedné vstupenky na každou A4 nabídnout
jedno celé PDF s více kusy na listu a alternativně ZIP jednotlivých PDF.

- Nový autorizovaný export manifest v `eshop_ticket_batches/exports.sql` předává
  jen metadata kompletních uložených singles a zmrazenou šablonu. Platí stejné
  viewer právo a dokumentový budget. Samostatný forward je
  `20261024001000_ticket_batch_exports.sql`; původní dávková migrace se nepřepisuje.
- A4 export skládá vektory z původních PDF, ořízne prázdné okolí podle původní
  ticketArea a zvolí orientaci A4 podle kapacity. Zachová fyzickou velikost,
  pokud se samotná vstupenka na list vejde. Okraj 18 pt a mezera 12 pt umožní řezání.
- ZIP obsahuje původní jednotlivé soubory beze změny, v pořadí ticket-001.pdf atd.
  Oba exporty zahrnují celou původní dávku včetně později prodaných/stornovaných
  kusů; existující upozornění na neplatné QR zůstává viditelné.
- Export nic nepřegenerovává ze živé konfigurace ani nepřepisuje uložené objekty.
  Stávající limit jednotlivé renderovací práce zůstává 20 stran; skládání celé
  dávky přijímá nejvýše 200 singles a jeho vstup i výstup omezuje dokumentová
  byte policy (výchozí 16 MiB). Při překročení se celý export odmítne.
- Čtyři nové Deno testy ověřují skutečné PDF včetně všech vložených kusů,
  200 kusů v jednom 50stránkovém souboru, ZIP se shodnými původními byty a chyby
  integrity/rozměrů/limitů. Nová Edge boundary kontrola ověřuje odmítnutí bez auth
  a neznámého formátu. Finální sada: 54 PASS.
- Rozšířený SQL foundation test na izolovaném lokálním backendu: PASS pro práva,
  digest, zmrazené rozměry a odmítnutí nehotových dokumentů. Nová funkce i fixture
  byly načteny v jediné transakci a celé ověření skončilo ROLLBACK.

- Finální Flutter widget test: PASS při šířce 390 px, obě volby vrací správný
  formát a nehotové singles nabídku nezpřístupní. Cílený analyzer všech tří
  dotčených Dart souborů: bez nálezů. Source/coverage automation: 9 PASS.

Poznámka pro budoucí integraci: při souběžném vývoji canonical main mezitím
obsadil timestamps 20261023200000 a 20261023210000 jinými releasy. Původní batch
migration a starý notification draft v tomto pracovním stromu jsou proto drafty;
release musí nejprve sladit jejich názvy, pořadí a efektivní zdroje s aktuálním main.
Nová export migrace 20261024001000 byla s vlastníkem sousedního release ověřena
jako nekolidující. Tyto drafty se nesmějí bez tohoto sladění nasazovat.
