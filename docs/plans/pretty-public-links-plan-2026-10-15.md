# Čitelné odkazy na události a formuláře s trvalou historií

Datum: 2026-10-15  
Stav: Implementováno a cíleně ověřeno lokálně; produkční inventura a nasazení nejsou provedeny  
Verification: standard - mění se veřejný URL kontrakt, autorizace zápisů a databáze

## Výsledek pro uživatele

Správce může změnit adresní název události i formuláře, vidí výslednou veřejnou URL a může ji zkopírovat. Automaticky generované adresy nových a duplikovaných položek mají krátký náhodný kód o 8 znacích, například `k7m4p9rx`, místo připojování `-copy-<hash>` ke starému odkazu nebo dlouhého UUID. Správce si může ručně zvolit popisný slug, například `ples-vetrkovice-2027`. Kopírování odkazu vždy používá poslední uloženou adresu.

Přejmenování `a -> b -> c` zachová všechny vydané adresy. Otevření `a` i `b` zobrazí tutéž položku a přepíše adresu v prohlížeči rovnou na `c`. Starou adresu nesmí převzít jiná položka. Změna URL nepřepisuje objednávky, odpovědi ani identity objektů.

## Rozsah a výklad zadání

- Rozlišovat duplikaci události/formuláře a kopírování URL do schránky; řešit obojí.
- Zachovat nynější strukturu cest: formulář `/form/<slug>`, událost podle existujícího veřejného routeru (např. `/<slug>/event`). Zkracuje se a zpřehledňuje slug; nezavádí se další zkracovač ani nová doména. Anglické `copy` a technické hashe z automaticky vytvářených slugů zmizí. Případné odstranění `/form/` a `/event` je samostatná změna routovacího kontraktu.
- Existující adresy plošně automaticky nepřejmenovávat. Správce si může vybrané nevzhledné adresy změnit; nové kopie už používají nový generátor.
- Událost a její formuláře mají samostatnou identitu a samostatnou historii. Přejmenování události samo nepřejmenuje již existující formuláře. Nový výchozí formulář dostane vlastní krátký náhodný kód, pokud správce výslovně nezadá jinou adresu.
- Předpoklad interpretace přepisu zadání: starý slug zůstává rezervovaný pro původní položku, jiná položka jej nesmí získat. To chrání již rozeslané odkazy před záměnou cíle.
- Název nové kopie akce dostane lokalizovanou závorku podle aktuálního jazyka uživatele při kopírování: `Ples (kopie)` v češtině, `Ples (copy)` v angličtině. Jazyk ani název neovlivňují automatický kód URL.
- Původní příprava zahrnovala pouze plán a realizační prompt. Následné zadání autorizovalo lokální implementaci a testy, nikoli produkční migraci, commit, push nebo deployment. Pracovní strom již obsahuje rozsáhlé rozpracované změny na `feat/occasion-setup-wizard-20261007`; implementace je musí respektovat.

## Ověřený současný stav

| Fakt a místo | Důsledek |
|---|---|
| `database/functions/others/duplicate_occasion.sql`, `duplicate_occasion_internal_v1`: událost má `link || '-copy-' || substring(md5(random()::text)...)`; zkopírované formuláře mají UUID bez pomlček. | Hlavní zdroj nevzhledných adres je serverová duplikace. |
| `database/functions/eshop_forms/duplicate_form_to_occasion.sql`: návrh z odkazu cílové události, při kolizi náhodný hash. | Opravit i samostatné kopírování formuláře. |
| `lib/components/forms/views/form_settings_content.dart`: pole odkazu, náhled a navigace po přejmenování již existují. `form_public_link.dart` sestavuje `/form/<link>`. | Rozšířit existující nastavení, nevytvářet paralelní editor. Dnešní náhled může vycházet z neuloženého textu. |
| `lib/components/occasion_settings/occasion_settings_tab.dart` a `occasion_advanced_settings.dart`: odkaz události lze editovat. | Doplnit stejná pravidla a zřetelnou uloženou URL i pro událost. |
| `get_form_by_link.sql` a `get_occasion_by_link.sql` vyhledávají aktuální `link`; `get_app_config.sql` také vyhodnocuje přímo `forms.link` a `occasions.link`. | Samotné přesměrování v UI nestačí, starý slug musí vyřešit server před načtením kontextu a oprávnění. |
| `update_form_internal_v1` kontroluje kolize přes organizaci; veřejné `get_form_by_link` vyhledává bez organizace. `update_occasion.sql` má další vlastní generování výchozího formuláře. | Nekonzistentní rozsah unikátnosti je nutné vyřešit před backfillem, nikoliv přidat další lokální kontrolu. |
| `lib/components/occasion/occasion_commands.dart` používá klientské sync commandy; `db_occasions.dart` může číst `get_occasion_for_edit_v1`. Formuláře mají vlastní `form_commands.dart`. | Nestačí změnit staré RPC fasády; zahrnout skutečné sync write/read cesty. |
| `duplicate_occasion.sql` ukládá natvrdo `title || ' (Copy)'`; `duplicate_occasion_client_sync_v1.sql` sestavuje stejný anglický suffix znovu pro `safe_label`. | Lokalizovat uložený název v jedné transakci a auditní popisek odvodit z výsledku. |
| `lib/components/occasion/occasion_creation_helper.dart` má odlišný HTML href a zobrazovaný text obsahující `/#/`. | Sjednotit také generované a kopírované HTML odkazy. |
| JS `form_page.js` pracuje s preview, waitlist a order capability fragmenty. `web_client/public/_redirects` posílá `/form/*` do JS a zbytek převážně do Flutteru. | Canonicalizace musí fungovat v obou klientech, zachovat query i fragment a nesmí obnovovat či ztrácet osobní tokeny. |

