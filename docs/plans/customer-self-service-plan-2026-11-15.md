# Zákaznická samoobsluha změn objednávky

Datum: 2026-11-15
Stav: Etapy 1-5 implementovány a lokálně ověřeny; nenasazeno, neaktivováno
Ověřování implementace: `standard` - autorizace, finance, kapacity a migrace
Výchozí revize průzkumu: `a7e52244a`

## Stav implementace 2026-11-15

Dokončeny jsou etapy 1-5 v pracovním stromu `/Users/miakh/source/festapp`.
Podrobný předávací záznam obsahuje
[RESULT](customer-self-service-RESULT-2026-11-15.md).

- Etapa 1: extra feature default off, soukromé revizované policies, typed práva,
  kanonické uložení formuláře a oddělené sdílené response/storno/refund efekty.
- Etapa 2: nezávislá scoped write capability, původní čtecí parent, ověření na
  uložený e-mail, paměťový write token, náhled a jednorázový receipted command.
  Existující web/Flutter přehled i URL e-mailového tlačítka zůstávají vstupem.
  Společný e-mailový presenter zmiňuje pouze serverem dostupné operace.
- Etapa 3: automatické i schvalované storno, samostatně povinný důvod,
  zamítnutí/stažení, evidence a rozhodnutí obsluhy v existujícím detailu,
  atomická podporovaná plná online refundace. Settlement má stále jediného
  vlastníka ve stávajícím platebním enginu. Vypnutí závazky nemaže.
- Etapa 4: skutečné `term_start_at/term_end_at`, explicitní produktové a bezpečné
  odpověďové mapování, omezený přesun se zachováním identit, ceny i původního
  odkazu, rotace QR a kanonické PDF/Wallet/email efekty. Nepodporované přesuny
  a storna jsou viditelnými požadavky bez předstíraného provedení.
- Etapa 5: ACL/definer registry, assembler a canonical source parity, cílené
  regrese, CZ/EN nápověda/navigace/vyhledávání/kontextové odkazy, skutečné light
  screenshoty a opakovatelný lokální e-mailový walkthrough. Nezávislá revize
  finálního webového rozsahu skončila `ship`; nativní vizuál tím není ověřen.

Ověřování `standard`: prošlo 14 různých cílených SQL souborů, 7 skutečných
PostgreSQL souběhů, 46 webových testů, 10 Edge/e-mailových testů, 8 bezpečnostních
migračních kontrol, 7 help kontrol, 5 Flutter widget testů v původní session
i v kanonickém CI vstupu, 1 core URI test a 18 kontrol CI kontraktu. Přesné
příkazy a hranice důkazů jsou v RESULT. Finální nové klientské soubory mají
cílený analyzer bez diagnostik. Širší kontrola existujících FormPage/settings
navíc hlásí stávající warning `must_be_immutable` a stylistické infos;
nejde o čistý celorepozitářový analyzer ani dokončené release gates.

Doložené opravy během ověření: zpřesnění skutečné termínové domény a mapování,
rozdělení údajů o požadavku od finančních faktů, společné lock pořadí a retry,
obnova PDF při editaci, zachování explicitně ukončeného Wallet odkazu,
rozlišení stejně datovaných cílových formulářů názvem a úplný Flutter náhled
cílových produktů. Dočasné autorizační bypassy nejsou součástí produktové cesty.

Aditivní migrace `20261115130000_customer_order_policy_foundation.sql` byla
přehrána pouze v ověřeném disposable lokálním runtime společně se současnými
kanonickými forwards. Zdrojový strom zároveň obsahuje samostatnou implementaci
slev; její změny zůstaly zachované. Canonical source parity společného stavu
prošla. Produkční migrace, deploy, aktivace, commit ani push nebyly provedeny.

## Závazné upřesnění před nasazením: všechny odpovědi zamčené

Uživatel výslovně zvolil „nechat zatím zamčené vše“. To nahrazuje dřívější
návrh zákaznického allowlistu: žádná přímá změna odeslaných odpovědí, včetně
jména a telefonu, není v tomto vydání podporovaná. Pořadatel ji nemůže zapnout.
Server odmítá edit challenge, starou write capability i přímé edit potvrzení,
i kdyby uložená starší policy edit povolovala. Nové policy ukládají explicitní
edit pravidlo pouze vypnuté. Klienti ignorují starou serverovou edit akci,
editor samoobsluhy nemá edit přepínač a e-mailový presenter editaci neinzeruje.
Samostatné běžné oprávnění obsluhy měnit odpovědi zůstává zachované.

Následující starší návrhové body o zákaznickém allowlistu jsou historický
kontext, nikoli dostupné chování tohoto vydání. Finální etapy 2 a 5 ověřují
výslovné uzamčení všech odpovědí; pozitivní capability/receipt/souběhové
kontrakty používají storno nebo pracovní požadavek. Storno, refundace a
podporované přesuny termínu zůstávají v rozsahu. Přesun pouze přemapuje
stávající odpovědi podle schváleného doménového mapování; zákazník je neupravuje.

