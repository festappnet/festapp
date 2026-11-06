# Rezervace s platbou pouze hotově a bez termínu úhrady

Datum: 2026-11-06  
Stav: Implementováno a lokálně ověřeno 2026-11-06; produkční aktivace neprovedena
Ověření při implementaci: standard (platební kontrakty, oprávnění a migrace)

## Průběžný stav implementace

- Lokální implementace dokončena: per-form cash-only, pokyny, skutečné none, kompatibilní čtení/zápis, ledger, historie, setup/MCP a oba klienti. Žádný další implementační krok není otevřený.
- Výchozí `main` byl `d47667c9fa879a6c4efc1044e838b16e17ee2245`; souběžná nesouvisející práce posunula HEAD během implementace. Cizí změny byly zachovány; tato relace neprováděla commit, push, produkční migraci ani nasazení.
- Fakturoid vyžaduje bankovní referenci: cash se odmítá při konfiguraci i opětovné validaci ve finalizeru, takže ani dodatečně zapojená povinná fakturace není tiše přeskočena.
- Kontroly a scoped caller důkazy jsou zaznamenané v závěrečném oddílu. Browser prošel na finálních SQL zdrojích; všechna jeho prostředí a přístupové údaje byly odstraněny.
- Limit ověření: skutečné odesílání e-mailů bylo vypnuté. Pro zákaznický přehled vydal testovací token skutečný lokální SQL issuer; vystavení odkazu e-mailovým tokem a doručení nebylo součástí browser důkazu. Renderery, skutečné náhledy a send fence mají cílené testy.

## Výsledek a rozsah

Pořadatel může používat formulář jako rezervační systém s cenami a platbou
pouze hotově. Nepotřebuje bankovní účet ani online bránu. Zákazník uvidí cenu,
potvrzenou rezervaci a pokyny k platbě na místě. Neuvidí platební QR, bankovní
údaje ani termín úhrady. Pořadatel následně eviduje skutečně přijatou hotovost.

Uživatel výslovně doplnil možnost **Bez termínu úhrady**. Jde o uloženou
politiku, nikoli o schování data v UI. U hotovosti je výchozí a závazná pro tuto
první verzi. Je dostupná také pro bankovní převod. Technická expirace online
platebního pokusu a krátkodobé držení míst před odesláním rezervace zůstávají
oddělené; volba je nesmí vypínat.

Zahrnout Flutter administraci i veřejné formuláře, JS veřejný klient, SQL,
Edge potvrzení/e-maily, založení akce, duplikace, administrativní tvorbu
objednávek a přijetí nabídky z pořadníku. Nepřidávat novou pokladnu, novou
platební bránu, účetní systém ani kombinace hotovost + online platební metody.
Žádné produkční změny, commit ani push nejsou součástí tohoto návrhu.

## Ověřený současný stav

Základ průzkumu: `main`, HEAD `a31277e3c`, s rozsáhlými existujícími lokálními
změnami. Důkazem je aktuální pracovní strom, nikoli pouze obsah HEAD.

| Zjištění | Místo | Důsledek |
|---|---|---|
| Banka je vestavěná metoda, jiné metody jsou směrovány do adaptéru poskytovatele. | `database/functions/payment_providers/{schema,registry}.sql`, `form_payment_availability_internal`, `payment_method_registered_internal` | Hotovost musí být explicitní vestavěná metoda; nesmí spadnout do online adaptéru. |
| Nastavení obsahuje `bankEnabled` a `providerConnections`; vypnutí všech metod u placeného formuláře je neplatné. | `payment_providers/{configuration,registry}.sql`, `eshop_forms/form_settings.sql` | Rozšířit jeden kanonický kontrakt nastavení a dostupnosti. |
| Finalizace vytváří payment_info, bankovní instrukce, deadline, alokace a objednávku. NULL délka dědí termín akce, případně týden. | `database/functions/eshop/finalize_ticket_order.sql` | NULL ani nula délky nejsou reprezentací režimu bez termínu. Opravit oba výpočty dědění v této funkci. |
| Hotovostní pohyb už existuje; managerovi lazily vytvoří účet typu CASH a spáruje pohyb. | `eshop_transactions/insert_manual_transaction_internal_v1.sql` | Znovu použít ledger a zámek podle jednotky/měny. CASH účet není bankovní účet pro převody. |
| Párování i přepočet plateb dnes počítají s metodou bank. | `eshop_transactions/apply_transaction_pairing.sql`, `eshop_orders/recalculate_order_payment_status.sql` | Přidání cash do pickeru nestačí; musí fungovat skutečné přijetí hotovosti a změny produktů. |
| Historie objednávky se čte podle práva číst objednávky. | `eshop_transactions/get_transactions_for_order.sql` | Čtení historie nemusí záviset na dnešním seznamu účtů. |
| UI nabízí přidání hotovosti, hledání závisí na bankovním oprávnění a příjemcovském účtu; má i náhradní ID 0. | `lib/components/eshop/views/transactions_dialog.dart` | Rozdělit dostupnost hotovosti, čtení historie a bankovního hledání; odstranit náhradní neexistující účet. |
| Odpojení účtu maže vazbu unit_bank_accounts, ne účet; kontrola závislých formulářů vychází z měn. | `eshop_bank_accounts/link_bank_account_to_unit.sql` | Cash formulář nesmí blokovat odpojení posledního bankovního účtu. Bankovní formulář nadále vyžaduje vyřešení závislosti. |
| FK transakcí na účet má ON DELETE CASCADE. | `database/tables/tables.sql`, `transactions_bank_account_fkey` | Historii chránit odpojením/archivací, ne fyzickým smazáním účtu s pohyby. Při implementaci ověřit finální migrované schéma. |
| Upomínky i změna deadline mají společného vlastníka. | `database/functions/emails/{set_payment_deadline,queue_payment_reminders}.sql` | Bez termínu nesmí vzniknout ani zůstat odeslatelná platební upomínka. |
| Úprava produktů znovu odvozuje termín z akce nebo sedmi dnů, nezávisle na původním termínu. | `eshop_orders/update_ticket_products_ws.sql`, blok 5a | Resolver nestačí zavolat pouze při vytvoření; úprava nesmí obnovit deadline u none/cash. |
| Edge vytváří bankovní QR pro placené objednávky mimo registry online poskytovatelů a stejnou podmínkou spouští Fakturoid. | `supabase/functions/send-ticket-order/index.ts`, větve před `presentPayment` a `prepareFakturoidTicketOrder` | Cash vyžaduje samostatnou prezentaci a vyřešení bankovního předpokladu fakturačního toku. |
| Potvrzení i změnový e-mail počítají s bankovní referencí; zálohový text odvozuje termín z aktuální feature. | `supabase/functions/_shared/orderEmailPresentation.ts` | NULL datum nestačí: použít metodu a uloženou deadline policy, nevyrábět náhradní text ani referenci. |
| Odebrání ruční úhrady kontroluje admina příjemcovského bankovního účtu, který cash nemá. | `eshop_transactions/delete_manual_transaction_ws.sql` | Výslovně upravit autorizaci opravy cash úhrady podle skutečné jednotky a CASH pohybu. |
| Hledání nepřipojených pohybů bere účet z payment_info; parametr bankAccount v dialogu tento SQL zdroj nemění. | `get_transactions_for_order_all_available.sql`, `search_transactions_dialog.dart` | Prohlížení historického účtu bez payment_info.bank_account potřebuje skutečný autorizovaný vstup, nikoli jen předání ID do widgetu. |
| Právo měnit bankovní transakce vyžaduje admina účtu i managera navázané jednotky. | `user_permissions/bank_operations.sql`, `automation/authorization/context_capabilities.sql.in` | Odpojený účet může mít zachované čtení, ale ztracené párování; historii neslibovat jako automaticky editovatelnou. |