Fakta vycházejí z aktuálního lokálního stromu, nikoli z ověřené produkční databáze. Testy se pro psaní plánu nespouštěly.

## Rychlý průběh implementace a rozdělení práce

Cíl je jeden souvislý implementační průchod a jedna společná cílená validační dávka. Vlny níže popisují závislosti a kritéria dokončení, nikoliv povinné zastávky, samostatné review nebo opakované spouštění testů.

1. Hlavní implementátor jednou uzavře inventuru writerů/readerů a s UI implementátorem potvrdí krátký kontrakt: automatické vytvoření bez explicitního slugu, návrat uloženého `link`, kolizní chyba a parametr jazyka duplikace. Neopakovat již doloženou architektonickou rešerši. Produkční preflight neblokuje napsání a lokální ověření implementace; blokuje až aplikaci migrace při skutečné kolizi.
2. **UI promyslí a implementuje GPT Astra Medium (`gpt-6-astra`, `reasoning_effort: medium`).** Po potvrzení kontraktu běží souběžně s SQL prací hlavního implementátora. Tímto zadáním je tato konkrétní delegace autorizovaná. Jediný UI pracovník vlastní nastavení, tvorbu a locale předání; žádné další agenty nebo nezávislé review smyčky.
3. Hlavní implementátor vlastní SQL, migraci, command adaptéry a canonicalizaci JS/Flutter. Před paralelními editacemi domluvit vlastnictví sdílených souborů: UI pracovník předá požadované podpisy commandů a hlavní implementátor je zapracuje; oba nikdy současně neupravují stejný soubor. UI nezačne znovu zkoumat backend.
4. Po spojení změn spustit dotčené SQL, JS a Flutter kontroly jako jednu dávku, nezávislé sady souběžně. Použít již připravenou izolovanou lokální DB, pokud je aktuální; celý bootstrap jen při potřebě aktualizace schématu. Po selhání opravit konkrétní příčinu a opakovat jen dotčenou sadu. Úplné repository gates patří až k případné publikaci, pokud je vyžadují pravidla.

Záměrně nepřidávat nový editor, správu historie v UI, tlačítko náhodného přegenerování, dostupnostní RPC při každém psaní, rezervaci draftů, nový routovací systém, nový překladový build pipeline, plošnou změnu tenantů ani HTTP redirect službu. Použít stávající nastavení, `CopyButton`, action bar, překlady a existující návratové modely. Rozsah serveru je větší než UI: historické rezervace musí pokrýt všechny skutečné write cesty, jinak by zrychlení porušilo zadání.

## Cílový kontrakt a vlastnictví

### Jediný vlastník adres v SQL

Přidat kanonické SQL zdroje do `database/functions/public_links/` a novou timestampovanou migraci. Doménové ukládací příkazy používají stejné interní alokační/rezervační funkce; nevzniká nezávislá rename RPC obcházející verze agregátu a sync receipts.

Dvě explicitně typované tabulky, například `public.occasion_link_reservations` a `public.form_link_reservations`, drží každý aktuální i historický slug a FK na stabilní ID cíle. Unikátnost slugu je v každé tabulce globální, protože současné veřejné čtecí RPC nedostávají organizaci. Slug formuláře a události se může shodovat: mají různé routovací jmenné prostory. Mezi dvěma organizacemi se tentýž slug stejného druhu nově nepřiděluje. Chyba kolize neprozrazuje název, vlastníka ani tenant cizí položky.