## Výsledek a produktový rozsah

V existujícím přehledu objednávky zákazník uvidí změny povolené pořadatelem,
jejich termíny a důsledky. Před provedením dostane serverový náhled. Změna má
potvrzení, historii a srozumitelný stav případného vrácení peněz.

Uživatelem upřesněná hlavní cesta: **stávající tlačítko v e-mailu -> stávající
přehled objednávky -> dostupné změny**. Nevytvářet druhé tlačítko do jiného
portálu ani vyžadovat účet pro otevření přehledu. Ověření konkrétní změny
probíhá až po výběru akce podle bezpečnostního kontraktu níže.

U stávajícího tlačítka rozšířit doprovodný text, například:
„V přehledu najdete stav objednávky a platby. Pokud to pořadatel umožňuje,
můžete zde také upravit údaje, požádat o storno nebo změnu termínu.“
Přesnou větu sestavit pouze z operací aktuálně zapnutých pro danou objednávku;
nepovolené změny neslibovat. Při vypnuté samoobsluze ponechat dosavadní text.
E-mail zachycuje stav při přípravě zprávy; přehled po kliknutí vždy ověří aktuální
policy a termíny. Starší již doručený e-mail nemusí být přepsán ani odeslán znovu.

Samoobsluha je samostatná extra feature akce, standardně vypnutá. Po jejím
výslovném zapnutí pořadatel ještě samostatně povoluje:

| Operace | Rozsah první verze |
|---|---|
| Úprava odpovědí | Pro zákazníka uzamčeno vše, včetně jména a telefonu. Opravy řeší existující oprávněná obsluha. |
| Storno | Celá objednávka nebo vybrané vstupenky včetně samostatných místenek; bez použitých vybraných vstupenek. U nezaplacené objednávky bez refundace. |
| Vrácení peněz | Celá dostupná zaplacená částka po stornu, bez storno poplatku. Automaticky jen do původního online zdroje, pokud connector podporuje zápis refundace. Banka/hotovost formou požadavku obsluze. |
| Přesun termínu | Celá objednávka mezi explicitně propojenými formuláři téže akce, stejné měny a čisté ceny, bez rezervovaných sedadel a změny příjemce/metody platby. |

Upřesnění zadání po prvním předání: zákazník může vybrat konkrétní vstupenky
ke stornu. Místenka sama storno neblokuje; uvolní se pouze vybrané sedadlo,
ostatní alokace a QR zůstanou zachované. Nedělitelná prodejní jednotka,
použitá vybraná vstupenka, immutable tisk nebo faktura stále vyžadují obsluhu.
Povinný důvod, schválení a lhůta platí pro výběr stejně jako pro celou objednávku.

Dílčí storno využívá stejný soukromý doménový owner jako dosavadní staff bulk
storno. Staff wrapper zachovává vlastní aktuální oprávnění po zámcích; customer
boundary navíc kontroluje přesné ticket IDs a zakazuje i sdílené odkazy do jiné
objednávky. Žádost ukládá přesný výběr pro pozdější schválení. Výběr se váže na
ověřovací e-mail, fingerprint i receipt. Nepřibývá finanční ledger.

Automatické dílčí storno je podporované u nezaplacené bankovní/hotovostní
objednávky a při explicitním režimu storna s ručně vyřizovanou refundací
u plně zaplacené kompatibilní objednávky. Dílčí online refundace/admission,
záloha, nejednoznačný snapshot a sleva zůstávají scoped požadavkem obsluze.
Dnešní provider owner vyžaduje pro částečnou refundaci vlastní admission
rozhodnutí nad skutečnými finančními fakty; nesmí se obejít z nového wrapperu.
Ruční vyřízení se opírá o stávající bankovní refund preparation a pozorovaný
settlement. Samotné storno není vrácená platba; zbývající placené vstupenky
nesmí zabránit uzavření již skutečně vypořádané dílčí refundace.

Přesun do jiné akce není v první verzi automatický: současná finanční a
reportovací identita je vázaná na původní akci. Zákazník může poslat požadavek
pořadateli; UI ho nesmí prezentovat jako dokončený přesun. Jde o vědomé omezení
návrhu, nikoli o předpoklad, že libovolné dvě akce již tvoří jednu sérii.

Mimo rozsah: změna přístupového/doručovacího e-mailu, bezpečný převod vlastnictví
nebo přeprodej vstupenky, výměna konkrétních sedadel, doplatky,
výměna měny, automatický bankovní převod a storno poplatky. Změna jména není
převodem vlastnictví; platí právo pořadatele zakázat ji u jmenných vstupenek.

## Ověřený současný stav

