# Jednotná správa členství, oprávnění a pozvánek

Datum: 2026-11-10  
Stav: Celý cutover lokálně implementovaný a ověřený; 8 canonical CI lanes PASS; produkční rollout neprovedený  
Ověřování implementace: standard (autorizace, veřejné kontrakty, migrace)  
Výchozí HEAD: `742d614b722bbe619b3a095f66605bd4bb536006`

## Výsledek a hranice

Správce přidá nebo najde člověka, zvolí rozsah a oprávnění a výslovně rozhodne,
zda odeslat pozvánku. Dostane jeden dohledatelný výsledek: existující nebo nové
členství, účinná nebo nabídnutá oprávnění a skutečný stav komunikace. Stejně
funguje správa organizace, správa akce a průvodce založením akce. Opakování po
výpadku nezaloží duplicitní účet, členství, grant ani e-mail.

„Organizace“ v zákaznickém UI znamená v tomto toku `public.units` (např. AKH).
`public.organizations` je tenant, nikoli další nově podporovaný rozsah pozvánky.
Podporované rozsahy jsou tedy `unit` a `occasion`; tenant administrace se nemění.

Rozsah zahrnuje nové i existující účty, přidání existujícího člena, ruční role,
pozvání, opakované odeslání, přijetí, expiraci, odvolání, stavové projekce,
Client Sync, šablony a oba klientské adaptéry, které tyto operace skutečně používají.
Importy, registrace, reception a companion flows ponechají svou identitu a
produktovou politiku. Musí používat společné primitivy identity/členství tam,
kde je dnes sdílejí; nezískají automatické rozesílání ani širší práva.
Pozvánka běžnému uživateli Festapp s vygenerováním a odesláním hesla zůstává
plnohodnotnou podporovanou cestou, včetně oprávněného nastavení nového hesla již
existujícímu běžnému účtu. Není to legacy cesta určená ke zrušení. Její zachování
a ověření je součástí dokončení tohoto plánu. Samostatný reset hesla, objednávkové
a přihláškové e-maily ani obecná fronta se nepřestavují; jejich kontrakty se chrání.

Upřesnění zadání 2026-11-10: sjednocení znamená společné řízení a dohledatelnost,
nikoli nahrazení všech produktových typů pozvánek jedním přijímacím odkazem.

## Podklady a jejich meze

| Ověřený fakt | Podklad | Důsledek |
|---|---|---|
| Noví členové akce se ukládají bez automatické pozvánky. | `database/functions/users/create_occasion_user_client_sync_v1.sql`; `lib/components/users/profile_commands.dart` | Výsledek uložení musí explicitně uvést, zda komunikace vznikla. |
| Pozvat v seznamu akce je samostatná operace. | `lib/components/users/views/users_tab_helper.dart`; `AuthService` | Přidání a pozvání potřebují společný explicitní command intent. |
| Účastnické přihlášení a oznámení týmu dnes sdílejí endpoint. | `supabase/functions/send-sign-in-code/index.ts`, `teamAccessNotice.ts` | Nelze sjednocení provést resetem hesel všech pozvaných. |
| Přijímací týmová pozvánka je vázána na setup draft a existuje jen pro akci. | `database/functions/occasion_setup/invitations.sql`; `send-occasion-team-invitations/handler.ts` | Doménový životní cyklus pozvánky nesmí vlastnit průvodce. |
| Správa organizace má vlastní command a nemá akci Pozvat. | `lib/components/unit/unit_commands.dart`, `views/unit_users_screen.dart`; `database/functions/people/unit_user_command.sql` | Společný orchestrátor a projekce musí obsloužit i unit scope. |
| Některé chyby se redukují na obecné odmítnutí bez důvodu. | `unit_user_command.sql: save_unit_user_client_sync_v1`; `profile_commands.dart` | Zachovat bezpečné typované důvody přes SQL, Edge i UI. |
| Platnost odchozí pozvánky je kontrolována i workerem. | `database/functions/emails/email_queue.sql: email_intent_valid` | Přesun tabulky vyžaduje současnou změnu worker validátoru. |
| Editor odvozuje historické pozvání i z přihlašovacích e-mailů. | `database/functions/users/get_occasion_users_for_edit.sql`; `database/tests/users/invitation_delivery_status_test.sql` | Stav komunikace a stav přijetí musí mít různé autority. |

Produkční diagnostika z tohoto rozhovoru: canonical tenant `festapptickets`,
generace 1, organization 3; Adventní duchovní obnova `1072624`, unit `2`.
Dva sledovaní lidé mají dnešní úspěšná přidání do akce a týmová práva. V unit
jsou také členy, ale bez organizačních rolí. Pro ně nebyl nalezen žádný záznam
v `email_messages`, tedy ani požadavek na doručení. Ověřované Vojtěchovy účty
mají `can_manage_unit_users(2)=true`.

To dokládá chybějící komunikační krok, nikoli konkrétní příčinu hlášeného selhání
přidání v organizaci. To dosud není reprodukováno. Samotné vynechání pozvánky
není důkazem poruchy poskytovatele ani důkazem, že uživatel klikl na Pozvat.
Plán nesmí tvrdit, že příčinu organizačního selhání už zná.

Pracovní strom obsahuje rozsáhlé cizí změny včetně uživatelské autorizace,
e-mailů a migrací. Před implementací zaznamenat jejich vlastníka a aktuální diff;
nepřepisovat je, nestashovat ani nezahrnout do publikace bez vyřešení rozsahu.
Neaplikovat všechny pending migrace jako vedlejší efekt této práce.

## Rozhodnutí cílové architektury

### Podporované produktové záměry

