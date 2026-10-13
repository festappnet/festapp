# Kapacita formuláře a náhradnické objednávky

Datum: 2026-10-13
Stav: Autoritativní plán pro implementaci; aplikace dosud nezměněna.
Ověřování implementace: **standard** (souběh, osobní odkazy, platby, migrace).
Podklad: dohoda s uživatelem a cílené čtení pracovního stromu nad HEAD `eb2304724`.

Pracovní strom při přípravě obsahoval rozsáhlé cizí rozpracované změny včetně
dotčených modulů. Tento úkol přidává pouze tento plán a související execution
prompt. Implementátor musí zachovat rozpracovanou práci a před úpravou konkrétního
souboru zkontrolovat jeho aktuální diff. Plán nenahrazuje AGENTS.md, CLAUDE.md,
docs/architecture/ai_context.md ani CONTRIBUTING.md.

## 1. Výsledek a rozsah

Editor nastaví maximální počet lidí ve formuláři. Po naplnění kapacity může
formulář přijímat náhradníky. Editor jim ručně potvrzeným odesláním nabídne volná
místa. Osobní odkaz otevře předvyplněný formulář; teprve potvrzení osob a produktů
vytvoří běžnou objednávku nebo na ni převede původní náhradnickou objednávku.

Součástí je SQL, migrace, Flutter administrace i formulář, veřejný JS formulář,
e-mailové šablony a jejich proměnné, Client Sync, historie, oprávnění a cílené
testy. UI využije existující formuláře, tabulky, dialogy, lokalizace a ukládání.

Mimo rozsah: společná kapacita celé události, náhradníci k plánku, automatické
odesílání nabídek, vlastní štítky/prioritní pravidla, limit počtu náhradníků,
automatický návrat ze stornované běžné objednávky, nový platební nebo e-mailový
engine, nasazení a propagace na produkční tenanty. Návrh ponechá jasnou hranici
pro budoucí kapacitu události, ale nyní nevytváří obecný víceúrovňový framework.

## 2. Závazná produktová rozhodnutí

Tato část zachycuje poslední schválené znění. Dřívější návrh samostatného typu
náhradnické přihlášky mimo `eshop.orders` je **nahrazen** společným záznamem
objednávky. Neimplementovat obě varianty.

1. Kapacita počítá **osoby**, nikoliv objednávky, produkty nebo součet produktových
   položek. Běžná nezaplacená objednávka kapacitu obsazuje.
2. Nastavení je per formulář. Bez limitu není režim náhradníků dostupný. Při
   `forms.blueprint IS NOT NULL` není dostupný limit formuláře ani náhradníci.
3. Veřejné přihlašování náhradníků se otevře pouze při naplnění dostupné kapacity
   a zapnutém režimu. Náhradník nevybírá produkty a nemá nic platit.
4. Existující omezení počtu osob v jedné objednávce platí i pro náhradníky.
   Celkový počet čekajících se zatím neomezuje.
5. Jedno podání nekombinuje běžnou a náhradnickou objednávku. Jsou-li volná dvě
   místa, běžnou objednávkou nelze přihlásit čtyři. Zbytek musí být samostatné
   náhradnické podání, až je veřejná kapacita vyčerpaná.
6. Aktivní čekající chrání odpovídající počet volných míst před veřejným prodejem.
   Uvolní-li se pět míst a čekají dvě osoby, tři se automaticky vrátí do prodeje.
7. Návrh příjemců se řadí podle času přihlášení a může zahrnout část skupiny.
   Editor musí návrh potvrdit a může vybrat kohokoliv. Automatické odeslání není.
8. Editor nabízí **počet míst**, nikoliv jména. Příjemce určí přijímané osoby.
   Nabídka má výchozí platnost ve formuláři, upravitelnou před odesláním.
9. Platná nabídka drží kapacitu osob. Příjemce nemusí potvrdit všechna místa
   najednou. Nepotvrzená místa dál čekají; menší objednávka není odmítnutí zbytku.
10. Přijetí, odmítnutí i zrušení čekání jsou možné jednotlivě. Editor může přijmout
    za příjemce přes stejný formulář, odmítnout jednotlivá místa nebo zrušit nabídku.
11. Vypršení, odmítnutí a zrušení nabídky editorem přesunou dotčené čekání na konec,
    s odlišným stavem, **bez blokování kapacity**. Automatický předvýběr je přeskočí.
    Editor je může ručně oslovit znovu, pokud je kapacita. Ostatním zůstane pořadí.
12. Vlastní zrušení čekání vyřadí dotčené osoby z aktivního pořadníku. Není to storno
    již vzniklé běžné objednávky a veřejný odkaz nesmí takové storno umožnit.
13. Osobní odkaz s tajným tokenem otevře předvyplněnou objednávku, nikoliv rovnou
    provede přijetí. Přijetí je explicitní potvrzení formuláře. Nabídka platí i po
    ručním uzavření běžného přihlašování nebo po jeho termínu.
14. **Poslední upřesnění kapacit produktů:** nabídka produkty nerezervuje. Produkty
    se obsadí až potvrzením běžné objednávky, včetně nezaplacené. Vybírá se podle
    aktuální dostupnosti. SQL musí současně zajistit kapacitu formuláře, maxima
    vybraných produktů i jejich inventory kontexty/pooly. Nabídka nezaručuje produkt.
15. Při přijetí celé zbývající náhradnické objednávky zůstává stejný order ID,
    `order_symbol`, `order_sequence` a historie. Při přijetí části vznikne nová
    propojená běžná objednávka a původní se zmenší. Každé samostatné částečné
    potvrzení vytváří novou objednávku; neupravuje už zaplacenou předchozí.
16. Storno běžné objednávky člověka nevrací mezi náhradníky.
17. Společná tabulka: jeden řádek za objednávku, jednotliví lidé/nabídky v detailu.
    Výchozí filtr **Aktivní** zahrnuje běžné nestornované objednávky a náhradnické
    objednávky s alespoň jedním aktivním čekajícím nebo platnou nabídkou.
18. Neaktivní náhradníci se ukážou po vypnutí filtru; zobrazit skutečný důvod,
    nikoliv „Storno“. Ve smíšené skupině jsou v detailu dostupní všichni zbývající.
19. Použít stávající práva pro prohlížení/správu objednávek, bez nové role.
20. Limit nesmí klesnout pod běžně obsazená místa plus platné nabídky. Samotné
    aktivní čekání tuto spodní mez nezvyšuje.
21. Dokud existují aktivní čekající nebo platné nabídky, nelze vypnout náhradníky,
    odstranit limit ani přepnout na plánek. Vynucení v SQL i vysvětlení v UI.
22. Zobrazení počtu zbývajících míst je nastavitelné, **výchozí hodnota zapnuto**.
    Číslo znamená místa skutečně dostupná běžnému přihlášení.
23. Při plné kapacitě bez náhradníků zůstane úvod formuláře a „Kapacita je naplněna“.
    Po uvolnění místa se přihlašování opět zpřístupní.

## 3. Ověřené výchozí body