| Fakt a místo | Dopad |
|---|---|
| `web_client/src/components/forms/order_overview.js` a `lib/components/forms/views/customer_order_overview.dart` již zobrazují přehled objednávky. | Rozšířit existující cestu, nevytvářet další zákaznický portál. |
| `supabase/functions/_shared/emailActionLink.ts` vlastní `overviewCopy`, `overviewEmailSubstitutions` a `overviewRequiredLinks`; `orderEmailOverview.ts` zajišťuje původní odkaz. | Rozšířit společný doprovodný text, zachovat URL i jedno stávající tlačítko a stejné chování v náhledu šablon. |
| `database/functions/eshop_waitlist/order_overview.sql` poskytuje `get_customer_order_overview`; `order_overview_access.sql` řeší capability a její životnost. | Současný čtecí odkaz automaticky neopravňuje ke změnám. |
| `cancel_order_domain_internal_v1` je již soukromý invoker bez klientských grantů. Kontrola role je ve ws wrapperu. | Zachovat tuto existující separaci; nevytvářet druhé bankovní storno. |
| `storno_order_client_sync_v1` vyžaduje `can_write_orders`; stejnou podmínku má interní wrapper storna. | Nelze zavolat administrátorský endpoint service klíčem a obejít tím zákaznické oprávnění. |
| `update_order_and_tickets_to_storno.sql` vlastní `cancel_order_domain_internal_v1`. | Nejprve oddělit doménový efekt od vstupní autorizace a zachovat administrátorskou kontrolu. |
| Tentýž storno owner odmítá online platby a bankovnímu stornu nuluje `orders.price`; `payment_providers/effects.sql`, `apply_provider_payment_effects_internal` vlastní online admission efekty. | Online storno nelze řešit odstraněním guardu nebo voláním bankovního storna; musí zachovat provider částku a vlastníka finančních efektů. |
| `update_order_detail_responses` kontroluje scope, očekávané hodnoty a povolené typy polí. | Znovu použít doménovou validaci, ale zákaznický allowlist je užší. |
| `repair_order_email_client_sync_v1` má vlastní audit, platební fingerprint a transport. | E-mail není obyčejná editovatelná odpověď; v první verzi zůstává u obsluhy. |
| `docs/architecture/payment-providers.md` rozlišuje bankovní instrukci, refund intent, dispatch a skutečné settlement facts. | „Požadavek přijat“ nesmí znamenat „peníze vráceny“. |
| `database/functions/user_permissions/payment_operations.sql` přiděluje finanční operace konkrétním rolím. | Zákaznická policy potřebuje vlastní úzký predicate, nikoli oslabení RBAC obsluhy. |
| `docs/architecture/ticket-wallet-connectors.md` používá stejné ticket identity, revokace a aktualizace. | Storno/přesun musí aktualizovat PDF/QR a Wallet přes stávající owner. |

Průzkum potvrdil zdrojové rozhraní, nikoli živou dostupnost všech operací.
Model opakovaných termínů nebyl doložen; proto jsou cíle přesunu explicitní.

## Pravidla pořadatele

### Extra feature a dílčí pravidla

Použít stávající systém occasion features s navrženým kódem
`customer_self_service`, `is_enabled=false`. Zaregistrovat konstantu, metadata,
model/factory, editor, `FeatureService` a JS projekci stejně jako jiné features
v `lib/components/features/`, `lib/components/occasion_settings/` a
`web_client/src/components/features/`. Nezavádět druhý globální entitlement.
Jde o volitelnou funkci, nikoli automaticky o zpoplatněný tarif.

Účinné povolení je průnik: zapnutá feature akce + zapnutá konkrétní operace
ve formuláři + aktuální oprávnění zákazníka + dostupnost operace pro konkrétní
objednávku. Samotné zapnutí feature nepovolí storno ani pohyb peněz.
Vypnutá/missing feature blokuje nové náhledy, challenge a commity také na serveru,
včetně starých odkazů. Čtecí přehled objednávky zůstává dostupný.

Feature save i finální command používají společný fence v pořadí stávajících
policy/capacity zámků. Změna feature zneplatňuje připravené náhledy a dosud
neprovedené write capabilities. Opětovné zapnutí je neobnoví. Nastavení operací
se zachová pro kontrolu pořadatelem, ale při prvním zapnutí jsou všechny vypnuté.
Přijaté refundace, požadavky a jejich recovery se vypnutím nezastaví a neschovají.

### Režimy storna a schválení pořadatelem

Upřesnění zadání z 2026-11-15: pořadatel může vyžadovat vlastní schválení
storna a důvod žádosti. Policy má `cancellation.mode` s hodnotami `automatic`
a `approval_required` a nezávislý boolean `cancellation.reason_required`.
Chybějící nebo neplatný režim nesmí povolit automatické storno.

- V automatickém režimu zákazník po e-mailovém ověření a náhledu výslovně
  potvrdí storno s uvedeným finančním důsledkem. Povinný důvod se kontroluje
  na serveru při náhledu i commitu, po ořezání mezer, v rozsahu 1-2000 znaků.
- V režimu schválení zákazník potvrzuje **žádost o storno**, nikoli provedené
  storno. Objednávka, vstupenky, kapacita a peníze zůstávají beze změny.
  UI před odesláním vysvětlí, že až do schválení platí původní objednávka.
