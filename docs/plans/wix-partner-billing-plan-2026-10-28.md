# Dokončení Wix Partner Billed aplikace

Datum: 2026-10-28
Stav: lokální účetní zdroj a dispatcher implementovány; skutečná účetní data, smlouva a produkční rollout nejsou hotové
Ověřování: standard; při vydání navíc všechny povinné release gates repozitáře

## Průběh realizace 2026-10-28

Aktuální [výsledek a blokery](wix-partner-billing-RESULT-2026-10-28.md) a
strojová evidence `integrations/wix/evidence/partner-billing-execution-20261028.json`
navazují na tento plán. Uživatel během realizace výslovně uložil navrhnout a
umístit chybějící servisní vyúčtování do obecné architektury a DB. Proto nově
vznikl jeden kanonický zdroj `public.service_fee_*`, nikoli odhad příjmů z objednávek
ani druhý Wix ledger. Jeho servisní import vyžaduje skutečné smluvní, platební
a akviziční podklady; žádné nebyly vymyšleny nebo vloženy do produkce.

Původní tvrzení, že není implementován účetní zdroj ani dispatcher, je nahrazeno
lokální implementací a projitými PostgreSQL/executor testy. Původní zjištění, že
není napojen skutečný účetní feed a chybí obchodní dokončení, stále platí.
Produkční read-only kontrola potvrdila nepřítomnost obou nových migrací a tabulek.

## Výsledek a rozsah

Dokončit skutečně integrovanou aplikaci vstupenky.online ve Wix App Marketu.
Instalace nemá vlastní předplatné; individuální servisní procento určuje smlouva
s pořadatelem. Wix dostává report pouze z našich skutečných servisních příjmů
pocházejících z Wixu, nikoli z nominální ceny vstupenek nebo prostředků pořadatelů.
Výsledkem má být ověřená produkční integrace, provozuschopný reporting a doložený
stav marketplace schválení. Odeslání ke schválení není schválení ani publikace.

V rozsahu jsou existující Wix widget, ověření původu, export servisních příjmů,
doručení billing událostí, smluvní dokončení a rollout pouze prod/festapptickets.
Mimo rozsah jsou ostatní tenanty, nový kupující checkout, změna Stripe modelu,
obecný fakturační produkt a placená registrace či placené testovací služby.

## Autoritativní stav a důkazy

| Fakt | Důkaz / vlastník | Důsledek |
| --- | --- | --- |
| Erel potvrdil fee-only základ, externí checkout a nulové samostatné publisher poplatky | Gmail 1a1825fe56ce9706, thread 1a18198a75444077; integrations/wix/evidence/commercial-clarification-20261028.json | Otázku základu provize znovu neotvírat bez nové protichůdné informace |
| Vyloučeni jsou stávající zákazníci, kteří nepřišli přes Wix; refundace patří původní instalaci | Stejný e-mail | Původ objednávky sám nedokazuje akvizici zákazníka |
| Dodatek není podepsán a označuje partnera jako corporation | integrations/wix/evidence/addendum-review-20261028.json | Michael Bujnovský, IČO 06455361, je OSVČ; nepodepisovat nepravdivé označení |
| Dotaz na správné označení OSVČ již odeslán | Gmail 1a18267de29c3241 ve stejném threadu | Nejprve zkontrolovat odpověď; nevytvářet duplicitní případ |
| Účet info@festapp.net ověřen, native unlisted 1.1 vydáno | commercial-clarification a minor-release-20261028.json | Není to veřejná marketplace publikace |
| Draft pricing je DYNAMIC s Custom plánem | integrations/wix/evidence/pricing-20261028.json | Žádná sazba ani nové předplatné nebyly vytvořeny; external billing activation není doložena |
| Původ je implementován a lokálně otestován | integrations/wix/billing/CHECKOUT-ORIGIN.md, evidence/checkout-origin-20261028.json | Backend, migrace, nový widget ani nový veřejný klient zatím nejsou nasazeny |
| CSV a API mají jednu projekci skutečných servisních příjmů | integrations/wix/reporting/prepare.mjs; billing/approval.mjs | Nejde o účetní zdroj ani o hotový dispatcher |
| Pracovní strom main obsahuje i cizí rozpracované změny | git status a git diff při zahájení | Nevzít do releasu Make, admin MCP ani nesouvisející Flutter změny |

