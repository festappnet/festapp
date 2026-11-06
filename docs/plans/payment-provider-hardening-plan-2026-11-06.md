# Dotažení platebních konektorů a společné autority plateb

Datum: 2026-11-06  
Stav: Lokální vlny 0-3 implementované a ověřené; vlna 4 implementovaná v omezeném sandboxovém rozsahu s reálnými důkazy; vlna 5 lokálně ověřená  
Ověřování při realizaci: `standard` - finance, oprávnění, souběh a veřejné kontrakty  
Výchozí stav: `main`, HEAD `a31277e3c3d761ed37d6425a1f2a731584b92e8d` plus současný necommitnutý refaktor  
Nezávislá architektonická kontrola: `gpt-6-astra`, reasoning `medium`, seniorní architekt, read-only; kontrola kódu i následná adversarial kontrola tohoto plánu, materiální připomínky zapracovány

## Stav realizace

Uživatel 2026-11-06 výslovně pověřil lokální realizací. Výsledek, konkrétní brány,
změny předpokladů, digesty a deletion ledger jsou v
[podrobném receipt](payment-provider-hardening/RESULT-2026-11-06.md).
Navazující [architektonické doplnění recovery](payment-provider-hardening/FOLLOWUP-2026-11-06.md)
odstraňuje vazbu finanční obnovy na údržbu účtu a doplňuje scope/budget guard.
Druhý skutečný adaptér má ověřený sandboxový tok platby, refundu a expirace přes
společného SQL ownera; viz [navazující výsledek](payment-provider-hardening/BARION-INTEGRATION-RESULT-2026-11-06.md).
Produkční rollout, úplný chargeback/reversal kontrakt a E1/E2 zůstávají uzavřené.
Závěrečné původní formulace o pověření k samotnému plánování jsou historickým
rozsahem vzniku plánu; nové pověření pokrývá místní implementaci, nikoli produkci.

## Výsledek a rozsah

Stripe i další poskytovatel používají stejná pravidla pro objednávky, vstupenky,
ochranu opakování a předání ověřených platebních skutečností. Adaptér vlastní
protokol poskytovatele. Nesmí kopírovat obchodní rozhodování o platnosti vstupenek.
Nejistý výsledek vzdálené operace nesmí způsobit novou platbu ani předstírané
potvrzení, že platba neexistuje. Přidání poskytovatele nesmí změnit bankovní
platby nebo nastavení jiného poskytovatele.

Plán zahrnuje SQL, Edge Functions, Flutter, webový formulář, obnovu plateb,
kompatibilitu vydaných odkazů, migrační cestu a ověření druhým skutečným
sandboxovým adaptérem. Součástí je vymezení vazby na existující evidenci provizí.

Nepatří sem nový účetní ledger, přesun všech Stripe tabulek do generického
schématu, košík s více pořadateli, automatické výplaty, zavedení záloh/příplatků,
libovolné měny, nové autorizační/capture režimy ani automatické účtování 4 %.
Skutečný výběr a rozdělování platformní provize je navazující produktová funkce
s vlastními vstupními podmínkami uvedenými níže. Připravenost konektorů sama
neznamená připravenost marketplace produktu k ostrému provozu.

## Ověřené skutečnosti a rozhodnutí z kontroly Astra Medium