- Žádost je viditelná v detailu objednávky a notification centru. Obsluha ji
  schválí nebo zamítne s volitelným vysvětlením; zákazník může dosud otevřenou
  žádost stáhnout. Zamítnutí/stáhnutí nemá finanční ani kapacitní efekt.
  Žádost nesmí být označena za vyřešenou jen tím, že byl odeslán e-mail.
- Pracovní stavy rozšířit na `open/approved/rejected/withdrawn/resolved`.
  `approved` označuje skutečně přijaté storno a navazuje na konkrétní command
  receipt; neznačí potvrzenou refundaci. Finanční stav se vždy čte z engine.
- Schválení používá aktuální oprávnění obsluhy a znovu ověří lifecycle, skeny,
  fakturu a finance. Podání žádosti nic nerezervuje a nezaručuje proveditelnost.
  Provede storno a případnou refund rezervaci atomicky přes stejné ownery.
  Pokud podmínky mezitím přestaly platit, ponechá žádost otevřenou s vysvětlením.
- Termín se posuzuje při podání. Pořadatel může včasnou žádost posoudit i později
  nebo po vypnutí feature; tím nevzniká zákazníkovi nové write oprávnění.
  Staré zákaznické capability při vypnutí zanikají, evidence žádostí zůstává.
- Důvod je osobní údaj. Uložit jej pouze do scoped evidence žádosti, nevkládat
  do technického auditu, logů ani notification payloadu. Finanční ledger se
  nerozšiřuje o kopii žádosti. Zákazník vidí stav a odpověď pořadatele v přehledu.
- Souběžné schválení, stažení, sken a admin storno serializovat; retry stejného
  schválení nesmí vytvořit další refundaci, historii ani potvrzovací e-mail.

### Nastavení ve formuláři

Nová policy má scope formuláře a revizi. Zapisuje se přes běžný receipted save
formuláře; nový typed predicate pro změnu pravidel respektuje uloženou akci.
Právo zapnout automatické refundace navíc vyžaduje stávající odpovídající
finanční oprávnění pro původní platební zdroje. Editor objednávek tím nezíská
právo rozhodovat o výplatě peněz.

- Každá operace má vlastní enable a absolutní `allowed_until` v UTC. Editor
  zobrazuje místní čas. Chybějící termín nebo neplatná policy znamená vypnuto.
- Povolená pole se ukládají jako explicitní ID a typy. Změna typu pole zneplatní
  povolení. Nikdy neumožnit měnit produkt, cenu, místo, souhlasy, skryté údaje,
  ověřenou identitu, doklad, datum narození nebo e-mail přes obecný JSON patch.
- Automatické storno bez refundace se povoluje jen pro objednávku bez přijaté
  platby; zákazník se nesmí nechtěně vzdát zaplacených peněz.
- U zaplacené objednávky povolit společný potvrzený krok storno + plná refundace,
  nebo výslovné storno + požadavek na ruční refundaci. Důsledek uvést předem.
  Pokud pořadatel nepovolil ani jednu cestu, nabídnout pouze kontaktování obsluhy.
- Přesun má explicitní allowlist cílových formulářů stejné akce. Oba formuláře
  musí změnu povolovat a konečné SQL ověří dostupnost, produkty i kapacitu cíle.
  Mapování produktů zdroj -> cíl je explicitní a úplné; chybějící mapování blokuje
  nabídku. Nelze odvozovat shodu produktů z titulku.
- Přesun je dostupný pouze s podloženým označením cílového termínu v existujícím
  modelu/formuláři. Neodvozovat datum akce od otevření prodeje. Pokud data termín
  nevyjadřují, nabídnout požadavek obsluze a samostatně popsat nutné rozšíření.
- Nová pravidla platí pro nové požadavky i existující objednávky; při každém
  potvrzení se kontroluje aktuální revize. Přísnější policy zneplatní starý
  náhled. Přijatý finanční závazek ale vypnutí funkce nesmaže.

## Kanonický kontrakt a autorizace

Nová doména `database/functions/customer_order_changes/` vlastní policy,
zákaznické oprávnění, náhled, command a audit. Navržené názvy jsou nové symboly.
Administrační a zákaznické vstupy sdílejí doménové efekty, nikoli oprávnění.

1. Přehled zůstává čtecím rozhraním. Projekce vrací jen `allowedActions` s důvody
   nedostupnosti a expirací pravidel; samotná projekce není oprávněním k zápisu.
2. Zahájení změny zašle jednorázový potvrzovací odkaz na uložený e-mail kupujícího
   přes `public.email_messages`. Nezmění příjemce podle vstupu prohlížeče.
   Použít stávající capability kryptografické primitivy; nevyžadovat vytvoření účtu.
3. Vlastní nová write capability je omezena na uloženou objednávku, tenant,
   formulář, operaci a otisk konkrétního návrhu. Platí 10 minut a pro jednu změnu.
   V databázi pouze hash, vazby, expirace a spotřeba; raw token jen v šifrovaném
   doručovacím zdroji. Nový odkaz nese token ve fragmentu, bootstrap jej odstraní.