| Fakt v pracovním stromu | Zdroj | Dopad |
| --- | --- | --- |
| Order má form, state, nullable payment_info, symbol a pořadí | `database/tables/tables.sql`, `eshop.orders` | Rozšířit existující objednávku, nevytvářet druhý root záznam |
| Veřejná tvorba má command receipt a transakční e-mailový intent | `database/functions/eshop_orders/create_ticket_order_client_sync_v1.sql` | Náhradnické operace musí mít stejné retry/sync vlastnosti |
| SQL tvorba načte formulář `FOR SHARE`, pak vytváří identitu, tickets, produkty, platbu a allocations | `database/functions/eshop/create_ticket_order.sql`, `create_ticket_order_internal_v1` | Pro limit nutná exkluzivní serializace; rozdělit přípravu identity od finalizace |
| Kontrola product.maximum počítá order_product_ticket; v této smyčce není product row lock | tentýž soubor, blok `product_data.maximum` | Form lock nestačí pro produkt sdílený více formuláři; zabránit check-then-insert race |
| Allocator vybírá spots pomocí `FOR UPDATE SKIP LOCKED` | `database/functions/inventory/apply_allocations.sql` | Zachovat canonical allocations, netvořit paralelní sklad |
| Dostupnost rozlišuje physical capacity, secret hold a sellable_capacity | `database/functions/inventory/is_product_dynamically_available.sql` | Ověřit stejné podmínky ve writeru; zobrazení samo negarantuje rezervaci |
| Edge flow má také Fakturoid prepare/complete/abort | `supabase/functions/send-ticket-order/index.ts` | Nevolat fakturaci pro waitlist; finalizaci přijetí integrovat s existujícím recovery |
| Mutable guard i filtr používají širokou podmínku „není storno“ | `database/functions/eshop_orders/check_order_is_mutable.sql`, `lib/components/eshop/order_grid_filters.dart` | Náhradníci potřebují explicitní operation guards |
| Základní OrderModel má jeden string state | `lib/components/eshop/models/order_model.dart` | Celkový stav nestačí pro částečné nabídky |
| Grid má společné hromadné akce a standardně filtr nestornovaných | `lib/components/eshop/views/orders_content.dart` | Upravit eligible actions a filtr, nikoliv obecně povolit všechny nestornované |
| Form editor používá Save/Discard a rozlišuje partial settings save | `lib/components/forms/README.md`, `views/form_settings_content.dart`, `database/functions/eshop_forms/update_form.sql` | Nová nastavení v existujícím kontraktu, zachovat nesouvisející pole |
| Form bundle je sdílený vstup pro rendering | `database/functions/eshop_forms/get_form_by_link.sql`, `get_effective_form_data.sql` | Přidat serverovou projekci kapacity a režimu |
| Všechny e-maily jdou přes jednu frontu a renderer | `database/functions/emails/email_domain.sql`, `supabase/functions/_shared/emailRenderer.ts` | Nové template codes a producer intents, žádný přímý provider send |
| Šablony dědí occasion/unit/organization | `lib/components/email_templates/README.md` | Dodržet stávající editor šablon a wrapper resolver |

Reprezentativní běžný tok: Flutter/JS -> send-ticket-order -> receipted SQL ->
create_ticket_order_internal_v1 -> products/payment/apply_allocations -> email
intent + Client Sync -> commit -> worker wake. Náhradnické potvrzení vstoupí do
stejné finalizační logiky; nedělá klientské storno a novou objednávku ve dvou krocích.

## 4. Cílový datový model a vlastnictví

Níže jsou **technická návrhová rozhodnutí**, nikoliv tvrzení o existujících tabulkách.
Přesné nové názvy zachovat konzistentně v SQL, modelech, migraci a dokumentaci.

### 4.1 Nastavení formuláře

Přidat typed sloupce na `public.forms`:

- `participant_capacity integer NULL`, NULL = bez limitu, jinak kladné číslo;
- `waitlist_enabled boolean NOT NULL DEFAULT false`;
- `show_remaining_capacity boolean NOT NULL DEFAULT true`;
- `waitlist_offer_duration_seconds integer NULL`, kladné při zapnutí režimu.

CHECK zajistí místní kombinace: blueprint vylučuje participant_capacity i
waitlist_enabled; zapnutí waitlist vyžaduje limit a platnou dobu. Přechodové kontroly
nad objednávkami patří do existujícího explicitního form-save RPC pod zámkem.
Částečný save rozlišuje chybějící klíč (neměnit) a explicitní NULL (zrušit limit).
Duplikace formuláře kopíruje nastavení, nikoliv obsazenost, nabídky, tokeny či pořadník.

Doba není uživatelem číselně určena. Bez domýšlení obchodního pravidla vyžadovat
zadání při prvním zapnutí; v UI zobrazit dny/hodiny, ukládat sekundy.

### 4.2 Objednávka a osoby

- `eshop.orders.state = 'waitlisted'` označí náhradnickou objednávku. Sémantika
  ostatních stavů se zachová. Výjimkou je nové rozlišení způsobilých akcí.
- Waitlisted order má NULL payment_info a NULL price; nemá tickets, produkty,
  allocations ani účetní/fakturační side effects. Nulová cena by mohla spustit
  existující free-order paid flow, proto není reprezentací náhradníka.
- Přidat `eshop.order_participants`: stabilní ID osoby, current_order_id,
  origin_order_id, form_id, odpovědi na osobní pole, ticket_id nullable, lifecycle,
  původní queue timestamp a aktuální queue position timestamp. Jedna osoba je
  jedna jednotka kapacity. Nepočítat osoby přes počet produktových vazeb.
- Náhradnické lifecycle: `waiting`, `offered`, `offer_expired`, `offer_declined`,
  `offer_cancelled`, `withdrawn`; běžné `admitted`, `cancelled`.
- Přesun přijatých participant rows do nové objednávky zachová stabilní ID a
  origin_order_id. Původní objednávka obsahuje pouze zbývající osoby; historický
  snapshot a odkazy uchovají původní složení, bez ztráty odpovědí.
- Přidat nullable `orders.source_waitlist_order_id` pro částečně vzniklé objednávky.
  Při přijetí všech zbývajících osob zůstane původní order ID a source není self-link.

Běžné objednávky: jeden participant na skutečnou osobu/ticket, ne na produkt.
Backfill musí používat distinct order/ticket páry. Případy bez jednoznačné vazby
(např. ticket bez produktu nebo pouze historický JSON) explicitně vyčíslit; nikdy
nevymýšlet osoby podle počtu produktů. Nejasná starší data blokují zapnutí limitu
jen dotčeného formuláře do opravy. Neprovádět nevratný rewrite historických snapshotů.

### 4.3 Nabídka a její místa

`eshop.waitlist_offers`: order/form scope, created_by, created_at, expires_at,
revision a audit metadata. `eshop.waitlist_offer_slots`: jedno rezervované místo,
offer_id, participant_id, výsledek (`pending`, `accepted`, `declined`, `expired`,
`cancelled`) a případná resulting_order_id. Jeden participant nesmí mít dvě pending
nabídky. Opakovaná nabídka je nový offer, stará historie se nepřepisuje.

**Technický předpoklad pro neadresnou nabídku části skupiny:** editor zadává pouze
počet. Server předběžně přiřadí sloty prvním způsobilým osobám té přihlášky podle
stabilního pořadí. Příjemce při přijetí může zvolit jiné dosud čekající osoby stejné
objednávky; server atomicky prohodí vazby, aniž změní počet rezervací nebo pořadí
nepřijatého zbytku. Není to editorův výběr jmen. V detailu vysvětlit, kterých osob
se aktuální nabídka týká a že výběr lze změnit. Při vypršení se neaktivují ostatní
nenabídnuté osoby. Tato deterministická vazba řeší evidenci jednotlivých expirací;
pokud UX zkouška ukáže, že neadresný počet potřebuje jiné chování, konzultovat jen
tento konkrétní bod, ne tiše deaktivovat celou skupinu.