`forms.link` a `occasions.link` zůstávají současným kanonickým slugem pro modely, katalogy, emaily a kompatibilitu klientů. Rezervační tabulky vlastní přidělení a historii. Každý zápis obou reprezentací je atomický ve stejném doménovém příkazu. Žádné persistentní aplikační triggery. RLS a práva nesmí dovolovat neprivilegovaný přímý INSERT/UPDATE/DELETE rezervací nebo obcházení změnou `link` přímo v tabulce.

Při odstranění cíle rezervace nezmizí: FK se může změnit na NULL a řádek zůstává tombstonem. Starý odkaz vrátí běžné nenalezeno, nikdy jiný obsah. Rezervaci nelze z uživatelského UI uvolnit. Nepřesouvat registraci adres na cascade delete organizace.

Interní resolver vrací stabilní ID; veřejný čtecí kontrakt vrací pouze již dovolený obsah s aktuálním `link`, bez nové obálky či dodatečného resolve RPC: klient porovná požadovaný slug s vráceným `link`. Nová metadata přidat pouze pokud konkrétní existující bundle aktuální `link` neobsahuje. Resolving samo nesmí rozšířit oprávnění, odemknout preview, zviditelnit demo nebo obcházet dostupnost formuláře. Interní SECURITY DEFINER funkce mají `search_path = public, extensions`, explicitní oprávnění, REVOKE přímého volání a žádné dynamické SQL z URL.

### Invarianty změny a generování

1. Alias odkazuje na ID, nikdy na jiný alias. `a -> b -> c` se řeší jedním dohledáním cíle a jeho současného slugu.
2. Nový aktuální slug zůstává rezervovaný a všechny předchozí rezervace zůstávají témuž ID. Návrat vlastní položky na její dřívější slug je dovolený. Stejný uložený slug znamená no-op.
3. Oprávnění, rezervace, změna `link`, verze agregátu a sync publikace tvoří stávající transakční command. Chyba uložení vrátí vše zpět. Replay stejného command ID nevygeneruje nový kód ani rezervaci a nezmění lokalizovaný název.
4. Zámek cílového řádku a UNIQUE constraint brání souběžnému zabrání adresy. Pro generátor použít jednotné transakční zamykání kandidáta a opakování po kolizi; žádné samotné `SELECT NOT EXISTS` jako záruka. Dodržet shodné pořadí zámků ve všech doménových příkazech.
5. Automatické kódy mají přesně 8 znaků z lowercase ASCII písmen a číslic, bez snadno zaměnitelných `0`, `1`, `o`, `i`, `l`. Generuje je server pomocí kryptografického zdroje náhody; nejsou odvozené z názvu, původního slugu ani ID. Jde o veřejný identifikátor, nikoliv přístupový token. Při kolizi s aktuální či historickou rezervací vygenerovat jiný stejně dlouhý kód; po 20 kolizích atomicky selhat, nikdy neprodlužovat URL suffixem nebo hashem. Generátor testovat s řízeným zdrojem kandidátů bez veřejně dostupného testovacího bypassu.
6. Ručně zadané slugy zůstávají povolené: lowercase ASCII písmena, číslice a jednotlivé pomlčky bez okrajových pomlček, limit 80 znaků. Server ověřuje platnost a kolize. Explicitní kolidující adresu potichu neměnit; správce ji musí opravit. U nové položky prázdný/nepředaný slug znamená automatické přidělení na serveru; UI ukáže, že krátká adresa vznikne po uložení. To platí i pro nové form create/update commandy, jejichž dnešní validace vyžaduje neprázdný link. U existující položky nepředaný slug zachová aktuální adresu a výslovně prázdný slug je chyba, nikoliv požadavek na náhodné přejmenování. Nerozlišovat automatickou a ruční volbu podle tvaru textu. Stávající create příkazy vrátí uložený `link` ve stávajícím modelu, aby UI nemuselo vymýšlet adresu nebo zavádět rezervaci draftu. Automatická změna názvu nepřepisuje ručně zadaný slug.
7. Neměnit uložené legacy adresy normalizací při čtení nebo backfillu. Nová pravidla platí pro nové a skutečně měněné slugy; běžné uložení jiného nastavení musí fungovat i se starým slugem. Přesný legacy match řešit před normalizací vstupu.
8. Pro události blokovat rezervované kořenové cesty podle `AppRouter.getRootLinks()` a skutečných hosting/static rout. SQL seznam odvodit z aktuálních rout při implementaci a přidat levnou kontrolu shody s existujícím routovacím kontraktem; kvůli tomuto seznamu nepřestavovat router ani generátory celé aplikace. Již uložená legacy adresa nesmí zablokovat save jiných nastavení.

### Přesměrování a kopírování