| Fakt v aktuálním kódu | Důsledek pro tento plán |
|---|---|
| `payment_providers/registry.sql: form_payment_availability_internal` přebírá root prvního poskytovatele podle abecedy a sjednocuje jeho `available`. Bankovní volbu a `reservationSeconds=1860` vytváří Stripe availability. | Banku a společná pole musí vlastnit společný modul, včetně varianty bez online konektoru. |
| `provider_unit_public_fields_internal` a `provider_form_editor_fields_internal` slučují cizí JSON do stejného rootu. | Data poskytovatelů oddělit podle ID; historická pole odvozovat pouze explicitním Stripe adaptérem. |
| `payments/contracts.ts: PaymentStore` vrací převážně `unknown`; `checkout.ts` čte `sessionId`, `sessionLookupCursor` a `refundCursor`. | Dekódovat výstupy na adaptéru; společný interface nesmí předepisovat Stripe stránkování. |
| `checkout.ts: recoverPaymentClaim` po vyčerpání hledání vytváří `noCheckoutVerified`. | Prázdné hledání může znamenat definitivní absenci jen s ověřenou zárukou daného protokolu. |
| `eshop_stripe/ingest.sql: ingest_stripe_payment_internal` přímo mění `storno/expired`, vstupenky a emailové verze. | Předchozí dokumentace nadhodnocovala společného ownera. Extrahovat společné uplatnění finančních důsledků. |
| `payment_providers/schema.sql: payment_info_provider_instructions` zakazuje zálohu pro všechny nebankovní metody; editor také zakazuje zálohy/příplatky a zobrazuje 1860 sekund. | Pouhé přidání UI capability by slibovalo něco, co SQL nepovoluje. Omezení zatím zachovat, jednotně projektovat ze serveru. |
| `occasion_setup_page.dart: _setupProvider` vybírá při neznámém ID první adaptér; hodnota `both` ztrácí identitu brány. | Ukládat bankovní volbu a poskytovatele nezávisle. Neznámá konfigurace vyžaduje opravu, nikoli náhradní Stripe. |
| `stripe-reconcile/index.ts` a `eshop_stripe/reconciliation.sql: request_stripe_reconciliation` vlastní jediný provozní vstup obnovy. | Zajistit obecný autorizovaný provozní vstup a explicitní registraci úloh. |
| `stripe/provider.ts` již používá 15sekundový timeout. | Nejde o absenci timeoutu Stripe; společný rozpočet a zacházení s nejistotou musí platit i pro další adaptéry. |
| `docs/architecture/service-fees.md` již definuje dohody, skutečné příjmy a alokace platformních poplatků. | Nevytvářet druhou evidenci příjmů. Chybí integrace výběru provize, nikoli celý finanční model. |

SQL cesty bez prefixu v tabulce jsou pod `database/functions/`; Edge cesty pod
`supabase/functions/_shared/`. Astra doporučil ponechat existující Stripe storage
a zpevnit skutečná místa rozšíření. Toto doporučení je přijato. Hypotetická
univerzální platební platforma by teď zvětšila riziko bez důkazu přínosu.

## Cílové vlastnictví a kontrakty

### Společný modul

- SQL vlastní formulářovou politiku, bankovní dostupnost, očekávanou cenu/měnu,
  vazby na objednávku, aplikaci finančních důsledků, admission a doručení.
- Edge orchestrace vlastní příkaz, neměnný pokus, fencing lease, typovaný výsledek
  operace, časový rozpočet a bezpečné rozhodnutí o opakování. Nepřekládá vendor
  stavy ani neposuzuje úplnost vendor vyhledávání.
- Společné DTO dostupnosti obsahuje `bank`, `providers[id]` a společnou politiku.
  Položka poskytovatele obsahuje `configured`, `available`, `recipient`,
  `supportedSurfaces`, strukturovaný důvod a efektivní omezení. Jedno místo v SQL
  rozhoduje, co je povolené; klient pouze zobrazuje a předběžně validuje.
- Uložená konfigurace má kanonické `bankEnabled` a
  `providerConnections[providerId]`. Draft průvodce používá stejnou strukturu;
  neukládá vedle ní další konkurenční `paymentMethod=both`.
- Legacy writer překládá pouze svou část konfigurace. Chybějící `payments`
  objekt nemění uložené platební nastavení. Přítomný starý Stripe-only objekt
  představuje původní bank/Stripe nastavení: odstranění Stripe bindingu smí
  zasáhnout Stripe, nikoli bindings jiných providerů. Moderní explicitní mapa
  je autoritativní snapshot jen v moderním kontraktu s platnou revizí formuláře.
  Konfliktní legacy a moderní příjemci se odmítají. Původní RPC podpis/parser
  zůstává na vnější hranici do doloženého ukončení jeho volajících.
- Rezervace inventáře, vzdálená platnost odkazu a stav došetření jsou různé
  skutečnosti. Zdrojem délky rezervace je serverová prodejní politika. Již
  založený pokus se nezmění úpravou dnešní konfigurace.

### Poskytovatel

- Adaptér ověřuje podpis/autentizovaný stav, účet, prostředí a vendor identity;
  překládá částky, platby, refundy a spory a vlastní vzdálené operace.
- Uchovává vlastní identifikátory, raw protokolová metadata, stránkovací kurzory,
  vlastní event journal a credential/onboarding postup. Tyto údaje se netváří
  jako společná pole `sessionLookupCursor`.
- Obnova vrací rozlišený výsledek `found`, `definitively_absent` nebo `unresolved`
  s plánem dalšího pokusu. `definitively_absent` má doloženou podmínku platnosti;
  chybějící či neúplné hledání zůstává `unresolved`.
- Schopnosti jsou rozdělené na záruky protokolu, podporu v našem adaptéru a
  způsobilost konkrétního účtu. Samotná schopnost API neopravňuje prodej.
