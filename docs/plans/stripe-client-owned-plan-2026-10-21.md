# Stripe na vlastním účtu pořadatele

Datum: 2026-10-21  
Stav: Implementovány oba klienty a ověřeny jejich testovací nákupy, podepsané webhooky, refundace a CMS handoff v odděleném sandboxu. Akceptace vln 0-5 zůstává otevřená podle matice důkazů; produkční pilot neproběhl  
Ověřování při implementaci: standard (platby, oprávnění, migrace)  
Realizace je autorizována navazujícím exekučním promptem pro vlny 0-5, bez produkčních zásahů. Aktuální důkazy a zbývající práce: [stav implementace](stripe-client-owned/IMPLEMENTATION-STATUS.md).

## Výsledek a rozdělení práce

Pořadatel propojí vlastní Stripe, zapne platbu kartou ve formuláři a spravuje finance přímo ve Stripe Dashboardu. Přihlášení do Stripe přes Google je podporované a nemění platební integraci. Google účet sám o sobě není platební účet; klient musí dokončit aktivaci Stripe obchodníka.

| Kdo | Odpovědnost |
|---|---|
| Klient | Vlastní Stripe účet, obchodní údaje, požadované ověření, bankovní účet pro výplaty, refundace, řešení sporů a účetnictví |
| Stripe | Platební stránka, zpracování karty, ověření obchodníka a výplaty podle nastavení účtu |
| Festapp | Objednávka, rezervace kapacity, bezpečné spuštění platby na správném účtu, převzetí stavu platby, vstupenky, historie a doručovací fronta |

Festapp musí mít vlastní aktivovanou integraci Connect a provozovat její backend. „Klient si vše řeší sám“ zde znamená samoobslužnou správu jeho financí; neodstraňuje technické povinnosti platformy.

První verze: Stripe Checkout, přímé platby (direct charges), plný Stripe Dashboard klienta, bez provize Festapp. Žádné vlastní formuláře pro karty, klientské tajné klíče, správa výplat, refundovací tlačítko ani automatické vracení peněz ve Festapp. Převody zůstávají dostupnou samostatnou metodou.

## Potvrzená východiska

| Fakt | Zdroj v repozitáři | Dopad |
|---|---|---|
| Objednávku přijímá Edge Function a vytváří receipted SQL příkaz | `supabase/functions/send-ticket-order/index.ts`, `database/functions/eshop_orders/create_ticket_order_client_sync_v1.sql` | Zachovat command ID, replay, kapacitní transakci a Client Sync |
| Finalizátor dnes vybírá bankovní účet a vytváří bankovní payment_info / referenci | `database/functions/eshop/finalize_ticket_order.sql`: `finalize_ticket_order_internal_v1`, zejména bloky bank_account a payment_info | Nestačí přidat odkaz do UI; oddělit instrukce banky od obecné pohledávky |
| Edge Function počítá s Fakturoidem a bankovním QR | `supabase/functions/send-ticket-order/index.ts`: `get_external_services`, `presentPayment` | Explicitně větvit podle metody; nevytvářet bankovní instrukce pro Stripe |
| Bankovní párování přepočítává payment_info z bankovních transakcí | `database/functions/eshop_transactions/apply_transaction_pairing.sql` | Stripe nesmí mít částky, které následný bankovní přepočet přepíše |
| Stav zaplacení a emailové záměry vlastní SQL | `database/functions/eshop_orders/recalculate_order_payment_status.sql`, `update_order_and_tickets_to_paid.sql` | Navázat na společný přepočet a `enqueue_paid_order_tickets`; nepsat další platební engine |
| Současný přechod umí znovu aktivovat expired objednávku | `update_order_and_tickets_to_paid.sql` | Stripe vyžaduje kontrolu kapacity před přechodem; pozdní platbu nelze slepě předat stávající funkci |
| Oba klienti zobrazují dokončení objednávky | `web_client/src/components/forms/order_result.js`, `order_overview.js`; `lib/components/forms/views/order_finish_screen.dart`, `customer_order_overview.dart` | Oba musí rozumět kartě, čekání na potvrzení a návratu ze Stripe |
| Účty bank se dnes sdílejí přes unit vazby a mají vlastní oprávnění | `lib/components/bank_accounts/README.md` | Stripe není falešný bankovní účet; nová připojení musí mít vlastní ověřené vazby a oprávnění |
| Přehled objednávky má výslovně pouze čtecí capability | `lib/components/forms/README.md`: Customer order overview; `database/functions/eshop_waitlist/order_overview_schema.sql` | Zavést samostatné oprávnění k pokračování v platbě, nerozšířit `order_view` |
| `payment_type` dnes znamená záloha nebo plná částka | `web_client/src/components/forms/order_preview.js`, `form_page.js` | Nová `payment_method` je jiná osa; nekolidovat se stávajícím payloadem |
| Platební nastavení už má vlastní draft a panel formuláře | `lib/components/forms/views/form_settings_content.dart`, `models/form_editor_draft.dart`; `packages/festapp_core/lib/src/forms/form_definition.dart` | Rozšířit existující nastavení a Save/Discard; nevytvářet druhé nastavení mimo draft |
| Správa unit má samostatnou bankovní routu a vstup z nastavení | `lib/app_router.dart`, `lib/components/unit/views/unit_settings_screen.dart`, `unit_admin_page.dart` | Stripe přidat jako sourozence, zachovat bankovní URL i model |
| Embedded protokol zakazuje přenos objednávek, secrets a platebních stavů parentovi | `docs/integrations/embedded-checkout.md`, `web_client/src/services/embed_bridge.js` | Platební handoff řešit na tenant originu bez rozšíření protokolu o citlivá data |
| Emailová observace není potvrzením platby | `web_client/src/components/forms/order_delivery_status.js`, `lib/components/forms/views/order_finish_screen.dart` | Oddělené stavy platby, vstupenek a emailu |
| DB umožňuje bank_account NULL, bankovní transactions vyžaduje účet | `supabase/baseline/20260906140000_schema.sql`: `eshop.payment_info`, `eshop.transactions` | Neplánovat odstranění neexistujícího NOT NULL; změnit doménový finalizátor a ověřit novější constraints |
| Denní report počítá pohyby z bankovních transactions | `database/functions/eshop/get_report_ws.sql`: `transactions_scope`, `payment_days` | Doplnit Stripe i do časových řad, nikoli jen celkového součtu |

Stávající pracovní strom obsahuje rozsáhlé jiné změny. Tento plán je posuzuje jako aktuální výchozí stav, ne jako práci k přepsání nebo revertování. Nebyl proveden test, migrace ani přístup do produkce.

## Rozhodnutí a externí ověření

1. Peníze za vstupenku vznikají na účtu klienta. Použít direct charges, nikoli destination charges nebo následné rozesílání prostředků z účtu Festapp.
2. Klient má plný Dashboard, Stripe vybírá platební poplatky přímo od klienta a platforma nepřebírá odpovědnost za záporné zůstatky klienta. U nově vytvářených Accounts v2 jde o `dashboard=full`, `fees_collector=stripe`, `losses_collector=stripe`. To nezbavuje Festapp odpovědnosti za vlastní účet nebo integraci. U připojených existujících účtů ověřit odpovídající vlastnosti; nepřepínat je automaticky na jiný finanční model.
3. Požadavek na existující vlastní účet má přednost před konkrétní verzí API. Stripe nyní doporučuje Accounts v2 pro nové platformy, ale připojení existujícího účtu dokumentuje přes OAuth. První vlna musí potvrdit podporovanou kombinaci pro náš Connect profil. Nezaměnit vytvoření nového účtu za propojení stávajícího.
4. OAuth má omezení pro účty řízené jinou platformou. UI ukáže srozumitelný důvod neúspěchu; bez souhlasu klienta nezakládat náhradní účet. Nepotřebujeme přístup ke Google účtu ani Google OAuth scope.
5. MVP nabízí pouze jednorázovou plnou úhradu objednávky kartou s okamžitým potvrzením. Odložené metody, zálohy/doplatky kartou, dělené úhrady a změna sedadel během aktivního Checkout pokusu nejsou součástí MVP. Omezení vynutit na serveru a vysvětlit v konfiguraci, nikoli tiše přepnout na převod. Bezplatné objednávky pokračují dosavadním postupem.
6. Výchozí vazba Stripe je na pořadatele `unit` v tenantovi `organization`; formulář vybírá pouze oprávněné připojení této unit. Pro MVP jedno aktivní připojení na unit; starší identita zůstává zachována pro historii. Pokud bude potřeba sdílet jediný účet mezi více units, navrhnout výslovné autorizované vazby před rozšířením, ne povolit libovolné zadání account ID.
7. Nastavení se jmenuje „Platby kartou“, veřejná metoda „Kartou online“. Technické výrazy Connect, account ID a PaymentIntent patří jen do diagnostiky. Google je přihlašovací volba na stránce Stripe; nezavádět paralelní „Připojit Google“ ve Festapp.
8. Změna metody po vytvoření objednávky není v MVP podporovaná. Návrat ze Stripe ponechává stejnou objednávku a umožní pokračovat v témže platném pokusu. Alternativní metodu si návštěvník vybírá před vytvořením objednávky; výpadek není důvod automaticky přidat novou objednávku.