Rezervační tabulky mají UNIQUE/B-tree index na slug; resolver dělá bodový lookup a join podle PK, žádné procházení historie. Resolver integrovat do existujícího načítacího RPC, bez dalšího síťového roundtripu a bez druhého generování form bundle/session.

První implementace používá canonicalizaci URL v aplikaci: JS `history.replaceState`, Flutter odpovídající replace routy po úspěšném načtení cíle. Není to HTTP 301/308. Hosting dnes nezná dynamickou historii databáze; skutečné HTTP přesměrování by vyžadovalo další serverovou hranu a není podmínkou tohoto zadání.

Přepisovat jen příslušný slug, zachovat cestu podstránky, query a původní fragment včetně order/waitlist capability. Při interní správě zachovat zvolenou záložku; nevyvolat smyčku, druhé načtení session formuláře, další položku historie ani reset rozepsaného formuláře. Není dovoleno přesměrování na libovolný host z uživatelského vstupu. Osobní tokeny se nesmí dostat do logů, analytiky ani obecného tlačítka pro kopírování veřejné URL.

Formulář i událost zobrazí odděleně editovatelný slug, náhled a tlačítko pro kopírování uloženého veřejného odkazu. Při neuložené změně kopírovat poslední uloženou URL označenou jako současná; neuložený návrh zůstává pouze náhledem. U nové neuložené položky kopírování není dostupné. U formuláře i události uložený slug držet v samostatném baseline aktualizovaném načtením nebo úspěšným save, nikoliv v mutovaném draft modelu: dnešní `_save` formuláře mění `_form.link` ještě před odpovědí serveru. Zamítnutý save, Discard a změna route musí ponechat nebo obnovit správný baseline. `DbForms.updateForm` dnes vrací void a nepromítá uložený model; `DbOccasions.updateOccasion` přebírá ze sync odpovědi ID/verzi/features, ale ne `link`. Hlavní implementátor upraví tyto adaptéry tak, aby UI vždy obdrželo serverem potvrzený `link` bez dalšího načítání jen kvůli adrese. Po úspěšném save okamžitě použít serverem vrácený kanonický link. Text u pole: původní adresy budou dále fungovat. Zachovat stávající dialogy, action bar a lokalizace.

## Implementační vlny

### 1. Inventura a atomická rezervace adres

**Změny:** Přidat rezervační tabulky, interní resolver a alokátor. Před nasazením read-only inventura aktuálních duplicit v rámci druhu, prázdných adres, konfliktů kořenových cest a současných UNIQUE/RLS/grantů v baseline plus následných migracích. Produkční audit až přes schválený backend-access postup a ověření tenant identity. Lokálně zachytit všechny reálné INSERT/UPDATE `link` cest ve `database/functions`, sync SQL v migracích a případné přímé klientské zápisy. Funkce žijící pouze ve staré migraci při změně vytáhnout do kanonického zdroje, historickou migraci nepřepisovat.

**Migrace:** V jednom koordinovaném DB kroku zablokovat souběžné zápisy do dotčených tabulek, zopakovat preflight, backfillovat přesné současné adresy a přepnout všechny write cesty na rezervace. Zahrnout `create_form`, `update_form_internal_v1`, `update_occasion`, `save_occasion_domain_command_internal_v1`, create/save/duplicate sync příkazy, skutečné finální vytvoření z occasion setup draftu, `duplicate_form_to_occasion`, `duplicate_occasion_internal_v1`, tvorbu výchozího formuláře a delete příkazy. Formální kontrola SQL grantů zabrání bypassu. Při změně tenantu cíle se rezervace nesmí převést na jiné ID.

**Existující kolize (upřesnění vlastníka níže):** Mezitenantové duplicity zachovat beze změny jako zmrazené tenant vazby. Globální rezervace je blokuje pro nové vlastníky. Kolize uvnitř tenantu nebo formulářového namespace zůstává stop podmínkou; žádné automatické přejmenování ani slučování. Resolver bez tenant kontextu nesmí vybrat náhodný cíl.

**Validace a exit:** SQL test rezervací, rollbacku, tombstonů, neoprávněného zápisu, dvou tenantů, návratu na vlastní alias a souběžné kolize. Prázdné legacy adresy nezískají tichým backfillem novou URL: zaznamenat jejich ID, při dalším explicitním vytvoření/úpravě použít nový kontrakt. Všechny současné neprázdné adresy mají rezervaci stejného ID; žádný produkční writer rezervace neobchází. Bootstrap lokální DB musí zahrnout nový kanonický zdroj a migraci bez dvojí implementace. `database/functions/occasion_setup/drafts.sql: build_occasion_setup_configuration` vytváří provizorní konfiguraci uvnitř rollback bloku: i případné rezervace musí beze zbytku rollbacknout, žádná draft adresa nesmí uniknout jako veřejná URL.