Pokud čekání osoby ukončí vlastní withdrawal, její pending slot se současně uvolní.
Manuální odmítnutí je explicitní akce s výběrem konkrétních osob/míst. Částečné
potvrzení nechá všechny nezvolené pending sloty beze změny.

Přijetí všech **zbývajících osob objednávky** = in-place conversion. Přijetí všech
míst aktuální nabídky nemusí být úplné přijetí objednávky, pokud v ní ještě někdo
zůstává. Neaktivní osoby musí být rovněž vyřešeny, aby nevznikla běžná objednávka
se skrytými čekajícími. Existují-li, jde o částečné přijetí s novým order ID.

## 5. Kapacita a transakční invarianty

Veškeré rozhodování vlastní SQL. Flutter/JS pouze vykreslují serverový snapshot.
Pro omezený formulář v daném serverovém čase:

```
C = participant_capacity
O = počet admitted osob v nestornovaných běžných objednávkách
R = počet pending offer slots s expires_at > server_now
W = počet aktivních waiting osob bez pending platné nabídky
F = max(C - O - R, 0)
H = min(F, W)                         # přednost čekajících bez osobní nabídky
P = max(F - W, 0)                     # dostupné běžné přihlášení
```

- `O + R <= C` je tvrdý invariant. Kapacitu lze snížit na O+R, i když existuje W.
- Nabídka přesune osoby z W do R; nenavyšuje dvakrát obsazení. Ruční oslovení
  neaktivního vyžaduje volné F; editor může přerozdělit přednost, ne obejít C.
- Přijetí přesune n z R do O v jedné transakci. Běžný submit musí mít n <= P.
- Expirovaný pending slot nesmí dál počítat do R ani se jeho osoba automaticky
  vrátit do W. Efektivní projekce používá expires_at i před během cleanup jobu.
- Odmítnutí, expiry, editor cancellation a withdrawal uvolní R/W podle stavu.
- Storno běžné objednávky/části tickets zmenší O a uvolní odpovídající produkty.
- Splatnost platby není sama storno. Bez existujícího explicitního uvolnění se
  nepřestane počítat neuhrazená objednávka jen kvůli názvu `expired`.
- Public counter je P. Admin vidí samostatně O, R, W, P a souhrn C, nikoliv matoucí
  jediné „obsazeno“ zahrnující celý neomezený pořadník.

Příklady: C=100/O=95/R=0/W=2 -> P=3. C=100/O=95/R=2/W=0 -> P=3.
Po expiraci těchto dvou nabídek a bez dalších čekajících -> P=5. Je-li W=10 a
C=100/O=95, P=0 a editor může nabídnout maximálně pět míst.

### Produkty a inventory

Nabídka ani waitlist registrace nevytvářejí `order_product_ticket` ani allocations.
Při potvrzení běžné objednávky validovat celý vybraný košík najednou: product.maximum,
součet požadovaných množství napříč osobami, shared inventory contexts/pools,
sellable_capacity, platné cizí secret rezervace a existující obsazenost.
Použít aktuální serverové ceny, platnost produktů a měnu. Žádné obejití dostupnosti
produktem zaslaným ručně v payloadu. In-place conversion má běžnou novou platební
splatnost od přijetí, nikoliv od registrace náhradníka.

Form row lock nestačí pro produkty sdílené formuláři. Všechny relevantní create,
edit, cancel a limit-change writers musí nabírat příslušné product/pool locky
ve stejném deterministickém pořadí a teprve pod nimi ověřit count/allocate.
`is_product_dynamically_available` je UI hint, ne náhrada writer validace.
V aktuálním allocatoru je vidět rozdíl vůči availability čtení (secret a sellable
limit); wave 2 musí prokázat jejich shodu pro dotčené writers, ne jen znovu zavolat
boolean helper bez zámku.

Pokud produkt mezitím dojde, vrátit strukturovanou chybu produktu. Nezměnit čekání,
nespotřebovat nabídku, nepřevést order state a nevytvořit platbu. Příjemce může
vybrat jiný produkt do konce nabídky. Kapacita formuláře není garance ubytování.

### Souběh a retry

- Serializovat všechny změny počtu osob/nabídek/nastavení per form pod exkluzivním
  form lockem. Nahradit nedostatečný FOR SHARE pro tento write path; neupgradeovat
  zámek až po zápisu, který by vytvořil deadlock.
- Závazné pořadí pro nové a upravené entrypoints: forms podle ID, orders podle ID,
  offers/participants, products podle ID, pools/contexts podle ID, fyzické spots.
  Před wave 2 ověřit kompatibilitu s existujícími order-sequence/advisory a inventory
  locky; změnit dotčené entrypoints společně, nikoliv uprostřed transakce.
- Multi-order storno/edit musí zjistit scope bez mutací, zamknout forms v pořadí,
  znovu ověřit scope a až potom pokračovat. Přímé legacy wrappers nesmí obejít lock.
- Každý command má idempotency key + hash scope/payload/identity. Replay vrátí
  původní výsledek; jiný payload se stejným ID selže. Expiraci kontrolovat serverem
  znovu po čekání na zámek, ne podle času otevření formuláře.
- Slot consumption, participants, order/products/payment, audit, email intents,
  receipt a Client Sync commit jsou atomické. Síťové volání neprovádět pod SQL locky.
- Zachovat existing Fakturoid recovery contract: finalizace přijetí musí mít
  kompenzaci/obnovu návaznou na stejný command. Neimplementovat automatické „vrácení
  do pořadníku“ při skutečném uživatelském stornu. Konkrétní abort semantics před
  použitím doložit cíleným testem; nepředpokládat, že smazání nového order je bezpečné
  pro in-place conversion původního waitlist order.

## 6. Veřejné a interní kontrakty

Navržené operace v `database/functions/eshop_waitlist/`, všechny v public schema:

| Operace | Oprávnění a vstup | Výsledek |
| --- | --- | --- |
| register_waitlist | otevřený formulář, nulové P, zapnutý režim; osoby/odpovědi, command identity | waitlisted order + potvrzovací email intent |
| get_waitlist_offer_proposal | order editor; form ID | snapshot revision, dostupný počet, příjemci/počty, výchozí platnost; žádná rezervace |
| send_waitlist_offers | order editor; explicitní výběr, počty, platnost, revision, command ID | atomické slots, tokeny, email intents; stale návrh vrátí nový stav k potvrzení |
| get_waitlist_offer_form | scoped offer token nebo ověřený editor | minimální předvyplněný bundle, pending počet, expiry, produkty |
| accept_waitlist_offer | scoped token/editor; vybrané person IDs, produkty, answers, command ID | in-place nebo nová běžná objednávka, zbývající nabídka |
| decline_waitlist_offer | scoped token/editor; konkrétní slot/person IDs, command ID | uvolnění, neaktivní pořadí na konci, audit |
| cancel_waitlist_offer | order editor; vybrané pending slots, command ID | stejné uvolnění s odlišným důvodem |
| withdraw_waitlist | manage token/editor; zbývající person IDs, command ID | ukončení čekání a případných slots |
| expire_waitlist_offers | private/service worker, bounded batch | materializace expiry a sync; neopakuje účinky |

Názvy transportních receipted fasád sladit se stávajícím Client Sync v1; helpery
nesmí získat anon grants. Nevytvářet neversionovanou alternativní mutation cestu.
Accepted command používá společnou finalizaci běžné objednávky vyčleněnou z
create_ticket_order_internal_v1. Nová identita se alokuje pouze pro běžnou tvorbu
nebo partial acceptance; existing target order ID je privátní ověřený parametr,
nikoliv volně posílaný anonymním klientem.