| Záměr | Účinek | Co nesmí sjednocení změnit |
|---|---|---|
| Pozvat běžného uživatele do Festapp | Oprávněně vytvořit účet nebo nastavit vygenerované heslo běžnému účtu a atomicky zařadit přihlašovací údaje do fronty. | Zachovat skutečné heslo a stávající přihlášení; nenahradit povinným přijetím týmového grantu. |
| Pozvat správce/editora nebo oznámit jeho přístup | Nabídnout konkrétní role k přijetí nebo oznámit již platný přístup. | Oznámení ani nabídka rolí samy nemění heslo existujícího účtu. |
| Přihláška/registrace účastníka a její komunikace | Existující doménový vlastník rozhodne o potvrzení, stavu přihlášky a případné potřebě účtu. | Samotná přihláška neuděluje týmová práva ani automaticky neresetuje účet; pokud produkt výslovně požaduje přístup do aplikace, použije legitimní účastnický credential záměr. |

Volbu záměru musí autorizovat backend podle účelu a uloženého kontextu. Nestačí
příznak od klienta. Běžný účastnický credential záměr nesmí obcházet ochranu
správcovského účtu: zachovat současné rozhodování podle živých práv, nikoli
uživateli s týmovými právy dovolit reset přejmenováním typu pozvánky.
Samostatný oprávněný reset hesla má nadále vlastní pravidla.

### Vlastnictví

Jeden doménový modul `database/functions/people/` vlastní orchestraci přístupu:
normalizaci záměru, rozlišení již uděleného přístupu a nabídky přístupu,
autorizaci, idempotenci, membership/role mutation, pozvánku a enqueue komunikace.
Zachová specializované interní vlastníky identity, profilů a členství; nezkopíruje
jejich implementace do nové monolitické funkce. Znovu použije Client Sync receipt
protokol a `email_messages`. Nevznikne druhá fronta, druhý profil ani obecný nový
framework pro všechny příkazy aplikace.

Navržené veřejné kontrakty modulu: `manage_member_access`, `get_member_access_status`,
`resend_access_invitation`, `revoke_access_invitation`, `get_access_invitation`,
`accept_access_invitation`. Existující verzované Client Sync názvy jsou vnější
protokolové adaptéry, ne důvod vytvářet paralelní doménovou implementaci.
SQL interní entry points nejsou spustitelné klientskými rolemi.

Command přijímá stabilní `commandId`, typovaný scope, userId nebo kanonický
sign-in e-mail, explicitní změnu profilu/rolí, expectedVersion a komunikační
záměr `none | participant_credentials | notify_existing_access | invite_to_accept`. Server načte tenant,
unit a případnou akci ze skutečných uložených vazeb; klientský tenant ani role
nejsou autoritou. Kombinace, které nedávají smysl, vrací typed rejection.

Výsledek má oddělené části `membership`, `access`, `communication`, `mutation`.
Obsahuje userId/invitationId/messageId, verze a bezpečný `reasonCode`.
`already_member` je normální výsledek a nabídne úpravu existujícího členství.
UI nepřekládá každý konflikt na hlášku „změnil jiný správce“.

### Hranice, které sjednocení nesmí změnit

- `participant_credentials` je komunikační záměr se stávajícími auth pravidly,
  nikoli nový obecný permission grant. Zachovat dnes podporovaný occasion
  kontext a nepovolit generování hesel z unit obrazovky jen proto, že nový
  transport umí oba scope. Případné rozšíření vyžaduje samostatný produktový
  požadavek a autorizaci; tento plán je nezavádí.
- Při samotném Pozvat/odeslat znovu se nemění profil, členství ani role. Command
  musí mít explicitní operaci, např. `save_member`, `send_invitation`,
  `save_member_and_invite`; notification-only cesta nesmí přehrát starý snapshot
  rolí. ExpectedVersion a autorizace se váží na konkrétní mutaci, ne univerzálně
  na libovolnou změnu zobrazovaného profilu.
- Atomická doména + e-mail platí pro výslovné `save_member_and_invite` a pro
  současný credential transition + enqueue. Neznamená nový požadavek, že se
  existující přihláška, objednávka nebo platba musí vrátit zpět, pokud selže
  volitelná pozvánka. Jejich transakční hranice a recovery vlastní jejich
  současná doména. Pozvánka se připojí jako dohledatelný idempotentní záměr.
- Požadavek explicitní volby platí pro nové ruční akce. Již nakonfigurované
  automatické potvrzení přihlášky nebo rozesílání podle současné produktové
  politiky zůstává automatické; nesmí nově čekat na kliknutí správce.
- Nová projekce nesmí udělat z role účtu typ účtu natrvalo. Rozhodnutí o
  credential záměru používá existující auth policy a aktuální scope pravidla;
  ne plošnou novou podmínku „má jakoukoli roli kdekoli“. Změna této policy není
  vedlejší efekt sjednocení.

### Členství, práva a souhlas

- `participant_credentials` zachová dnes existující `send-sign-in-code` ->
  `reset_password_and_enqueue_email` a `SIGN_IN_CODE` chování pro běžného
  uživatele. Konkrétní credential transition vlastní stávající auth SQL owner;
  společná orchestrace jej volá, neimplementuje podruhé. Existující účet se
  při legitimním záměru může oprávněně přenastavit na vygenerované heslo.
  Nový účet lze vytvořit ještě před odesláním, bez přijímacího týmového tokenu.
  E-mailové označení „kód“ samo nemění heslo na jednorázový token: zachovat
  současnou životnost credentialu, formát a způsob přihlášení. Expirace zprávy
  není automaticky expirací hesla.
- Běžné přidání člena nadále může členství a výslovně zvolené role uložit ihned.
  Se souhlasem odesílatele vytvoří oznámení o již uděleném přístupu. Nevyžaduje
  falešné přijetí a nemění heslo existujícího účtu.