### 2. Krátké náhodné adresy a lokalizovaný název kopie

**Změny URL:** V SQL nahradit tři zdroje dlouhých/hashovaných slugů z tabulky důkazů a vlastní generování default formuláře stejným alokátorem 8znakových kódů. Více formulářů v jedné kopii dostane samostatné kódy. Duplikace nekopíruje historii ani slug originálu. Kopie kopie má zase nový samostatný 8znakový kód bez připojovaných suffixů. Výslovně ručně zadané adresy zůstávají zachované.

**Změny názvu:** Aktuální jazyk získat z existujícího locale kontextu při zahájení duplikace (Flutter již používá `context.locale`). Přenést jazyk přes `DbOccasions.duplicateOccasion`, `OccasionCommands.duplicate`, demo duplikaci, setup wizard a SQL fasády do kanonického duplikačního commandu; všechny skutečné vstupy mají stejný výsledek. SQL ve stejné transakci uloží výsledný název s lokalizovaným suffixem; žádný druhý update po vytvoření. Přidat locale do idempotency payload hashe. Jsou tři vstupy: legacy `unit/views/occasions_screen.dart`, demo `occasion/demo/demo_occasion_banner.dart` a wizard přes `OccasionCreationHelper.createNewOccasion(source:)` při zapnutém `occasionSetupEnabled`. Jazyk zachytit jednou při zahájení copy intentu, uložit do wizard draftu a předat do jeho skutečného finálního commandu; demo retry používá původní `_command` i původní locale. Obnovení draftu ani retry po přepnutí jazyka nesmí změnit payload existujícího command ID. U wizardu doplnit suffix jen automaticky předvyplněnému názvu kopie; pokud uživatel název ručně přepíše, finální uložení respektuje jeho text a suffix znovu nevnucuje. Pro staré signatury zachovat jednoznačný dokumentovaný default `en` a delegování do stejné implementace; u existujících replay receipts zachovat původní hash kontrakt pro legacy volání. Přidání nové signatury nesmí způsobit nejednoznačné PostgREST overloady, staré granty nesmí zůstat na opuštěné implementaci.

Lokalizované suffixy přidat pro všechny podporované jazyky podle existujícího překladového systému; povinné přesné hodnoty jsou `cs: kopie` a `en: copy`, vždy malými písmeny uvnitř závorek. Pro neznámý jazyk použít `en`. Uložený název se po přepnutí jazyka již nemění. Z konce názvu zdroje odstranit opakovaný známý suffix kopie z podporovaných překladů a legacy `(Copy)`, pak přidat právě jeden podle aktuálního jazyka. Nesahat na text uvnitř názvu. Délku základu zkrátit před připojením suffixu podle skutečného limitu názvu tak, aby se závorka neztratila. `client_commit_items.safe_label` odvodit z uloženého výsledného názvu, nepřipojovat znovu vlastní anglické `(Copy)`. Suffix uloženého názvu vlastní jediný malý SQL překladový helper podle locale; klient posílá pouze jazyk a suffix znovu nesestavuje. Předvyplnění názvu copy draftu musí použít tentýž helper v existujícím draft create/save toku; nezavádět další síťové volání pouze kvůli suffixu. Explicitní příznak ruční změny názvu zabrání opětovnému přidání suffixu při finálním uložení. UI texty používají existující překladové soubory. Nevytvářet nový synchronizační/generační systém překladů.

**Migrace/odstranění:** Odstranit nahrazené lokální generátory veřejných slugů a oba hardcoded `(Copy)` výrazy; ponechat UUID technických klíčů a session. Stávající adresy ani názvy se nemění. Přizpůsobit návrhy v `occasion_creation_helper.dart`, `occasion/setup/`, `form_creation_helper.dart`; návrh nepřepisuje již ručně upravenou hodnotu.

**Validace a exit:** Rozšířit SQL testy duplikace a `database/tests/occasion_save_form_link_collision_test.sql` o délku/abecedu kódu, historicky obsazeného kandidáta, více formulářů, vyčerpání retry limitu a replay commandu. Ověřit český a anglický název v uložené akci i auditním popisku, přepnutí jazyka, kopii kopie, demo cestu a legacy fasádu. Flutter test ověří předání aktuálního locale do commandu. Nová kopie má samostatný 8znakový kód a lokalizovaný název s jediným suffixem; bankovní/media/sync chování zůstává správné.

### 3. Čtení starých adres a canonicalizace v obou klientech