Relevantní návaznosti: `docs/plans/payment-provider-hardening-plan-2026-11-06.md`,
`lib/components/{forms,eshop}/README.md`. Rozpracované provider změny zachovat
a cash přidat do jejich společné vrstvy, bez duplikované konfigurace.

## Rozhodnutí o produktu

1. V nastavení plateb přibude **Pouze hotově** s vysvětlením:
   „Rezervace se potvrdí bez platby předem. Platbu zaevidujete po přijetí hotovosti.“
   Volba funguje bez bankovního účtu i v případě, že účet nastavený je.
   Chybějící účet nesmí sám změnit existující bankovní formulář na cash.
   U nového formuláře bez účtu ji nabídnout jako dostupnou cestu a uložit
   explicitně při potvrzení. Přepnutí mění pouze budoucí objednávky.
   Nastavení je výslovně **pro každý formulář**, ne pouze globálně pro akci
   nebo jednotku. Dle upřesnění uživatele patří **Pouze hotově** přímo do
   stávající společné sekce výběru plateb, kde se vybírá bankovní účet
   a podpora Stripe či dalších poskytovatelů. Rozšířit současný výběr metod,
   nezavádět samostatný přepínač rezervačního režimu ani další nastavení
   označení. V témže místě pořadatel volí **Pouze hotově**, **Bankovní převod**
   nebo existující online možnosti a jejich podporované kombinace.
   U převodu vybere z dostupných účtů jednotky s podporou příslušné měny.
   Bez použitelného účtu se převod nedá nově aktivovat; vysvětlení nabídne
   nastavení účtu dle oprávnění. Existující online volby zůstávají zachované.
   Vybraná volba je ve společné sekci jasně pojmenovaná **Pouze hotově**.
   Případné existující souhrny plateb ukazují tutéž uloženou volbu; nevytvářet
   kvůli ní novou povinnou kategorii štítků ani ovládání v seznamu formulářů.
   Stejné označení zákazník vidí u platebních pokynů a ve shrnutí před
   odesláním, ne až po vytvoření rezervace.
   Označení v administraci vychází z uložené konfigurace formuláře; zákaznické
   potvrzení z uložené metody objednávky, aby pozdější přepnutí formuláře
   nepřeznačilo dřívější objednávky.
2. Pole **Pokyny k platbě**: volitelný prostý text, maximálně 1000 znaků.
   Prázdná hodnota zobrazí lokalizované „Zaplaťte prosím v hotovosti na místě.“
   Například „Částku uhraďte v hotovosti při vyzvednutí vstupenek u vstupu.“
   Zobrazit před odesláním, v potvrzení, e-mailu i přehledu objednávky.
   Nezaměňovat s existujícím `payment_message.type`, který vlastní zprávu pro převod.
3. Potvrzení: **Rezervace potvrzena**, celková cena, **K úhradě na místě**,
   pokyny a odkaz na detail. Žádný platební QR, IBAN, VS, odpočet ani výzva
   k převodu. Identifikátor objednávky zůstává. Vstupní/identifikační QR je
   jiný účel a tato volba jej sama o sobě neruší.
4. **Termín úhrady** má pro převod tři výslovné stavy: **Podle nastavení akce**,
   **Vlastní lhůta**, **Bez termínu úhrady**. Poslední stav nemá datum, bankovní
   upomínky ani automatické storno kvůli nezaplacení. Pro cash je zvolen
   automaticky; UI vysvětlí „Platba proběhne na místě, termín úhrady se neurčuje.“
   Bez termínu se žádný prázdný řádek, pomlčka ani „Zaplaťte do“ nevykreslí.
   Toto platí pro všechny zákaznické výstupy včetně e-mailů, záloh a PDF,
   pokud příslušná šablona dnes obsahuje platební termín.
5. Rezervace drží kapacitu/místa po úspěšném odeslání, není označená jako
   zaplacená. Interně může zůstat `ordered`; veřejný text vyjadřuje rezervaci.
   Uvolnění probíhá explicitním stornem nebo stávajícími nezávislými pravidly,
   nikoli expirací bankovní platby. Platná zůstávají pravidla prodejního období
   a krátkodobé blokace míst před odesláním.
6. **Přidat platbu v hotovosti** funguje bez bankovního účtu se stávajícím
   oprávněním managera jednotky. Umožní částečnou úhradu a pozdější doplatek;
   do zaplacení se zobrazuje zbývající částka. Zápis vzniká až převzetím peněz.
   Přechod na paid a další doručení vlastní existující platební lifecycle.
   Přijetí peněz ani odeslání potvrzení nesmí být vzájemně zaměněny.
7. Bez bankovního účtu administrace ukáže nezávazný hint:
   „Pro vyhledávání a párování bankovních transakcí nastavte bankovní účet.“
   Akce **Nastavit bankovní účet** se ukáže pouze oprávněnému uživateli.
   Hotovost je aktivní; bankovní hledání bez dostupného oprávněného účtu není.
   Platí výslovně také pro dialog **Přidat platbu (v hotovosti)** ze screenshotu
   uživatele: částka, pokročilá nastavení a potvrzení hotovosti zůstanou dostupné.
   Spodní bankovní část se přizpůsobí dostupným datům a oprávněním:
   - Bankovní objednávka má použitelný účet a oprávnění k hledání i párování:
     ponechat **Najít a propojit transakci**, i když účet zatím nemá pohyby.
     Prázdný výsledek hledání není důvodem nabízet nové nastavení účtu.
   - Není žádný nakonfigurovaný použitelný bankovní účet ani přístupná historie,
     zejména pokud banka nikdy nebyla nastavená:
     místo hledání ukázat uvedený hint a odkaz **Nastavit bankovní účet**.
     Oddělovač **NEBO** vynechat, protože nastavení účtu není alternativní úhrada.
   - Má-li uživatel čtecí právo k historickým pohybům, ale nelze je párovat,
     nabídnout **Zobrazit starší transakce**. Platí i pro cash objednávku:
     bankovní historii zpřístupnit k prohlížení, ne jako její úhradu.
     Bez práva nastavit účet
     zobrazit pouze vysvětlení, nikoli nefunkční nebo zakázaný odkaz.
   - Existuje aktivní banka, ale uživatel k ní nemá přístup: nenabízet nové
     nastavení jako řešení chybějícího oprávnění. Hotovost smí zapsat pouze tehdy,
     má-li vlastní příslušné oprávnění. U cash-only a existující banky nenabízet
     párování ani nepravdivou výzvu, že banka nebyla nastavena.
   Nevytvářet příznak „účet někdy existoval“: rozhodovat podle skutečně
   dostupných aktuálních/historických účtů, pohybů a jejich čtecích/párovacích
   oprávnění. Otevření nastavení nesmí zahodit rozepsanou částku, datum a poznámku;
   po návratu obnovit bankovní dostupnost bez automatického zápisu platby.