Externí podmínky: uživatel potvrdil, že má vlastní Stripe účet používaný v Mendeliu a později jej lze využít pro testování. Není potřeba plánovat založení prvního Stripe účtu. Samostatný sandbox/testovací přístup, způsobilost Connect profilu a klientova účtu, potřebné aktivace a oprávnění zatím nejsou ověřené. Bez nich lze implementovat a testovat lokální kontrakty, nelze prohlásit hotové živé platby. Před spuštěním znovu ověřit podporované země/měny, profil podnikání a skutečné poplatky; zde není cenová nabídka ani právní závěr. Tato informace není zadáním nyní měnit účet nebo spouštět testovací transakce.

Čtecí průzkum Mendelia našel `packages/app-shared/src/stripeClient.ts`, `stripeCheckout.ts`, `stripeWebhook.ts` a `checkoutEnv.ts` v repozitáři `/Users/miakh/source/roman_seznamka`. Obsahují Checkout, idempotency key a ověřování raw webhook podpisu; prohlédnutý Checkout adapter nevybírá připojený účet pomocí Connect scope. Jde o referenci existujících zkušeností, nikoli důkaz nastavení Stripe Dashboardu nebo přímou knihovnu pro Festapp. Žádné secrets nebyly čteny ani kopírovány a žádné Stripe API nebylo voláno.

## Cílový kontrakt a invarianty

### Datové vlastnictví

Navržený SQL vlastník je `database/functions/eshop_stripe/`, všechny funkce v `public` s explicitními eshop názvy, omezenými granty a kontrolou oprávnění. Nové tabulky v `eshop`:

- `stripe_connections`: organization, unit, prostředí, Stripe account ID, stav, ověřené capabilities, audit propojení/odpojení. Soukromé tokeny případně odděleně, šifrovaně a přístupné pouze backendu.
- `stripe_checkout_attempts`: neměnný snapshot order/payment_info, connection/account, částka v nejmenší měnové jednotce, měna, revize objednávky, časový limit, idempotency key, Session/PaymentIntent ID a stav. Jeden aktivní pokus na pohledávku, žádná změna příjemce historického pokusu.
- `stripe_event_inbox` a `stripe_payment_movements`: deduplikace událostí a samostatně ekonomických pohybů podle account + prostředí + provider ID. Úspěch, refundace a spory se evidují odděleně; opakovaný snapshot nesmí přičíst částku podruhé.

Unikátní omezení vynutí jednu aktivní connection na unit/prostředí a pro MVP jedno vlastnictví Stripe účtu na kombinaci account ID/prostředí. Opětovné připojení téhož účtu k téže unit je idempotentní; pokus o neplánované sdílení mezi units/tenanty se odmítne bez odhalení údajů cizího pořadatele. Inbox nesmí směrovat události jen podle volného metadata order ID. Testovací a live identita, secrets i připojení jsou oddělené; návštěvník na produkčním formuláři nemůže query parametrem přepnout do testovacího prostředí.

`eshop.payment_info` zůstává obecnou pohledávkou. Přidat explicitní metodu a vazbu poskytovatele, zpřístupnit Stripe objednávku bez bankovního účtu a bez bankovní reference. Do bankovních transakcí nevkládat smyšlené Stripe pohyby. Jeden SQL součet skládá bankovní a provider fakta do platebních souhrnů; všechny dosavadní zapisovače souhrnů musejí používat tentýž přepočet. Rozlišit hrubě zaplaceno, úspěšně vráceno a disponibilní čistou úhradu; Stripe poplatek nesnižuje zákazníkovu zaplacenou cenu.

Před migrací cíleně zkontrolovat novější constraints/FK a význam `paid`, `paid_externally` a vratek proti baseline a finančnímu reportu. Zachovat bankovní, ruční, externě zaplacené a zálohové kontrakty; potřebnou změnu obecného součtu definovat pomocí regresních případů, ne přejmenováním existujících polí. Refundace a částka blokovaná sporem nejsou stejný účetní pohyb; spor nesmí být podruhé odečten jako refundace. Celkové i denní reporty používají stejnou normalizovanou projekci a původní transakční datum, ne datum webhooku. Report nezaměňuje tržbu za výplatu na bankovní účet. Platební poplatky a payout reporty nejsou součástí MVP.

### Vstupní body

- Připojení: autentizovaný správce unit zahájí jednorázový flow. Callback ověří `state`, expiraci, uživatele a unit/organization proti serverovému záznamu. Account ID a oprávnění pocházejí od Stripe, nikoli z formulářového pole.
- Checkout: `send-ticket-order` přijme povolenou `payment_method` a po SQL commitu připraví Session na backendu pro uložený účet. Nezaměnit s `payment_type` (záloha/plná úhrada). Doplnit obnovení platby na existující objednávce pomocí samostatné úzce omezené `order_pay` capability; `order_view` zůstává pouze pro čtení. Znalost numerického order ID, Session ID, emailu nebo návratového nonce sama neopravňuje k platebnímu zápisu.
- Webhook: nová Edge Function ověří podpis nad původními byty a prostředí, potom předá do neveřejné SQL ingest hranice důvěryhodný účet a fakt. Zápis inboxu, pohybů, souhrnů, stavů, Client Sync a emailových intentů musí commitnout atomicky. Neúspěšná SQL receipt znamená retry, ne úspěšné HTTP potvrzení.
- Recovery: stejný backendový synchronizační modul dohledává zaseknuté pokusy a zmeškané události přes API ve scope správného účtu. Má trvalý cursor/stav, omezené dávky a bezpečné retry; není druhým platebním enginem.

`order_pay` vzniká v SQL spolu s regular objednávkou, včetně objednávky vzniklé přijetím waitlist nabídky. Ukládá se hash, vazba na objednávku, generace a expirace. Umožní jen založit/obnovit serverově určenou platbu téže pohledávky; neumožní změnit cenu, email, vstupenky, příjemce, zrušit objednávku nebo číst cizí data. Veřejný přehled vrací safe payment projekci, nikoli tajný token. Soukromý zdroj platebního odkazu pro email je šifrovaný stejně jako stávající capability zdroje; redelivery/reissue má explicitní oprávnění a revokaci. Pouhý view odkaz nesmí vystavit novou pay capability. Registrace na čekací listinu platbu ani `order_pay` nepotřebuje.

Obnovovací odkaz používá fragment, neposílá se do analytics, logu ani Stripe metadata. Chráněná návratová stránka před odchodem na externí origin používá `Referrer-Policy: no-referrer`. Dlouhodobé bearer tokeny nejsou query parametrem `success_url`/`cancel_url`. Návratový handle je náhodný, krátkodobý a omezený na jeden pokus; může obnovit pouze minimální bezpečný stav, ne vydat novou write capability. Pro plný soukromý přehled po ztrátě kontextu použít nezávislý emailový odkaz. Řešení nesmí vyžadovat third-party cookies nebo localStorage jako jediný zdroj obnovy.

| Navržená hranice | Volající a oprávnění | Jediný vlastník chování |
|---|---|---|
| `stripe-connect` | Auth správce unit; action start/status/pause/resume/replace/disconnect | Připojení, provozní dostupnost a audit, bez editace financí |
| `stripe-connect-callback` | Stripe OAuth návrat + svázaný jednorázový state | Ověření propojení; žádný neověřený client account ID |
| `send-ticket-order` | Dosavadní receipted create/accept kontrakt | Vytvoření objednávky; volá společný checkout modul až po SQL commitu |
| `stripe-checkout` | `order_pay` / omezený jednorázový handoff scope | Příprava/obnova téhož pokusu, nikdy nová objednávka |
| Návratový stav platebního pokusu | Omezený read-only return scope, serverově svázaný s pokusem | Minimální stav bez osobních dat; nelze směnit za pay token |
| `get_customer_order_overview` | Existující `order_view` | Úplný safe přehled vlastní registrace/objednávek, bez write scope |
| `stripe-webhook` a `stripe-reconcile` | Podpis poskytovatele / neveřejná servisní autentizace | Společný provider synchronizační modul a jedna SQL ingest hranice |

Jména nových Edge Functions jsou návrh kanonických vstupů, ne již existující soubory. Společné Stripe SDK/API volání, převod měny, idempotenci a mapování provider chyb soustředit do jednoho modulu pod `supabase/functions/_shared/`; neduplikovat je mezi create, resume a recovery. Webhook nevyžaduje JWT návštěvníka, ale vyžaduje platný Stripe podpis. Interní SQL ingest ani reconcile nesmí být přímo proveditelné anon/authenticated uživatelem.