- Údržba připojeného účtu je oddělená od `PaymentAttemptStore`. Veřejný registry
  zachová allowlist a explicitní továrny; nebude načítat moduly podle vstupu.

### Společné finanční důsledky bez přepisu ledgeru

V `database/functions/payment_providers/` vznikne neveřejný owner
`apply_provider_payment_effects_internal` s validovaným vstupním kontraktem pro
aplikaci ověřených provider efektů. Jeho přesný SQL podpis se uzavře ve vlně 2
podle skutečných uložených vazeb, před přesunem writerů ve vlně 3.
Stripe ingest nadále ověřuje a atomicky
ukládá své skutečnosti, poté zavolá tento owner ve stejné transakci a s původním
pořadím zámků. Owner znovu váže uložené order/payment/attempt/connection scopes;
nepřijímá instrukci klienta typu `markPaid=true`.

Owner centralizuje důsledky pro `paid`, `storno`, `expired`, refund/dispute hold,
admission a emailové verze. Použije existující paid primitive, totals a queue
intenty. Zachová rozdílnou bankovní a online politiku tam, kde je záměrná;
nepřepíše bankovní zálohy na model plné online platby. Žádný adaptér nesmí mimo
tento owner měnit doménové stavy a spouštět jejich emailové důsledky.

Provider úložiště může zůstat odlišné. Společný dekodér/validátor nesmí přijmout
chybějící finanční pole jako nulu, `invalid=false` ani chybějící pohyby jako
důkaz, že peníze neexistují. Vynutit stabilní identitu pohybu, účet/prostředí,
měnu, příslušnost k pokusu, konzistentní replay a vazbu refundu na původní platbu.
Neúplná pozorování nesmějí odvolat již doložená fakta.

## Invarianty, předpoklady a externí podmínky

1. Registrace, pořadí a neaktivní stav jiné brány nemění bankovní dostupnost ani
   příjemce a konfiguraci ostatních bran. Jeden adaptér může publikovat pouze svá data.
2. Jeden platební pokus má neměnné částky, měnu, příjemce, režim a identitu příkazu.
   Po timeoutu se nezakládá nový vzdálený pokus bez bezpečné recovery záruky.
3. Návrat z prohlížeče není platba. Webhook/obnova používají stejný owner a
   deterministický postup zámků; opakování nevytvoří druhé pohyby ani emaily.
4. Po uvolnění rezervace pozdní peníze neobnoví prodané místo. Pro nevyřešený
   případ vznikne explicitní evidence/hold a operátorské rozhodnutí; nejistota
   nesmí zmizet jako úspěšná expirace. Zachovat prokázanou stávající Stripe politiku.
   Rezervace inventáře je časově omezená: společný owner ji smí po uložené lhůtě
   uvolnit i při finančně `unresolved` pokusu, ale tento pokus zůstane evidovaný
   a v recovery. Uvolnění místa není důkazem neexistence vzdálené platby. Pokud
   dnešní Stripe strategie vyžaduje odlišný postup, výslovně jej zachovat a
   otestovat; žádná implicitní neomezená rezervace všech konektorů.
5. Vypnutí nových prodejů nebo odpojení účtu neodstaví recovery, historické čtení
   ani zpracování ověřených pozdních událostí.
6. Soukromé pay/return/handoff scopes zůstanou oddělené, neveřejné a bez cache;
   logy neobsahují bearer tokeny, celé návratové URL ani údaje zákazníků.
7. Výchozí produkt je jedna objednávka jednoho pořadatele, plná online platba,
   současné podporované měny a nulová nová platformní provize. Více pořadatelů
   v jedné platbě je samostatná změna modelu, nikoli automatická schopnost konektoru.

**Předpoklad A1:** Stripe chování má být zachováno. Rozhodující jsou současné
charakterizační scénáře a uložené finanční skutečnosti, nikoli pouze názvy helperů.

**Předpoklad A2:** kandidátem druhého konektoru je Barion z dříve založeného
sandboxu. V tomto plánování nebyly znovu ověřeny shop, klíče, API ani platformní
oprávnění. Realizátor ověří oficiální dokumentaci a stav konkrétního testovacího
účtu; tajemství nepatří do repozitáře ani do evidenčních výstupů. Nedostupný
sandbox blokuje jeho integrační důkaz, ne opravy vln 1-3.

**Externí podmínka E1:** obchodní způsobilost pro platby za cizí pořadatele,
merchant of record, náklady/spory, refund authority a případné rozdělení peněz
musí být doloženy konkrétním produktem a účtem poskytovatele. Podpora běžného
merchant checkoutu se nesmí označit za marketplace podporu.