8. Již připojené transakce jsou vidět i po odpojení účtu, pokud uživatel stále
   smí číst objednávku. Historické pohyby se nefiltrují dnešními aktivními účty.
   Hledání dalších starších nepřipojených pohybů používá existující bankovní
   čtecí oprávnění a historický účet; jeho odpojení nemaže členství účtu ani
   data. Efektivní oprávnění se však znovu vyhodnotí - zejména právo párovat
   může po odpojení zaniknout. Neudělovat přístup k celému bankovnímu výpisu
   z pouhého práva číst jednu objednávku.

## Kanonický kontrakt a invarianty

### Závazná architektura

Rozšířit existující hluboké moduly s malým společným rozhraním. Nevytvářet
nový cash subsystém ani obecný framework kolem dvou vestavěných metod.
Rozhraní ukryje rozhodování; volající nepotřebuje znát pořadí helperů,
default týdenní lhůty, typ CASH účtu ani pravidla provider registry.

| Modul a vlastník | Společné rozhraní | Co zůstane uvnitř implementace |
|---|---|---|
| Konfigurace plateb: `payment_providers/{configuration,registry}.sql` | Normalizace a validace uložené volby, dostupné metody a jejich schopnosti | bank/cash jsou vestavěné; online metody mají adaptéry. Žádná nezávislá registry v UI nebo copy logika v setup. |
| Platební politika objednávky: stávající finalizer + jeden soukromý SQL resolver | Vyhodnocení metody, effective deadline policy a neměnného snapshotu při vytvoření; čtení snapshotu při úpravě | Dědění, none/custom, zálohy, defaults, podmínky způsobilosti a odlišení expirace online pokusu. |
| Skutečné úhrady: existující transaction/pairing/reconciliation modul | Autorizovaný idempotentní command zapíše nebo opraví pohyb a vrátí výsledný platební stav | Scope, přesné částky, CASH účet, zámky, součty, změny stavu, audit a transakční email intenty. |
| Čtení objednávky: existující identity/overview/payment projekce | Jeden význam platebního DTO napříč checkoutem, detailem, e-mailem a synchronizací | Server odvodí platební stav a přípustné instrukce ze snapshotu a ledgeru; ne z dnešního formuláře. |
| Administrativní dostupnost: existující capability a transaction read modul | Oddělené povolené akce hotovost/zobrazení historie/hledání a párování/nastavení banky | Aktuální vs historický účet, scope a skutečná oprávnění. Žádné dotazy na nepřístupné pohyby pro UI hint. |
| Prezentace: existující společný Edge email helper + Dart Core/JS adaptér | Typované platební DTO -> lokalizovaný text a vykreslení | Lokalizace a formát; žádné dědění termínu, výpočet účetní způsobilosti ani odvozování metody z absence účtu. |

Kanonický význam projekce plateb:

- `method`: explicitní bank/cash/provider ID; online identita nezmizí pod „online“.
- `status`, `amount`, `paid`, `returned`, `remaining`, `currency`: autoritativní
  finanční fakta a odvozený zůstatek, ve stávajícím přesném wire formátu.
- `deadlinePolicy`: pro uloženou objednávku účinné `none|custom|provider`,
  případné `deadline` a samostatná expirace online pokusu. `inherit` je pouze
  vstup konfigurace, nikoli nevyhodnocená politika hotové objednávky.
- `instructions`: rozlišená data pro banku (reference a účet), hotovost
  (volitelné vlastní pokyny) nebo konkrétního poskytovatele. Neukládat
  druhý souběžný `payment_method` ani kopii amount/deadline v JSON.
  Snapshot nových metadat uložit pod jediný `payment_info.data.payment_policy`;
  stávající sloupce payment_method/deadline a existující bankovní snapshot
  zůstávají autoritou. Verzi nového snapshot formátu použít pouze pokud ji
  vyžaduje zavedený DTO kontrakt; nezakládat veřejné V1/V2 čtecí cesty.
- Admin akce zůstávají součástí autorizované admin projekce, veřejná projekce
  neobsahuje přístup k bankovní historii ani administrační práva.

Existující transportní obálky a podporované starší názvy mohou zůstat na svých
hranách, ale mapují na stejný obsah. Nevynucovat jeden nový síťový endpoint
pro nesouvisející use cases. Projekce nepřidává druhý finanční writer.
Žádné ruční sety `['bank','cash']` rozmnožené po volajících: SQL classification
vlastní registry modul; Dart ji čte v Core, JS ve stávajícím payment options
adaptéru a Edge ve společném platebním kontraktu. Klientské adaptéry validují
tvar a schopnosti, nerozhodují znovu obchodní politiku.

### Invarianty

- SQL vlastní metodu, cenu, měnu, dostupnost, politiku termínu, kapacitu,
  oprávnění i přechod zaplaceno. Klienti zobrazují serverovou projekci.
- Rozšířit `forms.data.payments` o `cashEnabled` (výchozí false) a `cashInstructions`.
  Pro cash-only: `cashEnabled=true`, `bankEnabled=false`, `providerConnections={}`.
  Cash kombinovaný s bankou či poskytovatelem se v první verzi odmítne na serveru.
  Zvolený cash režim není online poskytovatel a nesmí potřebovat handler,
  source token, příjemce, platební pokus, webhooks ani online rezervaci 1860 s.
  Změna volby je jeden atomický patch pod jediným settings ownerem; UI/MCP/setup
  neposílají několik nezávislých změn bank/cash/provider. Konfigurace nepřipustí
  kombinaci aktivního cash a starého legacy Stripe bindingu. Vyhodnocení
  klasifikace method nesmí záviset na přítomnosti nullable handleru u cash.
- `payment_info.payment_method='cash'`; příjemcovský bankovní účet, VS,
  creditor_reference, záloha a platební deadline jsou NULL. Price/amount,
  currency, paid a returned zůstávají skutečné finanční hodnoty.