Serverový form bundle přidá `capacity` (enabled/limit/remainingPublic/showRemaining)
a `registrationMode` (regular/waitlist/full/closed/blueprint). Administrace navíc
dostane O/R/W, revision a důvody blokovaných změn. Časové uzavření převáží veřejný
waitlist režim; výjimka platí jen pro scoped platnou nabídku, ne obecný query flag.

Chyby rozlišit kódy: FORM_CAPACITY_EXCEEDED, WAITLIST_NOT_AVAILABLE,
OFFER_EXPIRED, OFFER_CHANGED, OFFER_SLOT_ALREADY_RESOLVED,
CAPACITY_BELOW_COMMITTED, WAITLIST_HAS_ACTIVE_ENTRIES, BLUEPRINT_CONFLICT,
PRODUCT_CAPACITY_EXCEEDED, INVALID_CAPABILITY, COMMAND_PAYLOAD_CONFLICT.
Vložit do stávajícího error envelope, nepřepisovat celý veřejný error systém.

### Osobní odkazy a oprávnění

- Bearer capability není záruka „jen konkrétní člověk“: přeposláním lze předat
  přístup. Nevyžadovat nový login/OTP, který nebyl dohodnut. Scope vázat na tenant,
  form, order, offer, povolené operace a platnost.
- Kryptograficky náhodný token alespoň 256 bitů, v DB pouze hash; oddělený manage
  token pro zrušení čekání a offer token pro konkrétní nabídku. Order symbol není
  tajemství a nesmí sloužit jako capability. Nepoužít blueprint session secret.
- Token nepředávat analytice, logům, grid exportům, audit JSON nebo běžnému sync
  feedu. Preferovat URL fragment a výměnu přes POST, `Referrer-Policy: no-referrer`,
  necachovat citlivý bundle; ověřit kompatibilitu stávajícího routeru.
- Opakované otevření odkazu pouze čte. GET, preview e-mailu a crawler nikdy nepřijímá,
  neodmítá ani nespotřebuje slot. POST kontroluje token i osoby na serveru.
- Nabídka může být částečně přijímána opakovaně; token není globálně jednorázový,
  jednorázově se spotřebovávají jednotlivé sloty. Revoke po vyřízení/expiry/cancel.
- Manage token po in-place conversion nedává oprávnění stornovat běžnou objednávku.
  Náhodné ID/token kombinace vracejí bezpečnou chybu bez úniku cizích osobních údajů.
- Service role transport nevylučuje explicitní scope/permission validaci. Read-only
  order viewer nemůže mutovat. Žádné nové SECURITY DEFINER bez fixed search_path,
  explicitních oprávnění a parametrizovaných vstupů; nové tabulky bez přímého anon čtení.

## 7. UI podle současných komponent

### Nastavení

V `form_settings_content.dart` sekce „Kapacita a náhradníci“, existující Save/Discard.
Limit jako volitelná hodnota, počet zbývajících míst default zapnutý. Po zadání
limitu nabídnout „Povolit náhradníky“, po zapnutí pole platnosti nabídek. Nastavení
platnosti nabídky není stávající platební splatnost. Při plánku sekci nenabízet.
Blokovanou změnu doprovodit důvodem a aktuálními O/R/W. Žádné tiché mazání čekajících.

### Přehled objednávek

Použít `OrdersContent`, `SingleTableDataGrid`, stávající sloupce a jejich filtry,
symbol, řazení, export, poznámky, historii a email delivery status. Jeden row/order.
Výchozí checkbox filtr „Aktivní“ rozšíří význam jen v order listu; nesmí změnit
chování sdíleného filtru historie nebo tickets tab bez důvodu.

Waitlisted řádek: identity + kontakt + form + textový souhrn např.
„2 čekají · 1 nabídnuté místo“. Platební cena/splatnost prázdná; žádné QR/upomínka.
Jeden terminální důvod zobrazit jménem, smíšené důvody rozbalit v detailu. Nespoléhat
na barvu. Export nese typ/stav a počty, nikoliv falešné finanční nuly.

Toolbar nabídku zobrazí jen pro způsobilý formulář a oprávnění. V occasion přehledu
nenabízet součet míst napříč formuláři jako společnou kapacitu; akce vyžaduje výběr
jednoho formuláře. Hromadné akce mají explicitní eligible predicates. Smíšený výběr
nesmí tiše vynechávat waitlist položky a zároveň tvrdit, že zpracoval vše.

Souhrn nad přehledem formuláře: „Kapacita 100 · Přihlášeno 95 · V nabídkách 2 ·
Čeká 4 · Volná místa pro veřejnost 0“. Zobrazit akci na nabídnutí, pokud existují
volná F; návrh nic neodesílá. Po stornu pouze obnovit souhrn, neodesílat automaticky.

### Detail a odeslání

Detail řádku drží seznam osob, jejich stav, původní pořadí, aktuální nabídku/termín,
historii nabídek a propojené objednávky. Při in-place conversion zůstane historie
uvnitř běžné objednávky, nevzniká další „vyřízený“ řádek.

Odesílací dialog/stránka použije existující dialogové vzory: příjemci s editovatelným
počtem míst, termín, součet proti F, náhled e-mailu a jediná primární akce „Zaslat
nabídky“. Stale revision vyžaduje obnovení a nové potvrzení. Stav „Ve frontě“ není
„Doručeno“. Znovu kliknutí se stejným command ID nevytvoří další nabídku.

### Veřejný formulář

- Regular: běžný formulář, max osob min(per-order limit, P); při zapnutém counteru
  „Zbývá N míst“. Neodeslat větší skupinu a nesmí ji automaticky rozdělit.
- Full: úvod + „Kapacita je naplněna“ bez submitu, pokud náhradníci vypnutí.
- Waitlist: jasný titulek, osobní/kontaktní pole, žádné produkty/cena/platba.
  Potvrzení vysvětluje, že jde o čekání, ne garantovanou účast.
- Offer: stejné form builders, předvyplnění, počet dostupných míst a pevný termín,
  výběr přijímaných osob, aktuální produkty. Explicitní potvrzení a samostatné
  odmítnutí vybraných míst. Odmítnutí není zavření stránky ani menší počet přijatých.
- Po partial success zobrazit vzniklou objednávku a zbývající nabídnutá místa;
  nevymazat zbývající čekání. Editor používá stejnou komponentu s editor auth.
- Expired/cancelled/invalid link: srozumitelný stav, žádný aktivní platební formulář.
  Po submit race vrátit nový stav bez ztráty vyplněných nesenzitivních hodnot.
  Přechod regular -> waitlist musí uživatel potvrdit.

Stávající form.fields s povinnými product-dependent poli potřebují serverovou
i klientskou validaci podle režimu: při waitlist nevyžadovat skryté produktové
odpovědi, při acceptance je znovu vyžadovat. Server nesmí důvěřovat režimu v payloadu.
Původní odpovědi mapovat stabilními field IDs; odstraněné pole zachovat v historii,
nové povinné doplnit. Změna form schema nesmí přepsat údaje osoby jinou osobou.

Zachovat responzivitu, lokalizace, keyboard focus a zřetelné loading/error stavy.
Pokud je feature vypnutá, skrýt provozní waitlist UI; historické údaje nesmazat.
Dosavadní history/detail musí historický waitlist stav umět zobrazit i po vypnutí.
Reaktivace staré neaktivní osoby vyžaduje znovu zapnutý způsobilý režim.

## 8. E-maily, token delivery, sync a expirace