4. Kliknutí/GET nikdy neprovádí změnu ani spotřebu tokenu, včetně mail scanneru.
   Po načtení následuje náhled a explicitní potvrzení přes POST. Žádné tokeny
   do logů, analytiky, refereru nebo persistentního browser storage.
5. `preview_customer_order_change` vrací serverový rozpad a krátce platný otisk:
   scope, operace, payload, policy revision, aktuální odpovědi/ticket lifecycle,
   finance a cílová dostupnost. Raw capability a osobní údaje nejsou v auditu.
6. Edge `customer-order-changes` přijímá omezený payload, capability a command ID.
   SQL `command_customer_order_change` znovu ověří oprávnění, expiry, policy a
   fingerprint. Nikdy nevěří zaslanému order ID bez vazby na uložený scope.
7. Command receipt je vázán na capability identitu, operaci a hash vstupu.
   Spotřeba capability a doménový commit jsou atomické. Po síťovém výpadku lze
   stejný command bezpečně obnovit pod stejnou identitou, i když je capability
   již spotřebovaná tímto commandem; expiry/revokace stále blokuje přístup.
   Jiný command nemůže použít spotřebovanou capability. Zákazník si po expiraci
   obnoví oprávnění novým e-mailem a stav čte v existujícím přehledu.

Do získání odpovědi se nesmí domýšlet úspěch. 409 znamená obnovit náhled a
znovu potvrdit. 403/404 nezveřejňují existenci cizí objednávky. Tokeny a scope
se ověřují znovu i před replay receipt; starý čtecí odkaz nelze povýšit pouhou
změnou parametru. Reissuance/revokace zákaznického přístupu musí revokovat
související write capabilities.

Pro vydávání odkazů použít existující limity e-mailové fronty a doplnit limit
na objednávku + IP: nejvýše 1 pokus za minutu a 3 za hodinu, s generickou
odpovědí. Hraniční počet konfigurovat serverem. Veřejné endpoints mají body limit
a allowlist operací. Nové SQL funkce jsou v `public`, s explicitním search_path,
RLS a minimálními granty; service-only command není veřejné univerzální RPC.

## Finance, kapacita a neměnné vazby

Refundace zákazníka je úzká delegace udělená uloženou policy, ne simulovaná
role manažera. Soukromý refund-preparation owner sdílený s admin vstupem znovu
ověří částku, původní zdroj, měnu, support, pending reservations a finance.
Zákazník nemůže zadat příjemce, účet, provider ani vyšší částku.

Částka je nezáporný dostupný potvrzený zůstatek po předchozích refundacích,
pending rezervacích a relevantních sporech. Automatika neprovádí změny, pokud
finance nejsou úplné, probíhá spor nebo může ještě doběhnout inkaso. Předplněná
bankovní instrukce není důkaz odeslaných peněz; hotovost nevzniká kliknutím
zákazníka. U banky/hotovosti je požadavek obsluze nefinanční evidence a obsluha
využije současné oprávněné platební operace.

Storno a rezervaci automatické refundace zapsat jednou transakcí. Pokud rezervace
není možná, nic nestornovat. Externí dispatch proběhne později stávajícím workerem
bez DB zámků. Nejasný/selhaný dispatch nezpřístupní vstupenky znovu a nevytvoří
druhou žádost; zákazník vidí čekající či řešený stav. „Vráceno“ vzniká až z
potvrzeného settlementu. Pozdní platba po stornu nesmí oživit vstupenky;
existující reconciliation musí založit viditelný případ pro obsluhu a žádná
automatika nesmí vrátit více než skutečně dostupné peníze.

Online zrušení vstupu je nový doložený zákaznický záměr, nikoli falešný provider
refund observation. V etapě 1 vyčlenit soukromý společný admission-cancellation
owner, který použije dnešní invalidaci ticketů/kapacit a zachová původní online
cenu a payment identity. Napojit jej z refund effects i autorizovaného customer
commandu; stávající `apply_provider_payment_effects_internal` nadále jako jediný
interpretuje provider finanční fakta. Neodstraňovat guard z bankovního storna.
Pokud engine takový záměr zatím nezná, jeho zavedení a regrese patří do etapy 1,
nikoli do klientského wrapperu. Současně ošetřit callback/reconciliation tak,
aby přijaté zákaznické storno neobnovilo vstup ani znovu neposlalo platbu.

Přesun v rámci téže akce zachová order ID, ticket ID a původní payment_info,
bankovní reference i provider identitu. Změní jen povolený form/product scope,
odpovědi a kapacitní alokace; cena zůstane přesně stejná. Historie zachová
původní form i položky. Kapacitu cíle získat a zdroj uvolnit atomicky společným
ownerem. Zachovat běžnou validaci povinných produktů a target form fields.
Závod s nákupem, skenem, stornem a změnou policy musí mít jediného vítěze.
Nevolat produktový materializer, který vyžaduje ticket `ordered`, na již placený
ticket; nejprve vyčlenit sdílené validace a vytvořit explicitní move owner.