- Nový `forms.data.payment_deadline.mode` přijímá `inherit|custom|none`.
  Stávající `forms.deadline_duration_seconds` je jediná číselná délka pro custom;
  nevytvářet její kopii do JSON. Chybějící mode zachová současný výklad:
  uložená délka znamená custom, NULL inherit. Nula zůstává okamžitý termín.
  `none` obchází všechna COALESCE dědění a dává skutečný NULL deadline.
  Založení akce nabídne obdobnou politiku na svém existujícím form feature;
  dědění výslednou politiku vyhodnotí jedním SQL resolverem, ne v klientech.
  Na úrovni akce jsou jen custom a none; inherit patří formuláři. Bez nového
  pole zůstává historická feature beze změny se stávajícím týdenním defaultem.
  Zvolená metoda cash vždy vyhodnotí none. Pro online metodu resolver ponechá
  autoritu expirace provideru; none v kombinovaném bank/provider formuláři
  ovlivní jen objednávku skutečně vytvořenou bankovním převodem.
  U form mode inherit/none vymazat neúčinnou délku při explicitní změně mode;
  u custom vyžadovat platné nezáporné celé sekundy dle dosavadních mezí.
  Pro novou objednávku s časovanou bankovní politikou se při pozdější úpravě
  produktů zachová již uložený absolutní deadline. Nenastavovat novou lhůtu
  od okamžiku editace ani ji nepřebírat z mezitím změněné feature akce.
  Termín se změní jen výslovnou autorizovanou změnou termínu objednávky.
  Není proto potřeba duplikovat původní délku ve snapshotu objednávky.
- Snapshot metody, vyhodnocené politiky a vlastních pokynů vznikne s objednávkou.
  Výchozí text lokalizuje čtenář; explicitní text se nepřekládá automaticky.
  Pozdější změna formuláře nepřepíše staré pokyny, deadline ani účet objednávky.
  Cash-only uloží efektivní none explicitně; při přepnutí zpět na převod UI
  ukáže ponechané Bez termínu úhrady a dovolí změnu. Žádný skrytý návrat týdne.
  Klient nemůže objednat bank/provider na cash-only formuláři podvržením
  payment_method, ani cash na bankovním formuláři. Kontrola patří pod stejné
  form/order zámky jako finální cena a kapacita. Replay původní platné objednávky
  vrací původní výsledek i po pozdější změně nastavení; nový command musí splnit
  aktuální konfiguraci. Admin a pořadník nesmějí tiše použít bankovní default.
- U none nevzniká ani deadline zálohy. Zachovat celkovou cenu a zbývající dluh;
  cash první verze nepoužívá bankovní zálohový splátkový kalendář.
- U existující objednávky umožnit oprávněnou změnu termínu na žádný přes
  stávající command vlastnictví: zrušit budoucí upomínkové intenty, verzovat
  instrukce a zachovat historii. Odeslaný e-mail se zpětně nemění. Fronta musí
  před skutečným odesláním zkontrolovat aktuální politiku/verzi. Hromadné
  přepisování starých objednávek ani jejich změna metody nejsou součástí rozsahu.
  Nastavení žádného termínu u již existující bankovní zálohy vymaže také
  deposit_deadline a zneplatní zálohové upomínky, zachová však částky i úhrady.
  Úpravy produktů používají uloženou politiku objednávky: none zůstává none;
  historický NULL deadline bez uložené politiky automaticky nepřeklasifikovat
  na none. Jen historická objednávka bez `payment_policy` zachová dnešní výklad
  editace (nový termín z aktuální feature/defaultu). Tento omezený legacy výklad
  zůstane v jediném SQL policy owneru; nové objednávky mají snapshot vždy.
  První explicitní změna politiky staré objednávky založí snapshot a ukončí
  tento legacy výklad pro danou objednávku. Migrace jej nesmí zpětně vymyslet
  pouze podle NULL hodnoty nebo aktuálního nastavení formuláře.
- Povolit cash pohyb na cash i běžnou bankovní objednávku jako dnes. Na cash
  objednávku nepárovat bankovní pohyb, ani automatickým matchováním podle VS.
  Nezměnit ochrany pro online poskytovatele. Při opakování příkazu nesmí vznikat
  druhá úhrada; ověřit stávající receipted vstup a případný chybějící obalit
  stejným command mechanismem, nikoli novým ledgerem.
  Cash vstup v UI přijímá desetinné částky podle přesnosti měny (např. 250,50 CZK),
  nikoli dosavadní digitsOnly. Nový command přenáší přesný decimal nebo minor
  units, interně numeric; odmítne nulu, nečíselné hodnoty a přílišnou přesnost.
  Záporný pohyb je explicitní oprava hotovosti podle stávající politiky,
  nikoli nepojmenovaná platba. Po stornu se hotovost nevrací automaticky.
  Nový workflow vrácení peněz po stornu není součástí tohoto úkolu. Zachovat
  `check_order_is_mutable` a existující audit/opravná pravidla; neobcházet
  ochranu stornované objednávky přes actor_kind=system nebo oslabením guardu.
  Server odvodí jednotku, měnu a cílovou objednávku z uložených vazeb a ověří
  jejich shodu před vytvořením CASH účtu i pohybu. Klientské unitId ani
  paymentInfoId nesmějí umožnit úhradu cizí objednávky. Stejné kontroly platí
  pro opravu, odebrání a opakování commandu.
  Při nulové ceně nevzniká požadavek na hotovost: zobrazit Bez platby a použít
  existující bezplatný lifecycle bez účtu/QR/termínu. Pokrýt i přechod ceny
  0 -> kladná při editaci, aby cash objednávka nepřešla skrytě na banku.
- Odpojení účtu je změna dostupnosti pro nové převody, není kaskádové mazání
  účetních faktů. Případný existující delete vstup pro účet s pohyby musí
  bezpečně odmítnout fyzické smazání. Nepoužívat CASCADE jako běžnou operaci UI.

## Implementační kroky

### 1. SQL konfigurace, metoda a termín

Rozšířit `payment_providers/{schema,registry,configuration}.sql`,
`eshop_forms/{form_settings,form_payment_options}.sql` a vlastníky vytvoření,
aktualizace a kopie formuláře. Rozlišit vestavěné metody bank/cash od online
providerů ve všech společných dispatch helperech; nepřidávat falešný adaptér.
Upravit setup `occasion_setup/{drafts,finalize,bank_accounts}.sql` a příslušnou
payment normalizaci. Resolver termínu musí rozlišit none od inherit už před
prvním výpočtem ve finalizeru. Availability vrací cash a účinnou deadline policy.
Bankovní dostupnost se určuje z použitelného účtu/měny, nikoli pouze bankEnabled.

Migrace je dopředná, z kanonických SQL zdrojů. Existující formuláře/objednávky
zůstávají bank/provider a ponechávají původní termíny. Neodvozovat cash z chybějícího
účtu. Rozšířit settings allowlist, validace, DTO i MCP authoring nad stejným ownerem.

Ověření: cílené SQL kontrakty pro konfiguraci, chybějící účet, cash s cenou,
neplatné kombinace, partial patch/reset, kopii, none vs NULL vs zero a inherit
z akce. Výstup: otevřený cash formulář s cenou projde bez bankovního účtu;
neznámá metoda zůstane odmítnutá a bank/provider regresní testy projdou.

### 2. Rezervační a platební lifecycle