- `invite_to_accept` nabízí konkrétní práva. Do přijetí je neudělí a bez potřeby
  nevytváří účet. Existující účet se musí autentizovat jako pozvaná identita;
  nový účet vzniká při bezpečném přijetí podle současného account ownera.
- UI po přidání nabízí zřetelné Odeslat pozvánku. Odeslání vyžaduje explicitní
  volbu v dané operaci; obyčejné editace, importy a změny rolí nic skrytě neposílají.
  Pokud už přístup platí, UI vysvětlí, že odesílá oznámení o přístupu.
- Účast v akci neuděluje unit role. Unit role a role akce se vždy autorizují ve
  svém rozsahu. Pozvánka do akce nikdy nepřidá unit editor/manager práva.
- Role scope je typovaný snapshot existujících oprávnění, nikoli jen jeden
  společný enum editor/read_only: organizace a akce mají rozdílné role. Použít
  existující operation predicates a jejich pravidla pro přípustné granty.
- Přijetí přidává pouze dosud chybějící nabídnuté role; nesníží novější práva.
  Změna nabídnutého rozsahu/rolí po odeslání je revokace a nový záměr, nikoli
  přepsání starého tokenu. Aktuální oprávnění zvoucího se ověří při vytvoření,
  opakování, worker dispatch i přijetí. Odebrání příslušné pravomoci pozvánku zneplatní.

### Persistence a doručení

`user_info` a stávající account writer zůstanou jedinou autoritou identity,
`unit_users` a `occasion_users` autoritou členství a práv.
`public.access_invitations` bude přejmenovaná a rozšířená současná tabulka
`occasion_team_invitations`, nikoli další souběžná tabulka. Uloží nabídku přístupu,
rozsah, recipient identity, role snapshot, token hash, expiraci, revokaci,
přijetí a message vazby. `source_draft` bude volitelná auditní reference bez
kaskádového mazání pozvánky při smazání draftu. Unit je povinný a occasion je
volitelný s CHECK/FK zajišťujícími přesnou scope vazbu.

Oznámení o již uděleném přístupu nepotřebuje umělý záznam přijímací pozvánky.
Jeho komunikaci vlastní `email_messages` s vazbou na scope a recipient_user.
Stavová projekce skládá obě cesty; neduplikuje v nové tabulce stavy workeru.

Rozlišovat `not_requested`, `queued`, `provider_accepted`, `delivered`, `failed`,
`suppressed`, `cancelled`, `expired`; přijetí/revokace nabídky jsou samostatné
údaje. Absence delivery webhooku znamená neznámé doručení, nikoli selhání.
Provider acceptance není přijetí pozvánky ani potvrzení doručení do schránky.
`is_invited` a počty SIGN_IN_CODE zpráv nejsou autoritou přijetí týmových rolí.
Pro účastnický credential záměr jsou skutečné SIGN_IN_CODE send evidence nadále
platným podkladem stavu odeslání. Zachovat je i v účastnické projekci; starý
boolean lze odvodit pouze jako kompatibilní projekci bez vlastní zapisovací logiky.

Identita se hledá podle normalizovaného `user_info.email_readonly` v tenant scope
přes existujícího vlastníka. Použít `format_auth_email`, neskládat auth e-mail
řetězcem v nových cestách. Oznámení účtu doručovat přes `get_user_delivery_email`.
Nová nabídka práv jde na zvolenou kanonickou identitu; delivery override nesmí
sám přesměrovat důkaz vlastnictví identity. Zachovat pravidla sdílené schránky
s +N aliasy a explicitní volbu konkrétního účtu.

### Atomicita a retry

Při `none` se atomicky ukládá doména a receipt. Při požadované komunikaci se
membership/grant intent, pozvánka (je-li třeba), `email_messages` a receipt
commitnou v jediné SQL transakci. Pokud příprava šablony nebo enqueue selže,
nesmí UI oznámit úspěšné „přidat a pozvat“ s vynechaným e-mailem.
Po commitu může selhat doručení; členství zůstane a UI zobrazí queued/failed.

Edge orchestrace před transakcí autorizovaně načte serverový preview a připraví
stávajícím `prepareAccountEmail` zapečetěný snapshot. SQL znovu ověří scope,
recipient, role/version a vazbu připraveného obsahu. Trusted Edge snapshot musí
obsahovat serverem odvozený cíl a intent hash; SQL přijme pouze snapshot
připravený stejným oprávněným orchestrátorem, nikdy klientský content hash jako
důkaz jeho správnosti. Trusted snapshot ukládá service-only `stage_member_access_email` s ověřeným
actor ID, command ID, intent a preview hashem do krátkodobého privátního depositu.
Finální `manage_member_access` běží pod authenticated `auth.uid()` a spotřebuje
jen tento deposit. Klient nesmí dodat libovolný sealed obsah, recipient nebo role
jako důvěryhodné. Toto zpřesnění vychází z ověřené závislosti existujících
specializovaných writerů, abuse admission a receipt ownerů na auth.uid(): zachová
jejich jedinou implementaci i identitu aktéra bez servisního bypassu nebo druhé
kopie pravidel. Deposit není další fronta, delivery stav ani business autorita;
credential je v něm uložen pouze šifrovaně a po commitu se deposit odstraní. Zachovat queue admission
predicate a bezpečný actor audit, nikoli obcházet je obecným service_role grantem.
Při identitním souběhu SQL odmítne zastaralou přípravu bez dílčích zápisů.