Použitá vstupenka, immutable print batch, nevyřešená faktura nebo nekompatibilní
platební závazek automatické storno/přesun blokuje. Fakturoid vystavený doklad
vyžadující opravu znamená v první verzi ruční požadavek; nevytvářet novou
neověřenou větev dobropisů. Změna údajů nepřepisuje vydaný účetní doklad.
Přesun měnící obsah vstupenky přegeneruje doručení a aktualizuje Wallet;
původní QR symbol zneplatní přes stávající generátor a scanner owner, nikoli
zavedením dalšího druhu vstupenky. Historická PDF tak nelze použít na starý termín.

Lock order přebírá společné policy/capacity/domain ownery; cílové a zdrojové
formuláře a produkty zamykat ve stabilním pořadí. Konkrétní hierarchii zapsat
před implementací do kontraktu; zákaznický wrapper nesmí zamknout order před
zámky, které admin tok získává jako první. Žádné persistentní aplikační triggery.

## Implementační etapy

### 1. Policy a oddělení doménových efektů od oprávnění

- Přidat revizovanou policy do kanonického form save/projekce a typed predicates.
- Zaregistrovat extra feature `customer_self_service`, serverový fence a výchozí
  vypnutí. Kopie akce nesmí převzít write capabilities ani otevřené požadavky;
  kopie formuláře má dílčí povolení samoobsluhy vypnutá, dokud je pořadatel
  nezkontroluje a neuloží pro nový kontext.
- Ve storno/response ownerech vyčlenit soukromé efekty pro admin i zákaznický
  vstup. Stávající public/admin RPC zachovají vlastní kontrolu oprávnění před
  vstupem i receipt replay. Privátní helper nesmí mít klientský grant.
- Totéž připravit pro refund-preparation; nepoužívat service role jako důkaz
  zákaznického nároku. Zákaznická policy se nesmí stát univerzálním finančním RBAC.
- Migrace je aditivní; pro všechny existující formuláře vypnuto, bez zpětného
  udělení write práv stávajícím čtecím capability.
- Výstup a ověření: SQL ACL/regresní kontrakty prokážou nezměněný admin přístup,
  fail-closed policy a odmítnutí cross-tenant i read-token zápisů.

### 2. Potvrzení e-mailem, náhled a úprava údajů

- Přidat capability challenge, serverový náhled, jednorázový command, audit a
  transactional email intents. Použít existující command receipt mechanismus;
  nepřidávat druhý framework idempotence nebo druhou e-mailovou frontu.
- Rozšířit přehledy web/Flutter a modely v `packages/festapp_core` o stejné
  serverové akce. Nové změny nepotřebují novou veřejnou adresu portálu.
- Rozšířit společnou prezentaci v `_shared/emailActionLink.ts` o serverem
  doložené dostupné změny. Kontext předat z kanonické projekce přes přípravu
  e-mailu; samotný renderer nečte databázi a neduplikuje pravidla. Propagovat
  kontext do automatických zpráv, ručního resend a editorových náhledů. Udržet
  stávající `order_overview_url`/`order_overview_button` a povinné link-sloty;
  vlastní pořadatelův text nepřepisovat a nevložit druhé tlačítko.
- Zachovat validace formuláře, optimistic concurrency a minimalizaci údajů.
  Neplatné nebo mezičasem změněné pole zablokuje celý patch.
- Výstup a ověření: jedna bezpečně potvrzená změna kontaktu/odpovědí je vidět
  v administraci i přehledu; retry nemá druhý audit ani e-mail.

### 3. Storno a plná refundace

- Připojit kanonické storno a refund intent v jedné transakci s ověřením
  lifecycle a finance. Respektovat revokace, kapacity, historii, Client Sync,
  notifikace a Wallet owner. Storno nevyvolává neautorizované odeslání peněz.
- Implementovat režimy automatického a schvalovaného storna včetně povinného
  důvodu, zamítnutí a stažení dle výše uvedeného kontraktu.
- Pro nepodporovanou automatickou refundaci vytvořit scoped požadavek obsluze
  s jedním dedupe klíčem. Zobrazit jej v existujícím detailu objednávky a
  notification centru; nesmí se schovat jen do textového e-mailu.
- Stavy požadavku obsluze `open/approved/rejected/resolved/withdrawn` jsou pracovní evidence,
  nikoli financial ledger. Obsluha potřebuje aktuální práva pro finanční efekt.
  Zákazník může stáhnout pouze dosud neprovedený požadavek, ne již odeslanou platbu.
- Výstup a ověření: závod customer/admin a refund retry vytvoří jediný závazek;
  instrukce, pending a potvrzené vrácení jsou v UI rozlišitelné.

### 4. Omezený přesun termínu a žádosti mimo jeho rozsah