Nové template codes: `waitlist_confirmation` a `waitlist_offer`. Využít stejné
dědění occasion/unit/organization, wrapper, editor proměnných a lokalizační cestu.
Proměnné: order_symbol, occasion_title, participant_count, manage_waitlist_url,
manage_waitlist_button; pro nabídku navíc offered_count, offer_expires_at,
offer_url, offer_button. Oddělit escapovaný text/URL od důvěryhodně generovaného
HTML tlačítka. Nabídka obsahuje informaci, že produkty se volí podle dostupnosti.

Čekání: potvrzení bez platby. Nabídka: nový email. Přijetí: stávající běžné
potvrzení objednávky, platby a tickets podle normálního toku, právě jednou.
Automatické e-maily při odmítnutí/expiry nejsou požadované; nepřidávat je bokem.

SQL mutace vytváří durable intent v existující canonical email infrastruktuře.
Raw token nutný pro zaslání uchovat pouze v existujícím šifrovaném payloadu/secret
mechanismu fronty, nikdy v plaintext order.data nebo běžném intent logu. Pokud
aktuální producer renderuje později, v téže boundary vytvořit šifrovaný token
envelope; před implementací ověřit recipient/template binding. Transakční rollback
nesmí nechat zprávu s neexistující nabídkou. Žádná druhá fronta ani přímé SES.

Technické výchozí pravidlo: platnost běží od potvrzeného vytvoření nabídky/editorem,
ne od neprokazatelného přečtení e-mailu. V queue workeru zkontrolovat expiry/cancel
před odesláním, vypršelý email potlačit. Zpoždění/bounce nezruší automaticky nabídku;
editor vidí delivery problém a může nabídku zrušit/později vytvořit novou.

Každá mutace aktualizuje stejný Client Sync contract jako orders/inventory. Ověřit
entity registry, event/projection a invalidace form bundle; nepřidávat polling
paralelně ke stávajícímu sync. Samotný časový přechod zachytí idempotentní bounded
expiry job, ale správnost P/R a acceptance nesmí záviset na včasnosti cronu.
Žádné trvalé aplikační DB triggery.

## 9. Implementační vlny

### Vlna 1: schéma, čtení a migrační základ

**Cíl:** model počítá osoby a uchovává identity bez změny běžného chování.

Změny: `database/tables/tables.sql`, nové `database/functions/eshop_waitlist/`,
forward migration v `supabase/migrations/`; models/Tb constants; form save/load
a duplicate SQL. Indexy na form/lifecycle/queue, current_order, pending offer/expiry,
source waitlist a token hash. Vazby omezí cross-form/cross-tenant použití; ACL/RLS
bez veřejného tabulkového přístupu. Oprávnění přes fasády.

Migrace: aditivní, default unlimited/disabled, show remaining true. Backfill
jednoznačných běžných participant vazeb a report nejednoznačných dat. Existující
symboly/pořadí/ceny/historii neměnit. Aktualizovat bootstrap kanonické SQL podle
konvence repo; žádná produkční aplikace v této vlně.

Selhání/kompatibilita: starý klient nesmí nulovat nové settings při partial save.
Nesoulad počtu osob v backfillu musí být viditelný, ne maskovaný nulou.

Ověření: nový cílený `database/tests/eshop_forms/form_capacity_schema_test.sql`:
defaulty, CHECK, permissions, partial save, copy, backfill distinct osoby.
Exit: unlimited existující formuláře zachovají chování a data; bounded formulář
nelze aktivovat nad neověřeným počtem osob.

### Vlna 2: jediná finalizace a atomické kapacity

**Cíl:** poslední místo ani produkt nelze prodat dvakrát, ani přes jiný formulář.

Změny: `create_ticket_order.sql`, jeho Client Sync facade, `apply_allocations.sql`,
product availability, `update_ticket_products_ws.sql`, order/ticket storno wrappers,
`storno_tickets_client_sync_v1.sql`, form settings save a produktové/inventory
limit writes. Vyčlenit společné privátní dokončení order; nová běžná tvorba ho
použije ještě před přidáním acceptance calleru. Aktualizovat participant lifecycle
v každém dotčeném count-changing writeru, včetně ručních editors.

Před editací bounded search na `INSERT/UPDATE/DELETE eshop.orders`, tickets,
order_product_ticket a na volání `apply_allocations`, interní storno a replacement
v `database/functions/`. Sepsat konkrétní callers do implementation evidence;
nezahrnovat nesouvisející business moduly. Zkontrolovat lock order i allocator
`next_order_sequence`, nikoliv zavádět zámky naslepo.

Migrace/deletion: přesměrovat běžné callers na společné dokončení; odstranit
duplicitní finalizační těla, nezrušit existující publikované RPC fasády.
Selhání: celý submit rollback včetně účtování, products a participant ledger.

Ověření: stávající create/free/deposit/cancel/product tests + nové
`database/tests/eshop_forms/form_capacity_test.sql` a skutečný multi-connection
Node test proti disposable DB: dvě objednávky posledního místa, dva formuláře
sdílející poslední produkt, dva produkty sdílející poslední inventory místo.
Exit: invariants drží v konkurenčních transakcích, nikoliv jen v sekvenčním SQL testu.

### Vlna 3: registrace a lifecycle nabídek

**Cíl:** všechny přechody v sekcích 2, 4 a 5 fungují serverově s receipt/auditem.

Změny: nové waitlist SQL commands, token storage, proposal/send/accept/decline/
cancel/withdraw/expire; get_orders/get_orders_tab_data/get_order/history projekce;
Client Sync registry a event completion. Accepted caller použije finalizer z vlny 2
a stávající `send-ticket-order` payment/Fakturoid transport, bez jeho kopie.

Migrace/deletion: rozšířit registraci kanonických operací; žádná alternativní
waitlist tabulka roots, fake zero-price order ani draft ticket.
Selhání: stale proposal nic nerezervuje; replay neodešle duplicitní intent; abort
externí fakturace má otestovanou obnovu původního waitlist záznamu/slotů.

Ověření: nový `database/tests/eshop_orders/waitlist_lifecycle_test.sql` a
`waitlist_capabilities_test.sql`; command identity a cross-tenant testy. Multi-session
accept/cancel/expiry race v existujícím DB test prostředí. Exit: full conversion
zachová ID/symbol/sequence, partial vytvoří child, W/R/O se nikdy nedvojí.

### Vlna 4: e-mailové šablony a worker integration

**Cíl:** příjemce bezpečně dostane použitelný odkaz a editor vidí skutečný delivery stav.

Změny: `email_domain.sql`, registry/constraints fronty podle aktuálního schématu,
`emailRenderer.ts`, email queue source-validity guards, template resolver a
`lib/components/email_templates/` nabídka šablon/proměnných. Přidat bounded expiry
job přes existující scheduler; aktualizovat source-of-truth registrace jobů.

Migrace: seed defaultních šablon idempotentně, nepřepsat uživatelský obsah.
Selhání: pause/rate/quota/provider fail zachovají intent; neodeslat starý token
po zrušení/expiry. Žádné plaintext tokeny v historii a exportu.

Ověření: targeted Deno renderer/queue tests s mocked providerem, DB intent tests
na dedupe/rollback/stale suppression. Žádné skutečné odesílání lidem při testu.
Exit: dva nové template codes fungují se stejnými wrappers a jediným workerem.

### Vlna 5: administrace a veřejné formuláře

**Cíl:** dohodnuté chování používá současné UI bez přestavby navigace.