Náhodný token vzniká pouze serverově, do DB jde hash, do zapečetěného e-mailu
URL. Nezapisovat tokeny do logů, receipts ani běžné projekce. Při opakování stejné
operace se nejprve načte receipt před novým tokenem/renderem. Worker obnovuje
již uložený snapshot. Dvojklik a ztracená odpověď používají stejné commandId a
messageId; odlišný doménový payload se stejným ID je konflikt. Request hash vychází z
normalizovaného záměru, nikoli z náhodného tokenu či ciphertextu přípravy; jinak
by transportní retry vytvářel falešný konflikt. Retry po selhání musí
nejprve dohledat nerozhodnutý původní dispatch. Nesmí slibovat exactly-once
externí doručení při neurčité odpovědi poskytovatele.

Explicitní resend po terminálním výsledku vytvoří nový komunikační záměr.
U přijímací pozvánky atomicky zneplatní předchozí token a nabídku nahradí novou;
platí jen nový token. Auditní vazba predecessor/successor zachová historii.
Odvolání zneplatní token a zruší dosud neodeslané zprávy; již přijatý providerem
e-mail nelze vzít zpět. Odkaz po odvolání nesmí udělit práva.

## Zpřesnění kontraktu po hlubší kontrole

Tento oddíl zpřesňuje předchozí návrh a platí i pro všechny implementační vlny.

### Auth kontext a příprava zprávy

`reset_password_and_enqueue_email` používá `auth.uid()` a hierarchickou
`get_can_reset_user_password`, zatímco stávající notice producer přijímá ověřeného
aktéra v service-only RPC. Jde o dva transportní kontexty, nikoli dvě kopie pravidel.
Nesmí se prostě přepnout credential volání na service_role: to by změnilo význam
`auth.uid()` a mohlo pravidla obejít či zablokovat. Zachovat authenticated
credential boundary; pokud atomický nový command potřebuje service-only vstup,
nejprve extrahovat stejný operation predicate do interní varianty s explicitním
ověřeným actor ID a thin auth.uid() wrapperem. Stejný predicate musí volat původní
i nový vstup. Nefalšovat JWT claims přes `set_config` jako náhradu autorizace.

Preview pro `save_member_and_invite` je výpočet očekávaného výsledku výslovně
zadané změny, nikoli jen snapshot starého členství. Server připraví obsah pro
novou zamýšlenou roli a recipienta; finální transakce ověří expectedVersion,
identity vazbu, recipienta, doménový intent hash a aktuální pravomoci. Při nesouladu
vrátí konflikt před změnou hesla/rolí/enqueue. Sealed obsah a plaintext credential
smí přicházet z ověřené serverové orchestrace, nikoli z běžného klienta.

Kontrola replay je autorizovaná read-only operace před renderem. Přesto je
poslední autoritou transakční receipt po zámku: dvě současné první žádosti mohou
obě připravit obsah, ale pouze první jej commitne, druhá převezme jeho messageId.
Náhodný ciphertext či necommitnutý token druhé žádosti se zahodí. Výsledek se
nikdy nevrací z nově připraveného obsahu, pokud transakce replayovala starý intent.

Pauza/kvóta může odmítnout už `prepareAccountEmail` přes admission gate. UI musí
odlišit „nic uloženo, zkuste znovu“ od „uloženo a čeká ve frontě“. Nový flow nesmí
obcházet preparation gate; není přípustné zobrazit queued bez committed messageId.
Dávky mají per-recipient command identity a omezenou souběžnost, ne jednu dlouhou
transakci s čekáním na provider. Nový klient po enqueue načítá stav, neblokuje
uložení osm sekund čekáním na acceptance; starý HTTP kontrakt sent/202 zůstane
v mechanickém kompatibilním adaptéru.

### Heslo není jednorázový kód

`database/functions/users/sign_in_codes.sql` a
`supabase/functions/exchange-sign-in-code/exchange.ts` implementují zvláštní
jednorázové kódy s expirací a consume. Současný credential producer v
`database/functions/emails/email_domain.sql` ukládá skutečnou password transition
a `password_version`. Jejich souběžná existence není důvodem jednu větev smazat
v tomto cutoveru. Nevyvozovat společný protokol ze stejného šestimístného formátu.
Ve vlně 1 určit konkrétní producent -> uložený důkaz -> login consumer pro obě
cesty. Test musí ukázat úspěšné přihlášení právě odeslaným credentialem a správnou
životnost; pouhý test exchange endpointu není důkazem funkčního hesla.
Zachovat test `test/data_services/sign_in_code_login_test.dart` a
`database/tests/security/sign_in_codes_test.sql`; změna zde jen při prokázané
závislosti, nikoli jako plánované slučování auth mechanismů.

### Odvolání, souběhy a konkrétní návratový kontrakt

Odebrání členství nebo výslovné snížení rolí musí atomicky zneplatnit outstanding
nabídky, které by právě odvolaná práva mohly znovu přidat. Jejich queued zprávy
se stanou neplatnými; zachová se historie. To musí platit i pro staré delete/save
adaptéry, ne pouze pro nové UI. Nové opětovné pozvání je nový explicitní záměr.
Přijetí a odvolání/snížení práv používají společné scope/identity zámky a opětovné
ověření po zámku. Výsledek souběhu se serializuje; pozdější odebrání zůstane
účinné. Odvolání už přijaté pozvánky samo neodebírá členství: takový krok je
samostatná autorizovaná membership mutation.

Před kodifikací lock pořadí projít `database/functions/people/scope.sql`,
`unit_user_command.sql`, identity allocation, acceptance a credential writer.
Sjednotit pořadí jen v dotčených shared primitivách a jejich skutečných callerech;
nepřidat org lock před scope lock jen v novém vstupu. Dva současné accepty,
create/accept, credential resend a revoke/accept musí mít integrační test na dvou
DB connections. Opakovaný single-connection test není důkazem souběžné bezpečnosti.