Dřívější COMPLETION-PLAN-20261026.md a jeho execution soubor zůstávají historií
checkout/browser kvalifikace. Tento plán vlastní zbývající Partner Billed práci.
Historické důkazy nepřepisovat na nové úspěchy. Soukromý dodatek je v ignorované
integrations/wix/.private/, žádné tokeny ani osobní údaje nepřidávat do commitu.

## Vlastnictví a invarianty

1. Ceny, objednávky a peníze kupujících vlastní stávající SQL/payment hranice.
   public.create_ticket_order_command_internal je jediný změněný order command;
   nepřidávat druhý checkout ani persistentní aplikační trigger.
2. Wix token ověřuje _shared/wix/identity.ts přes token-info. SQL vydá 24hodinový
   podpis vázaný na formulář a nakonfigurovaný tenant. Podpis neuděluje oprávnění.
   eshop.order_checkout_origins se zapíše ve stejné transakci jako objednávka.
3. Pending identita nákupu ignoruje obnovitelný důkaz při fingerprintu, ale uchová
   původní důkaz pro přesný replay. Zachovat opravu v ticket_order_identity.js
   a DbOrders. Při blokovaném storage je záruka paměťová jen v rámci stránky.
4. Účetní zdroj vlastní sazbu smlouvy, skutečně uhrazený servisní příjem, daň,
   refundaci a akviziční důkaz. Export je adaptér tohoto zdroje, nikoli druhá kniha.
   Bez doloženého zdroje nevypočítávat naše příjmy ze zaplacených vstupenek.
5. reporting/prepare.mjs je jediná USD projekce CSV/API. Používá přesná celá čísla,
   historický kurz/sazbu a kumulativní refundace. billing/approval.mjs je jeden
   společný approval gate pro přípravu reportu i release kontrolu.
6. Dispatcher vlastní pouze doručení odvozených událostí. Trvalý delivery journal
   není ekonomický ledger. Neznámý výsledek není neúspěch a nesmí se slepě opakovat.
7. Žádná výchozí sazba pořadatele. Každý charge má organizerAgreementReference,
   organizerFeeRateBps, customerOrigin=wix a customerOriginEvidenceReference.

## Rozhodnutí, předpoklady a blokery

- Rozhodnutí uživatele: sazba individuálně podle smlouvy; žádný jednorázový
  publisher poplatek. Nulové fixní náklady dovolují pokračovat ve vydání.
- Chybějící fakt: autoritativní zdroj skutečně uhrazených servisních příjmů a
  akvizice zákazníka při zahájení neexistoval v nalezených repo hranicích.
  Nový obecný zdroj je implementován podle následného pokynu uživatele, ale
  konkrétní účetní feed, úhrady a akviziční podklady nejsou připojené. Není oprávněním
  vymyslet sazbu, zákazníka nebo účetní pohyb.
- Externí blokery: správný dodatek pro OSVČ, jeho dokončení, ověřená aktivace
  Partner Billed a rozhodnutí Wixu o marketplace. Jejich stav znovu přečíst.
- Předpoklad: dosavadní písemné obchodní potvrzení stále platí. Pokud nová smlouva
  zavádí širší základ nebo placený závazek, nepokračovat v tomto závazku a uvést
  přesný rozpor; ostatní nezávislou implementaci dokončit.

## Vlny provedení

### 1. Uzavřít původ skutečných účetních dat

Přečíst tento plán, CLAUDE.md, docs/architecture/ai_context.md a relevantní
AGENTS.md. Inventarizovat pouze Wix diff a aktuální evidence; nepřepisovat cizí
práci. Zkontrolovat poslední odpověď ve stávajícím Gmail threadu.

Vyhledat existující vlastníky přes database/functions/authoring/finance.sql,
napojené účetní exporty a jejich volající; název finance sám není důkazem ledgeru
našich poplatků. Vybrat existující prokazatelný zdroj plateb našich faktur/poplatků,
refundací, historických smluv a akvizice. Pokud je externí, připojit úzký export
s trvalými sourceReference. Definovat deterministickou alokaci k původním
objednávkám/instalacím; nejednoznačné položky zadržet, nepřiřazovat odhadem.