Create/resume/reissue mají existující abuse/rate-limit hranici i na nové cestě a omezený počet provider volání. Callback start má krátkodobou serverovou expiraci a jednorázový state; recovery má limity dávek a backoff pro provider rate limit. UX polling se nesmí stát volně dostupným endpointem vyvolávajícím neomezené Stripe API volání. Timeouty zachovají durabilní záměr a rozlišují retryable chybu od definitivního odmítnutí.

### Bezpečnost a souběh

1. Klientský vstup neurčuje příjemce, cenu ani měnu. Konverze peněz používá měnový exponent a přesná čísla.
2. Výsledek návratové URL pouze aktualizuje zobrazení. Vstupenky povoluje až serverově potvrzená úhrada.
3. Založení Session není distribuovaná SQL transakce. Nejprve uložit pokus, pak volat Stripe se stabilním idempotency key a výsledek dopsat. Po timeoutu dohledat tentýž pokus, nevytvářet další platbu. Po vypršení Stripe idempotency okna nesmí nejistý pokus automaticky dostat nový klíč.
4. Události mohou přijít před HTTP odpovědí, duplicitně a mimo pořadí. Při nejasném stavu načíst aktuální objekt ze správného účtu a nemíchat objektové snapshoty s přírůstkovým účtováním.
5. Zámky objednávky a kapacity používají stávající pořadí zámků. Aktualizovaný produktový předpoklad: po vytvoření Stripe objednávky rezervovat kapacitu pevně 31 minut. Stripe vyžaduje expiraci nejméně 30 minut od vytvoření Session, proto SQL snapshot přidává jednu minutu na dispatch. Počáteční požadavek mimo toto okno se nesmí změnit na novou cenu, nový klíč nebo prodlouženou rezervaci. Jde o technický návrh odvozený z [API kontraktu expires_at](https://docs.stripe.com/api/checkout/sessions/create#create_checkout_session-expires_at), nikoli o schválenou politiku produkčního pilotu. Případné prodloužení předchozího seat-selection locku se provede atomicky při vytváření objednávky, nikoli jen v klientském odpočtu. Po úspěchu rezervace přejde v prodej. Session nesmí přežít platnost kapacity; pokud nelze sladit limity Stripe, konec prodeje a kapacitu, platbu kartou server nenabídne a vysvětlí důvod. Před uvolněním kapacity ukončit pokus a řešit závod s potvrzením. Obnovení nebo druhá karta neprodlužuje celkový limit; žádné nekonečné blokování míst.
6. Platba po stornu, uvolnění kapacity nebo nečekaná druhá úhrada se zaeviduje a označí `action_required`; nikdy automaticky neobnoví obsazené sedadlo. Klient dostane upozornění přes společnou frontu a řeší refundaci ve Stripe. Zákazník vidí, že platba byla přijata a objednávka vyžaduje dořešení.
7. Po dobu aktivního pokusu blokovat změny ceny, sedadel a přepnutí metody. Storno koordinovat s expirací Session, zachovat doklad o skutečně přijaté pozdní platbě.
8. Automatické emaily a přílohy pouze přes `public.email_messages` / `process-email-queue`. Platební webhook neposílá email přímo.
9. Změny připojení platí pro budoucí pokusy. Odpojení nebo ztráta capability zastaví nové platby, zachová historii a nedělá z nezaplacené objednávky zaplacenou. Pokud po odpojení nelze synchronizovat, zobrazit čas posledního ověření a stav dořešení, nepředstírat aktuálnost.
10. V checkout Session zakázat změny množství, promotion codes, adaptive pricing a vlastní automatický výpočet daně, dokud nemají stejný serverový cenový kontrakt jako objednávka. Stripe dostává jen minimum: order reference, price snapshot, měnu a kontakt plátce; neposílat answers, identifikační doklady ani všechny držitele vstupenek. Změna kontaktního emailu v Checkout nepřepisuje email objednávky ve Festapp. V pilotu ověřit přesné položky i jejich součet v obou systémech.
11. Hosted Checkout explicitně omezuje metody na schválenou karetní sadu; nespoléhá na automatické zapnutí metod v Dashboardu. Aktivace další metody klientem ve Stripe nesmí obejít omezení MVP. U všech metod zůstává serverové ověření `payment_status`/PaymentIntent, ne samotného `checkout.session.completed`.
12. Zaplacená objednávka se po refundaci nebo holdu nemá znovu tvářit jako běžná nezaplacená objednávka. Provider fakta, doménové rozhodnutí o vstupenkách a výzva k další platbě jsou oddělené. Eligibility pro vystavení/odeslání vstupenky se kontroluje i při send-time/retry: refundace nebo spor po enqueue nesmí odeslat mezitím neplatnou vstupenku jako platnou.

### Refundace a spory provedené klientem

Klient refunduje a řeší chargeback ve Stripe; Festapp musí přebrat jejich dopad. První verze nemá automatické refundovací API ani automatický výběr vstupenek k částečné refundaci.

- Úspěšnou plnou refundaci zaznamenat; zneplatnit dosud nepoužité vstupenky přes společnou doménovou hranici. Selhaná nebo čekající refundace není definitivní vrácení peněz.
- Částečná refundace vytvoří `action_required`, ale sama nevybírá vstupenky ke zneplatnění a automaticky nezastaví celou skupinu. Může jít i o slevu bez rušení vstupenky. Oprávněný pořadatel v dořešení zvolí konkrétní dosud nepoužité vstupenky, nebo potvrdí „Vrácení části ceny bez zrušení vstupenek“. Bez tohoto rozhodnutí nesmí obecný přepočet kvůli nižší čisté úhradě omylem zneplatnit celou uhrazenou objednávku.
- Otevřený spor navrženě pozastaví dotčené dosud nepoužité vstupenky a vytvoří `action_required`. Jde o produktový předpoklad, ne vlastnost Stripe: před pilotem jej pořadatel musí znát a akceptovat. Při částečném sporu bez vazby na konkrétní vstupenky se pozastavení týká dosud nepoužitých vstupenek dané objednávky a vyžaduje dořešení. Použité vstupenky ani záznamy vstupů nemazat. Kapacitu při pouhém pozastavení neuvolňovat.
- Rozhodnutí o konkrétních vstupenkách proběhne auditovaným příkazem Festapp, nikoli přepsáním provider faktu. Obnovení po vyhraném sporu smí obnovit jen stále oprávněné a rezervované vstupenky. Finanční stav a admission hold jsou oddělené osy.
- Hold a zneplatnění musí respektovat SQL skener i offline scan projekce. Již odpojenému zařízení nelze zaručit okamžité doručení změny. Pro první pilot je proto podmínkou online kontrola Stripe vstupenek na všech přijímacích cestách; po výpadku spojení skener tyto vstupenky nepotvrdí offline a nabídne opakování nebo oprávněné ruční dořešení s auditem. Zapnutí Stripe nesmí potichu omezit existující bankovní offline vstupy. Plná offline podpora Stripe vyžaduje zvláštní politiku přípustného stáří dat a přijetí rizika, není automaticky součástí tohoto plánu. Již stažený QR/PDF nelze odvolat smazáním emailu.

## UI/UX kontrakt

Tato část je závazná pro implementaci obrazovek i jejich backendových projekcí. Konkrétní copy je návrh v češtině; implementace použije existující lokalizace a formální/neformální tón pořadatele. Není to samostatný redesign Festapp.

### Informační architektura a vizuální návaznost

| Místo | Úkol uživatele | Cílová podoba |
|---|---|---|
| Nastavení pořadatele (`unit`) | Připojit a spravovat účet | Nový vstup „Platby kartou“ vedle stávajících Bankovních účtů; vlastní deep link v unit administraci, bez přesunu bankovních URL |
| Platby kartou | Zjistit připravenost a další krok | Jedna stránka: název účtu/příjemce, stav přijímání plateb, samostatný stav výplat, poslední kontrola, jedna hlavní akce |
| Nastavení formuláře | Nabídnout kartu návštěvníkům | Existující sekce plateb: povolené metody, příjemce a srozumitelná eligibility; zachovat EditorActionBar a draft |
| Rekapitulace objednávky | Vybrat metodu a ověřit cenu | Rozšíření současné rekapitulace, žádný nový povinný registrační účet nebo nový mezikrok pro výběr Stripe |
| Výsledek a soukromý přehled objednávky | Dokončit platbu / získat vstupenky | Jedna stavová oblast s cenou, zbývajícím časem a jedinou hlavní akcí; zvlášť stav emailu |
| Detail objednávky v administraci | Dohledat platbu a dořešit výjimku | Platební timeline, safe reference a odkaz na Stripe; řešení platnosti konkrétních vstupenek |

Použít `Theme.of(context)`, `ThemeConfig`, `StylesConfig` a existující CSS tokeny (`--primary-color`, `--surface-color`, `--text-color`, spacing 8/16/24, `--form-max-width`). Nezavádět pevnou Stripe fialovou, nový font nebo samostatný design systém. Připojení je plná stránka, potvrzení odpojení používá `AppAlertDialog`. Nepřidávat vnořené modály přes order preview nebo další kartu kolem každého řádku.

Na mobilu jedna kolona, hlavní akce přes dostupnou šířku; na desktopu stav a účet přehledně nad podpůrnými detaily. Veřejný formulář zachová dnešní šířku a identitu pořadatele. Načítání nesmí skrýt už známou částku ani přesouvat tlačítko pod prstem. Barva stavu je doplněk textu a ikony.

### A. Připojení účtu pořadatelem

První zobrazení: „Přijímejte platby kartou na svůj Stripe účet. Výplaty, vracení peněz a reklamace plateb spravujete ve Stripe.“ Hlavní akce „Připojit Stripe“, sekundární odkaz „Jak to funguje“. Krátká nápověda může uvést přihlášení přes Google; není potřeba průvodce s marketingovými obrazovkami.

Průchod: vybraná unit -> zahájení flow -> systémový prohlížeč/Stripe -> návrat -> ověření účtu serverem -> zobrazení názvu a stavu -> „Nastavit ve formuláři“. Automaticky nezapínat kartu ve všech formulářích. Návratová URL není důkaz dokončeného ověření Stripe.

| Stav připojení | Text a další krok | Pravidlo |
|---|---|---|
| Nepřipojeno | „Připojit Stripe“ | Žádné vstupní pole pro account ID nebo API klíč |
| Připojování | „Čekáme na dokončení ve Stripe“ + „Ověřit stav“ | Krátkodobý pending flow; zrušení Stripe nezpůsobí ztrátu nastavení unit |
| Potřebné údaje | „Stripe potřebuje doplnit údaje“ + „Pokračovat ve Stripe“ | Obchodní údaje vyplňuje klient přímo u Stripe |
| Připraveno | „Platby kartou jsou dostupné“ + „Nastavit ve formuláři“ | Ověřené `charges_enabled` a potřebné capabilities, nikoli jen přítomný account ID |
| Výplaty vyžadují pozornost | „Platby lze přijímat, výplaty vyžadují doplnění ve Stripe“ | Příjem plateb a payouts neztotožňovat; podle skutečných capabilities může přijímání pokračovat |
| Pozastaveno ve Festapp | „Nové platby kartou jsou pozastavené“ + „Obnovit příjem plateb“ | Připojení a zpracování již založených pokusů zůstává aktivní |
| Omezeno Stripe | „Platby kartou teď nejsou dostupné“ + „Otevřít Stripe“ | Nové pokusy zakázané; bankovní metoda může pokračovat, pokud je zvlášť povolena |
| Stav nelze ověřit | „Stav se nepodařilo ověřit. Poslední ověření: …“ + „Ověřit znovu“ | Nezobrazit falešné „Odpojeno“; nový checkout musí provést serverový preflight |
| Přístup odvolán | „Účet už není propojený“ + „Připojit znovu“ | Historie zachovaná; synchronizační mezera výslovně viditelná |
| Přístup zamítnut uživatelem | „Propojení nebylo dokončeno“ + „Zkusit znovu“ | Běžný návrat bez chybového alarmu a bez vytvoření náhradního účtu |

Připojený účet zobrazit jako obchodní název a případně ověřenou zemi; technické ID skrýt pod „Podrobnosti“. V MVP nejde editovat příjemce přímo. Nahrazení účtu nejprve připraví kandidáta a až po jeho ověření atomicky přepne budoucí objednávky; původní připojení dál synchronizuje historii. Při chybě zůstává původní vazba.

„Pozastavit nové platby“ je běžná provozní akce. „Odpojit účet“ je samostatná druhotná akce: před potvrzením server vrátí počet dotčených aktivních formulářů a rozpracovaných plateb. Vysvětlit, že odpojení nevrací peníze, nemaže historii a může ukončit automatické přebírání změn. Aktivní Session se před odpojením musí vypořádat nebo ověřeně ukončit; při nejistotě odpojení z Festapp blokovat a nabídnout pozastavení. Externí odpojení přímo ve Stripe zůstává podporovaným chybovým scénářem.

### B. Oprávnění a návrat z externí stránky

| Role/scope | Vidí stav/příjemce | Zapíná metodu ve formuláři | Připojuje/nahrazuje/odpojuje účet | Dořeší konkrétní vstupenky |
|---|---|---|---|---|
| Správce unit v témže tenantovi | Ano | Při stávajícím právu editovat formulář | Ano, SQL kontrola správce unit | Při stávajícím právu editovat objednávku |
| Editor formuláře/akce | Jen potřebný stav vlastní unit | Při stávajícím právu editovat formulář | Ne; odkaz „Požádejte správce pořadatele“ | Jen pokud má zvlášť právo editovat objednávku |
| Čtenář objednávek | Safe platební fakta | Ne | Ne | Ne |
| Administrátor bankovního účtu | Jen podle svých ostatních rolí | Jen podle svých ostatních rolí | Bankovní oprávnění samo nestačí | Jen podle svých ostatních rolí |
| Návštěvník s `order_view` | Jen vlastní safe přehled | Ne | Ne | Ne |
| Návštěvník s `order_pay` | Jen operace platebního scope | Ne | Ne | Ne |

Nepřihlášený návštěvník pro nákup nepotřebuje Festapp ani Stripe účet. Odkaz „Otevřít Stripe“ v administraci otevírá skutečný Dashboard klienta, vyžaduje jeho přihlášení a neslibuje automaticky přístup všem editorům Festapp.

Connect v mobilní aplikaci používá systémový prohlížeč, nikoli webview pro Google login. Při odchodu zachovat uložený kontext unit, po návratu/`resume` znovu načíst serverový stav. Po vypršení Festapp session vyžadovat přihlášení téhož oprávněného uživatele; callback nepřivlastní účet jinému aktuálně přihlášenému uživateli ani jiné unit. Opakovaný callback nebo tlačítko Zpět nevytváří další propojení. Web má bezpečnou návratovou routu a pevně povolené cílové originy; libovolný `return_url` z klienta není povolený.

### C. Nastavení plateb ve formuláři

V existující sekci „Platba“ oddělit „Způsob platby“ (`payment_method`: převodem/kartou) od „Výše úhrady“ (`payment_type`: záloha/celá částka). Pro každý povolený způsob ukázat ověřeného příjemce a readiness. Při jedné metodě ji návštěvníkovi zobrazit jako shrnutí; nepoužívat radio pro jedinou volbu.

- Nový i existující formulář má kartu výchozím stavem vypnutou. Editace pouze ve vlastním draftu, uložení jediným existujícím save příkazem. Opuštění do Stripe respektuje stávající dirty guard; uložené platební nastavení se nemění pouhým návratem z propojení.
- U karty zobrazit: „Příjemce: …“, „Úhrada celé objednávky“ a navrženou pevnou rezervaci 31 minut. Bankovní splatnost zůstává samostatná a nepředstírá délku karetní Session. Cena na místě / virtuální příplatky zůstanou oddělené od částky stržené kartou.
- Chybí-li účet nebo oprávnění, ukázat důvod a odpovídající cestu ke správci. Propojení bez uložení nemění volby formuláře. Není-li karta kompatibilní s měnou, Fakturoidem, zálohou nebo koncem prodeje, server i editor vrátí konkrétní důvod.
- Server vrací jak nastavené metody, tak právě dostupné metody a stabilní důvody nedostupnosti. Dočasné omezení Stripe automaticky nesmaže nastavenou volbu. Veřejný formulář nabídne jen skutečně dostupné metody; pokud není dostupná žádná a objednávka je placená, vysvětlí nedostupnost před vytvořením objednávky a ponechá vyplněná data.
- Při odpojení nebo změně příjemce v jiné záložce se save/submit znovu validuje; žádné odeslání na starý nebo klientem podvržený účet. Kopie formuláře v jiné unit má kartu vypnutou, dokud se znovu nevybere oprávněný účet.
- Waitlist registrace má „Odeslat přihlášku na čekací listinu“ a nulovou splatnou částku. Při přijetí nabídky vzniká regular objednávka a její vlastní platební capability; platební deadline a deadline pro přijetí nabídky jsou odlišné. Částečné přijetí platí jen své vybrané vstupenky, nikoli celý zbytek čekací skupiny.

### D. Rekapitulace a přechod k platbě

Pořadí informací: akce a pořadatel -> vstupenky/sedadla -> kontaktní email -> částka skutečně splatná nyní -> metoda -> podmínky podle stávajícího formuláře -> hlavní tlačítko. Kontaktní email je vidět před odchodem a lze jej opravit před vytvořením objednávky. Cena obsahuje pouze to, co server opravdu účtuje; nejsou dodatečné karetní poplatky přidané až ve Stripe.

Pro kartu: hlavní akce „Objednat a pokračovat k platbě“, pod ní „Zaplatíte bezpečně přes Stripe. Vstupenky obdržíte po potvrzení platby.“ Pro banku: stávající potvrzení objednávky a její bankovní instrukce. Pro bezplatnou objednávku: „Dokončit objednávku“, bez platební volby a bez odchodu do Stripe. Pokud jsou obě metody, výchozí první dostupná může být karta, ale metoda je jasně viditelná a změnitelná před odesláním.

Ihned po stisku zobrazit lokální odezvu, blokovat opakované odeslání a zachovat rekapitulaci; po cca 1 s zobrazit „Připravujeme platbu…“. Při nejasném výsledku použít tentýž command ID. Není dovoleno ukazovat úspěšný nákup ani „Zkusit novou objednávku“, když mohl původní příkaz commitnout. Neúspěšné vytvoření Stripe Session po úspěšné SQL objednávce zobrazí existující order symbol a „Pokračovat v platbě“; znovu se nevytváří vstupenky.

Přihlášení ani registraci návštěvníka nepřidávat. Údaje pro kartu a případné 3D Secure zadává Stripe. Uživatel může změnit kartu nebo opravit zamítnutou platbu přímo v Checkout; není to důvod založit další Festapp objednávku. Uložená karta / Google Pay / Apple Pay se neslibují ikonou, pokud nejsou pro konkrétní platformu a účet skutečně dostupné; Google přihlášení pořadatele je nezávislá věc.

### E. Samostatný web, iframe a nativní aplikace

| Povrch | Odchod a návrat | Co se musí zachovat |
|---|---|---|
| Běžný web | Stripe-hosted Checkout v témže tabu; success/cancel na tenant origin | Existující order/attempt, safe návratový kontext, vybraný jazyk; back nesmí znovu submitnout formulář |
| Formulář vložený v iframe | Po vytvoření objednávky zobrazený přímý odkaz „Otevřít bezpečnou platbu v nové kartě“ na tenant handoff; otevření je výslovný uživatelův klik | Parent se nenaviguje, Stripe se nerenderuje do vnořeného iframe a nedostává osobní data přes embed bridge |
| Flutter web | Stejný princip jako běžný web; web router obnoví správnou tenant/form routu | Nepoužívat `dart:io`, nezdvojit příkaz po obnově runtime |
| Android/iOS | Externí systémový prohlížeč pro Checkout; návrat na HTTPS tenant stránku vždy funguje, návrat do aplikace jen přes existující ověřené app-link routování | Po `resume` read-only dotaz; zavření browseru ani kill aplikace neztratí objednávku; emailový odkaz slouží jako obnova |

Tenant handoff v novém tabu nejprve spotřebuje omezený handoff scope a teprve na vlastním originu připraví/otevře tentýž Stripe pokus. Nesmí se spoléhat na `window.open` až po dlouhém `await`, který browser zablokuje. Odkaz má `noopener`; citlivá oprávnění zůstávají uvnitř tenant kontextu a fragmentu. Nezavádět nové zprávy embed protokolu s URL Checkout, capability nebo payment status. Původní iframe si může vlastní oprávněnou observací obnovit stav; zavřené nové tabu nepovažuje za neúspěšnou platbu.

U sandboxovaného CMS, který nepovolí nové okno/tab, zobrazit instrukci „Otevřete formulář samostatně“ a odkaz. **Před potvrzenou objednávkou** může vést na obecný formulář se zachováním dat v mezích existujícího kontraktu. **Po potvrzení objednávky** musí pokračovat na její chráněný handoff/přehled, nikdy na prázdný nový nákup. V nepodporovaném CMS nepředstírat možnost karetního checkoutu. Rozšířit `docs/integrations/embedded-checkout.md` o přesný karetní kontrakt a potřebné sandbox atributy ověřené na fixture.

### F. Stavová matice návštěvníka

Serverový safe DTO přehledu oddělí `orderState`, `paymentState`, `admissionState`, `deliveryState`, `reservationExpiresAt`, `serverNow` a dovolené akce. Jména jsou navržený kontrakt, ne tvrzení o existujících polích. Stavy projekčně odvozovat z kanonických faktů; neukládat novou paralelní pravdu jen kvůli UI. Existující `order_view` může číst rozšířený safe DTO, ale pay akce vyžaduje zvláštní bearer. Token se nikdy nevrací jako součást tohoto DTO.

| Stav | Hlavní text | Hlavní akce / omezení |
|---|---|---|
| Objednávka vytvořena, platba připravena | „Dokončete platbu X Kč“; platnost rezervace | „Pokračovat k platbě“ se stejným platným pokusem |
| Připravování/nejistý timeout | „Ověřujeme přípravu platby“ | Bounded observace, poté „Ověřit stav“; nevytvářet novou objednávku |
| Návrat přes cancel URL / zavřená platební stránka | „Platba zatím není potvrzená“ | Po načtení serverového stavu pokračování, pokud je pokus stále otevřený; návrat není storno objednávky |
| Platba se potvrzuje | „Ověřujeme výsledek platby“ | Žádné druhé tlačítko Zaplatit, žádné potvrzení jen podle URL |
| Zamítnutá karta, pokus zůstává otevřený | „Platba nebyla dokončena“ | „Pokračovat k platbě“; detail karty zůstává u Stripe |
| Zaplaceno, doručování ve frontě | „Zaplaceno. Vstupenky připravujeme.“ | „Zobrazit objednávku“; nevyzývat k další platbě |
| Zaplaceno, email přijala odesílací služba | „Zaplaceno. Email se vstupenkami byl předán k odeslání.“ | Nenazývat provider acceptance doručením do schránky |
| Zaplaceno, email selhal/potlačen | „Platba je v pořádku, email se nepodařilo odeslat“ | Odkaz na přehled a kontakt pořadatele; resend pouze existující autorizovanou cestou |
| Vypršel čas bez zaplacení | „Rezervace vypršela“ | Nová objednávka až po definitivním serverovém vyloučení platby; neobnovovat původní sedadla automaticky |
| Přijata pozdní nebo duplicitní úhrada | „Platbu evidujeme. Objednávku musí dořešit pořadatel.“ | Kontakt pořadatele; neslibovat automatickou refundaci ani platnou vstupenku |
| Refundace čeká | „Vrácení peněz se zpracovává“ | Ukázat potvrzený stav platnosti vstupenek samostatně, neslibovat pevný termín připsání |
| Částečně vráceno | „Vráceno X Kč z Y Kč“ | Viditelné konkrétní platné/zrušené vstupenky; dořešení nevydávat za další dluh |
| Plně vráceno | „Platba byla vrácena“ | Neaktivní vstupenky výslovně označit, bez akce Zaplatit znovu |
| Vstup pozastaven kvůli sporu | „Platnost vstupenek je pozastavena“ | Kontakt pořadatele, stav nesmí být jen červený badge |
| Offline / stav dočasně nedostupný | „Aktuální stav nelze ověřit“ + čas poslední kontroly | Obnovit po návratu online; žádný optimistický úspěch, neaktivovat placení z neověřeného stavu |
| Neplatný/odvolaný soukromý odkaz | „Tento odkaz už není platný“ | Kontakt / oprávněné znovuzaslání; bez odhalení emailu nebo existence cizí objednávky |

Po návratu první čtení ihned, potom navrženě po 2/3/5/10/10 s; nejvýše cca 30 s v popředí. Čte se pouze lokální serverová projekce, ne Stripe API na každé otevřené stránce. Po limitu stabilní text „Potvrzení trvá déle“ a „Ověřit stav“, žádný nekonečný spinner nebo automatická opakovaná platba. Po skrytí záložky observaci pozastavit, při návratu aktualizovat a při dispose zrušit listenery. Jednorázový serverový preflight při zahájení platby používá ohraničenou recovery cestu, ne side effect v obecném read RPC.

Odpočet počítá ze serverového času a expirace; lokální čas zařízení neautorizuje nákup. Oznámit blížící se konec a konec bez předčítání každé sekundy screen readeru. Po vypršení načíst serverový stav místo okamžitého tvrzení o neúspěchu. Dvě záložky stejné objednávky sdílejí serverové pořadí a jeden aktivní pokus; stará odpověď nesmí přepsat novější zaplaceno/refundováno.

### G. Správa objednávky, výjimky a komunikace

Detail objednávky ukáže částku objednávky, přijatou částku, úspěšně vrácenou částku, stav sporu, platnost vstupenek, příjemce a poslední synchronizaci. V timeline použít skutečný čas události a zvlášť čas přijetí do Festapp. Odkaz „Otevřít platbu ve Stripe“ vede do správného účtu a prostředí; nemá-li uživatel Stripe přístup, jeho Festapp oprávnění ho nenahrazuje. Stripe receipt není automaticky daňový doklad nebo doklad z Fakturoidu.

Úloha `action_required` má důvod, částku, stav vstupenek, přiřazení správci a auditované uzavření. Pozdní/duplicitní úhrada: „Otevřít Stripe a vrátit platbu“, poté čekat na ověřený webhook/recovery; ruční tlačítko nesmí prohlásit refundaci za hotovou. Částečné vrácení: vybrat konkrétní nepoužité vstupenky k vyřazení, nebo potvrdit vrácení části ceny bez změny vstupenek. Konflikt s použitou vstupenkou ukázat přímo v seznamu, zachovat audit. Před uložením znovu ověřit aktuální skeny a provider revizi.

Upozornění pořadateli je trvalý banner/badge v detailu a jedna deduplikovaná zpráva do současné emailové fronty; opakování webhooku neposílá nový email. Zákaznická potvrzení rozlišují objednáno, zaplaceno, vstupenky a refundováno. Pokud pořadatel současně aktivuje Stripe receipts, nezavádět další duplikovaný Festapp platební receipt; ponechat odlišnou objednávkovou/vstupenkovou komunikaci. Neúspěch emailu nemění stav platby.

Skener při holdu ukáže „Vstupenka je pozastavená. Ověřte u pořadatele.“ a nepropustí vstup. Není potřeba ukazovat brigádníkovi citlivý detail finančního sporu. Při offline kontrole Stripe vstupenky: „Pro tuto vstupenku je nutné připojení“ a možnost opakovat; nepoužít úspěšnou barvu/zvuk. Ruční override jen samostatným oprávněním s identitou obsluhy a důvodem, nikdy automaticky.

### H. Přístupnost, responzivita a lokalizace

Implementační cíl WCAG 2.2 AA je technický požadavek projektu, nikoli právní certifikace. Vlastní rozhraní ověřit s klávesnicí a screen readerem; externí Stripe obrazovky jsou samostatná hranice ověřená sandbox průchodem.

- Ovládání dostupné Tab/Shift+Tab/Enter/Space, viditelný focus nezakrytý sticky akcí. Po validační chybě focus na shrnutí s odkazy k polím; po návratu do aplikace na nadpis stavu, ne do prázdné routy. Při tichém přepočtu focus nepřeskakuje.
- Nativní radio/fieldset/legend na webu, odpovídající `Semantics` ve Flutteru. Chyba u pole a vazba přes `aria-describedby`; stavová oblast `aria-live=polite`, urgentní chyba oznámena jednou. Aktualizace času a poll nesmějí opakovaně číst celou objednávku.
- Minimálně 4,5:1 běžný text a 3:1 velký text / důležité hranice komponent; ověřit skutečné tenant barvy a dark mode. Dotykové cíle navrženě nejméně 44 x 44 CSS px, nativně podle stávajících platformních pravidel. Zákaz hover-only vysvětlení.
- Šířka 320 CSS px, web zoom 200 % a reflow při 400 %, Flutter velký text; žádný horizontální scroll pro cenu a CTA, dlouhé názvy a emaily se zalomí. Sticky tlačítko respektuje safe area a klávesnici a nezakryje chyby/podmínky.
- Všechny texty v existujících `*_strings.dart` / JS strings a podporovaných překladech, bez nových hardcoded CZ dialogů. Měny přes existující lokalizované formátování; nerozřezat znak měny ruční interpolací a nezaokrouhlit centy. Datum/čas dle jazyka a timezone akce.
- `prefers-reduced-motion`, žádné oslavné animace před potvrzením platby. Vložený formulář nesmí přebarvit hostitelskou stránku nebo jí blokovat scroll. Odkaz do nového tabu tuto skutečnost oznamuje textem.

### I. Chybový kontrakt a ověřitelné copy

Backend používá stabilní aplikační kódy, nikoli syrovou chybu Stripe. Následující kódy jsou návrh pro implementaci; existující error envelope zachovat nebo vědomě rozšířit v obou klientech. Odpověď obsahuje bezpečný correlation ID, nikoli provider secret.

| Situace / navržený kód | Zpráva uživateli | Zachování stavu |
|---|---|---|
| `stripe_connection_not_ready` | „Platba kartou teď není dostupná.“ | Před submit ponechat formulář; po commitu zachovat objednávku |
| `payment_method_not_supported` | „Pro tuto objednávku nelze použít kartu.“ + konkrétní veřejný důvod | Nabídnout jiné povolené metody pouze před vytvořením |
| `checkout_preparation_pending` | „Ověřujeme přípravu vaší platby.“ | Stejný command/attempt, žádné druhé submitnutí |
| `reservation_expired` | „Čas na dokončení objednávky vypršel.“ | Nový nákup až po ověření platebního závodu |
| `payment_already_received` | „Tato objednávka už je zaplacená.“ | Přepnout na stav vstupenek, ne Stripe |
| `payment_action_not_allowed` | „Z tohoto odkazu nelze pokračovat v platbě.“ | View zůstává read-only; soukromý platební odkaz z emailu |
| `provider_temporarily_unavailable` | „Platební služba je dočasně nedostupná.“ | Retry jen existujícího pokusu po ověření |
| `order_requires_attention` | „Objednávku musí dořešit pořadatel.“ | Potvrzená finanční fakta a kontakt, nikoli další platba |

## Realizační vlny

### 0. Návrh obrazovek a jejich datového kontraktu

Před implementací uložit screen inventory a konkrétní návrhy v návaznosti na UI/UX část tohoto plánu: nepřipojený/připravený/omezený účet; nastavení formuláře; preview obou metod; připravování, čekání, zaplaceno s nedoručeným emailem; refundace a dořešení v administraci. Ukázat desktop i mobil, dlouhý název příjemce a skutečné tenant light/dark tokeny. Pro statické návrhy případně použít self-contained HTML otevřitelné přímo z disku, bez serveru; následná kontrola skutečné implementace musí proběhnout na obou klientech.

Definovat serverové `allowedActions`, safe DTO a oddělené capability scopes ještě před wiringem tlačítek. Sepsat návratové routy web/embed/native a pravidla uložení draftu. Zachovat konkrétní existující komponenty a patterny; žádné nové veřejné akce pro zákaznické storno ani záměna view odkazu za pay.

Validace: projít návrhem všechny řádky stavových matic a níže uvedená akceptační kritéria. Nejde o nezávislý audit ani schvalování každé obrazovky uživatelem; řešit běžné UI volby autonomně. Výstup: obrazovky, copy a API akce mají jednoznačné mapování a žádná větev nekončí výzvou k nové objednávce při nejasné platbě.

### 1. Ověření podporovaného připojení

Při pozdější realizaci nejprve navázat na existující Stripe účet uživatele, určit jeho dostupné testovací prostředí a ověřit Connect profil. Platební objekty pro Festapp oddělit označením a vlastními webhook endpointy/secrets; neměnit existující Mendelio endpointy. Potom v testovacím prostředí propojit klientem vlastněný účet, včetně loginu přes Google. Platforma a připojený pořadatel jsou dvě odlišné role, které musí testovací nastavení reprezentovat. Potvrdit direct Checkout, plný Dashboard, fee/loss nastavení, scope událostí, podporu měny a navrženou 30minutovou Session. Odděleně ověřit přístup obchodníka přes Google login a návštěvnický 3D Secure návrat; nejsou to stejné identity ani stejný callback. Zdokumentovat konkrétní verze API a omezení účtu řízeného jinou platformou. OAuth pro existující účet a případný Accounts v2 onboarding nejsou dvě paralelní platební implementace: výsledkem musí být stejný connection kontrakt. Nový účet nezakládat bez klientovy volby.

Validace: jeden sandbox průchod připojení, platby a ruční refundace; žádné živé peníze. Pokud chybí přístup do sandboxu, zaznamenat přesný blokátor a nepovažovat externí průchod za ověřený. Výstup: doložená zvolená integrační cesta před implementací jejího callbacku.

### 2. SQL model, oprávnění a obecný součet

Přidat canonical SQL a aditivní forward migrace pro připojení, pokusy, inbox, pohyby, admission hold, pay/handoff/return capability scopes a soukromé emailové zdroje. Rozdělit migrace jen podle skutečného pořadí nasazení, ne přepisovat publikovanou baseline. Změnit `finalize_ticket_order_internal_v1` jen v provider specifických blocích; zachovat receipted vytváření a waitlist finalizaci. Upravit souhrnný přepočet a všechny jeho bankovní zapisovače, včetně zachování `paid_externally`. Stripe volba bez bankovního účtu nesmí přidělovat VS ani generovat bankovní emailové instrukce. Upravit kopírování formulářů/akcí: nekopírovat Stripe příjemce přes hranici pořadatele nebo tenantu. Rozšířit `get_customer_order_overview` a finance report o kanonickou projekci bez ztráty dosavadního kontraktu. Veřejná rozšíření registru operací/Client Sync provést přes jeho existující generátory a kontraktní testy.

Validace: cílené SQL testy nové metody, oprávnění, capability izolace a revokace, přesné měny, atomických rollbacků a existující bankovní/free/deposit/Fakturoid případy. Výslovně test čtecího tokenu, který nesmí získat pay/handoff oprávnění; external-paid nesmí zmizet z přepočtu. Před spuštěním vybrat skutečné testy, zkontrolovat jejich počet. Výstup: Stripe pohledávka bez banky a nezměněné bankovní chování.

### 3. Samoobslužné připojení a backend Checkout

Přidat autorizovaný connection flow, callback a stav připojení v administraci unit. Uchovávat pouze potřebná oprávnění, neveřejné tokeny a backendové secrets; nikdy je nevracet do klienta/logu. Checkout připravit přes durable pokus, napojit `send-ticket-order`, obnovovací endpoint a tenant handoff/return. Callbacky musí mít allowlist originů a bezpečné obnovení unit/form kontextu. Připojení nekopírovat podle shodného emailu. Upravit potvrzovací emaily a payment presentation v obou klientech: karta nemá bankovní QR ani text vyzývající k převodu; reminder odkazuje na platnou order_pay cestu a po úhradě už nevyzývá k platbě. Fakturoid fakturaci nezaměnit s platební metodou; dokud se neověří souběh, serverově nepovolit Stripe na Fakturoid formuláři.

Validace: cílené Deno testy callbacku, CSRF, přepnutí uživatele/unit během callbacku, nepovoleného redirectu, timeout/retry a pokusu uhrazení cizí objednávky. Ověřit ztrátu storage, dvojí klik/dvě záložky, callback replay a oddělení návratového read handle od platebního oprávnění. Výstup: opakování příkazu vrací tentýž pokus a klient může pokračovat bez nové objednávky.

### 4. Potvrzení, refundace, recovery a vstupenky

Implementovat podepsaný Connect webhook v potřebných scopes (payment události připojených účtů, lifecycle připojení podle zvoleného API). Ingest zpracuje úspěchy, refundace, spory, expiraci, capability změny a odpojení. Napojit přepočet, admission hold, všechny přijímací cesty, report včetně denních řad a emailové záměry. Prvotní SQL paid transition pro Stripe musí být podmíněný kapacitou a refund/dispute eligibility, nikoli automatickou reaktivací expired objednávky. Pro přijímací cesty dohledat `scan_ticket`, QR/user varianty a `web_client/src/services/scanner_store.js` plus jejich Flutter adaptéry; neponechat vedlejší cestu bez Stripe online/hold kontroly. Recovery používá tentýž ingest. Admin uvidí úkoly dořešení a čas poslední synchronizace s odkazem do vlastního Stripe Dashboardu.

Validace: Deno podpis/špatné prostředí; SQL duplicitní události, různé event ID stejného ekonomického faktu, obrácené pořadí refundace/úspěchu, rollback email intentu, pozdní platba, storno souběžně s úhradou, částečná refundace bez plošného zneplatnění, otevření/uzavření sporu a zákaz vstupu s hold. Cílený souběhový test platebního pokusu a expirace i scan/dořešení. Refundace po enqueue musí zablokovat neplatný ticket email při send-time. Výstup: žádná dvojí tržba nebo dvojí vydání a dořešitelné nejisté stavy.

### 5. Oba klienti a ověření celé cesty

Form editor ukládá povolené metody a oprávněné připojení; SQL je autorita. Konkrétní švy: `form_settings_content.dart`, `FormEditorDraft`, sdílená `FormDefinition` a bundle DTO; JS `order_preview.js`, `form_page.js`, `order_result.js`, `order_overview.js`; Flutter `order_preview_screen.dart`, `order_finish_screen.dart`, `customer_order_overview.dart`; administrace unit a detail objednávky. Vygenerovat routy běžným postupem, needitovat `app_router.gr.dart` ručně. Ve všech těchto cestách dodržet UI/UX matice, včetně iframe, zachování draftu, stavů delivery a dořešení. Dokud skener nepodporuje domluvenou online politiku, nepovolit pilot pro jeho akci.

Validace: cílené JS a Flutter testy změněných cest, pouze jeden Flutter proces a testy `--concurrency=1`; sandbox E2E proti izolovaným datům pro úspěch, 3D Secure, zamítnutí, opuštění Checkout, opětovné pokračování, Google login klienta a refundaci v Dashboardu. Nezachytávat skutečné credentials do snímků/logů a neautomatizovat klientův osobní účet bez zadání. Ověřit web/embed cross-site fixture a native resume/restart; chybějící iOS/Android zařízení nahradit konkrétně přiznanou mezerou, ne tvrzením o ověření nativu. Browser v izolované headless session; nezasahovat do uživatelova okna. Výstup: stejný výsledek v obou klientech a shodné finance/skener/report, plus doložené podmínky kompatibility.

### 6. Samostatně autorizovaný pilot

Schéma a backend zavést před klienty, výchozí Stripe příznak vypnutý. Před produkční migrací ověřit aktivaci kanonického backendu a tenant identitu. Pilot až na výslovně zvoleném tenantovi/unit/akci; nepropagovat na ostatní prod větve. Klient musí dokončit vlastní aktivaci Stripe. Reálnou zkušební platbu/refundaci provést jen se zvláštním souhlasem k finanční operaci.

Rollback: vypnout nové Stripe pokusy, zachovat webhook/recovery, historii a rozpracované platby. Nemažte tabulky ani neodpojujte účet při technickém rollbacku. Sledujte stáří nevyřízených inboxů/pokusů, selhání podpisů a dořešované případy, bez citlivých údajů.

Rutinní nasazení a ověření živé verze delegovat podle AGENTS.md po přípravě validovaných změn a přesného rozsahu. Web lokálně sestavit a použít `automation/deploy_direct.sh`; tento plán žádné nasazení neautorizuje. Výstup: provozní průchod vybraného pilota a dohledatelné výsledky všech objednávek.

## Akceptační matice a důkazy

Každý řádek má podmínku, viditelný výsledek a vlastnící vrstvu ověření. Testy vzniknou během implementace; tato plánovací práce je nespouštěla. Není cílem testovat stejnou věc v každé vrstvě: SQL pro autoritu, Deno pro provider/HTTP hranici, UI test pro stav a focus, sandbox E2E pro skutečný handoff.

| ID | Scénář | Požadovaný výsledek / důkaz | Primární vrstva |
|---|---|---|---|
| A01 | Vlastní Stripe, login přes Google, návrat | Správná unit a obchodní účet; nic se nezapne v ostatních formulářích | Sandbox + UI |
| A02 | Zrušení propojení, session expiry, callback replay, jiný uživatel | Zachovaný kontext; žádné přivlastnění účtu ani duplicitní connection | Deno + SQL |
| A03 | Editor/čtenář/bankovní admin zkusí připojit Stripe | Server odmítne i při ručním volání; UI poskytne správnou nápovědu | SQL + UI |
| A04 | Účet umí charges, ale payouts potřebuje údaje | Dvě odlišná sdělení, žádné falešné „vše hotovo“ nebo svévolné plošné zablokování | Provider fixture + UI |
| A05 | Karta bez bankovního účtu, měna s centy | Správná pohledávka a přesná účtovaná částka, žádný bankovní QR/VS | SQL + Deno |
| A06 | Karta s nekompatibilním nastavením / žádná dostupná metoda | Konkrétní důvod před vytvořením, vyplněná data zachovaná | SQL + UI |
| A07 | Změna příjemce nebo odpojení v druhé záložce | Submit znovu validuje účet; historická platba zůstává původnímu příjemci | SQL + Deno |
| A08 | View token / Session ID / odhadnuté order ID použité pro platbu | Žádná pay operace, žádný vydaný pay bearer; soukromá data se neodhalí | SQL + Deno |
| A09 | Dvojí klik, dvě záložky, timeout po commitu Session | Jedna objednávka, jeden aktivní pokus, žádné zdvojení účtované částky | Souběhový test + Deno |
| A10 | Zamítnutá karta, 3D Secure, návrat přes cancel URL | Stejná objednávka, srozumitelný návrat, pokračování bez nové rezervace | Sandbox E2E |
| A11 | Ztráta spojení/storage, zavření browseru, native restart | Obnova z chráněného odkazu; nejistota není důvod k nové platbě | UI + sandbox platformní průchod |
| A12 | Webhook dříve než API odpověď, duplicitně nebo mimo pořadí | Konzistentní finanční fakta a právě jeden paid intent | SQL + Deno |
| A13 | Špatný podpis, nesprávný account/tenant/livemode | Žádný platební zápis ani únik provider detailů | Deno + SQL |
| A14 | Vypršení, storno, zavření prodeje a platba v souběhu | Žádný dvojí prodej; pozdní finance evidované jako dořešení | Souběhový SQL test |
| A15 | Zaplaceno, ale email failed/suppressed/pending | Žádná druhá výzva Zaplatit; přesné oddělené sdělení a kontakt | UI + email eligibility test |
| A16 | Plná refundace před i po enqueue vstupenek | Finance souhlasí; nevydat/neodeslat neplatné vstupenky; historii vstupů zachovat | SQL + send-time test |
| A17 | Částečná refundace u skupiny a použité vstupenky | Nezneplatnit plošně; konkrétní auditované dořešení; žádný nový karetní dluh | SQL + UI |
| A18 | Spor, vyhraný/prohraný spor, události mimo pořadí | Žádná dvojí refundace; hold a jeho změna dle oprávnění/kapacity | SQL + provider fixtures |
| A19 | SQL, QR/user a offline přijímací cesty | Pozastavené vstupenky nepustí; Stripe vyžaduje online; bankovní offline regresně funguje | Scan kontraktní testy |
| A20 | Cross-site iframe auto/fixed/two instances, blokované storage/popup | Bez citlivé postMessage, bez navigace parenta, pokračování stejné objednávky | Existující embed fixture rozšířená o sandbox handoff |
| A21 | Waitlist zdarma, plné/částečné přijetí nabídky | Žádná platba za čekání; úhrada jen nově potvrzených regular vstupenek | SQL + oba klienti |
| A22 | Banka, ruční úhrada, paid_externally, free, deposit, Fakturoid | Regresně stejný stav a doručení; Stripe omezení explicitní | Existující cílené SQL testy |
| A23 | Refundace a platby přes půlnoc / opožděný webhook | Celkový a denní report souhlasí, čas události zachovaný, payout není tržba | Report SQL + formatter test |
| A24 | Klávesnice, screen reader, 320 px, zoom, dlouhý překlad, dark tenant | Focus viditelný, stav oznámený jednou, nic zásadního nezakryté/neoříznuté | Skutečné UI v obou klientech |
| A25 | Pozastavení provozu, výpadek workeru, odpojení přímo ve Stripe | Stop nových pokusů, obnovitelné rozpracované stavy, historie a stáří synchronizace | Deno/SQL recovery + provozní runbook |

### Přiměřená validace při realizaci

- SQL: konkrétní nové testy pod `database/tests/eshop/stripe/` plus dotčené existující scénáře přes `node web_client/scripts/run_db_tests.js <konkrétní-soubor>` s `DATABASE_URL` výhradně disposable lokální DB. Jména nových testů vybrat podle invariantů, nikoli kopírování implementace. Zkontrolovat skutečný počet testů a canonical source parity podle CONTRIBUTING.
- Deno: cílené `*_test.ts` handlerů nové integrace, původní lockfile a potřebné úzké allow flags podle `automation/test_all.sh`. Stub provider pro unit/kontraktní testy; skutečné API jen sandbox průchod, nikoli nečekaný síťový požadavek v běžném testu.
- JS: `pnpm exec node --test` s konkrétními změněnými/new test soubory; zachovat `order_submission_result_lifecycle`, `order_delivery_status`, `order_overview` a embed testy jako regresní švy. Type/schema kontrakty ověřit tam, kde je projekt vlastní, ne přidávat paralelní validátor.
- Flutter: před spuštěním ověřit volný Flutter slot, cílené `fvm flutter test --concurrency=1 <konkrétní-soubor>` / `fvm dart analyze <změněný-soubor>`. Nespouštět více Flutter úloh současně.
- UI: automatizovaný headless agent-browser průchod s izolovanou session až nad skutečnou implementací; přednostně a11y snapshot pro stav, screenshot pro layout/zoom a skutečné theme. Deterministické CI/E2E příkazy zachovat podle repozitáře, ne obcházet přímo Playwrightem. Kde nejde OAuth/Google bezpečně automatizovat, zdokumentovat omezený manuální sandbox krok bez sdílení credentials.

### Brány před pilotem a residualní rizika

1. **Propojení:** skutečně doložené připojení existujícího účtu a jeho finančního modelu. Bez toho nelze nahradit požadavek klienta jiným typem účtu.
2. **Produktové nastavení:** potvrzená dostupná délka Session a serverově sladěná 30minutová kapacita; pořadatel zná politiku částečných refundací, sporů a online vstupu. Jsou to návrhové volby tohoto plánu, nikoli dříve uživatelem odsouhlasené obchodní podmínky.
3. **Bezpečné chování:** A08-A19 bez otevřeného selhání, zvlášť view/pay hranice, peníze, kapacita a admission. Známý problém v těchto oblastech nelze přejmenovat na UX drobnost.
4. **Povrchy:** každý povolený povrch má doložený happy path a návrat po přerušení. Neověřený native/iframe/CMS se neoznačuje za podporovaný; pilot může být explicitně web-only, není to důkaz hotového nativu.
5. **UI:** skutečné mobilní/desktop snímky hlavních stavů, klávesnicový průchod a přístupnost; pouhé čtení zdrojů nebo statický návrh není vizuální QA. Historický screenshot v `docs/archive/evidence/embedded-checkout-2026-10-20/` sloužil při tomto plánování jen jako kontext současného toku, ne jako ověření budoucího Stripe UI.
6. **Provoz:** existuje recovery, vypínač nových plateb, upozornění správci, readback historie a postup dořešení při odpojeném Stripe. Retence inbox payloadů/tokenů se řídí existujícími pravidly pro tajné/platební údaje; používat minimální fakta, ne nekonečný archiv celých provider odpovědí.
7. **Rozsah:** konkrétní tenant, unit, akce a další produkční či finanční úkony mají odpovídající zadání. Tento prohloubený plán je neprovádí.

Největší nejistoty jsou kompatibilita skutečného Connect profilu s existujícím účtem, sladění expirace s kapacitou, native/iframe návrat a změny platnosti vstupenek při refundacích. Existující Stripe účet uživatele je potvrzený; jeho testovací přístup a Connect nastavení nebyly při plánování ověřeny, stejně jako živé platby a nové obrazovky. Implementaci lokálních kontraktů to neblokuje, ale první externí vlna a uvedené produktové volby musí být uzavřeny před pilotem.

## Zachované a nahrazené hranice

| Hranice | Cílová akce | Důkaz |
|---|---|---|
| BankSync ingest a bankovní ledger | Zachovat pro převody | Bankovní regresní testy |
| Povinný výběr banky/QR/VS v obecné finalizaci | Omezit výslovně na bankovní metodu | Stripe-only objednávka bez banky a bez QR/reference |
| Přímé přepisování souhrnů jednotlivými adaptéry | Převést na společný SQL součet | Bankovní přepočet nepřepíše Stripe fakta |
| Zaplacení a doručení vstupenek | Zachovat společný SQL/email kontrakt | Atomický test paid + email intent a replay |
| Fakturoid, bezplatné a zálohové objednávky | Zachovat; nepodporované Stripe kombinace odmítnout | Dosavadní scénáře a explicitní serverové chyby |
| Ruční refundace a spory | Finance vlastní Stripe Dashboard klienta; Festapp přebírá dopad | Dashboard změna se projeví v reportu a vstupní kontrole |

## Definice hotovo

Klient se připojí včetně Google loginu, vidí platby na svém účtu a sám spravuje své finance. Oba klienti umožní bezpečně zaplatit a pokračovat v existující objednávce bez rozšíření read-only oprávnění. Ověřený úspěch vydá vstupenky jednou, refundace/spor ovlivní evidenci i vstupní oprávnění podle výslovné politiky, pozdní platba neprodá obsazené místo. Bankovní cesta a společná emailová fronta zůstávají funkční. Všechny povolené povrchy splňují příslušné řádky A01-A25 a pilot splnil své brány; nepodporované kombinace jsou explicitní a serverově vynucené. Lokální hotová implementace, ověřený sandbox a aktivní produkční pilot jsou tři samostatně vykázané stavy.

## Primární externí zdroje

Ověřeno při plánování 2026-10-21; před implementací první vlny ověřit znovu relevantní API kontrakty.

- [Přihlášení do Stripe přes Google](https://support.stripe.com/questions/log-in-to-stripe-with-a-google-account)
- [Direct charges a Checkout](https://docs.stripe.com/connect/direct-charges?platform=web&ui=stripe-hosted)
- [OAuth a existující účty](https://docs.stripe.com/connect/oauth-standard-accounts)
- [Omezení účtů řízených jinou platformou](https://docs.stripe.com/connect/oauth-changes-for-standard-platforms)
- [Doporučení Accounts v2 pro nové platformy](https://docs.stripe.com/connect/accounts-v2/saas-platform-payments-billing)
- [Dashboard a odpovědnosti](https://docs.stripe.com/connect/accounts-v2/connected-account-configuration)
- [Connect webhook scopes a události](https://docs.stripe.com/connect/webhooks)
- [Checkout Session API, příjemce, cena a návratové parametry](https://docs.stripe.com/api/checkout/sessions/create)
- [OAuth reference a povolené redirect URI](https://docs.stripe.com/connect/oauth-reference)
- [WCAG 3.3.1: identifikace chyby](https://www.w3.org/WAI/WCAG22/Understanding/error-identification.html)
- [WCAG 4.1.3: stavové zprávy](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html)
- [WCAG 2.4.11: viditelnost focusu](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html)
- [WCAG 1.4.10: reflow a zvětšení](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html)