Doložená změna předpokladu při implementaci (2026-11-15): `public.forms`
nemá datum konání termínu; `form_availability.sql` používá
`schedule.start_time/end_time` jako hranice prodeje. Tyto hodnoty nejsou termínem.
Před automatickými přesuny přidat do kanonického modelu formuláře nullable
`term_start_at` a `term_end_at` (UTC instants, end > start), editaci v časové
zóně akce a projekci do obou klientů i podkladů vstupenek. Automatický přesun vyžaduje skutečný začátek i konec obou termínů.
Ověření Wallet prokázalo, že neznámý konec nelze nahrazovat začátkem:
tím by byl průkaz označen jako prošlý již při zahájení. Neúplný termín
proto vyžaduje ruční posouzení a nevydává nový Wallet průkaz. Kopie formuláře čas i povolení
přesunů vynuluje k nové kontrole. Rozšíření jde přes receipted form save,
stejné optimistic concurrency a kapacitní zámky. Cíl se neodvozuje z titulku,
prodejního okna ani data celé akce. Podpora této domény je součást etapy 4,
nikoli podmínka pro implementaci etap 1-3.

- Přidat správu explicitních cílů a mapování produktů; náhled ukáže termín,
  nové položky, přesně nulový doplatek a aktuální kapacitu.
- Soukromý move owner zachová finanční identitu a atomicky převede původní
  ticket identity i alokace. Přegeneruje neplatný starý QR, aktualizuje PDF,
  Wallet a frontu potvrzení přes existující kanonické efekty.
- Cizí akce, jiná cena, sedadla a případ vyžadující opravu faktury jdou výslovně
  do požadavku obsluze bez změny objednávky a bez rezervace cílové kapacity.
- Výstup a ověření: přesun nepřekročí kapacitu, nevytvoří druhou platbu a není
  mezistav bez platného místa. Při konfliktu zůstává původní objednávka nedotčena.

### 5. Kontrakce a migrační rehearsal

- Povinně aktualizovat uživatelskou nápovědu v `automation/release/help/`
  a anglické protějšky v `en/`, včetně katalogu `pages.json`, navigace,
  vyhledávání a kontextových odkazů, pokud přibude nová sekce nebo článek.
  Pro pořadatele vysvětlit zapnutí extra feature a jednotlivých operací,
  termíny, povolená pole, cíle přesunů a práci s požadavky obsluze.
  Pro zákazníka popsat cestu ze stávajícího e-mailového tlačítka do přehledu,
  výběr změny, případné e-mailové ověření, náhled a potvrzení, sledování
  výsledku a obnovu při konfliktu. Odlišit přijatý požadavek, probíhající
  refundaci a skutečně vrácené peníze. Uvést omezení první verze a postup,
  když tlačítko změny není dostupné nebo už uplynul termín.
  Aktualizovat tematické návody nastavení akce, objednávek, plateb a řešení
  potíží podle skutečného rozsahu implementace. Nápověda nesmí slibovat
  automatický přesun mezi různými akcemi ani bankovní refundaci, kterou
  provádí obsluha. Zachovat CZ/EN shodu a neoznačit funkci za živou před deploy.
  Potřebné screenshoty po implementaci pořídit v light mode, s UI i daty
  v jazyce návodu a podle `automation/help_capture/README.md` a pravidel repo.
- Zapsat ACL manifesty/definer kontrakty, obnovu po výpadku, zákaznické chyby,
  lokalizace a doménovou dokumentaci. Česky „Stornovat“, vykání; klávesnice a
  čtečka musí zvládnout náhled i potvrzení. Zachovat lokalizační nastavení portálu.
- Odstranit případné dočasné bypass granty, duplicitní storno/refund logiku a
  experimentální route vytvořené touto implementací. Stávající čtecí overloady,
  admin RPC a payment connector protokoly zůstávají podporovanými hranicemi.
- Lokálně nacvičit pořadí schema/policy -> Edge a worker dependencies -> modely
  a UI. Zapínání operací není součást migrace.
- Výstup a ověření: žádná klientská cesta nepíše přes čtecí token ani přímo do
  financí. Nasazení a aktivace jsou oddělené, dosud neprovedené kroky.

## Souhra se slevovými kódy

Plán je nezávisle implementovatelný; doporučené pořadí je nejprve slevové kódy,
pak samoobsluha. Úprava údajů zachová slevu, storno nevrací limit použití a
refundace vychází z netto skutečně zaplacených peněz. První verze automatického
přesunu objednávku se slevovým kódem odmítne, dokud společný cenový owner neumí
zachovat původní slevový snapshot i cílový rozsah. Nabídne žádost obsluze.
Nesmí se pokusit slevu odebrat, znovu čerpat nebo navýšit částku původního checkoutu.

## Ověření při implementaci

V plánovací fázi se testy nespouštějí. Nové SQL kontrakty patří do
`database/tests/customer_order_changes/`; regresní oporu tvoří
`database/tests/eshop_orders/customer_order_overview_test.sql`,
`database/tests/payment_providers/payment_operations_test.sql` a
`database/tests/eshop_orders/refund_financial_projections_test.sql`.