Pokud žádný zdroj neexistuje, zaznamenat přesně chybějící údaje a položit jednu
konkrétní otázku na jejich skutečné umístění. Samotný procentní ceník nestačí.
Pokračovat mezitím nezávislým dispatcherem a testovacími fixtures.

Výstup: doložený zdroj a exportní kontrakt, nebo přesný účetní blocker.
Validace: syntetické charge/partial/full refund z projitého adaptéru do jediné
projekce; non-Wix/stávající zákazník a ticket face value se do exportu nedostanou.
Žádné reálné účtování ani reportování syntetických fixtures.

### 2. Doručení a reconciliation

Nejprve ověřit aktuální oficiální Wix API dokumentaci: app-instance-scoped OAuth,
request/response External Billing Events a případnou podporu idempotence či
reconciliation. Současné důkazy nedokládají business idempotency key; nevymýšlet ho.
Použít stávající backend secret/runtime mechanismus, nikdy browser nebo commit.

Přidat úzký serverový dispatcher nad neměnnou projekcí prepare.mjs. Pokud Deno
nemůže použít Node modul přímo, oddělit pouze čistou projekci od digest/filesystem
adaptéru; nevytvářet druhou implementaci výpočtů. Delivery journal drží stabilní
receipt identity + druh události, payload digest, cílovou instalaci, pokusy a
potvrzení. Atomic claim zabrání souběžnému odeslání. Rozlišovat připraveno,
probíhající pokus, potvrzeno, definitivně odmítnuto a neznámý výsledek. Pád procesu
po odeslání řešit jako neznámý výsledek. Rozpor digestu pod stejným klíčem odmítnout.
Timeout ani 5xx automaticky neopakovat bez doložené idempotence nebo reconciliation.

Migrace a funkce autorsky patří do kanonického database SQL; žádný trigger ani
reálný dispatch při pouhém generování CSV. Žádná aktivace automatického odesílání
před schválenými podmínkami a připojeným skutečným zdrojem.

Výstup: ověřený dispatcher a operátorská cesta pro unknown outcomes.
Validace přes skutečný executor s falešným providerem: souběh, response decoding,
commit-before-response-loss, restart, autentizace jiné instalace a refundace.

### 3. Dokončit obchodní a native stav

Přečíst odpověď na OSVČ ve stávajícím threadu a porovnat skutečný dodatek s již
potvrzeným fee-only základem. Dokončit pouze pravdivé údaje a kroky v dříve
uděleném oprávnění; nevydávat e-mailové potvrzení za podpis. Nový placený nebo
materiálně odlišný právní závazek vyžaduje konkrétní rozhodnutí uživatele.

Ověřit Custom plán, external billing activation, příslušná oprávnění, privacy,
podporu a testovací přístup. Nedoplňovat fiktivní sazbu. Skutečné release inputs
musí odkazovat na existující důkazy; neuvolňovat check-release.mjs kvůli blockerům.

Výstup: pravdivý nativní stav a dokončené podmínky nebo konkrétní externí blocker.

### 4. Koordinované nasazení a marketplace

Před publikací izolovat vlastní validovaný diff od cizí práce a ověřit aktuální
main/tenant ancestry. Publikovat do autoritativní větve podle pravidel repozitáře;
nevytvářet mezikrokový PR, pokud ho nevyžadují pravidla. Migrace
20261028140000_wix_checkout_origin.sql je zatím neaplikovaná; zkontrolovat ledger,
aktuální definici order commandu a případný souběžný vývoj před jejím provedením.

Pořadí: kompatibilní DB expanze -> backend s proof route -> veřejný klient
prod/festapptickets -> závislý Wix widget. Klient musí být na produkci před widgetem,
aby podepsaný kontext skutečně předal dál. Funkční endpoint musí existovat před
widgetem; nový bundle při chybě ověření checkout záměrně nezpřístupní.