Upravit `eshop/finalize_ticket_order.sql`,
`eshop_orders/{ensure_order_payment_instructions,recalculate_order_payment_status,operator_orders}.sql`,
`eshop_transactions/{apply_transaction_pairing,insert_manual_transaction_internal_v1}.sql`
a `emails/{set_payment_deadline,queue_payment_reminders}.sql`.
Zahrnout `eshop_orders/update_ticket_products_ws.sql`,
`eshop_transactions/{insert_manual_transaction,delete_manual_transaction_ws,remove_transaction_from_payment_info_ws}.sql`
a skutečný dispatcher/eligibility v `emails/email_queue.sql`. Každou větev
rozdělit podle odpovědnosti; např. zakázanou bankovní operaci nelze pro cash
opravit pouze plošnou změnou podmínky z bank na bank/cash.
Provést cílený soupis větví `method <> bank` v runtime SQL/Edge, aby cash
nebyl považovaný za provider. Zapojit admin objednávku, náhradu sedadel a
`eshop_waitlist/accept_offer.sql` do stejného finalizeru a snapshotu.
Pro none projít existující maintenance joby storen a upomínek i jejich finální
send fence. Platební termín se nesmí nahradit datem akce nebo zálohy.

V `supabase/functions/send-ticket-order/index.ts` povolit bankovní prezentaci
`presentPayment` výhradně pro skutečnou metodu bank, nikoli „není provider“.
Výstup cash vrací uložené pokyny/politiku a null payment_qr. Projít též
`read_order_identity`, `eshop_waitlist/order_overview.sql`, přípravu a hash
admin potvrzení, zákaznické přehledy a offline synchronizační projekce.
Snapshot metody/pokynů/politiky musí vstupovat do potvrzovaného preview hashe,
receipt odpovědi a historie; replay nesmí přepočítat pokyny z dnešního formuláře.

Fakturoid větev dnes očekává bankovní údaje a referenci. Cash-only nesmí
spouštět přípravu bankovní platby ani požadovat VS. V základním rezervačním
režimu bez fakturace se větev nepoužije. Je-li fakturace v konfiguraci povinná,
přes existujícího invoice ownera ověřit a implementovat explicitní hotovostní
režim bez fingované úhrady, nebo cash volbu odmítnout už při konfiguraci
s vysvětlením konkrétní nekompatibility. Nikdy tiše neobejít povinnou fakturaci
ani neselhat až po potvrzené alokaci. Výsledek této omezené kontroly zapsat
do plánu před implementací dotčeného invoice toku.

Potvrzení rezervace nečeká na zaplacení a používá existující transakční email
intenty. Nezavádět paralelní sender. Potvrzení nemusí být zaplacenou vstupenkou;
zachovat oddělení platebního a vstupního QR. Pokud dosavadní odesílání vstupenek
závisí na paid, cash odešle alespoň potvrzení rezervace a zákaznický odkaz ihned.
Skenování nezaplacené rezervace nesmí nepozorovaně vytvořit úhradu: zachovat
současné potvrzení nezaplaceného vstupu, nebo zapsat hotovost explicitní akcí.

Ověření: SQL integrace vytvoření, replay, alokace posledního místa, storno,
částečná/plná/odebraná hotovostní úhrada, editace produktů, přijetí z pořadníku,
směna/rozsah oprávnění, žádné online attempt ani bankovní instrukce pro cash.
Test none pokrývá i děděný deadline a zálohové upomínky, změnu existujícího
deadline na none a neodeslání již naplánovaného intentu.
Přidat editaci produktu po rezervaci s none (bez nového deadline), závod
změna metody vs checkout, receipt replay po změně formuláře, 0 -> placeno,
desetinnou částku, opakované potvrzení úhrady a opravu v povoleném lifecycle.
Pokus zapsat/opravit úhradu stornované objednávky musí nadále odmítnout guard.
Pro novou časovanou objednávku vytvořenou s lhůtou A změnit feature na B,
upravit produkt a ověřit, že původní absolutní deadline zůstal zachován;
zvlášť otestovat ohraničený výklad historické objednávky bez snapshotu.
Ověřit cizí paymentInfoId se zdánlivě správným unitId. Cash potvrzení musí
projít celým Edge tokem bez volání bankovního QR/fakturační reference.
Výstup: rezervace drží kapacitu a zůstane nezaplacená, dokud nevznikne pohyb.

### 3. Historie a přístup bez bankovního účtu

V `eshop_bank_accounts/link_bank_account_to_unit.sql` upravit kontrolu závislých
formulářů podle jejich skutečné metody, účtu a měny; CASH účet nenahrazuje účet
pro převod. Prověřit authoring/mutation owner odpojení i případného smazání účtu.
Historii v `get_transactions_for_order` ponechat navázanou na objednávku.
Přidání hotovosti používat přes kanonické manager oprávnění, ne přes přítomnost
banky. Flutter `transactions_dialog.dart`/`search_transactions_dialog.dart`
oddělí historii, dostupné bankovní hledání a hotovost; žádné account ID 0.
`add_cash_payment_dialog.dart` dostane serverem podložený stav bankovní části
pro hledání, čtení historie nebo nastavení účtu namísto jediného booleanu
`canManageBankTransactions`, který dnes umí bankovní část pouze skrýt.
Navigace na existující nastavení bankovních účtů zachová rozepsaný dialog.
Oprávněné hledání historického účtu nepotřebuje jeho nové aktivní propojení.
Nevytvářet ale nové právo párovat na odpojeném účtu: respektovat současné
`bank_account_write_rule`. Rozšířit existující autorizovaný read owner pro
historickou bankovní navigaci, aby uměl explicitní oprávněný účet bez
bank_account na cash payment_info. Pouhé předání bankAccount do dialogu dnes
nestačí. Cash dialog spouští prohlížení historie samostatnou čtecí akcí,
ne bankovní párování na cash. Serverová projekce rozliší existující banku
bez pohybů, žádnou banku, historii a nedostatečné oprávnění; nevrací PII ani
počty nepřístupných transakcí jen pro rozhodnutí o hintu.
Discovery odpojených účtů použije `get_my_admin_bank_accounts` nad zachovaným
členstvím uživatele, případně jeho stávající čtecí ekvivalent. Výběr historie
je osobní autorizovaný výběr účtu; odpojený účet automaticky nepřiřazovat
aktuální jednotce ani cash objednávce. `get_bank_accounts_for_unit_management`
zůstává seznamem nyní navázaných účtů. Historie pohybů připojených přímo
k objednávce se nadále čte samostatným order readerem. Kvůli hintu nezakládat
registr historických vazeb jednotka/účet a neprohledávat cizí objednávky.

Ověření: matice bez účtu/jen CASH/aktivní bankovní účet/odpojený účet s historií,
order reader vs manager vs bank reader, cizí jednotka a tenant. Odpojení
zachová konkrétní dříve připojené pohyby a jejich částky. Žádná nová práva
k nesouvisejícím transakcím. Widget test dialogu pokryje odkaz při nikdy
nenastavené bance, zachované historické hledání, čtecí oprávnění bez párování
a návrat z nastavení bez ztráty draftu či zápisu platby.
Zahrnout aktivní účet s nulou transakcí a managera bez bankovního admin práva;
ani jeden stav nesmí být mylně vyhodnocen jako nikdy nenastavená banka.
Výstup: hotovost i stará historie fungují bez banky.