**Externí podmínka E2:** sazba a základ provize, daňový režim, zaokrouhlení a
vracení provize při refundu nejsou schváleny tímto plánem. Při jejich absenci
zůstane výběr platformního poplatku vypnutý; žádný implicitní default 4 %.

## Realizační vlny

### Vlna 0 - Zafixovat kompatibilitu a integrační důkaz

**Změny:** Zachytit relevantní dirty diff a kontrolní součty vstupů bez zahrnutí
tajemství. Současný workspace měl při průzkumu 876 změněných/neversionovaných
položek; nic nehromadně neobnovovat ani necommitovat. Vytvořit v podadresáři
`docs/plans/payment-provider-hardening/` capability matrix s oficiálními zdroji,
datem a account-level důkazy pro Stripe a kandidáta. Popsat zejména idempotency
retenci, dohledání po timeoutu, úplnost hledání, expiraci, callbacky a refundy.

Zafixovat fixtures před upgradem: bankovní záloha, Stripe ordered/paid/sent,
částečný/plný refund, spor, expired, rozpracovaný lease a existující callback
receipt. Použít existující SQL fixture ownery, bez produkčních exportů zákazníků.

Ještě před první změnou kanonického SQL zmrazit
`20261106120000_payment_provider_connectors.sql`: digest, source manifest a
reprodukovatelné přesné vstupy archivovat jako historickou evidenci mimo aktivní
`database/functions/`. Výchozí je zmrazení i bez znalosti produkční aplikace.
Starý assembler přepnout na kontrolu této historické evidence obdobně jako
současný Stripe history checker; založit nový
`automation/payment-provider-hardening-migration.json` a jeho assembler pro
nové kanonické změny. Nečekat s tím na vlnu 5, protože vlny 1-3 již mění zdroje
současného assembleru. Nová migrace obsahuje potřebnou expanzi/redefinice,
nikoli opakovaný `CREATE TABLE` původního registru.

**Validace / exit:** Každá neověřená schopnost má hodnotu unknown a bezpečné
chování; historické stavové/historické/emailové očekávání a neměnné migrační
vstupy jsou zaznamenané. Account-level evidence může zůstat označená jako
nedostupná; to neblokuje vlny 1-3 ani lokální migrační důkaz. Blokuje pouze
příslušný skutečný sandboxový acceptance krok a jeho prodejní aktivaci.
Žádné skutečné peníze, produkční účty ani obcházení chybějícího schválení.

### Vlna 1 - Deterministické projekce a uložená identita poskytovatele

**Změny:** V `payment_providers/registry.sql` přestavět availability, unit a
editor projekce. Banku a prodejní politiku vypočítat jednou, data poskytovatele
vnořit pod jeho ID. Odmítnout nesprávné ID/shape; porucha nekonfigurovaného
poskytovatele nesmí zablokovat jinou metodu. Chybně nakonfigurovaný vybraný
poskytovatel je unavailable s diagnostikou, bez náhradní brány.

Legacy root Stripe projekci vytvořit výhradně ze Stripe položky. Dart
`FormPaymentOptions` a JS availability převést na kanonický DTO; omezit legacy
čtení na vyjmenované vnější adaptéry, ne obecný výběr prvního poskytovatele.

V `form_settings_content.dart`, `occasion_setup_page.dart`, core metadata,
`occasion_setup/{drafts,finalize}.sql` a `eshop_forms/form_settings.sql` sjednotit
konfiguraci na `bankEnabled` + `providerConnections`. Migrace starých draftů
`stripe/both` musí zachovat uložený příjemce. Nejednoznačný draft bez příjemce
vyžaduje explicitní opravu. Odstranit `_setupProvider` fallback na první položku.
Efektivní omezení a délku rezervace vrací server; UI neslibuje zálohy/příplatky,
které společná politika stále odmítá. Změna jednoho příjemce zachová ostatní.

**Migrace:** Expand DTO a čtení, převod draftů/metadat s kontrolou konfliktů,
přepnutí writerů, teprve pak odstranění duplicitních uložených klíčů. Staré
mobilní verze jsou vnější kompatibilní vstup, ne důvod dvou autorit v databázi.

**Validace:** Rozšířit `database/tests/payment_providers/`, core payment tests,
web registry tests a Flutter form/settings/setup scénáře o: žádný online
poskytovatel + funkční banka; dva poskytovatelé v různém pořadí; kolize klíčů;
bank + druhý poskytovatel round trip; legacy Stripe klient ukládající formulář
s druhým providerem bez ztráty jeho bindingu; explicitní odstranění jen Stripe
starým klientem; konflikt modern/legacy a stale modern snapshot;
neznámý provider a pozdní odpověď příjemce po přepnutí editoru.