Rozlišit domain disposition (`applied`, `unchanged`, `conflict`, `rejected`)
a komunikační stav. Úspěšný replay neudělá druhý commit a vrátí původní immutable
receipt/reference; aktuální delivery se načte separátně podle messageId.
Bezpečné reasonCode zahrnou alespoň `already_member`, `invalid_email`,
`scope_denied`, `credential_operation_denied`, `version_conflict`,
`command_payload_conflict`, `preparation_deferred`, `invitation_expired`,
`invitation_revoked`, `wrong_identity` a `upgrade_required`. Veřejný lookup
neodhaluje adresář účtů; podrobnosti jsou jen v oprávněné editorové projekci.
Zachovat raw SQL chybu jen v chráněném diagnostickém logu s correlation ID,
nikoli v zákaznické odpovědi. Nezavádět univerzální obsluhu všech chyb aplikace.

### Migrační a provozní hranice

Přejmenování tabulky vyžaduje aktualizovat i SQL těla uložená jako text,
RLS/policies, grants, queue admission/validity, realtime či publication registry,
canonical source manifests, test fixtures a provozní skripty. Samotný seznam
pg_depend nestačí. Před DDL sestavit konkrétní inventář ze scoped `rg` i katalogu.
Backfill zachová historický editor/read_only význam, nikoli default nových rolí.
Scope CHECK musí odmítnout occasion s jiným unit/tenantem; neurčité vazby se
reportují jako migrační blocker, neopravují se odhadem.

Migrace už přijatých/odeslaných pozvánek neodesílá žádné nové zprávy, neuděluje
žádné nové role a nevytváří nové účty. Unit invity dostanou unit destination;
staré event URL zůstanou event URL. Template context musí podporovat chybějící
occasion bez předstírané akce. Nové fallbacky nesmějí ignorovat existující
customizované šablony; testovat global/unit/occasion inheritance a locale.

Samotné plánování neopravňuje měnit historické customer role ani odesílat
pozvánky sledovaným lidem. Při budoucím rolloutu ověřovat skutečnou queue health
read-only, doručování nejprve na disposable backendu se stubbed providerem.

## Vlny implementace

### 1. Reprodukce a zafixování veřejného kontraktu

Nejprve zafixovat zachovávanou účastnickou cestu: generování hesla,
`send-sign-in-code`, `reset_password_and_enqueue_email`, navazující přihlášení
včetně `exchange-sign-in-code`, šablonu SIGN_IN_CODE a skutečné podmínky použití
v přihláškách. Rozlišit form/order confirmation a app-access pozvánku podle
existujících callerů a konfigurace; nevymýšlet nové automatické rozesílání.

Cíl: znát přesný symptom organizačního přidávání a mít ochranu původního případu.
Na disposable lokální DB vytvořit unit managera, dva existující účty, novou
identitu a akci; projít vytvoření v unit, přidání existujícího, odebrání a znovu
přidání, udělení rolí a přidání v akci. Zachytit RPC request a bezpečnou chybu.
Pokud se organizační selhání neobjeví, přidat cílený test současného chování a
zaznamenat, že konkrétní historický bug zůstává nepotvrzen. Nevymýšlet příčinu.

Zmapovat skutečné call sites níže uvedených adaptérů včetně řetězcových RPC,
Edge registrací, generated API a serverových importů. Vyřešit kolizi s rozpracovanými
změnami. Ověřit finální roli/grant matici vůči typed operation predicates.

Validace: cílený SQL scénář v `database/tests/people/` přes
`node web_client/scripts/run_db_tests.js database/tests/people/access_management_test.sql`
a cílené transport testy. Výstup: reprodukce nebo explicitně doložená mez,
matice příkazů a očekávané odpovědi, žádná produkční testovací data.

### 2. Kanonický doménový owner a schema expansion

Implementovat nové kontrakty v `database/functions/people/`, forward migraci,
RLS, revoke/grant a scope constraints. Použít stávající locks, identity allocator,
receipt a Client Sync publish owners; opravit normalizaci lookupu také u
`update_user_internal_v1` bez druhé implementace account creation.
Rozšířit permission registry, capability projekci a jejich kanonické source
manifesty tak, aby unit i occasion měly přesné create/notify/invite/revoke/read
operace. Interní helpery nesmějí být veřejným bezpečnostním obchvatem.

Přejmenovat tabulku při zachování ID, token_hash, expirací, příjemců, přijetí a
message_id. Historické draft pozvánky přenést 1:1 včetně rolí a původu. Nepřevádět
SIGN_IN_CODE na smyšlené přijetí týmové pozvánky ani obecné členství na
odeslaný e-mail; skutečnou účastnickou historii odeslání naopak zachovat.
Nové doménové stavy přidávat před čtenáři; destructive contraction až ve vlně 5.

Validace: disposable migrační fixture s pending, accepted, expired pozvánkou,
smazáním draftu a duplicitní identitou; SQL RBAC a concurrent command testy.
Výstup: stejná operace v obou scope vede přes jednoho vlastníka; grant ani role
se nemění bez správné autorizace a žádná data nejsou ztracena.

### 3. Jedna orchestrace a skutečná stavová projekce

Přidat společný Edge access-management boundary, renderer a připravené enqueue
přes existující `_shared/emailQueueClient.ts`. Průvodce i správa členů jej volají;
SQL command vytvoří doménu a e-mail atomicky. Pro již platný týmový přístup použít
TEAM_ACCESS_NOTICE, pro účastnický credential záměr zachovat SIGN_IN_CODE a
atomickou credential transition, pro nabídku práv TEAM_INVITATION s kontextem unit/occasion.
Lokalizovat role, cíl a šablony přes existující mechanismus, bez hardcoded češtiny.

