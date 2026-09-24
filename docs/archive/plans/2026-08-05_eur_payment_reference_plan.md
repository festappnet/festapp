# Kanonický EUR platební kontrakt a bezpečné párování bankovních transakcí

Date: 2026-08-05
Status: Implemented and locally verified; production rollout remains gated
Verification: standard

## Outcome

Nová bankovní objednávka v EUR dostane právě jednu stabilní ISO 11649 RF
creditor reference. Zákazník ve všech výstupech uvidí tutéž referenci a EUR QR
kód bude platný EPC SCT payload se strukturovanou RF referencí. Nová CZK
objednávka zůstane byte-for-byte kompatibilní v podstatných SPD/QR Platba
polích a nadále používá variabilní symbol.

Fio API i bankovní e-mail budou pouze dvěma ingest adaptéry nad jedním uloženým
modelem bankovního pohybu. Jediný SQL matcher rozhodne, zda lze příchozí pohyb
automaticky přiřadit. Jediný interní SQL mutation owner následně provede
attach/unlink, přepočítá `paid`/`returned` a stav objednávky a atomicky zapíše
audit. Žádný importer, ruční wrapper ani delete/unlink cesta nebude upravovat
vazbu nebo peněžní agregace vlastní implementací.

Automatické přiřazení nastane jen při validním, přesném a jediném kandidátovi na
stejném cílovém účtu a ve stejné měně. Konflikt signálů, kolize, odchozí nebo
nulový pohyb, neověřená identita e-mailové notifikace a chybějící reference
zůstanou bez vazby. Retry ani kombinace e-mail → API nesmí jednu platbu
započítat dvakrát.

Toto je úplný canonical cutover interního pairingu. Záměrně zachované externí
hranice jsou pouze:

- CZK variabilní symbol a SPD;
- přesně vymezený legacy VS fallback v bankovním textu;
- veřejné názvy autorizovaných Flutter RPC, pokud jejich přejmenování nemá
  produktovou hodnotu. Za nimi však musí být jediná implementace.

## Scope

### In scope

- ISO 11649 RF generování, normalizace, MOD 97 validace, persistence a
  neměnnost na `eshop.payment_info`.
- Povinná EPC data účtu, včetně explicitního názvu příjemce platby.
- Bezeztrátové uložení Fio `column27` a provider-aware identit bankovního
  pohybu/notifikace.
- Bezpečná reconciliation e-mailového provisional záznamu s pozdějším Fio API
  pohybem pouze přes bankou vydaný společný identifikátor.
- Jeden automatický matcher a jeden interní mutation owner pro všechny
  attach/unlink/delete-manual cesty.
- Oprava grantů, permission checks, audit, retry, concurrency a idempotence.
- EUR EPC QR a jednotné platební instrukce pro confirmation, reminder, update,
  paid output a veřejný order-result klient, pokud platební data vrací.
- Additivní forward migrace, lokální ověření, read-only produkční preflight,
  slovenský SEPA pilot, explicitní aktivace a post-check.
- Jednotlivé ručně schválené historické pairing operace.
- Tenant-neutral source alignment do určených produkčních větví po samostatném
  oprávnění.

### Out of scope

- Fuzzy párování podle jména, částky, podobnosti textu, data v tolerančním okně
  nebo „unikátních centů“.
- Automatické sloučení e-mailu a API bez společného bankovního ID.
- Automatické rozhodování mezi více kandidáty.
- Nový dashboard všech nespárovaných transakcí.
- Nová produktová notifikace po každé částečné platbě.
- Hromadné mazání či automatické spojování historických pohybů.
- Merge celých tenant větví nebo produkční deploy bez zvláštního souhlasu.
- Zpětné rozeslání RF pro uzavřené historické objednávky.

## Non-negotiable constraints

- Zápisová obchodní logika patří do SQL. Dart/JS/Deno adaptéry parsují,
  prezentují a volají RPC; nerozhodují o pairingu.
- Nové funkce jsou v `public`. Každá `SECURITY DEFINER` funkce má
  `SET search_path = public, extensions`, explicitně kvalifikuje `eshop.*`,
  kontroluje oprávnění/volající roli a nepoužívá raw dynamic SQL.
- Nevznikne persistentní application trigger. Neměnnost RF se prosadí přes
  privátní zápisovou hranici, ACL/RLS a test absence jiných writerů.
- Forward změny tvoří dva nové unikátní čtrnáctimístné soubory po tracked
  baseline `20260805230000`: nejprve foundation schema/ACL/ingest/pairing,
  potom oddělená RF writer activation. Aplikovaná historie se nepřepisuje a
  data backfill není schovaný v žádné z nich.
- `supabase/baseline/20260805230000_production_schema.sql` je testovací fixed
  point. `database/tables/tables.sql` a relevantní `database/functions/**`
  odrážejí cílový čistý install; produkční deploy kontrakt jsou forward migrace.
- Implementace vznikla v čistém izolovaném worktree ze SHA
  `526e322a999b396dfa9730b66661f49ad3fe1059` a po lokálním ověření byla
  přenesena do tenant-neutral `main` historie.
- Produkční migrace, deploy Edge Functions/klientů, živá mikroplatba, změna
  produkčních dat a push vyžadují samostatné oprávnění.
- RF je po prvním zveřejnění neměnná. Rollback může zastavit vydávání nových
  referencí, ne smazat či regenerovat vydané reference.
- EPC payload smí obsahovat structured reference nebo unstructured remittance,
  ne obojí. Pro EUR se použije pouze structured RF.
- EPC vyžaduje jméno příjemce a IBAN; amount je EUR 0,01 až 999999999,99.
  Aktivace nesmí proběhnout, pokud účet nemá validní `creditor_name` a IBAN.