**Exit:** Pořadí providerů neovlivní výsledky; `both` již není kanonický uložený
údaj; všechny konfigurační writery zachovají identitu poskytovatele a příjemce.

### Vlna 2 - Typovaná obnova bez předstírané jistoty

**Změny:** V `payments/contracts.ts` definovat discriminated claim
`read/busy/dispatch`, commit receipt, verifikované financial facts a výsledky
recovery. `unknown` smí zůstat na nedůvěryhodném RPC vstupu, za adaptérovým
dekodérem už ne. Rozdělit attempt persistence a connection maintenance.

V `connectors/stripe.ts` ponechat Stripe hledání a kurzory. Společné
`checkout.ts` pracuje s explicitním `found/definitively_absent/unresolved` a
uloženými deadline údaji. Zachovat prověřené Stripe validace, včetně stránkování;
nesnížit jejich důkazní úroveň jen kvůli zobecnění. Retry po ztracené odpovědi
nebo po konci vendor idempotency retence nepoužije automaticky nový create.

Přidat autorizovaný `payment-reconcile` vstup a registraci runtime-writer-policy,
coverage manifestu a configu. Scheduler používá explicitní instalované joby,
per-provider rozpočet, timeout, backoff a férový bounded výběr. Recovery není
podmíněná povolením nových prodejů. Zachovat jeden aktivní schedule pro danou
práci; starý `stripe-reconcile` pouze deleguje pro existující volající.

V `registry.ts`/webhook/reconcile zajistit stabilní kategorie chyb a interní
diagnostiku: provider, attempt/command, operace, retry class, stáří nejistoty,
ztráta lease a correlation ID. Veřejná odpověď nesmí zveřejnit výjimky ani tajemství.

**Validace:** Deno společný kontrakt s adaptérem bez seznamu sessions a bez
spolehlivé remote expirace; timeout po úspěšném remote create; neúplné hledání;
webhook před commit; stale lease; dvojí callback; retry mimo retenční okno;
pozdní platba po uvolnění míst; create stále unresolved po konci rezervace;
porucha jedné brány nevyhladoví druhou. Ověřit
machine auth, granty, vypnuté prodeje a chybějící credentials.

**Exit:** Společný engine nečte vendor session/kurzorová pole. Unknown výsledek
nevyrobí potvrzenou absenci ani náhradní charge. Recovery má provozního ownera,
jednu aktivní cestu plánování a dohledatelné nevyřešené případy.

### Vlna 3 - Jeden owner finančních důsledků

**Změny:** Rozdělit `eshop_stripe/ingest.sql` na ověření/uložení Stripe faktů a
volání společného ownera pod `payment_providers/`. Přesunout z něj doménové
zápisy, nikoli přejmenovat Stripe tabulky. Převést také refund/admission
rozhodnutí, projekce a recovery na stejné uplatnění důsledků. Konkrétní větev
legacy callbacku nebo operator refundu nesmí zůstat bočním writerem.

Zachovat `payment_financial_totals_internal`, existující paid primitive,
`reconcile_order_payment_internal_v1`, receipt replay a email queue jako vlastníky
jejich dosavadních odpovědností. Společný validovaný financial envelope nesmí
vyvozovat úspěch z neúplného provider JSON. Duplicitní pohyb/event musí mít
stejné skutečnosti; změněný payload pod stejnou identitou se odmítne atomicky.

Před extrakcí zaznamenat lock ordering ve Stripe ingest/pay/recovery a jejich
vazbu na form/order/payment zámky; nový owner jej nesmí obrátit. Síťová volání
neprovádět uvnitř databázové transakce. Neúspěch enqueue nebo doménové aplikace
vrátí zpět celé uložení nových skutečností a umožní bezpečný replay.

**Validace:** SQL matice pro stejné scénáře s dvěma adaptéry: chybný účet,
prostředí, měna, částka, cizí pokus; duplicita/konfliktní replay; neúplný refund;
partial/full refund; otevření/uvolnění sporu; used/storno vstupenky; pozdní
payment; selhání enqueue a opakování. Zvlášť dvouspojení concurrency pro
webhook/recovery/checkout, refund/admission a uvolnění rezervace. Deadlock,
timeout nebo skip potřebného scénáře není úspěch.

**Exit:** Stripe adaptér mimo společného ownera přímo nemění doménové stavy
orders/tickets, emailové verze ani nevytváří ticket email intenty. Finanční
storage a původní identity zůstávají zachované. Charakterizační chování banky
a Stripe i historie je beze změny kromě explicitně opravených chyb.
Caller audit zahrnuje i zachované legacy RPC/wrappers: jejich staré podpisy
smějí zůstat, staré samostatné doménové writery nikoli. Všechny delegují na
stejného ownera i během kompatibilního rolloutu.