### 4. Editory a zákaznické výstupy

Rozšířit `packages/festapp_core/lib/src/{payments,forms}` a
`lib/components/forms/views/form_settings_content.dart`, payment method cards,
feature editor termínu a setup. `FormPaymentOptions` i JS protějšek dnes filtrují
nebankovní metody podle registry konektorů; cash musí projít jako vestavěná metoda.
Round trip všech tří režimů termínu nesmí ztratit explicitní none.
Hotovost zapojit do existujícího společného výběru platebních metod a účtu
v `form_settings_content.dart`/payment method cards, včetně dosavadních online
provider voleb. Tento výběr ukládá jednu kanonickou konfiguraci; žádný další
nezávislý boolean rezervačního režimu nebo editovatelný štítek. Při cash-only
sekce nenabízí účet jako povinný údaj a nesmí zobrazovat zavádějící chybu
chybějícího Stripe příjemce. Bankovní/online detaily odpovídají zvolené metodě.

Upravit JS `web_client/src/components/forms/{form_payment_options,payment_method_picker,order_result,order_overview,payment_details}.js`,
Flutter `order_finish_screen.dart`, `customer_order_overview.dart` a jejich
platební prezentaci. E-mail používá `supabase/functions/_shared/{paymentPresentation,ticketEmail}.ts`
a společné platební/email helpery; dohledat skutečnou hydrataci používaných
šablon a tiskových instrukcí. Žádný termín nepřidávat klientským fallbackem.
Výslovně upravit `supabase/functions/_shared/orderEmailPresentation.ts` a jeho
`confirmationPaymentSubstitutions`, `updateBalanceReasoning` i zálohové větve:
cash nikdy nevolá povinnou `paymentReferenceValue`, bank s none nepoužívá
formátovaný prázdný termín uvnitř věty „do“. Změnové a doplatkové e-maily
čtou stejnou uloženou politiku jako první potvrzení. Upravit i náhledy šablon
nad stejnými helpery, nikoli náhradní ukázkový render.
Pokyny vykreslovat jako bezpečný text; nepřidávat HTML interpretaci.
Lokalizovat nové labely a výchozí texty pro všechny existující jazyky.

Ověření: cílené unit/widget testy nastavení, výsledku a detailu, Edge email
prezentace pro cash/none/bank s termínem/provider. Jeden izolovaný průchod
nová rezervace bez účtu -> potvrzení -> historie -> hotovost -> aktualizovaný
zůstatek. Další průchod převod s none ověří zachovaný platební QR bez termínu.
Browser delegovat dle AGENTS.md; všechny agentní sessions bez zvuku.
Výstup: shodná informace ve všech aktivních čtečkách, žádný platební QR u cash.

## Odstranění předpokladů a kompatibilita

| Současný předpoklad | Cílová změna | Důkaz |
|---|---|---|
| Každá nebankovní metoda má provider handler. | Rozlišit cash před provider dispatch. | Cash integrace bez attempt a tokenu. |
| NULL délka dnes dědí deadline, který editor neumí explicitně vypnout. | Explicitní none; NULL délka zůstává inherit. | None přežije save/reload, zděděný týden i editaci produktů. |
| Chybějící účet může být nahrazen ID 0. | Žádné hledání bez platného oprávněného účtu. | Bez banky není chybový RPC. |
| Pouze metoda bank může přijmout ruční pohyb a přepočet. | Přidat cash se stejným ledger ownerem. | Částečné i plné uhrazení cash. |
| Libovolný placený formulář blokuje odebrání banky. | Závislost podle skutečné platební konfigurace. | Cash neblokuje; převod má bezpečný guard. |
| Finalizer i produktový editor samostatně dědí týdenní termín. | Jeden resolver při vzniku snapshotu; editor respektuje uloženou politiku. | None zůstane zachované po editaci. |
| Edge a e-mail odvozují banku z absence online adaptéru. | Explicitní společný platební kontrakt a rozlišené instrukce. | Cash potvrzení i změna bez reference/QR. |
| UI boolean slučuje nastavení, hledání a historii. | Serverová projekce dostupných akcí nad stejnými capability pravidly. | Účet bez pohybů, historie a absence práv mají odlišné výsledky. |

Architektonická akceptace je součást dokončení, ne samostatný pozdější refaktor:

- Seznam skutečných callerů společného resolveru a payment projekce se doloží
  scoped `rg`; staré výpočty deadline v dotčených writerech jsou odstraněné,
  ne ponechané za dalším ifem nebo jako fallback.
- Jednotlivé obrazovky pouze vykreslují instrukce a dostupné akce. Změna
  pravidla none nesmí vyžadovat úpravy každé obrazovky nebo e-mailové šablony.
- UI, MCP, setup a pořadník volají stejné normalizační/finalizační vlastníky.
  Jeden command vlastní celou transakci, receipt a efekty; žádné ruční klientské
  pořadí „vytvoř rezervaci, účet, pohyb a pošli e-mail“.
- Testy jdou přes stejná rozhraní jako skuteční volající. SQL integrace dokazují
  pravidla, Dart/JS testy jejich interpretaci a zobrazení. Nekopírovat SQL
  resolver do test helperů ani do každého klienta jako referenční implementaci.
- Aktualizovat existující `lib/components/{eshop,forms}/README.md` a příslušný
  Core kontrakt o vlastnictví metody/politiky/snapshotu. Nevytvářet další
  konkurenční architektonický dokument ani ponechané přechodné cash API.

Zachovat dosavadní bankovní a online kontrakty, receipty a podporované mobilní
hranice. Starý klient nesmí novou metodu interpretovat jako banku ani zničit
none při full save. Před aktivací otestovat starší full-save payloady; vynechané
nové klíče se zachovají, výslovný reset se řídí novým settings ownerem.
Pro čtečky, které cash neumí, vrátit podporovanou zprávu k aktualizaci nebo
otevření aktuálního webu, nikoli platební instrukce k jiné metodě.
Pokud starý bank-only payload ukládá cash formulář, nesmí samotná přítomnost
bankEnabled=true změnit metodu bez nového explicitního záměru. Neumí-li starý
vstup tento záměr rozlišit, odmítnout změnu platební sekce s chybou vyžadující
aktualizaci; nesouvisející bezpečné patche zachovat. Testovat konkrétní staré
full-save payloady, nikoli předpokládat, že zachování vynechaných klíčů stačí.