Změny: `form_settings_content.dart`, `form_model.dart`, `db_forms.dart`,
`orders_content.dart`, `order_grid_filters.dart`, `eshop_columns.dart`,
`order_model.dart`, nový scoped detail/dialog; Flutter `form_page.dart`, form
holders/builders a public JS `form_page.js`, `form_session.js`, `form_data_reader.js`,
`components/eshop/db_orders.js`; router osobního odkazu. Respektovat současné
service/command hranice a strings files. Nepřepisovat generované router soubory ručně.

Migrace/deletion: nahradit broad non-storno action predicates pro orders explicitními
capabilities; zachovat nezměněný filter kontrakt tickets/history tam, kde je správný.
Selhání: network retry zachová command identity, vypršelá stránka neodešle starý
submit, products-full chyba zachová nevyužitou nabídku. Osobní údaje neukládat
do obecné anonymní cache jako veřejný form bundle.

Ověření: cílené Flutter widget/model testy a JS form tests (viz sekce 10), následně
jeden ucelený lokální E2E scénář ve disposable tenantovi. Browser v izolovaném
headless session dle festapp-local-e2e a agent-browser skills. Exit: celý scénář
nastavení -> naplnění -> čekání -> nabídka -> partial -> full -> storno je průchozí.

### Vlna 6: kontrakt, dokumentace a připravenost k release

**Cíl:** žádný entrypoint neobchází kapacitu nebo interpretuje náhradníka jako platbu.

Změny: bounded audit order consumers (reports, finance export, bank pairing,
reminders, ticket sending/scanning, manual price edits, history, deletion, form
field deletion guards a duplication), aktualizace Forms/Eshop/Email Templates
README a dotčených API docs. Waitlisted osoby nejsou účastníci reportu ani výnosy.
Původní form field usage guard musí zahrnout uložené participant answers.

Deletion ledger níže dokončit; nepřepisovat mimo rozsah obecné UI/sync/payments.
Ověření: spustit pouze dotčené regresní sady; scoped `fvm dart analyze` a build
veřejného klienta, pokud byly změněny routing/bundling části. Passing checks
neopakovat bez změny pokrytého kódu. Exit: všechny řádky acceptance matrix projdou,
zbývají jen explicitně neautorizované produkční kroky.

## 10. Ověření a akceptační matice

Testy patří k behavior contracts, ne k přesnému textu překladu nebo helper implementaci.
Nové názvy souborů ve vlnách jsou plánované. Test runner vyžaduje izolovanou DB:

```sh
# Bootstrap pouze ověřené disposable DB dle CONTRIBUTING.md, nikdy produkce.
./automation/bootstrap_local_db.sh
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/eshop_orders/waitlist_lifecycle_test.sql
fvm flutter test test/components/eshop/order_grid_filters_test.dart test/components/eshop/order_grid_permissions_test.dart
node --test web_client/tests/forms/waitlist_flow.test.js
```

Další cílené SQL soubory spouštět stejným runnerem; JS multi-connection test musí
použít pg proti téže disposable DB a bezpečně uklidit svůj tenant. Deno testy
spouštět přes existující repository test workflow s minimálními oprávněními pro
konkrétní změněné moduly; nepoužít testovací credentials pro remote databázi.

| Scénář | Povinný důkaz |
| --- | --- |
| Unlimited a blueprint | původní přihlášení beze změny, žádné waitlist UI ani server bypass |
| Snížení limitu | C < O+R zamítnuto; samotné W snížení neblokuje |
| Feature disable / blueprint switch | aktivní waiting/offers blokují; historie zůstane čitelná |
| Poslední místo | dva souběžné submits, právě jeden úspěch, druhý nespadne tiše do waitlist |
| Produkty a inventory | souběh přes dva formuláře i sdílený pool nepřeprodá maximum |
| Waitlist bez produktů | žádná platba, ticket, allocation, faktura, upomínka ani paid free-order větev |
| Uvolní se 5, čekají 2 | public P=3, předvýběr nejvýše 2; žádný automatic send |
| Nabídka 2 skupině 4 | návrh jen počet, potvrzení editora; příjemce může vybrat jiné dvě osoby |
| Partial 1 ze 2 | nový child order, druhý slot dál pending, původní řádek se zmenší |
| Full remaining | stejný ID/symbol/sequence, běžná platební splatnost od potvrzení |
| Expiry/decline/editor cancel | různé důvody, konec pořadníku, R/W se uvolní, auto návrh přeskočí |
| Neoslovený zbytek skupiny | zachová původní pořadí a aktivní waiting stav |
| Withdrawal osoby | jen tato osoba/slot, nelze stornovat accepted běžnou objednávku |
| Closed form + valid offer | veřejný submit uzavřen, scoped offer lze potvrdit |
| Product sold out during form | žádná částečná konverze ani spotřeba nabídky, konkrétní chyba |
| Token replay/scan | GET nic nemění, duplicitní POST nezdvojí order ani e-mail |
| Cross-tenant/person tampering | bezpečné odmítnutí, žádný únik dat a žádná mutace |
| Fakturoid failure | recovery nerozbije původní identitu ani nedvojí capacity/platbu |
| Background expiry job delayed | public P správné a expired acceptance zamítnuto i bez cronu |
| UI active filter | regular + active waitlist default; neaktivní po vypnutí; skupina viditelná při 1 aktivním |
| Mixed selection | paid/send-ticket actions odmítnou nezpůsobilé, read-only editor nesmí mutovat |
| E-mail queue delayed/cancelled | žádný neplatný offer email send, viditelný queued/failed stav |
| Existing orders and copies | žádné přečíslování, ztráta dat, kopie bez živých nabídek/tokenů |

## 11. Nahrazené cesty a rollout

| Artefakt/chování | Akce | Důkaz |
| --- | --- | --- |
| Starší návrh samostatného waitlist root typu | neimplementovat | jediná identita v eshop.orders |
| Duplicitní order finalization pro acceptance | nevytvářet | běžný i offer caller používají tentýž private finalizer |
| „state != storno“ jako univerzální povolení paid/send/delete | nahradit jen dotčené order actions explicitním kontraktem | action/security tests |
| Počet produktových řádků jako počet lidí | nepoužít | distinct participant test s více produkty na osobu |
| Klientské přepočty a lokální accepted flags | nepoužít jako autoritu | SQL races a stale UI test |
| Přímé e-maily, druhá fronta a persistent business triggers | nevytvářet | registrace producerů pouze do canonical queue/explicit commands |
| Staré publikované běžné RPC kontrakty | zachovat jako stávající transport, směrovat na canonical helper | běžné regresní testy |

Produkce není autorizována tímto plánovacím úkolem. Budoucí release vyžaduje
vybraný jeden tenant a příslušný backend/web release workflow. Pořadí: schema
expansion a kompatibilní writers/readers -> backfill a kontrola counts -> Edge,
worker a klienti -> aktivace nastavení konkrétního formuláře. Před povolením nové
funkce starým klientům vracet explicitní unsupported mode/bezpečně uzavřený submit,
nikoliv běžný checkout pro waitlist. SQL nepovolí bypass ze starého klienta.

Rollback po vzniku waitlist dat nesmí shodit nový state/sloupce nebo skrýt živé
nabídky. Preferovat forward fix; nouzově pozastavit nové nabídky/přihlašování při
zachování správy existujících rezervací. Neobcházet dohodnutý zákaz vypnutí feature
s aktivními záznamy. Před migrací záloha podle normálního workflow, žádný zásah do
zmrazeného starého cloud backendu. Neprovádět automatické multi-tenant šíření.

## 12. Předpoklady, zbytková rizika a hotovo