- `automation/project.conf` je jediný zdroj live Supabase cíle. Před live
  pozorováním se musí ověřit `SUPABASE_URL` a `FORCE_OCCASION_LINK` podle
  `docs/architecture/ai_context.md`; `.env.local` neurčuje cílový projekt.

Oficiální kontrakty:

- [Fio API, aktuální dokumentace](https://www.fio.cz/docs/cz/API_Bankovnictvi.pdf)
- [EPC069-12 v3.1](https://www.europeanpaymentscouncil.eu/sites/default/files/kb/file/2024-03/EPC069-12%20v3.1%20Quick%20Response%20Code%20-%20Guidelines%20to%20Enable%20the%20Data%20Capture%20for%20the%20Initiation%20of%20an%20SCT.pdf)

## Fixed point and change type

- Repository fixed point ověřený 2026-08-05:
  `526e322a999b396dfa9730b66661f49ad3fe1059` na
  `prod/csmostrava2026`.
- Stávající plán a execution prompt jsou výchozí rozhodnutí; tento dokument je
  nahrazuje jako autoritativní verze.
- Change type: additivní externí EUR capability + úplný interní cutover na
  jeden matcher a jeden pairing mutation owner.
- Produkční live fakta níže pocházejí z dřívější read-only kontroly 2026-08-05.
  Implementační agent je před produkčním krokem musí znovu ověřit; nesmí je
  považovat za neměnná.

## Current-state evidence

| Type | Claim | Evidence | Consequence |
|---|---|---|---|
| Fact | Aktivní veřejný writer je wrapper `create_ticket_order` → `create_ticket_order_client_sync_v1` → `create_ticket_order_internal_v1`; source file se stále jmenuje `create_ticket_order.sql`. | `supabase/migrations/20260802234000_client_sync_v1_expansion.sql`; `database/functions/eshop/create_ticket_order.sql` | RF se přidá do interního writeru i do nové forward migrace. Nesmí se editovat jen live funkce ani stará historická migrace. |
| Fact | Order writer dnes generuje pouze VS a response obsahuje `order.payment_info`, nikoli `payment_qr`. | `database/functions/eshop/create_ticket_order.sql`: insert `eshop.payment_info`, final `JSONB_BUILD_OBJECT` | Nový QR kontrakt musí mít skutečného producenta; Flutter fallback na neexistující `payment_qr.spd` není rollout kompatibilita, ale dead assumption. |
| Fact | Fio import ukládá `column5/7/16/25`, ignoruje `column27`, deduplikuje podle `transaction_id` a páruje přes `LIMIT 1`. Pairing exception pouze vypíše jako `NOTICE`. | `database/functions/eshop_transactions/insert_transactions.sql` | Import musí uložit raw reference, vracet per-item verdict a odstranit swallowed error i inline matcher. |
| Fact | Fio API definuje `column22` jako ID pohybu, `column17` jako ID pokynu a `column27` jako Reference plátce. | Fio API PDF, mapping `Column*` | Tyto identity se nesmí zaměnit; source schema musí pojmenovat movement ID a command ID odděleně. |
| Fact | Fio e-mail parser mapuje text `ID pokynu` do `ParsedTransaction.transactionId`, který SQL uloží jako `transactions.transaction_id`. | `supabase/functions/bank-mail-parser/parser.ts`; `bank-mail-parser/index.ts`; `process_email_transaction.sql` | Současná e-mail/API deduplikace porovnává semanticky různá ID. Parser musí vracet provider-aware `bank_command_id`, nikoli falešné movement ID. |
| Fact | Email SQL má fuzzy dedupe `(account, VS, amount, date ±3 days)` a vlastní VS matcher bez account/currency filtru. | `database/functions/eshop_transactions/process_email_transaction.sql` | Fuzzy dedupe i inline matcher musí být odstraněny; mohou zahodit legitimní opakovanou platbu nebo přiřadit cizí objednávku. |
| Fact | Vazbu/agregace mění minimálně `add_transaction_to_payment_info`, `add_transaction_to_payment_info_ws`, `insert_manual_transaction`, `remove_transaction_from_payment_info_ws` a `delete_manual_transaction_ws`. Dvě unlink cesty ručně odečítají agregáty. | `database/functions/eshop_transactions/*.sql`; focused `rg` writerů | Canonical cutover musí zahrnout všechny tyto cesty, ne jen dva importéry. |
| Fact | `remove_transaction_from_payment_info_ws` nepoužívá `recalculate_order_payment_status`; obsahuje prázdný placeholder branch. | tentýž SQL soubor | Ruční unlink je dnes druhý, neúplný stavový automat a bude nahrazen tenkým wrapperem nad canonical ownerem. |
| Assumption to verify before deploy | Live grants nízkoúrovňových pairing funkcí mohou být širší než zamýšlená service/internal boundary. | tracked migration history plus required live `has_function_privilege` preflight | Foundation migrace vždy explicitně revoke/grant nastaví bez spoléhání na současný implicitní stav. |
| Fact | Email QR helper vždy staví SPD s `X-VS` bez ohledu na měnu. | `supabase/functions/_shared/qrCodePayment.ts` | Potřebuje čistý currency router a samostatný EPC encoder. |
| Fact | Confirmation, update, reminder a paid šablony si samy skládají payment data a čtou VS přímo. | `supabase/functions/send-email/getTicketOrder*Template.ts` | Jednotný presenter musí být jediným vlastníkem reference, amount due a QR vstupu. |
| Fact | `eshop.bank_accounts` nemá pole s jasnou sémantikou právního jména příjemce. `title` je obecný název účtu. | `database/tables/tables.sql`; `lib/components/bank_accounts/README.md`; `bank_account_model.dart` | Přidat `creditor_name`; nepoužívat potichu `title` jako EPC beneficiary name. |
| Fact | Flutter čte `payment_qr.spd`, ale v aktuálních producentech nebyl nalezen žádný `payment_qr`. | `order_finish_screen.dart`, `payment_qr_card.dart`, repository-wide `rg` | Implementovat rovnou jediný `payment_qr.payload` kontrakt. Nedržet dead `spd` fallback rollout okno. |
| Fact | Fakturoid standardně dopočítává vlastní VS, ale API dovoluje VS zadat při vytvoření. | `supabase/functions/send-ticket-order/fakturoid.ts`; Fakturoid API v3 invoices | Pro EUR se Fakturoidu předá původní VS a lokální VS se po vytvoření RF nesmí změnit; CZK chování zůstane beze změny. |
| Fact (live, reverify) | 1 742 payment info, 22 EUR, 10 otevřených EUR; žádný NULL VS. Jedna kolize VS na stejném účtu/měně. | read-only agregace 2026-08-05 | Backfill zůstane omezený; VS `LIMIT 1` je prokazatelně nebezpečný. |
| Fact (live, reverify) | Dřívější dry-run našel dvě kladné nespárované platby s jediným kandidátem podle symbolu v message. | read-only kandidátní dotaz 2026-08-05 | Historické přiřazení smí proběhnout jen jednotlivě po novém dry-runu a schválení ID. |

### Representative flow today

1. Public order jde přes client-sync wrapper do `create_ticket_order_internal_v1`,
   který vytvoří `payment_info` s VS a vrátí order JSON.
2. Confirmation je transakčně zařazeno do `queue_emails`; Deno template vytvoří
   SPD QR z VS. Reminder/update/paid načítají `payment_info` znovu a mají vlastní
   skládání instrukcí.
3. Fio JSON jde přes `fetch-transactions`/`synchronize-orders` do
   `insert_transactions`. Bankovní e-mail jde přes `bank-mail-parser` do
   `process_email_transaction`.
4. Oba importéry dnes samostatně vybírají `payment_info` a volají
   `add_transaction_to_payment_info`.
5. Ruční attach/unlink/delete používají další SQL implementace stejné mutace.

## Target architecture

### 1. Canonical payment identity owner

`eshop.payment_info` vlastní platební identitu:

- `variable_symbol bigint NULL` — zachovaná CZK/legacy reference;
- `creditor_reference text NULL` — canonical uppercase ISO 11649 bez mezer;
- `creditor_reference` vzniká pro bankovní EUR payment info jako
  `RF{check}{variable_symbol}`; jedna až deset číslic VS zůstává v RF beze změny
  a pouze dostane povinný ISO prefix a dvě kontrolní číslice;
- partial unique index zaručí unikátnost neprázdných RF v rámci bankovního účtu;
- normalizace pro zobrazení přidává mezery po čtyřech znacích, DB hodnota ne;
- po vytvoření RF tvoří VS a RF jednu neměnnou identitu; Fakturoid dostane stejný
  VS a nesmí lokální hodnotu přepsat. Identita nezávisí na jménu zákazníka.

`eshop.bank_accounts.creditor_name text NULL` je explicitní EPC beneficiary
name. Je upravitelné pouze bank-account adminem. Bankovní EUR účet není
activation-ready, pokud `creditor_name` po trimu není 1–70 podporovaných znaků
nebo `account_number` není validní IBAN.

### 2. Canonical bank observation model

`eshop.transactions` zůstává účetním pohybem, ale identity budou explicitní:

- `ingest_source text NOT NULL` s bounded hodnotami, např. `fio_api`,
  `fio_email`, `airbank_email`, `manual`;
- `transaction_id` znamená pouze provider movement ID, nikdy e-mailové
  `ID pokynu`;
- `command_id` znamená provider command/instruction ID (`column17` u Fio);
- `external_id` zůstává transport/message ID;
- `payer_reference` uchovává raw `column27`/ekvivalent, bez normalizace;
- ostatní raw reference fields zůstávají ve stávajících pojmenovaných sloupcích.

Před přidáním unikátních indexů se provede read-only duplicate preflight. Bank
account už určuje provider, proto se zdrojový kanál nesmí stát součástí identity
a povolit duplikát téhož pohybu z e-mailu a API. Cílové identity jsou:

- API movement: `(bank_account_id, transaction_id)` pro non-NULL movement ID;
- e-mail transport retry: `(bank_account_id, external_id)` pro non-NULL message ID;
- cross-channel reconciliation: pouze explicitní společný bankovní
  identifikátor se stejnou sémantikou, u Fio přednostně
  `(bank_account_id, command_id)`, ale až po potvrzení reálnými fixtures a
  duplicate query.

Pokud e-mail nemá provider ID bezpečně sdílené s autoritativním API pohybem,
záznam se uloží, ale automatický matcher vrátí
`ineligible/unverified_identity`. Amount/date/name/VS kombinace se nikdy
nepoužije k deduplikaci. Pokud pozdější API záznam nelze bezpečně reconcile,
nesmí být automaticky spárován vedle již ručně spárovaného provisional řádku;
konflikt jde do ruční kontroly. Reconciliation doplní autoritativní movement ID
do existujícího řádku a zachová email `external_id` pro transport replay; nesmí
vytvořit druhý účetní row.

### 3. Canonical pairing mutation owner

`public.apply_transaction_pairing(...)` je jediná interní funkce, která smí
změnit `eshop.transactions.payment_info` nebo z této vazby odvodit
`payment_info.paid/returned`.

Contract:

- inputs: transaction row ID, target payment-info ID nebo NULL pro unlink,
  bounded `method`, actor UUID/actor kind a reason/details bez PII;
- row-lock: zamkne transaction a dotčené old/new `payment_info` v deterministickém
  pořadí;
- checks: existence, expected current link, currency, povolená CASH výjimka,
  idempotence a caller boundary;
- side effects: nastaví vazbu, přepočítá `paid` i `returned` z aktuálních řádků
  pomocí jediné agregační implementace, zavolá
  `recalculate_order_payment_status` pro starou i novou objednávku a zapíše
  audit ve stejné DB transakci;
- output: machine-readable JSON result, žádné lokalizované věty;
- permissions: `REVOKE ... FROM PUBLIC, anon, authenticated`; pouze konkrétní
  interní owner/service boundary. Uživatelské wrappers provedou permission
  checks před voláním.

`add_transaction_to_payment_info` bude po migraci buď odstraněn, nebo pouze po
dobu jedné lokální implementační vlny mechanicky deleguje na nového ownera.
Finální stav nesmí obsahovat jeho starou agregaci. Protože jméno není externí
protokol, preferovaný finální stav je starou funkci odstranit a upravit všechny
repo call sites/tests.

`eshop.transaction_pairing_events` je append-only audit změn vazby. Minimální
sloupce: event ID/time, immutable numeric transaction snapshot ID, nullable FK
na živý transaction s `ON DELETE SET NULL`, old/new payment-info ID, action,
method, actor UUID/kind a bounded JSONB diagnostics bez raw message/jména/účtu.
Delete manual transaction nejprve provede auditované unlink a teprve potom
smaže manual row; audit přežije díky snapshot ID.

### 4. Canonical automatic matcher

`public.match_bank_transaction(p_transaction_id bigint)` je service-only
decision owner. Načte již uložený row, zamkne jej, vyhodnotí všechny signály a
při jediném bezpečném kandidátovi zavolá `apply_transaction_pairing`.

Verdicts:

- `paired` — právě jeden kandidát, mutace uspěla;
- `already_paired` — idempotentní replay bez druhé auditní/peněžní změny;
- `unmatched` — žádný kandidát;
- `ambiguous` — více kandidátů nebo validní signály míří různě;
- `ineligible` — amount <= 0, chybí účet/měna, unverified e-mail identity nebo
  malformed-only reference inputs;
- `failed` se nevyrábí jako business verdict; neočekávaná SQL chyba se
  rollbackne a importer ji vrátí jako explicitní per-item error.

Signal extraction:

1. explicitní numerický `transactions.vs` v rozsahu 1–10 číslic;
2. validní RF z celého `payer_reference` po povolené space normalization;
3. validní RF token v `message_for_recipient`, `user_identification` nebo
   `comment`, ohraničený nealfanumerickými hranicemi, max. ISO délkou a následně
   ověřený MOD 97;
4. pouze když explicitní VS chybí: legacy VS, pokud celý trimnutý message je
   1–10 číslic nebo obsahuje explicitně označený token `VS`/`variabilní symbol`.
   Libovolné holé číslo uvnitř volného textu není automatický signál.

Každý kandidát musí mít stejný `bank_account`, `upper(trim(currency))` a
`amount > 0`. Matcher shromáždí distinct kandidáty pro každý validní signál;
nikdy nepoužije `LIMIT 1` jako rozhodnutí. Jeden signál s více candidates nebo
dva signály s rozdílným targetem znamenají `ambiguous`.

### 5. Canonical customer payment presenter

Jeden pure TypeScript modul v `supabase/functions/_shared/` přijme canonical
payment context a vrátí:

- `reference_kind`: `VS` nebo `RF`;
- `reference_raw` a `reference_display`;
- `qr_format`: `SPD` nebo `EPC_SCT`;
- `qr_payload`;
- human-readable account/IBAN, amount due a currency.

Pro CZK router volá `buildSpdPayload`; pro EUR `buildEpcSctPayload`. EPC encoder
explicitně sestaví řádky dle EPC069-12 v3.1, včetně version/charset/SCT,
creditor name, IBAN, `EUR{amount}` a structured RF; BIC je pouze podle pravidel
specifikace. Encoder odmítne invalidní EUR/IBAN/name/RF/amount a nikdy současně
nevloží unstructured remittance.

Order response má jediný nový blok `order.payment_qr` s `format` a `payload`.
Protože starý `payment_qr.spd` nemá v tomto fixed point producenta, nevznikne
compatibility reader ani alias. Flutter widget se přejmenuje z `spd` na
`payload` v témže commitu jako producent.

## Invariants

1. Nová aktivovaná bankovní EUR objednávka má právě jednu validní RF a validní
   EPC creditor data; selhání reference/QR prerequisites rollbackne order.
2. RF ani jeho podkladový VS po zveřejnění nelze změnit; Fakturoid dostane stejný VS.
3. Jedna bankovní observation může mít nejvýše jednu aktivní payment-info vazbu
   a do agregátu vstoupí nejvýše jednou.
4. Žádný fuzzy dedupe ani fuzzy matcher nezahodí legitimní opakovanou platbu.
5. Všechny attach/unlink/delete-manual cesty používají jednoho mutation ownera.
6. `paid` a `returned` jsou vždy přepočteny ze source rows, nikdy inkrementálně
   odečítány v wrapperu.
7. Každá změna vazby a smazání manual transaction má audit ve stejné transakci.
8. `unmatched`, `ambiguous` a `ineligible` nemění vazbu, agregát, order state ani
   e-mail queue.
9. Automatický matcher nepáruje přes jiný účet/měnu, odchozí/nulový pohyb,
   jméno, samotnou částku ani datum.
10. Interní importer/matcher/mutation RPC nejdou volat z PUBLIC/anon/auth.
11. CZK zůstává SPD + VS; EUR je EPC SCT + RF; hybridní payload neexistuje.
12. Staré klienty additivní DB expansion nerozbije; customer-visible aktivace
    nastane až po pilotu a připravených klientech.

## Entry points and forbidden bypasses

Allowed:

- `fetch-transactions` / `synchronize-orders` (service role) →
  `insert_transactions` → canonical ingest/reconcile → matcher → mutation owner;
- `bank-mail-parser` (service role) → `process_email_transaction` → stejná cesta;
- Flutter manual insert/attach/unlink/delete RPC → permission check → mutation
  owner;
- order writer → canonical RF helper; Deno/Flutter/web → canonical presenter
  contract.

Forbidden:

- přímé `UPDATE transactions.payment_info` mimo mutation owner;
- ruční arithmetic update `paid/returned` mimo canonical recalculation;
- vlastní lookup `payment_info` v importeru/manual insertu;
- veřejné volání service-only functions;
- fuzzy duplicate match, silent catch/`NOTICE`, `LIMIT 1` jako ambiguity policy;
- trigger, dual write, permanent feature flag nebo dočasný V1/V2 alias;
- EPC beneficiary name odvozené bez explicitního account-owner data contractu.

## Decisions, assumptions, blockers

### Decisions

- **D1:** RF payload je původní jedno- až desetimístný VS; výsledná reference má
  povinný ISO prefix `RF` + dvě kontrolní číslice a potom přesně stejné číslice
  VS. Vejde se do ISO 11649 maxima a neobsahuje PII.
- **D2:** RF je jen pro bankovní EUR payment info; historické/closed/CASH mohou
  zůstat NULL.
- **D3:** `creditor_name` je nové explicitní pole bank accountu; `title` se
  nereinterpretuje.
- **D4:** Pairing mutation a matching decision jsou dva hluboké moduly: matcher
  vybírá, mutation owner jediný mění stav.
- **D5:** Legacy message VS je přijatelné jen jako celý message nebo označený VS
  token, ne libovolné číslo ve volném textu.
- **D6:** E-mail/API dedupe vyžaduje společný bankovní identifikátor se stejnou
  sémantikou. Amount/date/name nejsou identita ani při jediné shodě.
- **D7:** Částečná platba se může připojit; existující order-state recalculation
  rozhodne, zda je objednávka zaplacena.
- **D8:** `payment_qr.spd` se neudržuje, protože nemá producenta v tomto fixed
  pointu. Cílový kontrakt je ihned jediný `format/payload`.
- **D9:** Historický pairing je operace nad explicitně schválenými transaction
  IDs, ne součást migrace.
- **D10:** Pilot gate je rollout stav, ne trvalý runtime feature flag.

### Assumptions requiring bounded resolution

- **A1:** Fio e-mail `ID pokynu` skutečně odpovídá API `column17`; impact if
  false: cross-channel auto-reconciliation pro tento provider se zakáže;
  resolve by: anonymizované paired fixtures a duplicate cardinality query před
  indexem/deployem.
- **A2:** Slovenská banka zachová RF v některém z `column27/16/7/25`; impact if
  false: customer EUR RF lze stále zobrazit, ale automatic RF matching pro
  daný účet se neaktivuje; resolve by: schválená 0,01 EUR pilotní platba.
- **A3:** Produkční client-sync wrapper odpovídá baseline/fixed pointu; impact if
  false: mohl by existovat další writer; resolve by: před implementací porovnat
  signatures/source a před deployem live `pg_get_functiondef`.
- **A4:** Staré klienty ignorují additivní response fields; impact if false:
  nasadit tolerantní reader před rozšířeným writer response; resolve by:
  contract test obou veřejných order entry points.
- **A5:** Určené EUR bank accounts mají známý právní `creditor_name`; impact if
  false: EPC aktivace je blokována pouze pro nepřipravený účet; resolve by:
  bank-account admin preflight, nikoli odhadem z titulu occasion/unit.

### Blockers / separately authorized actions

- **B1:** Live Supabase introspection a production preflight podle canonical
  project resolution.
- **B2:** Production migration/deploy a branch synchronization.
- **B3:** Reálná slovenská SEPA mikroplatba minimálně 0,01 EUR.
- **B4:** Customer-visible activation a backfill otevřených EUR payment info.
- **B5:** Jednotlivé historické pairing mutations, commit, push a cherry-pick.

## Deletion and retention ledger

| Artifact | Final action | Proof |
|---|---|---|
| Inline matcher v `insert_transactions` | Delete | focused source search + Fio fixture reaches canonical matcher |
| Inline matcher a fuzzy ±3-day dedupe v `process_email_transaction` | Delete | absence search + equal-payment regression |
| Fio e-mail `ID pokynu` → `transaction_id` mapping | Replace with `command_id` | parser contract fixture |
| Direct aggregation in `add_transaction_to_payment_info` | Delete after call-site migration | no old function definition/calls in active source/migration |
| Arithmetic unlink in `remove_transaction_from_payment_info_ws` | Delete; wrapper delegates | search has no `paid = paid - ...`/placeholder branch |
| Arithmetic delete in `delete_manual_transaction_ws` | Delete; canonical unlink then delete | audit + recalculation test |
| Manual insert inline VS lookup | Delete; explicit target is validated or matcher is called | call graph/search |
| PUBLIC/anon/auth EXECUTE on internal helpers/importers/matcher | Revoke | `has_function_privilege` tests and live post-check |
| Raw direct update of `transactions.payment_info` | Keep only inside canonical owner | repository-wide writer search |
| `payment_qr.spd` and `PaymentQrCard.spd` | Delete/rename to `format/payload`; no fallback | final `rg` has no active `spd` contract reader |
| Currency-blind `generateSpdString` public helper | Replace by routed pure encoders | encoder tests + absence search |
| Duplicate payment presentation in templates | Replace by shared presenter | all four templates import same helper |
| Temporary pilot flag/config/version alias | Do not create; remove if implementation introduces one | absence search |
| CZK VS/SPD | Intentionally retain external boundary | CZK regression snapshot |
| Strict labelled/full-message legacy VS rule | Intentionally retain bounded boundary | positive + false-positive tests |
| Closed historical EUR rows without RF | Intentionally retain NULL | scoped post-check |

## Implementation waves

### Wave 0 — Freeze the real contract and create red-capable tests

**Invariant gained:** implementation starts from the actual baseline/client-sync
topology and every later cutover has an owning regression seam.

**Changes**

- Read this plan first, then create a clean isolated worktree and record SHA.
  Pokud plán není součástí base commitu, přenes pouze tento plán a jeho execution
  prompt; nekopíruj žádné jiné dirty user files.
- Read `docs/architecture/ai_context.md`, `lib/components/eshop/README.md`,
  `lib/components/bank_accounts/README.md`, `docs/backend/edge_functions.md` and
  current migration-layout rules.
- Confirm active definitions/signatures for order writer, five pairing mutation
  paths, two importers and both unlink RPCs from baseline/source. If evidence
  differs, update this plan before implementation.
- Add one focused SQL suite under
  `database/tests/eshop/transactions/payment_pairing_contract_test.sql` covering
  matcher + mutation invariants, and focused Deno/parser/QR tests in the nearest
  existing test locations.
- Required red-capable fixtures: VS NULL + full-message symbol; duplicate VS;
  conflicting VS/RF; wrong account/currency; outgoing/zero; malformed RF;
  unlabelled numeric prose false-positive; replay/concurrency; manual attach,
  unlink and delete; two identical legitimate payments; email-first/API-second.

**Validation**

- `bash automation/tests/migration_layout.test.sh`
- run the new focused SQL test through the repository's current DB test runner
  against a disposable database. Before code it must fail for the intended
  assertion, not because setup/function is missing.

**Exit condition:** evidence table is current and tests identify every mutation
entry point and original failure without relying on live data.

### Wave 1 — Additive schema, provider identity and EPC account prerequisites

**Invariant gained:** schema can represent RF, raw bank reference, safe source
identity, creditor name and durable audit without changing customer behavior.

**Changes**

- Add to `database/tables/tables.sql` and the first, foundation forward migration:
  `payment_info.creditor_reference`, `transactions.payer_reference`,
  `transactions.ingest_source`, `bank_accounts.creditor_name`, pairing audit
  table and scoped indexes/checks.
- Migrace přidá `ingest_source` nejprve nullable, provede explicitní bounded
  backfill na `manual` / `email` / `api` / `legacy`, nastaví default pro nové
  canonical writers a teprve potom `SET NOT NULL`. Nezanechá nullable mezistav.
- Add pure immutable SQL helpers for RF canonicalization, MOD 97 validation and
  generation. CHECK validates canonical uppercase/no-space stored RF; unique
  partial index enforces non-null uniqueness.
- Backfill only unambiguous `ingest_source` metadata from existing mechanical
  facts (`manual` transaction type, non-null external email ID, API movement ID).
  Unknown stays explicit `legacy`, not guessed.
- Run read-only duplicates queries before unique indexes. Do not make
  `(command_id)` unique until A1 and live cardinality are confirmed.
- Extend bank-account management read/write RPC, Dart model/UI and strings with
  `creditor_name`. Replace the existing `update_bank_account` signature
  atomically; do not leave an overloaded old signature. The new optional named
  argument preserves old client calls, while activation requires its value.
  Reapply the existing intended owner/grants explicitly after drop/recreate and
  add a `pg_proc` assertion that exactly one `update_bank_account` overload
  remains.
- Define RLS/grants for audit and new fields. `creditor_reference` is writable
  only by controlled SQL writer/backfill; `creditor_name` only by bank admin.

**Migration/deletion:** no RF backfill, no pairing, no production activation.

**Failure/compatibility:** malformed raw payer reference is stored but cannot
match. Schema fields remain nullable. Migration raises on unsafe duplicate
assumptions rather than silently discarding rows.

**Validation:** RF vectors/round-trip/checksum/length/index tests; bank-admin
authorization tests; old named `update_bank_account` call without new optional
arg still resolves; migration-layout test.

**Exit condition:** a local clean database stores and validates all new facts,
while newly created orders still behave exactly as before.

### Wave 2 — Canonical pairing mutation refactor

**Invariant gained:** exactly one SQL owner changes pairing state, aggregates,
order status and audit.

**Changes**

- Implement `apply_transaction_pairing` per target contract.
- Recalculate aggregates from rows after every attach/unlink; do not preserve
  incremental subtraction branches.
- Migrate `add_transaction_to_payment_info_ws`, `insert_manual_transaction`,
  `remove_transaction_from_payment_info_ws` and
  `delete_manual_transaction_ws` to thin authorized wrappers.
- Manual insert with explicit payment-info ID validates target via canonical
  owner. Pro zachování veřejného kontraktu může wrapper bez explicitního ID
  rozpoznat VS pouze v rámci zadaného unit + měny a pokračuje jen při právě
  jednom kandidátovi; nikdy nepoužije `LIMIT 1`. Samotnou vazbu, agregace a audit
  stále provede výhradně canonical owner.
- Delete-manual flow: authorize, canonical unlink + audit, assert type `manual`,
  delete row, preserve audit snapshot.
- Remove old `add_transaction_to_payment_info` implementation and migrate
  repository tests/callers to the canonical owner/wrappers.
- Revoke internal function grants; explicitly preserve only authorized public
  wrapper grants.

**Failure/compatibility:** deterministic row-lock order prevents deadlocks when
moving between payment infos. Idempotent same-target attach makes no duplicate
audit event. Expected business errors have stable codes; wrappers do not catch
all errors and relabel authorization failures as HTTP 500 JSON.

**Validation:** focused attach/move/unlink/delete/concurrency/security tests plus
existing manual transaction, deposit, overpayment and revert scenarios.

**Exit condition:** repository-wide writer search shows one active
`SET payment_info` owner and no incremental paid/returned mutation in wrappers.

### Wave 3 — Canonical ingest, reconciliation and matcher cutover

**Invariant gained:** both bank channels store provider-correct identities and
reach one automatic decision owner without fuzzy loss or double counting.

**Changes**

- Update Fio API mapping: column22 → movement `transaction_id`, column17 →
  `command_id`, column27 raw → `payer_reference`; retain columns 7/16/25.
- Update `ParsedTransaction` to expose `ingestSource`, `movementId`,
  `bankCommandId`, `externalId` and optional `payerReference`. Fio email
  `ID pokynu` maps only to `bankCommandId`.
- Make both SQL importers call one ingest/reconciliation helper or share exactly
  the same conflict rules. Remove fuzzy time-window dedupe.
- Reconcile a provisional email row only when provider contract proves a shared
  ID with equal account/currency/amount and no competing row. Conflict returns
  explicit error/ambiguous state and changes neither existing row nor pairing.
- Implement matcher rules and call canonical mutation owner for `paired` only.
- `insert_transactions` returns per-item `{source_id, stored_id, ingest_status,
  match_verdict, reason}` plus summary. Expected unmatched/ambiguous does not
  fail ingestion. Unexpected errors rollback that item subtransaction and are
  returned/logged explicitly, never swallowed as `NOTICE`.
- `process_email_transaction` returns the same normalized result shape.

**Deletion:** delete both inline matchers, Fio-email semantic ID mismatch and
all fuzzy dedupe branches.

**Validation:** Fio `column27` fixture; Fio-email ID mapping fixture; both import
orders; equal legitimate payments; transport replay; email/API reconciliation;
unverified email identity remains unpaired; matcher positive/negative matrix;
ACL tests.

**Exit condition:** both importers have identical verdict semantics, one payment
adds to `paid` once under all replay orders, and absence searches satisfy ledger.

### Wave 4 — RF writer and one customer presentation contract, locally only

**Invariant gained:** complete code is ready for pilot, but production customers
still have not been activated.

**Changes**

- In `create_ticket_order_internal_v1`, insert payment info, obtain ID, generate
  RF for bank EUR, update it exactly once and include it in `order.payment_info`.
- If EUR account lacks valid creditor name/IBAN or RF generation fails, raise a
  stable error and roll back the order.
- Put the writer replacement in the second, activation forward migration and
  keep its behavior identical to the final source SQL. Do not include data
  backfill in this migration.
- Implement pure `buildSpdPayload`, `buildEpcSctPayload` and shared payment
  presenter. Validate EPC byte/field limits and structured-only remittance.
- Route confirmation/update/reminder/paid through the presenter. Amount passed
  to QR is the same amount due shown in text (deposit/balance/full).
- Add `order.payment_qr = {format, payload, ...human fields}` to the real order
  response producer. Update Flutter to read only `format/payload`, rename widget
  property, display/copy RF, and remove `spd` assumptions in the same wave.
- If `web_client` actually consumes the order response in the targeted tenant,
  render payment fields with DOM text nodes/`textContent`; otherwise record it
  as verified non-consumer, do not invent dead UI.
- Update shared translations via repository commands.

**Compatibility:** old closed EUR order without RF displays legacy VS details
and must not synthesize RF. New activated EUR order cannot degrade to EUR SPD or
EPC without reference. CZK remains unchanged.

**Validation:** create-order SQL contract through public wrapper and replay;
known EPC payload lines + independent decoder/parser fixture; CZK SPD snapshot;
all four template scenarios including deposit/balance; Flutter public result
test; web test only if consumer exists.

**Exit condition:** locally, new EUR order has the same RF in DB, response,
email text and EPC payload; CZK regression is unchanged; no `payment_qr.spd`
reader remains.

### Wave 5 — Standard local proof and deployable artifact boundary

**Invariant gained:** implementation is complete without requiring production
authority.

**Changes**

- Run one targeted standard batch covering SQL, Deno, Flutter/web and migration
  layout. Then run `./automation/test_all.sh` only if required by current
  pre-production workflow or immediately before an authorized rollout.
- Run final reachability and absence searches from deletion ledger.
- Produce a sanitized preflight SQL script that only reports counts/reason codes
  and a separate explicit-ID operations script; neither runs automatically.
- Update `docs/setup/bank_import.md` (create if genuinely absent and consistent
  with repo docs) with identity mapping, verdicts, manual handling and rollout.

**Exit condition:** local handoff can name the one matcher, one mutation owner,
all migrated callers, exact test results and all still-unapplied operational
steps. No production action is implied.

## Authorized rollout runbook (not part of local implementation authority)

### P0 — Resolve target and revalidate live state

1. Resolve project from `automation/project.conf` and verify configured occasion.
2. Compare live function signatures/definitions and migration state with source.
3. Re-run duplicate/cardinality/ACL/RF/EUR-account preflight read-only.
4. Fill and verify `creditor_name` only through an authorized bank-admin action.
5. Stop on target mismatch, unknown applied migration, duplicate provider IDs or
   missing EPC prerequisites.

### P1 — Deploy safe backend expansion/cutover without customer RF activation

Deploy schema, ACL, provider identity, canonical mutation owner, matcher and raw
import changes. Do not yet deploy/enable the order writer/customer presenter if
release packaging cannot separate it safely. Observe importer results and
confirm no duplicate paid increments.

### P2 — Pilot gate

1. Create one controlled payment info/reference without exposing RF globally.
2. Send approved Slovak SEPA 0,01 EUR using EPC structured RF.
3. Capture only sanitized Fio field structure.
4. Verify one stored movement, one matcher target, one audit event and exactly
   +0,01 EUR aggregate.
5. Add the anonymized real fixture to tests. If RF is missing/transformed or ID
   mapping differs, update this plan/source and do not activate P3.

### P3 — Customer-visible activation and bounded RF backfill

Deploy order writer, Edge templates and target clients as one coordinated
release. Backfill only explicitly selected open EUR payment-info rows with valid
account prerequisites, after count snapshot and within a transaction that aborts
on any collision/invalid row. Never backfill closed orders or rewrite RF.

### P4 — Historical resolution and final branch alignment

Run dry-run again. After organizer approval, invoke canonical manual pairing for
only listed transaction IDs, one by one, and verify aggregate/state after each.
Cherry-pick the same tenant-neutral commits to `prod/hvezdamorska` and
`prod/csmostrava2026` only after approval. Deploy shared DB once, not per branch.

## Rollback limits

- Before P3, disable new auto-match calls if necessary while retaining raw
  observations, restrictive ACL and canonical manual mutation.
- After P3, rollback may stop issuing new RF/customer QR, but existing RF and
  audit remain. Matcher continues accepting issued RF.
- Rollback never restores fuzzy dedupe, inline matcher, public internal grants,
  arithmetic unlink or `payment_qr.spd` dead contract.
- Schema/data removal is not a hot rollback. Use a separately reviewed forward
  contraction only after all readers are proven absent.

## Verification matrix

| Risk/invariant | Stable seam | Required proof |
|---|---|---|
| RF checksum/length/uniqueness | pure SQL helpers + constraints | official vectors, mutation, bigint round-trip, collision |
| RF immutability | writer/ACL | unauthorized update denied; retry returns same value |
| Provider ID semantics | parser + ingest fixture | column22/17/27 and Fio email ID mapping |
| No fuzzy data loss | ingest reconciliation | two equal payments both persist; no ±date query |
| Cross-channel idempotence | email/API integration | shared provider ID results in one accounting movement/effect |
| All mutation paths canonical | SQL call graph/search | one `SET payment_info`, wrappers delegate |
| Aggregate correctness | mutation owner | attach/move/unlink/delete/replay recalculates from rows |
| Concurrency | DB integration | concurrent matcher/attach yields one link/audit increment |
| Ambiguity safety | matcher matrix | duplicate/cross-signal conflict changes nothing |
| Account/currency/direction | matcher matrix | all negative cases remain unpaired |
| Authorization | privilege + actor tests | anon/auth denied internals; valid wrappers allowed |
| EPC compliance | pure encoder | mandatory name/IBAN/EUR/reference, limits, structured xor text |
| CZK compatibility | pure encoder/template | stable SPD fields incl. X-VS |
| Customer consistency | order/template/UI contracts | identical RF and amount due everywhere |
| Cutover absence | focused `rg` + DB ACL observation | every deletion-ledger item proven |
| Production state | authorized post-check | functions/deploy ACTIVE, data invariants and source hash |

Suggested final focused commands (adapt exact test paths created by the change):

```bash
bash automation/tests/migration_layout.test.sh
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/eshop/transactions/payment_pairing_contract_test.sql
deno test supabase/functions/bank-mail-parser supabase/functions/_shared
fvm flutter test test/components/forms test/components/bank_accounts test/components/eshop
cd web_client && npm test
```

Do not blindly run a directory command if the repository runner does not accept
it; select the concrete new/existing files and record the exact invocation.

## Definition of complete

- [ ] Every automatic entry point reaches `match_bank_transaction`.
- [ ] Every attach/unlink/delete-manual entry point reaches
      `apply_transaction_pairing`.
- [ ] Only the canonical owner writes `transactions.payment_info` and derived
      aggregates.
- [ ] Inline matchers, fuzzy dedupe, semantic ID mismatch, arithmetic unlink,
      swallowed pairing errors and dead placeholder code are removed.
- [ ] Internal RPC grants deny PUBLIC/anon/auth; public wrappers retain explicit
      permission checks.
- [ ] New activated bank EUR orders have immutable valid RF and EPC-ready
      creditor data.
- [ ] Fio `column27`, column22 and column17 are persisted with correct semantics.
- [ ] Unverified email observations cannot be automatically double-counted.
- [ ] Matcher rejects ambiguity, conflict, wrong account/currency, invalid
      reference and non-positive amount.
- [ ] Automatic/manual link changes and manual deletion are atomically audited.
- [ ] EUR text/QR/UI use the same RF/amount; CZK remains VS/SPD.
- [ ] No active `payment_qr.spd`, parallel template logic, V1/V2 compatibility
      alias, temporary flag or obsolete grants remain.
- [ ] No historical transaction was bulk-paired; every changed ID was approved.
- [ ] Standard validation passes and production/pilot state is either verified
      complete or explicitly listed as unapplied.
- [ ] Shared backend was deployed once and both approved tenant branches contain
      the same neutral commits, if rollout authority was granted.

## Residual risks

- A payer bank may not preserve RF. The pilot decides activation for the target
  account; strict legacy VS/manual review remains the bounded fallback.
- Some bank e-mails may not carry a provider-stable identity. Those messages
  cannot be safely auto-reconciled and intentionally remain unpaired rather than
  risk double counting.
- Historic VS collisions cannot be retroactively made unique. They remain
  ambiguous; RF fixes newly issued identity only.
- Account-holder naming and supported EPC character set require real bank-admin
  data. The system must fail closed instead of inventing a name.
- Partial-payment notification policy is unchanged and remains a separate
  product decision.