Změnit `email_intent_valid`, příslušné producer admission predicates,
reporting a status bundly: worker kontroluje konkrétní platnou pozvánku nebo
živé členství a scope oprávnění. Oznámení neodeslat po odvolání členství.
Wake-up až po commitu se stejnou recovery cron cestou. Stav je dostupný podle
scope, invitationId, userId a messageId, včetně pozvánek bez existujícího účtu.

Validace: Deno handler testy pro přípravu/enqueue failure, lost response,
queued -> provider_accepted, webhook delivery, suppression a odvolání při
čekání. SQL rollback pro selhání enqueue a integrace worker validity.
Výstup: žádný úspěšný command s požadovanou komunikací nemá chybějící messageId;
čtenář odliší nevyžádané odeslání, frontu, odeslání a přijetí.

### 4. Všechny produktové vstupy a klientská synchronizace

`unit_commands.dart`, `profile_commands.dart`, `db_users.dart`, unit users screen,
users tab/helper a setup finalizace přejdou na společný transport a stavový model.
Použít sdílenou komponentu nabídky pozvání a výsledku v existujícím UI systému.
Upravit invitation page pro oba scope, bezpečný návrat do správné organizace/akce,
existující/nový účet a neplatný odkaz. Zachovat původní veřejnou cestu
`/team-invitation?token=...` pro platné dříve odeslané odkazy.

Průvodce předá do stejného commandu explicitně potvrzený seznam příjemců a rolí.
Při retry finalizace se nevytvoří druhá akce ani druhé pozvánky. Každý příjemce
má vlastní stabilní command a výsledek; částečné selhání dávky neruší úspěšné.
Unit editor před založením duplicity nabídne existující členství; přidání/změnu
rolí a notifikaci zobrazí odděleně. Aktualizovat i dynamicky nalezené web klientské
callery, pokud pro tento flow existují; nevytvářet nepoužívanou druhou UI implementaci.

Client Sync publikuje správné scope, verze a invalidace; přijetí/odebrání musí
aktualizovat i privátní projekci cílového uživatele a capabilities. Po změně
identity/contextu nezobrazit výsledek předchozího účtu.

Validace: rozšířit `test/components/unit/unit_commands_cases.dart`,
`test/components/users/profile_commands_cases.dart`, occasion invitation/setup
cases a příslušné test wrappery. Cílené lokální E2E obou scope podle
`festapp-local-e2e` a `agent-browser`, v izolovaném testovacím prostředí se ztlumeným prohlížečem,
bez skutečného outbound provideru. Browser delegovat podle AGENTS.md.
Výstup: všechny tři obrazovky mají konzistentní záměr, role, stavy a opravný krok.

### 5. Kontrakce, kompatibilita a důkaz jediné cesty

`add_user_to_unit` je další existující přímý klientský RPC, volaný z
`DbUsers.addUserToUnit`. Převést jej na mechanický adaptér společného membership
ownera, včetně receipt/Client Sync pro nové callery; nesmí zůstat samostatným
nezachyceným writerem vedle `save_unit_user_client_sync_v1`. Původní interní
volání z importů/registrací přesměrovat podle jejich zachovávaných transakčních
hranic, nikoli přes HTTP orchestrace nebo nové automatické e-maily.

| Současný artefakt | Finální zacházení | Důkaz |
|---|---|---|
| `occasion_team_invitations` a setup-specific write logika | Jedna přejmenovaná tabulka a společný owner, žádná druhá zapisovatelná kopie. | Catalog + migrate fixture + caller search. |
| `preview_occasion_setup_invitations`, `enqueue_occasion_setup_invitation`, `send-occasion-team-invitations` | Přesunout nové callery; ponechat jen mechanický adaptér, prokáže-li se starý externí klient. | Runtime registrace a inventář callerů. |
| `get_occasion_team_invitation`, `accept_occasion_team_invitation` | Původní platné odkazy/klienti mají tenký adaptér nad novým ownerem. | Starý token přijme správný účet a nevytvoří druhý grant. |
| `send-sign-in-code` týmová větev a `teamAccessNotice.ts` | Doménová logika oznámení přesunuta do společného ownera; starý endpoint pouze přesměruje týmový záměr. Účastnický credential flow zůstane podporovaným produkčním kontraktem, nikoli deprecated adaptérem. | Team invite nikdy neresetuje heslo, participant auth regrese projde. |
| `update_unit_user`, `update_user`, `save_unit_user_client_sync_v1`, `create_occasion_user_client_sync_v1` | Migrovat sdílené doménové kroky; staré publikované RPC zachovat pouze jako autorizované mechanické adaptéry. | Žádná kopie grant/identity/notify pravidel. |
| `data.is_invited`, SIGN_IN_CODE-only týmová projekce | Odstranit smíchání týmového přijetí a účastnického odeslání; zachovat účastnické SIGN_IN_CODE evidence i historii bez přepisování. | Notice/pending/accepted fixture a nulové nové zápisy příznaku. |
| Setup-only tabulkové reference v workeru, templates, reporting a testech | Migrovat ve všech registrech, výběru testů a canonical source manifests. | Catalog dependency kontrola + worker testy + scoped search. |

Každý ponechaný adaptér musí mít v implementačním výsledku konkrétního klienta,
minimální doloženou verzi protokolu a odstranitelnou podmínku (vynucený upgrade nebo
zánik platných historických odkazů). Inventář neprokázal číselnou minimální vydanou
app verzi; nelze ji odhadovat. Neversionované signatury proto zůstávají podporované
pro všechny instalované klienty, v1 protokoly pro jejich stávající v1 klienty.
Contraction čeká na doložené vynucení nového klienta. Publikované RPC, routy a verzované protokoly
nelze bez důkazu spotřebitelů prostě přejmenovat. Interní obsolete verze a helpery
se mažou; historické aplikované migrace zůstávají neměnné.