- **Předpoklad A1:** všechny podporované běžné objednávky lze spojit s jednotlivými
  osobami. Ověří wave 1 na schema/fixtures; nejednoznačné legacy případy explicitně
  blokují aktivaci dotčeného formuláře, ne celou implementaci.
- **Předpoklad A2:** technické předběžné přiřazení neadresných nabídnutých míst
  odpovídá UX skupiny (sekce 4.3). Je to specifikovaný implementační default,
  nikoliv uživatelem výslovně vybraný způsob person bindingu.
- **Předpoklad A3:** nabídka běží od commitu odesílacího příkazu. Doručení není
  garantované; UI musí ukázat queue stav. Změna začátku běhu podle doručení by byla
  nové zásadní produktové rozhodnutí.
- **Riziko:** refaktor finalizace a Fakturoid abort in-place identity je citlivý.
  Povinná cílená integrační evidence ve vlně 3; neobejít odstraněním původního order.
- **Riziko:** současně rozpracovaný product-type/editor cleanup může změnit field
  kontrakty. Před implementací dotčené vlny aktualizovat pouze konkrétní neplatné
  faktické odkazy, neprovádět nové plošné architektonické šetření.
- **Blokery:** žádné pro lokální implementaci po odsouhlasení jejího zahájení.
  Produkční přístup a release jsou samostatná autorizovaná práce. Pokud některý
  předpoklad změní uživatelské chování, konzultovat jednu otázku s kontextem.

Hotovo znamená: všechny dohody ze sekce 2 mají implementovanou canonical cestu;
kapacity osob i produktů drží pod souběhem; full/partial identity funguje; oba
klienti a editor sdílejí stejné SQL rozhodování; historie, tokeny, email queue,
sync a explicitní permissions jsou pokryté; cílené testy prošly; relevantní docs
jsou aktualizované; není implementovaná paralelní waitlist/order finalizace.
Produkční nasazení se ve finálním handoffu označí samostatně jako neprovedené,
dokud nebude výslovně autorizované a doložené.

## 13. Pevné implementační hranice a algoritmy

Tato část zpřesňuje předchozí vlny pro implementaci modelem GPT-6.1-Sol Medium.
Je závazným rozdělením odpovědností, ne seznamem alternativ k dalšímu navrhování.
Implementátor může upravit názvy při konkrétní kolizi v repozitáři, ale nesmí
přesunout business pravidla do UI nebo vytvořit druhou autoritu kapacity.

### 13.1 Moduly a jejich rozhraní

| Vlastník / cílový soubor | Veřejné rozhraní nebo role | Co sem nepatří |
| --- | --- | --- |
| `database/functions/eshop_waitlist/schema.sql` | nové sloupce, tabulky, indexy, constraints a ACL; stejné definice zapojit do canonical bootstrapu | pravidla přechodů v triggerech |
| `database/functions/eshop_waitlist/form_capacity.sql` | `get_form_capacity_snapshot_internal(form_id, at_time)` vrací C/O/R/W/F/H/P; writer helper ověřuje limit pod form lockem | ceny, tokeny, e-mail rendering |
| `database/functions/eshop_waitlist/participants.sql` | registrace, přesun a lifecycle osob; zápisy pouze volané uvnitř doménových commandů | veřejný generic CRUD s libovolným state |
| `database/functions/eshop_waitlist/offers.sql` | návrh, vytvoření, decline/cancel/withdraw a bounded expiry; explicitní vstupy ze sekce 6 | vytváření běžných plateb a tickets |
| `database/functions/eshop_waitlist/capabilities.sql` | kontrola hash/scopu/expiry/revocation, minimální read bundle | čtení podle samotného order symbol |
| `database/functions/eshop_waitlist/accept_offer.sql` | jediný orchestrátor přijetí a jeho command receipt | kopie produktových/platebních pravidel |
| `database/functions/eshop/finalize_ticket_order.sql` | nový privátní finalizer vyčleněný z create_ticket_order_internal_v1; target order + validovaný payload | autorizace z libovolného target ID klienta |
| `database/functions/eshop/create_ticket_order.sql` | stávající veřejně používaný interní create kontrakt: nová identita a volání finalizeru | další tělo finalizace pro běžné objednávky |
| `lib/components/forms/waitlist_commands.dart` | typed facade nad ClientCommandTransport: proposal/send/accept/decline/cancel/withdraw | výpočty kapacity nebo optimistické spotřebování nabídky |
| `lib/components/forms/models/form_capacity_model.dart` | parser serverového capacity/mode DTO | samostatný kalkulátor C/O/R/W |
| `lib/components/eshop/models/waitlist_summary_model.dart` | souhrn lifecycle a eligible actions pro row/detail | odhad stavu z ceny nebo existence payment_info |
| `web_client/src/components/forms/waitlist_commands.js` | veřejné capability read/write transporty s command identity | přímé writes do tabulek |
| Existující Flutter/JS form builders | režim regular/waitlist/offer ovlivní zobrazení a lokální validaci | nové oddělené kopie formulářového enginu |

Nové SQL helpery jsou private invoker-only, bez anon/authenticated EXECUTE; granty
mají jen doménové fasády s kontrolou oprávnění. Názvy transportních RPC konkrétně
zapsat do stávající command registry ve vlně 3. Před paralelizací workerům předat
hotové request/response typy, ne pokyn „dohodněte si API mezi sebou“.

### 13.2 Read kontrakty

`capacity` DTO má `enabled`, `limit`, `remainingPublic`, `showRemaining`.
`registrationMode` je explicitní enum ze sekce 6; offer bundle přidá mode `offer`,
který smí vzniknout jen po autorizaci capability/editor. `limit` a remainingPublic
jsou NULL pro unlimited/blueprint, nikoliv nula. Server time a expiresAt jsou UTC.
UI může zobrazit countdown, nemůže podle lokálních hodin autorizovat přijetí.

Admin projekce přidá `occupiedPeople`, `offeredPlaces`, `waitingPeople`,
`offerablePlaces`, `revision`, `canSendOffers` a `blockedReason`. Proposal revision
je serverový snapshot pod stejným form lockem; ne jen náhodné UI číslo. Buď persistent
form revision zvýšená každým dotčeným commandem, nebo hash všech relevantních hodnot
snapshotu; **použít persistent `forms.capacity_revision bigint default 0`**.
Při potvrzení vždy i po shodě revision znovu ověřit časové expirace a F, protože
časový přechod může nastat bez writeru. Stale návrh nic částečně neodešle.

Order read projekce přidá `waitlistSummary` pouze pro waitlisted order nebo jeho
historický původ: počty podle lifecycle, pending places a earliest expiry.
`isActive` a seznam `allowedActions` vycházejí ze stejného SQL pravidla; frontend
je používá pro UI, ale server každou mutaci znovu ověří. Historické propojení se
čte autorizovaně; neverejný origin_order_id se nesmí změnit na veřejný read key.

### 13.3 Přesný průběh přijetí

1. Ověřit syntaxi a capability/editor scope. Založit/načíst command receipt podle
   stávajícího mechanismu, svázaný se stejným principal/scopem a payload hashem.
   Replay nezakládá nový target order ani nové email intents.
2. Zamknout form, související orders, offer a participants podle lock protokolu.
   Znovu ověřit scope, aktuální serverový čas, nevyčerpané slots a vybrané osoby.
   Materializovat pouze dotčené vypršelé pending slots přes tentýž expiry helper.
3. Zkontrolovat unikátnost vybraných person IDs a počet n <= platných pending míst.
   Případné prohození předběžných participant-slot vazeb provést atomicky. Nepřijímat
   již admitted/withdrawn osobu ani osobu rezervovanou jinou platnou nabídkou.