Konkrétní zápisový kontrakt: současný receipted form command dostane v JSON
vstupu volitelný `payment_selection_intent: 'replace'`. Jde o záměr operace,
ne uloženou konfiguraci; zahrnout jej do command hash. Nový editor/MCP/setup
jej pošle jen při explicitní změně platební metody, společně s kompletní novou
volbou a již existující kontrolou původní verze formuláře. Bez tohoto záměru
na cash formuláři server zachová platební konfiguraci při nesouvisejícím patchi,
ale konfliktní starý full save odmítne atomicky. Nové zapnutí cash/none také
vyžaduje explicitní změnu známých settings, nikoli odvození z vynechaného pole.
Výstup chyby používá stávající bezpečnou obálku daného commandu a strojový
`errorCode: 'PAYMENT_CLIENT_UPDATE_REQUIRED'`; klient zůstane v draftu.

Čtecí ochranu nelze zajistit pouze novým polem v odpovědi starému klientovi.
Aktuální veřejný form/order reader a checkout příprava přijmou deklaraci
podporovaných schopností `cash_reservations` a `no_payment_deadline` v jednom
JSON vstupu `client_capabilities`. Rozšířit aktuální transport nad stejným
read ownerem; stávající vydané RPC signatury ponechat jako jejich omezenou
fasádu bez těchto schopností, nikoli jako druhou implementaci. Pro cash nebo
explicitní none starému transportu vrátit před odesláním platebních instrukcí
bezpečnou chybu v jeho stávající obálce (stejný errorCode a text k otevření
aktuálního webu). Nevyžadovat capabilities pro historické bank/provider
objednávky bez nového snapshotu. Deklarace klienta není autorizace.
Checkout command zároveň zkontroluje skutečnou podporu zvolené metody a
policy; starý přednačtený formulář nesmí obejít guard nového readeru.
Aktivace je podmíněná ověřením těchto konkrétních starých readerů a commandů;
nelze-li některý ochránit, daný vstup pro nový režim zablokovat před aktivací.
Dočasný rollout gate tuto trvalou kompatibilitní ochranu nenahrazuje.

## Ověření a nasazení

Při implementaci použít cílené DB testy přes
`node web_client/scripts/run_db_tests.js <konkrétní-test.sql>` a cílené JS testy
v package directory přes `pnpm exec node --test <konkrétní-testy>`.
Flutter/Core cíleně přes existující repository harness; před spuštěním ověřit
volný Flutter slot, testy `--concurrency=1`. Výběr přesných souborů zaznamenat
po doplnění testů. Nespouštět testy pouze kvůli tomuto plánovacímu dokumentu.

Minimální akceptační matice:

| Scénář | Očekávaný důkaz |
|---|---|
| Cash-only, žádný účet, kladná cena | Potvrzená kapacita, ordered, pokyny, null deadline/QR/reference, žádný provider attempt. |
| Cash-only, banka existuje | Stejná rezervace, bez platebního hledání banky; historie jen oprávněným čtenářům. |
| Banka bez termínu, se zálohou i bez ní | Platný bankovní QR, žádný datumový text, deadline ani zálohová upomínka. |
| None po změně produktů či po pozdější změně feature | Zůstane původní snapshot none; nepřibude sedm dnů ani datum akce. |
| Banka s vlastním/zděděným termínem a online provider | Dosavadní deadline/pokusy/doručení a ochrany jsou funkční. |
| Nová cash metoda, starý klient a replay | Žádný bankovní fallback; bezpečné odmítnutí nevyjádřitelné změny; původní receipt stabilní. |
| Odpojený účet, již připojené i nepřipojené pohyby | Připojené čte order reader; širší historii jen bank reader; editace jen s živým write právem. |
| Aktivní prázdný účet / žádné bankovní právo / jen CASH účet | Tři odlišné stavy dialogu, žádný účet ID 0 nebo falešná výzva k nastavení. |
| Částečná/plná úhrada a oprava, replay, pokus o zápis po stornu | Přesné částky, jeden pohyb na command, audit; storno guard nadále odmítá mutaci, used ticket zůstává chráněný. |
| Bezplatná objednávka a pozdější zvýšení ceny | Žádná výzva k platbě při nule; správná uložená metoda při zvýšení ceny. |
| E-mail potvrzení, změna a doplatek | U cash žádná povinná bankovní reference; u none žádný obnovený termín. |

Plán byl prověřen čtením uvedených SQL/Edge/Dart vlastníků a porovnáním
jejich podmínek. Původní matice určovala požadované důkazy. Výsledky dokončené lokální implementace
a skutečně spuštěné kontroly jsou níže; produkční použití z ní nevyplývá.

Nasazení je samostatná autorizovaná operace. Pořadí: kompatibilní schema a SQL,
Edge/prezentace, oba klienti, teprve potom zpřístupnění nové volby ve vybraném
tenantu. Je-li nutný rollout gate, jeden dočasný capability gate s výslovným
odstraněním po upgradu; nevytvářet druhý implementační režim.
Rollback po vzniku cash objednávek nesmí vracet backend, který cash nečte;
omezit nové vytváření a opravit dopředně, data a úhrady zachovat.

## Předpoklady, rizika a dokončení

- Návrhové rozhodnutí: první verze nabízí cash-only, nikoli cash kombinace.
  Rozšíření kombinací později nesmí vyžadovat nový ledger.
- Rezervace bez termínu může blokovat místa až do ručního storna. Nastavení to
  vysvětlí; nevymýšlet skrytou náhradní expiraci.
- Aktuální pracovní strom obsahuje souběžnou rozsáhlou práci. Implementace musí
  zachovat její vlastnictví a ověřit zejména provider a notification kontrakty.
- Nebyla kontrolována živá data ani finální produkční schema. Žádné změny na
  produkci nejsou předpokladem dokončení lokální implementace.
- Hotovo znamená funkční placenou rezervaci bez účtu, žádný platební QR u cash,
  skutečný none bez data/upomínek/storna kvůli úhradě, zachovanou historii po
  odpojení účtu a správné skutečné hotovostní úhrady v obou klientech.
  Banka s termínem, banka bez termínu, bezplatná objednávka i online provider
  musí projít cílenými regresními kontrolami. Produkční nasazení se vykazuje
  odděleně, nikoli jako provedené automaticky s dokončením vývoje.

## Dokončení a ověření 2026-11-06

### Vlastníci a odstraněné cesty