**Změny:** `get_form_by_link`, `get_occasion_by_link`, `get_app_config`, `get_occasion_for_edit_v1`, `get_form_for_edit` a oprávnění přes form link řeší starý slug přes stejný resolver. Ostatní link-based RPC dohledat cíleně v `database/functions` a sync definicích: inventář, email templates, reporty, seznamy formulářů. Předávat kanonický slug dál nebo resolvovat na společné hranici, nikdy směšovat starý link a nový kontext. Stabilní ID zůstává vlastníkem autorizační kontroly. U link-only admin rout (např. `form_tab.dart` porovnává slug proti seznamu formulářů) nejprve převést vstup na kanonický slug ve stávajícím načítání, teprve potom vyhodnotit členství; platný starý admin odkaz nesmí být zamítnut jako neexistující.

Ve `web_client/src/components/forms/form_page.js`, `services/router_service.js`, Flutter `form_page.dart`, `router_service.dart` a occasion startup načítání zapojit replace pouze po úspěšném resolve. Form waitlist/order větve mohou načítat bundle jinou cestou: kanonický link získat z autorizovaného bundle, nevyžadovat jinak zakázané veřejné načtení. Aktualizovat aktuální identitu editoru, cache a sync katalogy stávající invalidací; nezavádět další alias cache ani offline databázi. Dříve neznámý alias vyžaduje online resolve; offline nelze slíbit poznání pozdějšího přejmenování.

**Kompatibilita:** Zachovat staré veřejné cesty včetně existující hash-route normalizace. Email, QR, osobní odkazy a záložky vydané před změnou fungují i po více renamech. Změna slugu sama nepřepisuje `FORCE_OCCASION_LINK`, tenant config ani externí integrace; před nasazením ověřit, že tyto vstupy projdou alias resolverem. Odkazy historicky ztracené před zavedením registru nelze rekonstruovat bez dalšího důkazu.

**Validace a exit:** JS testy alias -> canonical s query/hash a bez reloadu; Flutter cílené route/startup testy včetně admin záložky. SQL ověří stejnou identitu/oprávnění pro současný i starý link a zákaz čtení přes cizí tenant/demo. `a` i `b` končí přímo na `c`, bez řetězu a bez druhého vytvoření session.

### 4. Nastavení, kopírování a závěrečný úklid

**Změny:** Upravit existující settings a `FormPublicLink`; doplnit uloženou URL a kopírování události. Cíleně projít generátory veřejných odkazů v Dart/JS, `web_client/src/components/occasion/occasion_link.js`, kartách událostí a generovaném HTML. V každé platformě používat společný URL helper a kanonický `link`, query/capability přidávat jen při úmyslném vytvoření osobního odkazu. Zachovat externí registrační odkazy a běžná pravidla výběru událost vs. formulář.

**Odstranění:** Smazat nahrazené dlouhé generátory veřejných slugů, duplicitní neatomické kolizní kontroly a rozdíl href/text u nově generovaného HTML. Existující veřejné routy a rezervační aliasy jsou záměrná trvalá kompatibilita, nemažou se. Technické UUID, sync verze a nesouvisející rozpracované změny nejsou součást úklidu.

**UI zadání pro GPT Astra Medium:** Vlastní `form_settings_content.dart`, `form_public_link.dart`, `occasion_settings_tab.dart`, `occasion_advanced_settings.dart`, prezentační části create helperů, `occasion/setup/{occasion_setup_page,occasion_setup_draft,occasion_form_draft}.dart`, předání zachyceného locale na copy vstupu a potřebné existující strings/translations. Zachovat stávající rozložení a advanced sekci. Náhled neuloženého odkazu je prostý text, nikoliv aktivní CopyButton nebo slib dostupnosti. Odstranit automatické odvozování adresy z názvu a lokální ověřování unikátnosti; kolize rozhoduje SQL při save. `Utilities.isValidUrl` dnes připouští uppercase/underscore bez nového limitu, proto na měněné slugy použít úzký dohodnutý validátor bez globální změny Utilities. Nepouštět unconditional sanitizaci přes `onSaved` na nezměněnou legacy adresu. Opravit i wizard URL náhledy obsahující `/#/`. UI worker nedělá SQL, architekturu resolveru ani router; změny command adaptérů koordinuje s hlavním implementátorem.

**Validace a exit:** Cílený widget test kopíruje uloženou URL před save a novou po save; zamítnutý save ponechá původní URL. Cílené JS testy karet a URL helperů. Aktualizovat forms/occasion README a architektonický popis vlastnictví adres. Žádný známý generátor veřejné URL nekopíruje zastaralý slug či neuložený návrh jako platnou adresu.

## Ověření při implementaci