### Vlna 4 - Skutečný druhý sandboxový konektor

**Změny:** Podle ověřené matrix z vlny 0 implementovat omezený adaptér pro
zvolený sandbox: připojení účtu, vytvoření jedné platby, návrat, ověřenou
notifikaci/polling a obnovu nejistého create. Doplnit SQL provider storage,
registraci a klientský bezpečný redirect policy. Využít společného ownera;
nekopírovat Stripe ingestion/storno/admission CASE do nového adresáře.

Povolit pouze ověřené a implementované schopnosti konkrétního účtu. Zahájení
refundu z aplikace musí mít skutečný sandboxový důkaz, nebo zůstat explicitně
unsupported se zachovanou operátorskou politikou. Pozorování a bezpečná aplikace
refundů/sporů provedených mimo aplikaci jsou jiná povinnost: jejich chybějící
podpora blokuje prodejní aktivaci, pokud takové události u dané brány mohou
nastat. Unsupported zahájení neznamená, že se externí refund ignoruje.
Merchant-only test nesmí
zapnout označení marketplace. V testech držet i záměrně odlišný test double
bez vyhledávání sessions; druhý skutečný adaptér ho nenahrazuje.

**Validace:** Redigovaný sandboxový receipt s identitami testovacích pokusů,
stavů a očekávaných uložených důsledků; úspěch, decline, opakování callbacku,
neplatná autentizace, timeout/recovery a expirace/pozdní platba. Testy nesmějí
utrácet skutečné peníze. Browser pouze v autorizované vedlejší kartě přes
Panerelay a delegovaný Terra postup; žádné přepínání uživatelových oken.

**Exit:** Druhý reálný protokol projde vertikálním tokem bez změny společné
obchodní logiky. Případná chybějící oprávnění/aktivace účtu jsou přesně uvedený
blocker; fake test se nesmí vydávat za skutečný integrační důkaz.

### Vlna 5 - Migrační důkaz a konečné odstranění duplicit

**Změny:** Doplnit forward migraci a assembler manifest pro změněné SQL.
Nejprve zjistit skutečný stav aplikování `20261106120000`; tento plán jej
neověřoval na produkci. Aplikovanou/sdílenou migraci nikdy nepřegenerovat.
Výchozí postup je nová navazující migrace. Ověřit zmrazení a nový source
manifest založené již ve vlně 0; zde je nezakládat poprvé. Starý assembler
musí zůstat kontrolou svého neměnného historického vstupu.

Projít deletion ledger níže, přesměrovat klienty/job konfiguraci a aktualizovat
`docs/architecture/payment-providers.md`, `ai_context.md`, policy a coverage
manifest. Do výsledkového receipt uložit přesné revize a digesty vstupů,
použité DB projekty, testy, rozdíly od plánu a stav externích podmínek.

**Validace:** Fresh baseline + všechny forward migrace a samostatný upgrade
z předchozího connector stavu se zachovanými fixtures. Porovnat order/payment,
events, movements, capabilities, tickets, history a email receipt před upgradem
a po něm; schema migrace nesmí sama přepočítat nebo odeslat historické platby.
Ověřit ACL, RLS, zdrojový parity check, privacy hosting/cache a registry ID parity
napříč SQL/Edge/Dart/JS. Znovu spustit jen affected brány.

**Exit:** Žádná druhá doménová implementace; všechny zachované legacy cesty mají
jmenovaného vnějšího volajícího a kontraktový test. Lokální výsledek je oddělený
od produkčního stavu a od spuštění marketplace/provizí.

## Provize a marketplace - přesně oddělený navazující rozsah

`service_fee_agreements`, `service_fee_settlements` a `service_fee_allocations`
zůstávají jediným zdrojem skutečného příjmu Festapp. Buyer charge, procesní
poplatek brány, závazek vůči pořadateli a vypořádaná platformní provize nejsou
zaměnitelné. Buyer webhook sám nevytvoří přijatý platformní příjem.

Po doložení E1/E2 navazující implementace snapshotuje schválené podmínky,
základ, měnu a alokační instrukci při vzniku pokusu. Ověřené skutečné settlement
a reversal údaje napojí na stávající source s dohledatelnou proveniencí; příjem
se neodvozuje procentem z objednávky zpětně. Zachovat existující Wix/acquisition
a reporting pravidla. Pokud API stávajícího importu nestačí, rozšířit kanonický
owner dopředně, nevytvářet druhý writer s odlišnými finančními pravidly.