Validace: `rg` nad dotčenými lib/web/SQL/Edge/automation/docs cestami kombinovat
s pg_proc ACL/dependency kontrolou a seznamem deployovaných funkcí. Aktualizovat
users README, email contracts a source parity testy. Výstup: žádný neúmyslný
bypass; každý přeživší starý název je doložená vnější hranice nebo historie.

## Efektivní provádění a pořadí důkazů

1. Jednou zaznamenat branch/HEAD, stav pracovního stromu a dotčené zdrojové změny.
   Znovu neprovádět produkční diagnostiku, pokud ji nevyžaduje nové zjištění.
   Známé neznámé řešit ve vlně 1, ne před každou další úpravou.
2. Sepsat stručnou fixture/command matici a začít disposable SQL kontraktem.
   Implementovat po koherentních vertikálních řezech: existující unit člen +
   notice; occasion člen + notice; pending invite + accept/revoke; zachování
   participant_credentials; setup/UI caller cutover; migrace/kontrakce.
   Schéma rozšířit před prvními závislými callery. Neoptimalizovat pořadí tak,
   že se přeskočí autorizace nebo ochrana historických tokenů.
3. Použít existující identity, receipt, queue, template a sync abstractions.
   Nevytvářet novou frontu, obecný workflow engine, druhý auth systém ani novou
   databázi rolí. Stavět jen minimální sdílený orchestrátor a scoped příkazy.
4. V jednom řezu nejprve doplnit hodnotný contract test na skutečné hranici,
   poté změnit související SQL/Edge/klienta a spustit jeden cílený batch. Rerun
   pouze po změně pokrytého kódu nebo při nové konkrétní nejistotě. Testy prose,
   snapshoty implementačních helperů a plošné buildy po každém souboru vynechat.
5. Concurrency, migraci a skutečné login chování ověřit jejich vlastními
   integračními seamy. Browser až po stabilním API; použít jeden existující
   lokální testovací backend/server a izolovanou session, žádné produkční fixtures.
6. Na konci jednou ověřit deletion ledger a dotčené canonical CI lanes. Nečekat
   na kompletní Flutter build, když otázku řeší targeted Dart analyzer/test.
   Plné release gates spouštět až při autorizovaném vydání. Passing check znovu
   nespouštět bez relevantní změny.
7. Průběžně aktualizovat tento plán jen při změně doloženého faktu/rozhodnutí.
   Závěrečný implementační výsledek zapíše přesné check commands/results,
   unresolved historical bug, retained external adapters a production status.
   Nepřidávat další odtržený plán nebo další revizní fázi.

## Ověření a podmínky dokončení

Implementační testovací matice musí pokrýt:

- Účastnickou pozvánku novému i existujícímu běžnému účtu: skutečně se nastaví
  vygenerované heslo, funguje přihlášení, e-mail obsahuje odpovídající údaje a
  retry zachová tentýž credential intent. Nikdy nedělat nové heslo při pouhé
  obnově stavu queued. Při rollbacku enqueue nesmí zůstat změněné heslo.
- U skutečného resent credential záměru po terminálním výsledku ověřit novou
  credential verzi a zneplatnění zastaralé zprávy podle auth ownera. Neaplikovat
  pravidla rotace týmových tokenů na hesla účastníků.
- Životnost hesla a stávající způsoby loginu zůstávají stejné; expirace e-mailu
  se netváří jako automatické zneplatnění účtu nebo hesla.
- Přihlášku bez app-access záměru, přihlášku s existujícím legitimním app-access
  záměrem a oddělení potvrzení/platby/účasti od týmových práv. Případný
  credential záměr musí být dohledatelný a neduplikovat potvrzovací zprávu.

- Notification-only a resend nemění role/profil; unit scope neumožní nový
  credential reset. Selhání volitelné pozvánky nevrátí zpět platnou přihlášku,
  objednávku či platbu a nezastaví jejich stávající automatická potvrzení.
- Nový účet / existující účet / již existující člen / již udělené role v obou scope.
- Rozdílná velikost písmen a whitespace, sdílená schránka s +N aliasem,
  delivery override a cizí tenant; nevznikne nesprávná identita ani únik údajů.
- Unit manager / unit editor / occasion manager / pouhý účastník / nepřihlášený;
  přímý RPC, spoofed actor/scope, replay po odebrání práv a role escalation.
- Žádná nová ruční komunikace bez volby; zachované stávající automatické
  přihláškové zprávy; atomický enqueue; dočasný výpadek, kvóta,
  suppression, dvojklik, souběh, ztráta odpovědi, partial batch a nový resend.
- Nový/existující účet při přijetí, nesprávný přihlášený účet, expirovaný,
  odvolaný, opakovaně přijatý a starý nahrazený token; nové role nikdy nesníží
  aktuální práva. Přijetí po odebrání práv zvoucímu je odmítnuto.
- Migrace historických pozvánek zachová tokeny, přijetí a message vazby;
  odstranění draftu neodstraní platnou pozvánku; členství neznamená doručení.
- Worker i UI respektují pauzu, demo ochrany a živé scope oprávnění;
  status read neodhalí cizí adresy ani tokeny. Client Sync obnoví oba účty správně.

SQL testy spouštět jen proti označené disposable lokální DB přes repository runner.
Deno testy jen s potřebnými oprávněními a stubbed providerem. Dart/Flutter cílenými
existujícími wrappery; před Flutter úlohou ověřit volný workstation slot,
`fvm flutter test --concurrency=1`. Nespouštět test po každém editování souboru.
Před publikací použít affected canonical CI mirror lanes z `automation/test_ci.sh`;
seznam získat `python3 automation/ci/run.py list` a výběr podle aktuálních inputs.
Pro publikaci/release nejsou cílené testy náhradou CI gates.