- Použít izolovanou lokální DB podle `CONTRIBUTING.md`, nikdy produkční DB jako testovací backend. Nové SQL testy přidat např. do `database/tests/public_links/`; zahrnout skutečné command fasády, nejen interní helper.
- Spouštět cíleně `DATABASE_URL=<lokální DB> node web_client/scripts/run_db_tests.js <konkrétní test.sql>`, JS `cd web_client && node --test <dotčené testy>` a `fvm flutter test <dotčené suites>`. Pro souběh použít dvě skutečné DB sessions mimo jednoduchý rollback test a vlastní izolovaná data.
- Zahrnout `web_client/tests/services/form_link_path.test.js`, `tests/core/router_service.test.js`, `tests/components/occasion_card_links.test.js` a Flutter `test/startup/app_router_deep_link_test.dart`, `test/router_reserved_paths_test.dart` podle skutečně změněného kontraktu. Přidat testy aliasů, nikoliv plošně přepisovat testy na nová očekávání bez kontroly chování.
- Před commit/publikací splnit repository gates z `CONTRIBUTING.md`; úplnou sadu spustit až pro konkrétní hotový balík, nikoliv při plánování nebo po každém editování. Browser smoke jen lokálně v izolované headless session podle repository pravidel, bez zásahu do uživatelova Chrome.

## Nasazení a rollback

Produkční operace nejsou autorizované tímto plánem. Při později schváleném nasazení vybrat jeden tenant; nevydávat další `prod/*` varianty. Sdílená DB změna musí být kompatibilní se stávajícími klienty ostatních tenantů. Pořadí: inventura a záloha, atomická DB migrace všech writerů a resolverů, ověření backfillu/grantů, klienti, smoke starého i nového odkazu. Nevydávat nové klienty před serverovou podporou historie. Web stavět lokálně a nasazovat přes `automation/deploy_direct.sh` podle aktuálních pravidel projektu.

Rollback UI je možný při ponechání serverového registru a resolveru. Nevracet staré writer funkce, které by nezaznamenaly změnu adresy. Po prvním přejmenování jsou rezervace trvalým uživatelským kontraktem; nemaže je rollback ani restore staršího klienta. Známé kopírování staré URL starším klientem zůstává funkční díky aliasu. Před produkční migrací explicitně zhodnotit lock timeout a délku backfillu podle inventury.

## Hotovo lokálně a zbývající provozní rizika

- [x] Ručně lze přejmenovat událost i formulář; UI kopíruje poslední uloženou URL.
- [x] Duplikace a automatické vytvoření používají samostatné náhodné 8znakové kódy; kolize nezpůsobí prodlužování adresy. Ručně zadané popisné adresy lze nadále použít.
- [x] Název kopie obsahuje právě jeden lokalizovaný suffix, česky `(kopie)`, anglicky `(copy)`, podle jazyka uživatele při vytvoření; auditní popisek odpovídá uloženému názvu.
- [x] Všechny od zavedení historie vydané adresy směřují na stejnou identitu a poslední kanonickou URL; jiný cíl je nemůže převzít ani po smazání.
- [x] Souběh, rollback transakce, replay, tenant hranice, oprávnění a query/fragmenty mají cílené důkazy.
- [x] Existující form bundle/session, příjem objednávek, preview a waitlist/order capability zůstávají funkční; generování URL a sync invalidace používají kanonický link.
- [x] Všechny nalezené write/read bypassy jsou převedené, nahrazené generátory odstraněné, dokumentace odpovídá výsledku.

Neověřené předpoklady: produkční globální kolize, přesné aktuální DB grants/indexy a úplný seznam writerů mimo dohledané doménové cesty musí uzavřít vlna 1. Nelze slíbit obnovu odkazů přejmenovaných před vznikem historie. Přesměrování v první verzi vyžaduje běh aplikace a připojení; HTTP status pro roboty tato změna neřeší.

## Implementační zjištění 2026-10-15

Průvodce v původním stromu neměl finální create/save command: v
`occasion_setup_page.dart` pouze ukládal dokončený koncept. Proto byl doplněn
`finalize_occasion_setup_draft` a samostatná finální UI akce se stabilním command
ID a revizí. Uložení konceptu zůstává možné. HTTP synchronizace externích
událostí byla dalším writerem `occasions.link` a používá stejnou rezervaci.
Produkční inventura, migrace ani deployment nejsou tímto provedeny.

## Výsledek lokálního ověření