- `payment_providers/registry.sql` vlastní klasifikaci bank/cash/online. `payment_policy.sql::resolve_payment_policy_internal` je společný resolver; `resolve_form_payment_policy_internal` pouze načte uložený formulář a feature. Stejný resolver používá autorizovaný SQL kontext náhledu draftu. Žádná klientská implementace dědění termínu nepřibyla.
- `finalize_ticket_order_internal_v1` volá resolver, capability guard, validaci konfigurace a vrací `customer_order_payment_internal`. `update_ticket_products_ws` volá jen `refresh_order_payment_deadline_internal`. Původní paralelní výpočty termínu byly odstraněné; jediný výslovný legacy výklad zůstává v policy owneru pro objednávku bez snapshotu. Původní absolutní deadline nových objednávek se při editaci nepřepočítává.
- `get_form_by_link(jsonb)` a `get_customer_order_overview(jsonb)` hlídají deklarované schopnosti; vydané signatury delegují bez nich. Form command hash obsahuje `payment_selection_intent`; starý konfliktní full save vrací bezpečnou obálku s `PAYMENT_CLIENT_UPDATE_REQUIRED`. Core authoring allowlist zachovává cash i `payment_deadline.mode`.
- `get_transactions_for_order` promítá autorizované akce a připojené pohyby. Osobní historie používá `can_read_bank_transactions` a `get_bank_transaction_history`, nikoli právo číst objednávku. Bankovní write guard se přepočítá i po odpojení. Odstraněn účet ID 0, původní boolean dialogu i duplicitní gridová navigace; grid/detail používají `showOrderCashPaymentDialog` a uchovávají draft během nastavení a historie. FK účtu je RESTRICT, bez kaskádového mazání ledgeru.
- Edge bankovní QR a reference jsou omezené bankovní metodou. Cash/none prezentace, potvrzení, doplatek a oba skutečné setup náhledy používají společné renderery. Náhledy čtou projektovanou SQL politiku a neobnovují ukázkový bankovní termín. Flutter/JS vykreslují pokyny jako text. Aktualizovány existující Forms/Eshop/Core README a generovaná MCP reference.

Scoped kontrola callerů byla provedena nad `finalize_ticket_order.sql`, `update_ticket_products_ws.sql`, `get_form_by_link.sql`, `order_overview.sql` a `admin_form_orders.sql`. Zbývající `method <> bank` větve jsou výhradně bankovní ochrana instrukcí a fence bankovních upomínek, nikoli dispatch každé nebankovní metody do provideru. V platebních writerech už není druhý týdenní fallback.

### Skutečně provedené kontroly

| Oblast | Výsledek |
|---|---|
| Disposable SQL matice `run_db_tests.js` | 16/16 finálních kontraktů; samostatně následně 1/1 cash setup + kopie + anonymní checkout. Cash, bank/none se zálohou, custom/inherit/zero, repricing, legacy snapshot, replay, storno, odpojená historie, oprávnění, Fakturoid, skutečné preview a send fence. |
| Dodatečné finanční guardy a dostupnost | `cash_command_guards_test.sql` + `cash_policy_regression_test.sql` 2/2. Neplatná přesnost/NaN/nula/numeric JSON, cizí jednotka/měna/objednávka, odmítnutí starého checkoutu a podvržené banky, přesná záporná oprava, zachování used vstupenky a replay po odebrání práv. NULL i nepodporovaná měna banky neposkytují převod. Nové kontrakty jsou součástí kanonických CI kroků `seat-contract`, `ticket-edge`, `ticket-core` a `ticket-client`; generovaná kanonická SQL parita byla aktualizována. |
| Finální veřejný přehled `customer_order_overview_test.sql` | 1/1 nad disposable DB: obě vydané RPC signatury, skutečná role anon, starý klient odmítne cash i bank/none, schopný klient je načte; přímý interní bypass není povolen. Zachované původní kontroly scope, revokace, expirace a stabilních e-mailových zdrojů. |
| Souběh `payment_product_transition_concurrency.test.mjs` | 9/9: zámky bankovních změn/repricing, storno, opožděný e-mail, přesun mezi scope, dvě cash rezervace o poslední místo a zamítnutí přesunu hotovosti do cizí jednotky. |
| MCP `forms`, `forms-settings-postgres`, `forms-completion-postgres`, `seat-orders-postgres`, `orders-postgres` | 52/52, bez skipů, nad skutečnou disposable DB. Včetně cash administrativní objednávky a cash náhrady sedadel. |
| Edge platební/objednávkové helpery | 39/39; potvrzení CZK/EUR bez reference, pokyny a escaping, none se zálohou, identita commandu a invoice guardy. |
| Edge skutečné náhledy a deposit prezentace | 38/38. `deno check` prošel pro send-custom-email a všechny tři dotčené order e-mailové šablony. |
| JS veřejné formuláře a přehled | 51 cílených testů, po opravě očekávaného capability transportu všechny prošly; dotčený přehled samostatně 32/32. Cash výběr/potvrzení/přehled, bankovní QR/reference a okamžité vykreslení. |
| Core + Flutter | Core 17/17; Flutter výběry 14 + 27 + 8 testů prošly. Skutečný formulářový editor zachová cash/none v odesílaném Core snapshotu; dialog přijme desetinnou částku a uchová částku, datum i poznámku po návratu z nastavení. Flutter běžel vždy jediný, s `--concurrency=1`. |
| Statické kontrakty | Cílený Dart analyzátor bez chyb a varování (ponechané informační stylové diagnostiky), `docs:check`, `git diff --check` a parita cash migrace prošly. Manifest obsahuje všechny změněné SQL funkční ownery; změna schema registru a FK je v hlavičce dopředné migrace. |
| Browser s reálným lokálním Auth/REST/Edge | Cash objednávka 154: 150 CZK, ordered, žádná banka/reference/QR/deadline; skutečný autorizovaný příjem 50 CZK a obnovený přehled se zůstatkem 100 CZK/historií. Bank objednávka 155: 150 CZK, skutečný QR/účet/reference, žádný termín ani zálohový termín. Izolovaná muted Terra session; všechny její služby uklizené. |

Dodatečný cílený důkaz zákaznického přehledu: `DATABASE_URL=<disposable-local-db> node web_client/scripts/run_db_tests.js database/tests/eshop_orders/customer_order_overview_test.sql`, výsledek 1 passed / 0 failed. Po této kontrole se měnil pouze tento záznam výsledku; implementační zdroje a digest migrace zůstaly stejné.

Přesné příkazy, digest a omezení browser důkazu: [uložený receipt](../development/cash-reservations-browser-2026-11-06.json). Browser průchod ověřil migraci s SHA256 `27db5afcc72af8c5db222ba5d3980e46f0467c121c93970876ade07d26e9557a`. Následný regresní důkaz odhalil nabídku banky při NULL podporovaných měnách; owner dostupnosti nyní považuje NULL za prázdnou množinu. Aktuální sestavená migrace `20261106220000_cash_reservations.sql` má SHA256 `7913e779c50fe3285665e0450768305859b03b3a76a09ab51d8aa9f78f9b3519`. Je připravená, nikoli aplikovaná do produkce. Testovací databáze dostaly finální kanonické ownery; finální již jednou instalovaná migrační hlavička se na nich nespouštěla znovu jako celek.

Opravy testovacích vstupů zachovaly finanční a autorizační assertions: explicitní cash úhrada má skutečnou objednávku; dostupnost banky má skutečně nakonfigurovaný účet; pozitivní přesun ručního pohybu používá dvě objednávky ve stejné jednotce/organizaci a samostatný negativní případ prokazuje zákaz cizí jednotky. Worker send fence se ověřuje jeho skutečnou service rolí nad reálně zařazenou upomínkou, bez odeslání. Žádný z požadovaných výsledků nebyl dosažen skipem či oslabením ochrany.

Produkční SQL, skutečné platby, externí odesílání, commit, push ani nasazení tato implementační relace neprováděla. Případná produkční aktivace nadále vyžaduje samostatné vydání a jeho platné repository gates.