Dokončeno lokálně navíc vyžaduje prokázané zachování účastnických pozvánek
s generovaným heslem a legitimních přihláškových toků. Všechna cílová UI používají společný owner, kontrakt
má uvedené regrese, žádný neautorizovaný vstup neudělí role ani neodešle zprávu,
retry neztrácí/nekopíruje záměr, chyby jsou dohledatelné a deletion ledger uzavřen.
Produkčně dokončeno navíc vyžaduje samostatně autorizovaný a ověřený rollout.

## Rollout, rollback a zbývající rizika

Tento úkol schvaluje plán, nikoli implementaci, commit, push, produkční migraci,
rozesílání pozvánek ani deploy. Při následné implementaci znovu načíst změněné
zdroje a aktualizovat fakta; neprovádět další plošný architektonický průzkum.

Před produkcí připravit jednu scoped forward migraci z canonical SQL, zálohu a
read-only preflight počtů/starých tokenů/ACL. Nejdříve rozšířit backend a bezpečné
adaptéry, pak nasadit společný worker/Edge a klienta; kontrakce až po důkazu
migrace callerů. Po dobu smíšených klientů běží jediný doménový owner.
Rename tabulky a změna všech SQL závislostí musí být atomické; kompatibilní
Edge musí být připravené před kontrakcí, která by je zneplatnila.

Před tenant overlay/deploy musí projít exact baseMainSha release gate pro všechny
canonical GitHub CI jobs. Vybrat pouze jeden potvrzený tenant (výchozí předpoklad
festapptickets); ostatní prod větve neměnit. Web build lokálně a nasazení
`automation/deploy_direct.sh`; nikoli GitHub Deploy workflow. Restart Functions
jen přes schválený pause/drain + runtime restart helper + worker health + resume.
Rutinní release delegovat dle AGENTS.md. Ověřit API kontrakt, queue health a live
verzi; skutečné e-maily a změny zákaznických rolí jen s konkrétní autorizací.

Rollback nesmí obnovit druhého vlastníka ani resetování hesel u týmu. Při
nebezpečné chybě pozastavit příslušné pozvánky/worker podle runbooku, ponechat
durable intents a audit a opravit vpřed. Před kontrakcí lze vrátit klienta jen
na verzi obslouženou mechanickými adaptéry. Nevracet schema destruktivně přes
nově přijatá oprávnění. Již odeslaný e-mail nelze vrátit.

Zbývající rizika: historické organizační selhání není reprodukováno; přesná sada
starých mobilních/web klientů a životnost veřejných kontraktů vyžaduje inventář
ve vlně 1; aktuální pracovní změny mohou změnit výchozí fakta. U poskytovatele
nelze v neurčitém dispatch výsledku garantovat přesně jeden doručený e-mail.
Žádné z těchto rizik neopravňuje přidat druhou business cestu nebo obejít gates.

## Lokální implementace a důkazy 2026-11-10

Celý cílový owner, scoped schema/lifecycle, orchestrace, produktové vstupy,
kompatibilní vnější adaptéry, worker/šablony/projekce a forward/source registry
jsou implementované. Podrobný výsledek, uzavřený deletion ledger a přesné
provedené testy jsou v `access-membership-invitations-RESULT-2026-11-10.md`.
Routing/browser v obou scope i všech 8 affected canonical CI lanes prošlo.
Výsledek eviduje přesné navazující běhy, opravy regresí a uzavřený deletion ledger.

Původní organizační scénář prošel; canonical lookup normalizuje case/whitespace
s identity lockem. Historická příčina zákaznického hlášení není doložená.
Účastnické generované heslo zůstává skutečným heslem, ověřeným lokálním GoTrue;
týmová pozvánka ho nemění. Přihláškové a automatické potvrzovací kontrakty prošly.

Při skutečném browser průchodu se prokázala ztráta tokenu mezi invitation a login
návratem. Oprava zachovává explicitní typed invitation destination před obecnou
occasion navigací, včetně bezpečného lokálního Google return path. Nejde o nový
veřejný redirect protokol ani o změnu platnosti historických odkazů.

Pracovalo se v původním rozpracovaném stromu bez přepsání cizích změn. Žádný
commit, push, skutečný e-mail ani produkční změna nebyly provedené. Publikace a
rollout nadále vyžadují samostatnou autorizaci a předepsané release gates.

## Dodatečně autorizované začlenění a nasazení

Uživatel po dokončení lokální implementace výslovně zadal merge do main,
publikaci a nasazení, včetně hotové stránky `/pro-media` s balíčkem log.
Příprava probíhá v izolovaném worktree `festapp-access-release-20261110`,
nikoli přepsáním původního sdíleného pracovního stromu.

Nový main již obsahuje publikovaný forward17 kontrakt týmových e-mailů.
Společný producer proto používá jeho kanonické `occasionTitle`, `roleLabel`,
`invitationUrl` a `occasionAdminUrl`; draft-only aliasy eventTitle/eventUrl
se nezavádějí. Odpovídající popisy jsou už součástí main. Historické pending
zprávy si ponechávají svůj encrypted snapshot a vlastní šablony už zachovává
publikovaný conversion owner. Test společného rendereru navíc ověřuje jediné
escapování názvu scope.

Dosud nepublikovaný access draft160000 se při tomto začlenění nahrazuje
novou migrací `20261111010000_access_membership.sql`, po všech aplikovaných
migracích i Wallet hotfixu233000. Již aplikované migrace se nepřepisují.
Další release gates a skutečné nasazení jsou evidované v samostatném
release receiptu a závěrečném předání.