- Podporovaný `automation/bootstrap_local_db.sh` prošel v izolované DB na `127.0.0.1:55432`; migrace je sestavená z kanonických SQL souborů označených přímo v ní. Novější změny funkcí byly aplikované a cíleně testované v téže lokální DB.
- Prošlo 13 cílených SQL sad: veřejné odkazy, kolize default formuláře, duplikace a její oprávnění, demo kopie, drafty, tenant hranice, čtení/smazání/editace formuláře, bankovní priorita, bezplatná objednávka a waitlist capabilities. Samostatný test dvou reálných DB sessions prokázal souběžnou kolizi a zákaz převzetí historické adresy.
- Prošlo 56 JS testů routeru, URL helperů, karet, načítání aliasu bez druhé session a order/waitlist větví bez veřejného načtení formuláře.
- Prošly cílené Flutter sady (45 testů základní dávky, následné rozšířené startup/navigation sady). Testy zahrnují uložený copy baseline, zamítnutý save, locale commandu a admin alias se zachováním záložky/query. Cílený analyzátor nemá chyby; existující lint informace a upozornění na mutable widgety zůstávají.
- Lokální inventura aktivních PostgreSQL funkcí nalezla i staré `update_occasion`, `update_occasion_182`, `duplicate_form`, `copy_form_with_fields` a skrytou HTTP sync implementaci. Podporované fasády delegují do commandů; opuštěné implementace jsou odstraněné. Starší čtecí fasády používají stejný resolver, veřejný starší form bundle deleguje do kanonického readeru.
- Upravené testovací fixtures výslovně rezervují své adresy. Starý tenant test již nevytváří neplatné duplicitní globální adresy: ověřuje historický alias, tenant kontrolu a konflikt cizí rezervace. Regresní fixtures mají skutečné editor role a produkty přiřazené ke správnému formuláři/události.

Před nasazením zbývá výslovně autorizovaná produkční inventura kolizí, prázdných a rezervovaných adres, kontrola práv/indexů, záloha a posouzení lock timeoutu/backfillu. Potom atomická migrace a vydání klientů pro jeden vybraný tenant, v tomto pořadí. Staré rezervace se při rollbacku nemažou. V této implementaci nebyl proveden produkční přístup, migrace, deployment, commit ani push.


### Upřesnění vlastníka 2026-10-15: stávající duplicity ponechat

Vlastník po produkční read-only inventuře výslovně požaduje zachovat všechny
stávající adresy včetně duplicit a připravit nový kontrakt pro budoucí tvorbu
a přejmenování. Tím nahrazuje původní stop podmínku pro mezitenantové duplicity.
Inventura našla 23 skupin duplicit akcí mezi tenanty, 0 uvnitř tenantu,
0 duplicit formulářů, 0 prázdných adres akcí a 2 prázdné adresy formulářů.

Migrace nic nepřejmenovává. Jedinečné adresy rezervuje přímo na stabilní ID.
U stávajících mezitenantových duplicit ponechá globálně blokovanou rezervaci
a zmrazené vazby `(slug, organization) -> occasion ID`. Veřejný app-config
předává svůj ověřovaný tenant; přihlášené editory resolver omezuje jejich
tenantem. Bez tenant kontextu nejednoznačná adresa nevybere náhodný cíl.
Vazby zůstanou historickými aliasy i po explicitním přejmenování a tombstony
po smazání. Noví vlastníci je nemohou získat. Nové zápisy žádné takové vazby
nevytvářejí a nadále vyžadují globálně jedinečnou rezervaci. Kolize uvnitř
jednoho tenantu nebo formulářového namespace zůstává stop podmínkou.
Prázdné legacy adresy zůstávají beze změny.

Ověření: kanonický backfill, zachování názvů/adres, veřejné tenant rozlišení,
historie po přejmenování, vlastní návrat, zákaz převzetí a smazání testuje
`automation/tests/public_link_backfill.test.mjs` v lokální rollback transakci.
Produkční inventura byla pouze čtení; migrace ani deployment tím nejsou provedeny.

### Integrační ověření po upřesnění vlastníka

Task-only změny jsou sloučené s `origin/main` na `100cae0e3` v odděleném
pracovním stromu `/private/tmp/festapp-pretty-public-links-20261015`. Novější
demo simulace, startup recovery, tenant kontroly a order-overview chování
zůstávají zachované; původní rozsáhlý rozpracovaný strom není nahrazen.

- Lokální baseline bootstrap prošel. Finální migrace je `20261015200000`,
  aby následovala novější již existující overview migrace. Její finální SQL
  bylo úspěšně aplikováno do izolované lokální DB; generátor je
  `automation/assemble_pretty_public_links.py`.
- Prošlo 13 cílených SQL sad, skutečný dvousession test kolize a nový test
  kanonického backfillu se zachováním existujících tenant duplicit a tombstonů.
- Prošlo 57 cílených JS testů a 103 Flutter testů. Cílený Dart analyzátor
  nemá chyby; ponechává existující lint informace a mutable-widget varování.
- Produkce byla pouze čtena. Žádná produkční migrace, deployment, commit
  ani push nejsou součástí tohoto výsledku.