Tato funkce potřebuje vlastní uzavřený acceptance rozsah: přesné zaokrouhlení
v minor units, neměnné historické dohody, nulový poplatek, vícenásobný callback,
částečný/plný refund a fee reversal, skutečné provider fees, settlement mismatch
a reconciliation. Dokud není schválena a ověřena, nový collector zůstává
vypnutý a UI nic neslibuje. Tento plán neobsahuje právní závěr o žádné bráně.

## Deletion ledger a záměrná kompatibilita

| Artefakt | Finální akce | Důkaz |
|---|---|---|
| Root převzatý od prvního provideru, flatten provider polí | Odstranit; kanonické namespaced DTO | Pořadí/kolize/no-provider SQL test |
| Interní `both`, fallback na první bránu, souběžné modern/legacy config writery | Migrovat a odstranit z kanonického uložení | Round trip a konfliktní upgrade fixtures |
| Vendor `session*`/refund kurzory ve společném enginu | Přesunout do adaptéru | Scoped reference check + odlišný provider test |
| `Promise<unknown>` za dekodérem, neurčitý success receipt | Nahradit typovaným výsledkem | Typecheck a malformed RPC fixtures |
| Doménové UPDATE a ticket/email důsledky ve Stripe ingest | Přesunout do společného ownera | Reference/caller audit a behavior/concurrency tests |
| Duplicitní Stripe-only aktivní recovery schedule | Nahradit jedním registrovaným schedulerem | Job inventory a overlap/replay test |
| `/stripe/*`, potřebné `stripe-*` endpointy a již vydané scopes | Zachovat pouze vnější protokolové adaptéry | Původní odkazy, raw signature, auth a scope tests |
| Stripe tabulky, event IDs, uložené peníze a historie | Zachovat; žádný kosmetický storage rename | Upgrade data equality |
| Legacy Stripe response pole pro vydané mobilní klienty | Odvozovat pouze ze Stripe v jediném adaptéru | Snapshot starého kontraktu, nezávislý na další bráně |
| Platformní fee source a bankovní ledger | Zachovat stávající authority | Žádný nový paralelní příjmový/platební writer |

Externí compatibility adaptér se odstraní až po doloženém konci skutečných
volajících nebo expiraci vydaných scopes. Datum odstranění není vhodné vymyslet
bez evidence. Záměrně zachovaná jména nejsou výjimkou pro druhý business engine.

## Ověřovací příkazy a izolace

Plánování žádné testy nespustilo. Dřívější průchod 143 Deno testů, 20 SQL
souborů a Flutter/web kontrol je výchozí evidence, nikoli ověření budoucích změn.

Pro níže uvedené DB příkazy realizátor nejprve rezervuje vlastní lokální projekt
`festapp-payment-provider-hardening`, workdir
`/tmp/festapp-payment-provider-hardening-db` a volný port 55472. Zkopíruje
`automation/local_db/supabase/config.toml` do jeho `supabase/config.toml` a nastaví
shodné project ID, DB port 55472 a volný shadow port 55470. Pokud jsou porty
obsazené, zvolí jiný volný pár a aktualizuje všechny své proměnné; jiné projekty
nezastavuje. Teprve potom spustí vlastní disposable bootstrap:

```sh
export FESTAPP_LOCAL_DB_PROJECT_ID=festapp-payment-provider-hardening
export FESTAPP_LOCAL_DB_WORKDIR=/tmp/festapp-payment-provider-hardening-db
export FESTAPP_LOCAL_DB_PORT=55472
export FESTAPP_STRIPE_TEST_CONTAINER=supabase_db_festapp-payment-provider-hardening
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55472/postgres?sslmode=disable'
./automation/bootstrap_local_db.sh
```