- Autorizační matice: cizí tenant/form/order, neplatný/read/revoked/expired token,
  jiná operace, replay změněných bytes, nový příjemce, nepovolený field a rate limit.
- Feature: missing/off/on/off/on, nezapnuté dílčí operace, přímý command při vypnutí,
  revokace náhledů a capability při vypnutí, doběhnutí přijaté refundace a čtení
  přehledu bez zapnuté samoobsluhy.
- Schvalování: automatické/schvalované storno, povinný/volitelný/prázdný/příliš
  dlouhý důvod, zamítnutí, stažení, schválení po termínu/vypnutí a chybějící
  finanční právo obsluhy. Schválení není settlement a podání nemění vstupenky.
- Souběh: schválení/stažení/skener, dvojí schválení, zákazník/admin, policy změna, dva skeny, dva přesuny na poslední místo,
  pozdní přijatá platba, dva refund požadavky a výpadek po DB commitu.
- Finance: bank/cash/provider, no-money, částečně zaplaceno, již vráceno, pending
  a nejasný dispatch, spor a nekompletní ledger. Vypnutí prodeje nesmaže závazek.
- Lifecycle: čekací listina, dílčí waitlist acceptance a linked child orders,
  used/expired/storno, print-batch immutability, faktura a slevový snapshot.
  První verze self-service pro čekající či složené waitlist rodiny nabídne
  stávající waitlist akce/obsluhu, nikoli změnu celé rodiny jedním order ID.
- Přesun: úplnost produktového mapování a required fields, jiná cena/měna,
  účet/provider, sedadla a jiná akce; staré QR se neověří, nové funguje.
- Web/Flutter: obnovení náhledu při 409, odchod/návrat, pending stav, double-click,
  přístupnost a žádný únik capability do analytiky nebo odpovědi cizího scope.
- E-mailová cesta: skutečné současné tlačítko otevře tentýž přehled s povolenými
  akcemi; starý odkaz začne fungovat se změnami po zapnutí feature, ale nezíská
  write právo bez dodatečného potvrzení. Text odpovídá zapnutým operacím, po
  vypršení termínu nic neslibuje nový e-mail; preview a resend používají tentýž
  presenter. Rozšířit `supabase/functions/_shared/orderEmailOverview_test.ts`.
- Příkazy: `node web_client/scripts/run_db_tests.js database/tests/customer_order_changes/self_service_test.sql`
  po vytvoření nového kontraktu a dotčené existující SQL testy; cílené Deno
  testy nového Edge rozhraní; v `web_client` přes `pnpm exec node --test`
  vybrané `.test.js` testy přehledu a změn. Flutter cases přidat do příslušné
  existující session a spustit `fvm flutter test --concurrency=1`, pouze při
  volném workstation Flutter slotu. Dodržet běžné cílené gates v CONTRIBUTING.

## Nasazení, předpoklady a hotovo

Dokončení zahrnuje aktualizovanou CZ/EN nápovědu, funkční odkazy z UI,
vyhledatelný postup a kontrolu shody návodu se skutečně implementovanými kroky
i omezeními. Použít existující cílené help kontroly; neověřovat pouze README.

Uživatelem upřesněný směr: samoobsluhu vést jako samostatnou volitelnou feature
stejně jako slevové kódy; konkrétní operace zpřístupnit až po jejich nastavení.
Uvedené bezpečné hranice první verze jsou návrhovým rozhodnutím. Nejde o
uživatelem výslovně schválená konkrétní storno pravidla.
Před produkční aktivací musí pořadatel nastavit termíny a pravidla;
nic neudělovat automaticky migrací. Žádný plán netvrdí zákonný nárok na refundaci.

Automatické přesuny závisí na doložitelném modelu cílového termínu. Pokud
průzkum implementátora ukáže, že jej nelze reprezentovat existujícím formulářem,
upravit etapu 4 na konkrétní rozšíření domény a popsat dopad před implementací;
nevydávat pouhé přepsání titulku za podporu opakovaných akcí.

Produkční migrace, deploy a aktivace nejsou autorizovány tímto zadáním.
Budoucí rollout vyžaduje ověření canonical backend targetu, migraci se zálohou,
příslušnou webovou release gate a jediný vybraný tenant. Rollback vypne nové
akce/vydávání capability, zachová audit, již přijaté požadavky a refund recovery;
nesmí znovu oživit stornované vstupenky nebo zrušit finanční fakta.

Hotovo: všechny povolené změny procházejí týmž doménovým ownerem jako obsluha,
vlastním scoped zákaznickým oprávněním a idempotentním commandem. Audit, kapacita,
finance a doručení souhlasí. Povinné cílené kontroly projdou, nejsou otevřené
bypass grants ani alternativní ledgery a předání uvádí přesné hranice automatiky,
výsledky migrace a oddělený stav implementace/nasazení/aktivace.