Použít festapp-backend-access skill a chráněný Functions restart: pause/drain
emailů, restart-production-functions.py, probe workeru, resume a delivery health.
Nerecreatovat kontejner částečným compose. Web sestavit lokálně a nasadit přes
automation/deploy_direct.sh, nikoli GitHub-hosted build. Rutinní deploy a monitoring
delegovat levnějšímu agentovi podle AGENTS.md s přesnými revizemi a gates.

Veřejnou produkci ověřovat read-only. Celý order/charge/refund scénář nejprve
prokázat na disposable datech, včetně obnovy důkazu při ztracené odpovědi, více
widgetů a zachování kontextu v přímém odkazu. Žádné produkční nákupy, holdy nebo
syntetické billing události bez samostatného oprávnění. Aktuální SDK token-info
seam je lokálně mockovaný; ověřit reálný Wix host token bez zveřejnění tokenu.

Teprve po splnění gates odeslat marketplace submission a uložit native receipt.
Review pending je nedokončený externí stav. Verzi ani schválení neodhadovat.

## Ověřování a známé limity

Dosavadní výsledky: 28 Wix testů + build/package; 77 Edge testů; 13 web testů;
čerstvá disposable DB migrace + origin test a 2 existující DB regrese. Čísla jsou
historická evidence pro tehdejší vstupy, nikoli automaticky platná po nové změně.

Relevantní příkazy z rootu, JS přes pnpm 11.24.0:

- pnpm --dir integrations/wix test; build/package až po finálním bundle diffu.
- pnpm --dir web_client exec node --test tests/forms/ticket_order_identity.test.js
  tests/components/db_orders_command_identity.test.js tests/core/checkout_origin.test.js
  tests/forms/order_result_reservation.test.js (jeden příkaz).
- deno test --allow-env --allow-read --allow-net supabase/functions/_shared/wix/identity_test.ts
  supabase/functions/wix-checkout-context/handler_test.ts
  supabase/functions/_shared/edgeEntrypoints_test.ts; přizpůsobit repository Deno configu.
- node automation/hetzner-supabase/merge/edge-function-test-coverage.mjs.
- Disposable DB: automation/bootstrap_local_db.sh s vlastním workdir/project/port;
  node web_client/scripts/run_db_tests.js checkout_origin_test.sql
  client_sync_v1_runtime_test.sql eshop/stripe/create_order_test.sql s lokálním DATABASE_URL.

Plný policy suite dříve selhal kvůli chybějícímu occasion-lifecycle záznamu inventory
už v baseline. Neprohlašovat celý gate za zelený; před release znovu určit aktuální
stav a vyřešit ho s vlastníkem. Neopakovat nezměněné passing testy bez důvodu.
Flutter nespouštět pro samotný widget; při povinném tenant buildu dodržet jediný
Flutter proces na workstation. Nedotýkat se cizích Supabase projektů nebo fixture dat.

## Retence, odstranění a rollback

- Zachovat historické 20261026 browser důkazy, ale nové pokračování směrovat sem.
- Odstranit pouze případné nové duplicitní výpočty/ad hoc odesílače; prokázat rg
  volajících a jedním approval/projection kontraktem. Existující druhý ledger nenalezen.
- Podpis v URL je krátkodobý důkaz původu, nikoli credential. Nesmí být uložen do
  order.data ani public logs; pending browser command ho drží jen do terminálního
  výsledku. Historické účetní podklady a doručovací receipts zachovat.
- Při neúspěšném rolloutu nejprve vrátit závislý widget na poslední funkční bundle.
  DB expanzi nerušit za provozu; zachovat původ, pending replay a potvrzené události.
  Nezapnout nepodepsaný fallback jako trvalý druhý billing režim.

## Dokončeno teprve když

- Skutečná smluvní sazba a settled fee source jsou napojeny a akvizice doložena.
- Charge/refund mají jeden výpočet, bezpečný dispatch a ověřitelnou reconciliation.
- Dodatek/activation i publisher fees jsou skutečně dokončené a doložené.
- DB/backend/klient/widget jsou na správných produkčních revizích a fungují spolu.
- Marketplace skutečně publikuje aplikaci; pending review zůstává blocker.
- Evidence uvádí aplikované migrace, revize, přesné testy a zbylé externí limity.