- Deno: `deno test --frozen --lock=supabase/functions/deno.lock --allow-env --allow-net --allow-read supabase/functions/_shared/payments/ supabase/functions/_shared/stripe/ supabase/functions/stripe-connect/handler_test.ts supabase/functions/stripe-connect-callback/handler_test.ts supabase/functions/_shared/edgeEntrypoints_test.ts`; přidat nové endpoint/protocol scénáře do této sady a coverage manifestu.
- SQL se zděděnými proměnnými vlastního bootstrapu: `pnpm --dir web_client exec node scripts/run_db_tests.js database/tests/payment_providers/ database/tests/eshop/stripe/ database/tests/eshop_orders/payment_lifecycle_`. Doplnit dotčené setup/form/fee testy podle vlny, ne celou databázi po každé editaci.
- Concurrency se stejnými proměnnými: `pnpm --dir web_client exec node --test tests/database/stripe_concurrency.test.js` plus nový společný matrix test vedle něj. Harness musí ověřit disposable identity; chybějící env/skip není průchod.
- Dart core, z `packages/festapp_core`: `fvm dart test test/forms/form_payment_options_test.dart test/payments/connector_test.dart`; dotčené setup metadata fixtures přidat podle změněného kontraktu.
- Flutter: `fvm flutter test --no-pub --concurrency=1 test/components/stripe_payments/ test/startup/startup_widget_cases.dart test/components/occasion/occasion_setup_story_shell_test.dart` plus nové společné testy. Na workstation smí běžet pouze jedna Flutter/Dart validační úloha současně.
- Web: přes pnpm spustit dotčené `web_client/tests/forms/*payment*`, `card_payment_*`, callback bootstrap a `automation/tests/{google_auth_hosting,google_auth_links,csp_policy,pwa_offline,pwa_reconcile,edge_function_test_coverage}.test.mjs`; před spuštěním vybrat existující soubory, ne neověřený shell glob.
- Statické brány: cílený `fvm dart analyze`; z `packages/festapp_core` příkaz `fvm dart run tool/check_architecture.dart /Users/miakh/source/festapp`; z rootu `node automation/hetzner-supabase/merge/edge-function-test-coverage.mjs`, assemblery `--check`, `python3 automation/baseline.py check`, `git diff --check`.

Použít vlastní disposable Supabase project přes `automation/bootstrap_local_db.sh`
s explicitním project ID/workdir/portem a po práci jej zastavit. Nikdy nepoužít
produkční DB jako test harness. Před velkými opravami unrelated test gates
zaznamenat, zda selhávaly už na výchozím dirty stavu; neoslabovat jejich očekávání.
Známé výchozí širší chyby se týkaly rich-description sanitizace, překladových
artefaktů a neklasifikovaných Flutter test roots. Nové chyby z těchto vln se
nesmějí schovat za tento seznam.

## Pořadí nasazení a návrat

Tento požadavek autorizuje plán, nikoli spuštění vln, produkční migraci nebo
publikaci. Při pozdější realizaci oddělit lokální implementaci od samostatně
autorizovaného produkčního rolloutu. Nové brány zůstávají pro prodeje vypnuté.

Po pověření: ověřit skutečný canonical backend/activation a zvoleného jediného
tenanta; nejprve kompatibilní schema/čtení, potom společné writery/Edge, klienty
a schedule, nakonec kontrakce. Při obnově Functions použít canonical restart
postup z ai_context včetně pozastavení/drain email queue, worker probe a health.
Web release používá lokální build a `automation/deploy_direct.sh`; routine
deploy provádí pověřený levnější subagent podle repo pravidel.

Návrat znamená zastavit nové prodeje postiženou bránou a ponechat recovery a
finanční fakta. Destruktivní down migrace, replay starých writerů, vynulování
faktů ani opětovné rozběhnutí starého schedule nejsou bezpečný rollback.
Contract/schema contraction až po důkazu, že kompatibilní writery již neběží.

## Definice dokončení

- [x] Vlny 0-5 mají receipt s výsledkem, revizemi a konkrétními testy; žádná
  neprovedená externí validace se neoznačuje jako průchod.
- [ ] Banka, dva provider adaptéry a jejich pořadí mají nezávislé projekce;
  uložené configy a drafty vždy uchovají skutečně zvolenou identitu.
- [ ] Typovaný recovery kontrakt odděluje neexistenci od nejistoty; druhý
  skutečný sandboxový protokol prokáže použitelnost společného toku.
- [x] Finanční důsledky mají jednoho SQL ownera; replay, souběh a selhání queue
  neztrácejí peníze, historii ani admission integritu.
- [ ] Fresh i populated upgrade projdou, schema/DTO/registry/config jsou koherentní
  a všechny deletion položky jsou odstraněné nebo výslovně omezené na vnější protokol.
- [x] Existující service-fee authority zůstává jediná; výběr provizí není
  aktivován bez E1/E2 a samostatné realizace finanční funkce.
- [x] Výsledek výslovně rozliší lokální code-ready, chybějící sandbox/account
  evidence, případně neprovedený produkční rollout a marketplace obchodní gate.

Zbytková rizika: skutečné protokoly a oprávnění další brány ještě mohou vyžadovat
úpravu kontraktu; historické externí klienty nelze odstranit pouze změnou serveru;
silný SQL owner stále důvěřuje prověřenému serverovému adaptéru při ověřování
vzdáleného protokolu. Tyto skutečnosti neřeší kosmetické přejmenování na generic.