4. Rozhodnout full/partial z aktuálních zbývajících participant rows podle sekce 4.3.
   Full použije původní target ID bez nové alokace symbolu/pořadí. Partial vytvoří
   nový target a vazbu source_waitlist_order_id přes stávající identity allocator.
5. Připravit běžný payload osob a produktů, validovat všechna aktuální povinná pole
   a scope produktů. Pod product/pool zámky zavolat společný finalizer. Ten vytvoří
   produkty/tickets/payment a allocations stejným způsobem jako regular create.
   Free-order flow má explicitně správný předchozí state pro existing paid transition.
6. Přesunout/aktualizovat participants a slot outcomes; snížit R o n a zvýšit O o n.
   Zapsat audit před/po, propojení target order, receipt, email intent a Client Sync.
   Při full změnit původní state; při partial přepočítat původní souhrn.
7. Commit je jediný úspěch. Výjimka kteréhokoliv bodu vrací celý command zpět,
   včetně nového target, změn participant vazeb a produktových allocations.
   Po commitu pokračuje stávající external-payment/email transport.

Výsledek acceptance obsahuje běžný order response, `sourceOrderId`, `conversion`
(`in_place`/`split`) a nový waitlist summary. Klient nemá odvozovat výsledek
porovnáváním počtu tickets s počtem lidí nebo z nového čísla objednávky.

### 13.4 Fakturoid: konkrétní recovery hranice

Dodatečně ověřený fakt: `database/functions/emails/fakturoid_email_gate.sql`,
`abort_fakturoid_ticket_order_v1`, dnes při selhání přípravy volá běžné storno.
Pro waitlist acceptance se tento abort **nesmí použít beze změny**. Nejde o
uživatelské storno a nesmí definitivně odstranit původní čekání.

Rozšířit existující complete/abort fasády o branch ověřený podle acceptance commandu.
Do nové `eshop.waitlist_acceptance_attempts` uložit command ID (unique), source/target
order ID, full/partial variantu, přesné zvolené participant/slot IDs, předchozí
waitlist data potřebná k návratu a stav `preparing`/`completed`/`aborted`.
Záznam vytvořit transakčně při acceptance jen tam, kde se spouští external-payment
prepare. Během `preparing` zablokovat konkurenční edits/storno target a vybrané osoby;
počítají se už do O, nikoliv zároveň do R. Neoslovený zbytek skupiny není blokovaný.

- Complete přepne attempt na completed ve stejné transakci jako existing completion;
  druhé volání je replay, nezmění znovu participant/slot state.
- Abort pod form/order zámky zruší jen účinky tohoto attemptu, využije canonical
  release allocations/tickets, odstraní aktuální vazbu na neúspěšnou platbu a
  vrátí vybrané osoby do původního waitlisted order. U full obnoví původní data
  a stav bez změny ID/symbol/sequence; u partial zachová neúspěšný child jako storno
  v historii a vrátí osoby do source. Nesmí restore přepsat mezitím změněný zbytek.
- Je-li nabídka stále platná, obnoví původní slots jako pending (O -> R); je-li
  po termínu, vrátí osoby jako offer_expired bez kapacitního držení (O -> 0).
  Žádná nová nabídka ani prodloužení termínu bez editora.
- Opakovaný abort je no-op podle attemptu. Zrušený payment confirmation intent se
  neobnovuje. Pozdní complete po aborted se odmítne; nový pokus potřebuje nové
  command ID a nové ověření nabídky. Timeout s nejistým provider výsledkem zachová
  stávající provider idempotency/reconciliation, nevytváří druhou platbu.

Povinné testy: full a partial abort, opakovaný abort/complete, expiry během prepare,
pozdní complete, pokus o ruční edit během preparing a zachování neosloveného zbytku.
Schema attempt journalu patří do vlny 1, implementace do vlny 3. Nesmí zůstat TODO
„nějak ošetřit Fakturoid“ ani být nahrazena vypnutím jeho podpory.

## 14. Efektivní realizace se subagenty a modely

Výslovné zadání uživatele: koordinátor **GPT-6.1-Sol, Medium**, implementace UI/UX
**Astra, Medium**, při implementaci zapojit subagenty. Jde o budoucí implementaci,
nikoliv požadavek paralelně implementovat při samotném psaní tohoto plánu.

### Rozdělení práce a závislosti

1. Koordinátor (`gpt-6.1-sol`, reasoning `medium`) vlastní SQL schema, identity,
   finalizer, lock protocol, capabilities, Fakturoid recovery, command registry,
   migrace a integrační rozhodnutí. Nezadává tyto vzájemně závislé změny několika
   nezávislým agentům. Nejdříve dokončí vlny 1-3 a zafixuje DTO, chyby a test fixtures.
2. Potom spustí subagenta **UI/UX** (`gpt-6-astra`, `medium`): vlastní Flutter
   administraci, Flutter/JS veřejné formuláře, modely/parsers, klientské command
   adapters, routing, lokální UI strings a jejich cílené widget/JS testy. Použije
   ux-designer skill a současné komponenty; drží dohodnuté UX bez nového interview.
3. Souběžně může spustit subagenta **E-maily** (`gpt-6.1-sol`, `medium`): vlastní
   renderer, templates/proměnné, email-template editor, queue integration a jejich
   testy. SQL entrypoints/schema/migrace nemění; požadované změny předá koordinátorovi.
4. Třetí subagent **Regresní testy backendu** (`gpt-6.1-sol`, `medium`) dostane hotové
   contracts a vlastní pouze nové DB lifecycle/security/multi-connection testy.
   Hlásí konkrétní selhání koordinátorovi; neopravuje souběžně produkční SQL.
5. Koordinátor integruje výsledky, provede společnou validaci a kontraktový audit
   vlny 6. Žádný další obecný „review everything“ subagent ani opakované průzkumy.

Maximálně čtyři současně aktivní agenti včetně koordinátora. Model overrides při
spawn použít s `fork_turns="none"`; každému poslat cestu k celému plánu, relevantní
sekce, aktuální DTO, konkrétní vlastněné soubory a exit condition. Pokud požadovaný
model není dostupný, oznámit to a vyžádat alternativu, ne tiše nahradit Astra pro UI.

Žádní dva agenti nezapisují tentýž soubor. Sdílené translation JSON, router config,
test runner registrace a migration assembler vlastní koordinátor: pracovníci
předají přesný seznam změn nebo samostatný patch pro integraci. UI subagent může
vlastnit feature strings soubory, e-mailový subagent své template strings; sdílený
katalog integruje koordinátor. SQL fixtures bootstrapuje jen koordinátor; při
parallel DB testech samostatné tenant fixtures a žádný souběžný reset DB.

### Pracovní balíčky a předání

Každý worker dostane: cíl, soubory které smí měnit, neměnný request/response
kontrakt, 3-8 acceptance scénářů z matice a cílený validační příkaz. Předá soubory,
výsledek checku a konkrétní blokery. Nevymýšlí si nové endpointy, nové product state,
nové approval flows ani jiné názvy polí mimo dohodnutý kontrakt.

Koordinátor vede stručný stav balíčků přímo v tomto plánu během implementace.
Testuje po souvislé změně, ne po každé editaci. Nejprve levné SQL/contract testy,
potom cílené klientské testy, nakonec jeden propojený E2E průchod. Nedělat plošné
buildy více tenantů ani volat full test_all po každém workerovi. Passing test
neopakovat, pokud se jeho pokrytý kód od té doby nezměnil.
