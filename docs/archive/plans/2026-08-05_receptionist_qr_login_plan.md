# Recepce, role recepčního a přihlášení přes QR

Date: 2026-08-05
Status: Ready for execution
Verification: standard

## Outcome

Je-li na akci zapnutá nová feature `reception`, může administrátor nebo manažer
v tabulce uživatelů přidělit účastníkovi roli **Recepční**. Recepční pak ze svého
profilu otevře obrazovku **Recepce**, zadá povinně jméno, příjmení, e-mail a
explicitní volbu pohlaví, volitelně vybere existující standardní skupinu a
ubytování, založí nový účet v aktuální organizaci a současně jej přidá do
aktuální akce. Před zápisem uvidí omezené upozornění na přesné shody jména a
příjmení. Po úspěšném vytvoření může zobrazit a stáhnout přihlašovací QR kód
nového účtu.

Na přihlašovací obrazovce je při zapnuté feature ikona fotoaparátu. Naskenování
platného přihlašovacího QR vytvoří běžnou Supabase session a pokračuje stejnou
post-login synchronizací a navigací jako přihlášení e-mailem a heslem.

Hotový stav je pozorovatelný takto: právo je per occasion, bez zapnuté feature
není recepce dostupná ani na backendu, QR neobsahuje heslo ani UUID uživatele,
v databázi není uložen jeho plaintext a starý QR po rotaci nebo odebrání
členství již nelze použít. Recepční může svoji čerstvou registraci nouzově
zrušit: backend nejdřív odebere membership a QR (okamžité uzavření occasion
dat), potom globálně zruší refresh sessions. UI otevřeně uvádí, že již vydaný
Supabase access JWT může technicky žít do své krátké expirace, ale bez
occasion membership nezíská neveřejná data ani doménové operace dané akce.

## Scope

### In scope

- SimpleFeature `reception`, ve výchozím stavu vypnutá, včetně metadat a českých
  a anglických textů.
- Per-occasion příznak `occasion_users.is_receptionist` a sloupec **Recepční** v
  administrátorské tabulce uživatelů.
- Úzce vymezené backendové příkazy pro kontrolu přesné jmenné shody, načtení
  minimálních registračních voleb, založení účtu se skupinou/ubytováním,
  vydání/rotaci QR a nouzové zrušení čerstvé registrace.
- Obrazovka Recepce dostupná z `UserPage` oprávněnému uživateli.
- QR scanner na loginu, anonymní výměnná Edge Function a společná post-login
  finalizace v `AuthService`.
- Promítnutí práva do klasického app configu i `private_profile` client-sync V1.
- SQL, Edge Function a Flutter testy bezpečnostních hranic a hlavních toků.
- Serverově auditovaná nouzová akce, která zneplatní QR, odstraní occasion
  membership právě vytvořeného účtu a zruší jeho refresh sessions.

### Out of scope

- Hromadný import, odesílání QR e-mailem, tisk štítků/PDF sestav a evidence
  odbavení recepcí.
- Přihlášení stávajícím vstupenkovým QR nebo profilem s prostým UUID; stávající
  `entry_code` a ticket scanner zůstávají oddělené kontrakty.
- Samoobslužné zobrazení přihlašovacího QR běžným uživatelem.
- Seznam celé účastnické základny pro recepčního nebo úprava již existujících
  účtů. Recepční vidí jen omezené exact-name kandidáty a své čerstvé registrace.
- Vytváření nových skupin, správa skupinových členů nebo přidělení group-admin
  práva. Recepce může jen vybrat jednu existující standardní skupinu.
- Rezervace konkrétního inventory spotu/lůžka. Recepce přiřazuje existující
  occasion accommodation service stejně jako Users grid; inventory allocation
  zůstává samostatný kapacitní proces.
- Produkční migrace, nasazení Edge Function, commit a push.

## Constraints

- Jde o autentizaci a nový privilegovaný zápis, proto je ověřovací režim
  `standard` bez ohledu na osobní výchozí low-risk režim.
- Všechna doménová oprávnění musí být v SQL/RPC; skrytí tlačítka v Dart UI není
  bezpečnostní hranice. Každá `SECURITY DEFINER` funkce musí mít explicitní
  `search_path = public, extensions` nebo prázdný search path s plně
  kvalifikovanými názvy.
- Nepoužívat persistentní aplikační trigger. Vytvoření identity, occasion
  membership a QR credential musí vlastnit explicitní transakční command.
- Přihlašovací QR je ekvivalent hesla. Nesmí se logovat, ukládat v plaintextu,
  posílat do telemetry ani zobrazit znovu bez rotace.
- QR payload i session tokeny se přenášejí pouze v HTTPS POST body/response,
  nikdy v URL, query, route nebo redirect fragmentu. Exchange/cancel odpovědi
  mají `Cache-Control: no-store` a nesmí je cachovat service worker/proxy.
- Supabase `service_role` zůstává pouze v Edge Function. Flutter obdrží session
  až po úspěšné anonymní výměně opaque QR credentialu.
- „Odhlásit všechna zařízení“ nesmí být prezentováno jako okamžité zneplatnění
  stateless access JWT. Supabase globální sign-out zruší refresh sessions, ale
  access token zůstává platný do `exp`; okamžitou occasion ochranu proto vlastní
  odebrání membership před pokusem o Auth sign-out.
- Používat `fvm`; `app_router.gr.dart` se pouze regeneruje, ručně se neupravuje.
- Existující worktree je rozpracovaný a mění mimo jiné `occasion_user_model.dart`,
  `user_columns.dart`, `users_tab.dart`, `auth_service.dart`, překlady a shared
  Edge auth. Implementace musí tyto uživatelské změny zachovat a slučovat po
  symbolech, ne přepisovat celé soubory.

## Current-state evidence

| Claim | Evidence | Consequence |
|---|---|---|
| Role účastníka je per occasion. | `database/tables/tables.sql`: `public.occasion_users`; `lib/components/users/occasion_user_model.dart`: role flags | Nová role patří do `occasion_users`, ne do `user_info`. |
| App config vrací kompletní řádek aktuálního `occasion_users`. | `database/functions/others/get_app_config.sql`: `occasion_users%rowtype`, `row_to_json(occasion_user)` | Klasická větev získá nový sloupec automaticky, Dart model jej ale musí parsovat. |
| Editor bundle role vybírá explicitně. | `database/functions/users/get_occasion_users_for_edit.sql`: `visible_users` a explicitní select | `is_receptionist` se musí do bundle doplnit ručně. |
| Admin grid má vzor pro feature-gated boolean role. | `lib/components/users/views/users_tab.dart`: approver/cleaning columns; `user_columns.dart`: `_statusColumn` | Recepční dostane stejný typ checkbox sloupce, viditelný jen s feature `reception`. |
| Aktualizaci existujících uživatelů vlastní RPC s manager/admin kontrolou. | `database/functions/users/save_occasion_user_for_edit.sql`: `save_occasion_user_for_edit_internal_v1` | Přidělení role zůstane manager/admin operací; recepční nesmí získat obecné `canUpdateUsers`. |
| Současné vytvoření uživatele je manager/admin-oriented a má dvě klientské větve. | `lib/components/users/db_users.dart`: `updateOccasionUser`; `lib/components/users/profile_commands.dart`; `create_occasion_user_client_sync_v1` v migraci `20260802234000_client_sync_v1_expansion.sql` | Recepce potřebuje nový úzký command, ne rozšíření obecného editorového oprávnění. |
| Client-sync private profile dnes nese jen část occasion práv. | `get_private_profile_payload_v1` v `20260802234000_client_sync_v1_expansion.sql`; `lib/data_services/client_sync/client_sync_projection.dart:userInfo` | `isReceptionist` se musí přidat do factory i Dart projekce, jinak se UI liší podle protokolu. |
| Existující QR profil/vstupenka není autentizační credential. | `lib/components/users/views/user_page.dart:_showFullScreenDialog` ukládá UUID; `lib/components/scan/scan_page.dart`; `database/functions/eshop_orders/scan_ticket.sql` | Styl scanneru lze sdílet, payload ani backend se nesmí znovu použít. |
| Login má jednu heslovou finalizaci v `AuthService.login`. | `lib/data_services/auth_service.dart:login`; `lib/components/users/views/login_page.dart` | QR login musí sdílet validaci organizace, refresh-token storage, synchronizaci, notifikace a navigaci. |
| Privilegované serverové operace patří do Edge Functions s explicitním auth. | `docs/backend/edge_functions.md`; `supabase/functions/_shared/auth.ts` | Anonymní QR exchange bude samostatná výjimka s vlastním tokenovým ověřením, nikoli `manageUsers`. |
| Supabase umí serverově vytvořit magic-link token a OTP ověřením vydat session. | [Supabase admin `generateLink`](https://supabase.com/docs/reference/javascript/auth-admin-generatelink), [Flutter `verifyOtp`](https://supabase.com/docs/reference/dart/auth-verifyotp) | Edge Function může bez e-mailu vyměnit dlouhodobý opaque credential za jednorázový Auth doklad/session; klient nikdy nedostane service key. |
| Globální sign-out zruší refresh sessions, ne již vydaný access JWT před jeho expirací. | [Supabase signing out](https://supabase.com/docs/guides/auth/signout), [Supabase sessions](https://supabase.com/docs/guides/auth/sessions) | Nouzová akce musí nejdřív zavřít doménový přístup odebráním occasion membership a teprve potom revokovat Auth sessions. |
| Existující group editor RPC vrací celé členství a vyžaduje editor-view. | `database/functions/users/get_all_user_group_info.sql`: `get_all_user_groups`; `lib/components/groups/db_groups.dart` | Recepční nesmí tento RPC dostat; potřebuje nový minimální katalog pouze ID/název standardních skupin. |
| Standardní skupina je `user_group_info.type IS NULL`; membership je `user_groups` s `is_admin`. | `database/functions/users/import_user_group_assignments.sql`; `replace_group_assignments_client_sync_v1` | Reception create smí vložit nanejvýš jednu existující group membership s `is_admin=false`. |
| Jednoduché ubytování už Users grid ukládá jako occasion service code a server kontroluje katalog. | `OccasionUserModel.fromPlutoJson`; `save_occasion_user_for_edit_internal_v1` | Recepce použije stejný service tvar a validaci, nikoli přímou inventory/spot alokaci. |
| `f_unaccent` dává stabilní lower+unaccent normalizaci. | `database/functions/others/f_unaccent.sql` | Exact-name upozornění může být case/diacritics-insensitive bez fuzzy výpisu celé databáze. |

### Representative current flow

Admin upravuje role v `UsersTab` -> `OccasionUserModel.fromPlutoJson()` ->
`DbUsers.updateOccasionUser()` -> `save_occasion_user_for_edit` (nebo
`save_profile_client_sync_v1`). Po přihlášení `get_app_config_v219` naplní
`RightsService`; při client-sync V1 se soukromý profil skládá přes
`get_private_profile_payload_v1` a `ClientSyncProjection.userInfo()`.
Ticket/profile QR dnes pouze předává identifikátor do vstupního scanneru a
žádnou session nevydává.

## Target architecture and invariants

### Canonical owners and contracts

1. **Role a feature gate**
   - Zdroj pravdy: `occasion_users.is_receptionist` plus enabled
     `occasions.features[code=reception]`.
   - SQL helper `get_is_receptionist_on_occasion(oc)` vrací pouze explicitní
     roli; manager/admin nejsou do sloupce implicitně zapisováni. Samostatný
     capability helper/command povolí recepci explicitnímu recepčnímu a také
     managerovi/adminovi pro dohled.

2. **Minimální registrační katalog a kontrola shod**
   - `get_reception_registration_options_v1(p_occasion)` vrátí pouze existující
     standardní skupiny `{id,title}` a povolené accommodation items
     `{code,title,placeTitle}` z aktuální occasion. Nevrací členy skupin,
     kapacity, poznámky ani profilová data.
   - Create command vždy serverově porovná `f_unaccent(btrim(name))` a surname
     se stejnou normalizací proti uživatelům stejné organizace. Pokud existují
     přesné shody a klient neposlal explicitní `confirmSameName=true`, vrátí
     bezpečný 409 s nejvýše 10 minimálními kandidáty: jméno, příjmení, pohlaví,
     rok narození pokud existuje, maskovaný e-mail a příznak členství v aktuální
     occasion. Nevrací UUID, telefon, celé datum narození, poznámky ani odpovědi
     z formulářů. Fuzzy/prefix search se nepovoluje.
   - Potvrzení shody není autorizační token; pouze chrání obsluhu před omylem.
     Command po potvrzení znovu vyhodnotí aktuální shody. Shodný canonical e-mail
     zůstává tvrdý konflikt a nikdy nevytvoří druhou identitu.

3. **Vytvoření recepčního účtu**
   - Jediný veřejný zápis je idempotentní `SECURITY DEFINER` command, např.
     `create_reception_user_v1(p_occasion, p_command_id, p_profile,
     p_group_id, p_accommodation_code, p_confirm_same_name)`.
   - Ověří actor, feature, occasion/organization, velikost a povolené klíče
     profilu; přijme povinný e-mail, jméno, příjmení a explicitní volbu pohlaví
     z canonical enum (`male`, `female`, explicitní „neuvedeno“). Volitelné jsou
     telefon a datum narození. Role flags, raw services, ticket, group-admin a
     libovolná occasion data ze vstupu odmítne podle explicitního allowlistu.
   - V jedné transakci alokuje canonical sign-in email podle stávající email
     identity politiky, vytvoří Auth/user_info identitu s kryptograficky
     náhodným neprezentovaným heslem, vloží neprivilegované occasion membership
     a auditní `reception_registrations` receipt. Pokud je group ID přítomné,
     zamkne a ověří existující `user_group_info` stejné occasion s `type IS
     NULL` a vloží `user_groups.is_admin=false`. Pokud je accommodation code
     přítomný, ověří enabled services/accommodation konfiguraci a existenci kódu
     v occasion katalogu, potom uloží stejný `services.accommodation` tvar jako
     Users grid. Retry stejného command ID vrátí původní bezpečný výsledek a
     nevytvoří druhý účet.
   - Create command **nevrací QR plaintext** a jeho idempotency ledger jej nikdy
     neukládá. UI po úspěchu samostatně zavolá issue/rotate command; ztracená
     odpověď pouze způsobí další rotaci, nikoli duplicitní účet.

4. **QR credential**
   - Nová RLS-enabled tabulka, např. `public.user_login_qr_credentials`, má
     právě jeden aktivní řádek pro `(occasion, user)`, composite FK na
     `occasion_users ... ON DELETE CASCADE`, SHA-256 hash náhodného nejméně
     256bit tokenu, audit (`created_by`, `created_at`, `rotated_at`, `revoked_at`)
     a žádný plaintext. `reception_registrations` odděleně drží bezpečný audit
     `{occasion,user,created_by,created_at,status,cancelled_by,cancelled_at}` a
     neobsahuje QR/session secret.
   - QR payload je verzovaný a typovaný, např.
     `festapp-login:v1:42:AbCdEf...` (occasion ID + base64url token). Neobsahuje
     UUID, e-mail, heslo ani session token. Parser odmítne jiné schéma/verzi a
     rozumně omezí délku.
   - Plaintext se vrátí jen v přímé odpovědi issue/rotate commandu, která se
     neukládá do idempotency/audit ledgeru. Opětovné zobrazení znamená atomickou
     rotaci; předchozí token okamžitě přestane fungovat.

5. **Anonymní exchange**
   - Edge Function `exchange-login-qr` přijme jen `{payload}` přes POST, token
     nezaloguje a vrací jednotnou chybu pro neplatný, odvolaný, cross-occasion
     nebo feature-disabled credential.
   - Service-role RPC podle hashe ověří aktivní membership, feature a
     organization. Edge Function přes Supabase Admin vytvoří magic-link/OTP pro
     interní Auth e-mail, jednorázový doklad serverově ověří a klientovi vrátí
     pouze session data potřebná pro `setSession`. `generateLink` neposílá
     e-mail.
   - Flutter po `setSession` znovu provede `validateCurrentOrganization`; tím je
     serverová kontrola doplněna existující tenant ochranou klienta.
   - Úspěšný exchange aktualizuje pouze mechanická pole `last_used_at` a
     `use_count` credentialu explicitním RPC zápisem; receptionist UI tak může
     u své čerstvé registrace ukázat „QR byl použit“, aniž by vidělo session,
     zařízení nebo IP adresu.

6. **Nouzové zrušení čerstvé registrace**
   - Autentizovaná Edge Function `cancel-reception-registration` přijme
     occasion + target user + idempotency key. SQL command povolí recepčnímu jen
     registraci, jejíž `created_by=auth.uid()`, je stále aktivní a vznikla v
     omezeném okně (rozhodnutí: 30 minut); manager/admin může zrušit aktivní
     reception registration bez časového limitu.
   - SQL část pod row lockem označí receipt `cancelled`, použije kanonický
     cleanup `delete_occasion_user` pro skupiny/events/saved state a smaže
     occasion membership. Credential zanikne FK cascade. Tato část proběhne
     **před** Auth revokací, takže i při výpadku Auth je neveřejný occasion
     přístup uzavřen.
   - Edge Function následně přes admin `generateLink` + serverové `verifyOtp`
     vytvoří krátkou target session a na user-scoped klientu zavolá global
     `signOut`, čímž zruší všechny refresh sessions včetně dočasné. Nikdy
     neloguje target identity ani tokeny. Selhání Auth kroku vrátí bezpečný
     `domain_blocked_auth_revocation_pending`; retry dokončí revokaci.
   - Už vydaný access JWT nelze před `exp` spolehlivě anulovat přes standardní
     Supabase sign-out. Proto se v UI akce jmenuje **Zrušit registraci a
     zablokovat přístup**, ne pouze „okamžitě odhlásit“; její bezpečnostní efekt
     stojí na odstranění membership, nikoli na slibu okamžité smrti JWT.

7. **Flutter UI**
   - `RightsService.canUseReception()` je pravda jen při enabled feature a
     explicitním recepčním nebo manager/admin capability.
   - `ReceptionPage` je chráněná při renderu i při přímé navigaci. Formulář
     vytvoří jeden účet, po úspěchu ukáže jméno, sign-in e-mail a QR se stažením.
     Obsahuje povinná pole jméno, příjmení, e-mail a explicitní pohlaví, plus
     volitelné selecty jedné standardní skupiny a ubytování z minimálního
     katalogu. Při 409 ukáže exact-name kandidáty a vyžádá potvrzení „je to jiný
     člověk“. Reset formuláře odstraní plaintext token z widget state.
   - Success panel ukazuje stav nepoužit/použit a po dobu bezpečnostního okna
     výraznou potvrzovanou akci **Zrušit registraci a zablokovat přístup**.
     Obrazovka může po reloadu načíst jen vlastní aktivní registrace z posledních
     30 minut, nikdy obecný roster.
   - Login camera action otevře specializovaný scanner založený na stejném
     `mobile_scanner` nastavení jako ticket scan (QR-only, fresh refs/state,
     web ZXing setup), ale s vlastním parserem a bez raw-value logování. Po
     detekci scanner zastaví; při bezpečné chybě jej lze obnovit.
   - `AuthService.loginWithQr()` a heslový login volají jednu společnou interní
     post-login finalizaci.

### Invariants

1. Recepční nikdy nezíská obecné `canUpdateUsers`, admin tab ani možnost měnit
   role existujících uživatelů.
2. Feature vypnutá = UI skryté a všechny reception backendové commandy odmítnuté, i když
   `is_receptionist=true` historicky zůstane v řádku.
3. Nový účet vždy patří do stejné organizace a aktuální occasion jako actorův
   recepční kontext; žádné ID organizace z klienta se nepovažuje za autoritu.
4. Recepční nemůže novému účtu podstrčit manager/editor/receptionist ani jiná
   privilegia.
5. Databáze uchovává pouze hash QR tokenu. Token ani session se nevypisují do
   logů, audit payloadů, exceptions nebo analytiky.
6. Rotace, revoke, odstranění occasion membership a deaktivace feature blokují
   nové QR loginy. Již vydané sessions se řídí běžným Supabase lifecycle; rotace
   sama je globálně neodhlašuje.
7. Úspěšný QR login vytváří stejný lokální refresh-token stav, private/public
   sync a notification identity jako heslový login.
8. Klasická a client-sync V1 projekce vracejí stejnou hodnotu
   `is_receptionist`.
9. Exact-name lookup nikdy není obecné vyhledávání: vyžaduje celé normalizované
   jméno i příjmení, je omezený počtem výsledků a vrací maskované minimum.
10. Group/accommodation ID z klienta jsou pouze návrhy; command je znovu ověří
    proti aktuální occasion a nikdy nevytvoří skupinu ani inventory spot.
11. Nouzové zrušení nejdřív odebere occasion membership a QR, potom revokuje
    refresh sessions. Částečné selhání tedy skončí bezpečně uzavřenou doménou.
12. Před dokončením feature musí být prokázáno, že chybějící membership odmítne
    všechny private roots a participant write commandy této occasion. Nalezený
    bypass se opraví u canonical SQL ownera; veřejná data dostupná anonymovi
    nejsou porušením tohoto invariantu.

### Entry points and forbidden bypasses

- Povolené: minimální reception options RPC, exact-match pouze uvnitř create
  command, explicitní issue/rotate command pro právě vytvořený výsledek/managera,
  nouzové cancel pro vlastní čerstvou registration, anonymní
  `exchange-login-qr`, manager/admin save role přes existující profile command.
- Zakázané: přímý insert/update credential tabulky z Flutteru, přímé volání
  `create_user_in_organization_with_data_pure`, rozšíření
  `create_user_in_organization_with_data_ws` pro recepčního, login podle UUID,
  ticket symbolu nebo e-mailu bez credentialu, vrácení Auth e-mailu z exchange,
  použití editor group RPC (s participant rosterem), vytvoření skupiny nebo
  přímá inventory alokace z reception flow, cancel cizí/starší registrace.

## Decisions, assumptions, and blockers

### Decisions

- **D1:** Feature code je `reception`, role column je `is_receptionist` a český
  label **Recepční**. Feature a role jsou oddělené: feature řídí dostupnost,
  role konkrétní uživatele.
- **D2:** Role je per occasion, protože je udělována ve sloupci occasion users a
  oprávnění se vztahuje k recepci jedné akce.
- **D3:** QR je opakovaně použitelný odvolatelný credential, nikoli jednorázový
  obrázek; jeho odcizení má stejný dopad jako odcizení hesla.
- **D4:** Pro QR login vznikne samostatný payload a credential store. Existující
  `entry_code` UUID a ticket QR se autentizačně nepovýší.
- **D5:** Recepční může založit pouze nový neprivilegovaný účet a bezprostředně
  vydat/rotovat jeho QR; nedostane seznam ani editaci všech occasion users.
- **D6:** Heslo nového účtu je náhodné a UI jej nezobrazuje. Uživatel se může
  vedle QR později dostat k běžnému heslu existující reset/invite cestou.
- **D7:** Stávající occasion data se nebackfillují o feature. Administrátor ji
  musí na požadované akci výslovně zapnout.
- **D8:** Jméno, příjmení, e-mail a explicitní pohlaví jsou povinné. Skupina a
  ubytování jsou volitelné a vybírají se pouze z existujícího occasion katalogu.
- **D9:** Shoda jména není důvod účet automaticky sloučit ani odmítnout; zobrazí
  se minimální exact-match warning a obsluha výslovně potvrdí jinou osobu.
  Shodný canonical e-mail je naopak hard conflict.
- **D10:** Nouzová akce je cancel occasion registration, ne smazání Auth identity.
  Odebere membership a QR, zachová organization identity pro pozdější bezpečnou
  obnovu managerem a zruší refresh sessions best-effort s retry.
- **D11:** Recepční může zrušit pouze svou aktivní registraci do 30 minut;
  manager/admin může řešit starší incident. Tím se omezuje destruktivní dosah
  kompromitovaného receptionist účtu.
- **D12:** Ubytování znamená jednoduchý occasion accommodation service používaný
  Users gridem; rezervace konkrétního lůžka/spotu není implicitní vedlejší efekt.
- **D13:** Exact-name kontrola probíhá jen uvnitř create commandu, nikoli přes
  samostatný libovolně volatelný search endpoint. Create/issue/cancel mají
  serverový per-actor rate limit bez ukládání hledaných jmen; anonymous QR
  exchange má upstream/per-source throttling a 256bit token zůstává hlavní
  ochranou proti hádání.

### Assumptions

- **A1:** Explicitní „neuvedeno“ je platná volba pohlaví, ale prázdné/nevybrané
  pole není; dopad při požadavku jen na muž/žena: zúží se enum v UI a commandu.
- **A2:** QR má fungovat opakovaně jako průkaz a jeho fyzický držitel je
  oprávněn účet přihlásit; dopad při požadavku na jednorázovost: credential
  se po exchange spotřebuje a UI musí vždy generovat nový.
- **A3:** Camera action se zobrazuje jen v kontextu occasion se zapnutou
  `reception`; dopad při požadavku na globální scanner: QR payload musí nejdřív
  bezpečně načíst/změnit occasion context před exchange.
- **A4:** Jedna standardní skupina na osobu odpovídá současnému import/admin
  chování; dopad při více skupinách: vstup i validace se změní na omezený set,
  ale nikdy nepovolí `is_admin`.

### Blockers

- None pro implementaci. Produkční aplikace migrace a deploy Edge Function
  vyžadují samostatné pověření.

## Deletion ledger

| Artifact | Current role | Final action | Removal proof |
|---|---|---|---|
| Použití prostého `userData.id` v profile QR | Vstupní/evidence QR | Zachovat pouze jako hranici `entry_code`; nikdy nepoužít v loginu | Test odmítne UUID/ticket QR v login parseru a exchange |
| Duplikovaná post-login logika | Hrozila by při přidání QR větve | Extrahovat jedinou finalizaci sdílenou heslem a QR | Unit test obou vstupů + `rg` na sync/storage sekvenci |
| Předchozí QR hash při rotaci | Platný login credential | Atomicky nahradit/odvolat | SQL test starý token odmítne a nový přijme |
| Plaintext QR ve widget state | Potřebný jen pro jedno zobrazení | Vymazat při resetu/dispose/navigaci; nikdy persistovat | Widget/unit test stavu a code review bez storage/log callů |
| QR plaintext v idempotency response ledgeru | Původní návrh spojoval create a QR response | Oddělit idempotentní identity create od nepersistované issue/rotate odpovědi | SQL assertion, že command/audit tabulky token neobsahují |
| Aktivní domain membership po incidentu | Samotný Auth sign-out ponechá JWT do expirace | Cancel command nejdřív odstraní membership a QR, až potom revokuje sessions | SQL test membership/data gates + Edge partial-failure test |
| Dočasné kompatibilní overloady/V2 názvy | Nejsou požadovány | Nevytvářet; nové kontrakty pojmenovat finálně, `_v1` jen tam, kde je součást client command protokolu | `rg` na reception aliases/placeholders |

## Implementation waves

### Wave 1 — Schema, feature a neobejitelná oprávnění

**Goal**

Databáze umí reprezentovat reception feature, per-occasion roli a bezpečný
hashed QR credential, ale zatím není dostupný žádný klientský create/login tok.

**Changes**

- Přidat novou časově seřazenou migraci do `supabase/migrations/` a zrcadlit
  výsledný stav v `database/tables/tables.sql`:
  `occasion_users.is_receptionist boolean not null default false`, RLS-enabled
  `user_login_qr_credentials` s výše popsanými constraints/FK/auditem a
  RLS-enabled `reception_registrations` pro bezpečný lifecycle/audit create a
  cancel. Credential má composite FK na membership s cascade; receipt odkazuje
  na occasion a `user_info`, nikoli na membership, aby po cancel zůstal audit.
  Authenticated/anon nedostanou přímé CRUD policies.
- Přidat kanonické SQL soubory do `database/functions/user_permissions/` pro
  `get_is_receptionist_on_occasion` a capability check používaný reception
  commandy. Obyčejný recepční se nesmí stát součástí existujících obecných
  manager/editor helperů.
- V `feature_constants.dart`, `feature_service.dart`, `feature_metadata.dart`,
  `features_strings.dart` a `assets/translations/{cs,en}.json` přidat SimpleFeature
  `reception`, app-supported, default disabled. Propagovat stejné překlady podle
  repo mechanismu i do web klienta, nikoli ručním divergentním textem.
- Doplnit `Tb.occasion_users.is_receptionist` a případný table descriptor pro
  credential tabulku v `lib/database_tables/tb.dart`.

**Migration/deletion**

- Additive migration; existující `occasion_users` dostanou `false`. Žádný
  feature backfill a žádný persistentní trigger.

**Failure and compatibility**

- Starší klienty nový sloupec ignorují. Feature zůstane vypnutá, dokud ji admin
  explicitně nezapne. RLS tabulka nemá obecné client CRUD policies.

**Validation**

- Targeted DB test přes `node web_client/scripts/run_db_tests.js database/tests/users/reception_qr_login_test.sql`:
  default false, helper odděluje occasion, feature-off capability selže a obě
  nové tabulky nepovolí anon/authenticated direct CRUD.

**Exit condition**

- Schema rozlišuje recepčního a bezpečně drží jen hash credentialu; žádný
  současný klient tím nezíská nové oprávnění.

### Wave 2 — Jediný transakční create/rotate contract a client-sync konzistence

**Goal**

Oprávněný recepční dokáže idempotentně založit pouze neprivilegovaný účet v
aktuální occasion, bezpečně zkontrolovat přesnou jmennou shodu, přiřadit
validovanou skupinu/ubytování a samostatně vydat QR bez plaintextu v ledgeru.

**Changes**

- Přidat doménový SQL modul pod `database/functions/users/` pro:
  - `get_reception_registration_options_v1`: jen `{id,title}` standard groups a
    `{code,title,placeTitle}` accommodation katalog, žádní participants;
  - `create_reception_user_v1`: actor/feature/tenant kontrola, required
    name/surname/email/explicit sex, exact-name 409 response, profile allowlist,
    group/accommodation validation, canonical email allocation, náhodné heslo,
    identity + membership + group/service + registration receipt v jedné
    transakci a command-id replay bez QR secretu;
  - `issue_reception_login_qr_v1`: vlastnictví čerstvé registration nebo
    manager/admin, row lock a atomická issue/rotace s plaintextem pouze v přímé
    response, nikoli v mutation ledgeru;
  - `cancel_reception_registration_v1`: idempotentní receipt state transition a
    canonical membership cleanup; vlastní registration max 30 minut nebo
    manager/admin;
  - `get_my_recent_reception_registrations_v1`: pouze actorovy aktivní receipts
    max 30 minut s minimální identitou a QR used state;
  - service-role-only resolver credentialu pro Edge Function.
- Commandy před doménovou prací aplikují bounded per-actor rate counter, který
  ukládá jen actor, časový bucket a count, nikoli jméno/e-mail/input. Limit a
  bezpečná 429 response jsou konstanty testované v SQL.
- Znovu použít existující email identity helpery a čistou identity factory tam,
  kde zachovají `email_readonly`, organization-prefixed Auth email a delivery
  pravidla. Nevolat starý široký web-service facade jako autorizační zkratku.
- Rozšířit `save_occasion_user_for_edit_internal_v1` o
  `is_receptionist`, přičemž jeho existující manager/admin kontrola zůstane.
- Rozšířit `get_occasion_users_for_edit` o nový explicitní field.
- V nové migraci nahradit `get_private_profile_payload_v1` tak, aby occasion
  payload nesl `isReceptionist`, aktualizovat client-sync source metadata pro
  nový sloupec a zajistit private-profile impact při změně role aktuálního
  uživatele. Nedělat paralelní V2 factory.
- Command outcome/audit nesmí obsahovat e-mail, token ani Auth UUID v safe label.
  Create response/ledger neobsahuje token; issue/rotate response jej vrátí bez
  replay persistence. `last_used_at/use_count` jsou mechanická metadata, nikoli
  session/device audit.

**Migration/deletion**

- Při rotaci přepsat starý hash pod row lockem; při cancel/delete membership jej
  smaže FK cascade. Registration receipt zůstane jako `cancelled` audit bez
  secretu. Žádný plaintext se nemigruje.

**Failure and compatibility**

- Stejný `p_command_id` a stejné parametry replaynou původní výsledek bez další
  identity; stejný command ID s jiným hashem se odmítne. Současné vytvoření
  stejného e-mailu využije organization-level advisory lock a vrátí stabilní
  domain error. Exact-name check se opakuje v create transakci. Neplatná/cizí
  group nebo accommodation hodnota rollbackne celý create. Ztracená QR response
  nevytvoří druhý účet; další issue pouze bezpečně zrotuje credential.

**Validation**

- Nový SQL contract test: receptionist/manager/admin success, participant a
  cross-occasion denial, feature-off denial, input role escalation denial,
  duplicate-name 409/minimal fields/explicit confirm, duplicate-email hard
  conflict, retry/concurrency behavior, group/accommodation cross-occasion a
  escalation denial, žádný plaintext v DB/auditu/command ledgeru, rotate
  invaliduje starý token, cancel ownership/time-window/idempotency a membership
  delete cascade.
- Rozšířit `database/tests/client_sync_v1_contract_test.sql` o source/factory a
  projection contract pro `is_receptionist`.

**Exit condition**

- Existuje právě jeden auditovatelný create command; jeho úspěšný commit vždy
  vytvoří identity, membership, validované volby a receipt bez QR plaintextu.
  QR issue/rotate je oddělené a nemůže duplikovat identitu.

### Wave 3 — Admin sloupec a obrazovka Recepce

**Goal**

Manager/admin přidělí roli a recepční bezpečně vytvoří jednoho nového uživatele
z profilové části aplikace.

**Changes**

- `OccasionUserModel`: přidat `isReceptionist` do konstruktoru, JSON parse,
  `toUpdateJson`, Trina row a `fromPlutoJson`; zahrnout do `isPrivileged`, aby
  případná lifecycle logika privilegované členství nesmazala jako běžné.
- `UserColumns`/`UsersTab`: přidat `RECEPTIONIST`, localized title **Recepční** a
  feature-gated checkbox vedle ostatních práv. Checkbox používá stávající
  manager/admin save boundary; nepřidá recepčnímu `canUpdateUsers`.
- `ClientSyncProjection.userInfo()` a relevantní tests/fixtures: mapovat
  `isReceptionist`; `RightsService` přidat `isReceptionist()` a
  `canUseReception()` s feature gate.
- Vytvořit feature-oriented `lib/components/reception/` se strings, service/
  command adapterem a `ReceptionPage`. Route zaregistrovat v `app_router.dart`,
  poté regenerovat AutoRoute. Přímý vstup bez capability zobrazí access denied/
  bezpečně naviguje zpět.
- `UserPage`: přidat tlačítko/sekci Recepce pouze při
  `RightsService.canUseReception()`.
- Formulář použije repo form helpers a `ExceptionHandler.guard`; po commandu
  vyžaduje jméno, příjmení, e-mail a explicitní pohlaví, načte minimální selecty
  jedné standardní skupiny a ubytování a neposílá raw services/group object.
  Při exact-name 409 zobrazí jen serverem vrácené maskované kandidáty a vyžádá
  potvrzení jiné osoby. Po create samostatně issue QR, zobrazí jej přes
  `qr_flutter`, jméno a canonical sign-in e-mail a nabídne download stejným
  technickým stylem jako současné QR. Opakované zobrazení je explicitní
  **Vygenerovat nový QR** s potvrzením, protože ruší starý.
- Success/recent-registration panel polluje jen minimální receipt stav a ukáže,
  zda byl QR použit. Po dobu 30 minut nabízí dvoukrokově potvrzené
  **Zrušit registraci a zablokovat přístup**; UI jasně popíše odebrání účasti,
  QR a sessions i limit access-JWT expirace.
- Přidat české a anglické texty přes feature-specific strings, bez `.tr()` v
  UI mimo strings getter.

**Migration/deletion**

- Žádná další data migration. Po opuštění success state zrušit plaintext token
  v paměti; neukládat do offline cache/secure storage.

**Failure and compatibility**

- Network error před odpovědí se řeší replayem stejného command ID, ne novým
  create. Network loss při issue znamená novou rotaci. Duplicate email zobrazí
  doménovou chybu; exact-name candidates jsou k dispozici pouze oprávněné
  recepci a jen při celé shodě obou polí. Stale katalogová volba je serverem
  odmítnuta a UI options obnoví. Camera/login/cancel Edge orchestrace není
  součástí této vlny.

**Validation**

- Targeted Flutter model/widget tests: sloupec jen při feature, právo v obou
  projekcích, přímá route denial, required sex, minimální option mapping,
  exact-name confirmation, formulář neodesílá role/raw services/group-admin,
  success/reset lifecycle nedrží token a recent list je actor-scoped.
- `fvm dart run build_runner build --delete-conflicting-outputs` po route změně.

**Exit condition**

- Zapnutá feature + přidělený checkbox zpřístupní Recepce; recepční vytvoří
  účet s validovanou skupinou/ubytováním a dostane právě jednou renderovatelný
  QR, ale nevidí admin tab ani roster. Shodné jméno vyvolá explicitní varování.

### Wave 4 — QR exchange a login scanner

**Goal**

Držitel platného reception QR se na login obrazovce přihlásí do správné
organizace stejnou session pipeline jako heslem.

**Changes**

- Přidat `supabase/functions/exchange-login-qr/index.ts` a malý čistý modul pro
  parse/validation. CORS a error mapping přizpůsobit repo patternu, ale endpoint
  je pouze POST/OPTIONS, nepoužívá obecný `authorizeRequest`, odmítá oversized
  body a nastavuje `Cache-Control: no-store`. QR/session secret nikdy není URL,
  query ani redirect. Přidat bounded upstream/per-source throttling dostupný v
  Supabase Edge prostředí; neukládat raw IP.
- Edge Function zavolá service-role-only resolver; po validaci použije
  `supabaseAdmin.auth.admin.generateLink`, ověří jednorázový token serverovým
  anon klientem a vrátí session. V žádné větvi nelogovat request body, token,
  user ID, e-mail, generated link ani refresh/access token.
- Přidat autentizovanou `supabase/functions/cancel-reception-registration/`.
  Nejprve user-scoped RPC provede idempotentní domain cancel. Potom Edge Function
  vytvoří přes Admin generate/verify dočasnou target session a zavolá global
  sign-out na user-scoped klientu. Dočasná session ani target údaje se nevrací
  recepčnímu. Pokud Auth krok selže, membership/QR zůstávají bezpečně zrušené a
  response dovolí idempotentní retry pouze Auth části.
- V `AuthService` extrahovat post-login finalizaci z `login`; přidat
  `loginWithQr(payload)`, které invokuje Edge Function, nastaví session přes
  refresh token, ověří organization a spustí stejnou finalizaci.
- Přidat specializovaný login scanner widget/page pod reception/users feature.
  Reuse konfiguraci `MobileScannerController` a web ZXing setup ze scan flow,
  ne `ScanPage` ticket business logic. Implementovat QR-only, debounce,
  stop/resume, camera permission/unavailable stav a bezpečnou obecnou chybu.
- `LoginPage`: při enabled `reception` přidat camera icon s tooltipem. Po
  úspěchu použít existující `finishSuccessfulSignIn`/navigaci; během exchange
  zabránit druhému submitu.
- Aktualizovat `docs/backend/edge_functions.md` o endpoint, anonymous credential
  auth, authenticated cancel orchestration, pořadí domain-before-Auth, omezení
  access JWT do expirace, potřebná secrets a zákaz logování.

**Migration/deletion**

- Odstranit duplikovanou post-login sekvenci z heslové větve ve prospěch
  společného ownera. Žádný fallback na UUID/ticket/password QR.

**Failure and compatibility**

- Invalid/rotated/feature-off/cross-tenant token vrací stejný 401/403-safe
  výsledek; UI neprozradí účet. Chyba před vznikem session scanner obnoví;
  chyba po `setSession` použije stávající organization validation/logout.
  Web bez kamery ukáže vysvětlení a zachová email/password login.
- Cancel nesmí vrátit target UUID/e-mail/tokens v chybě. Opakování po domain
  success znovu nemaže data, jen dokončí session revocation. Odebraný user může
  s dosud platným JWT číst nejvýše veřejná data dostupná i anonymovi; všechny
  private occasion roots a write commands musí selhat kvůli chybějící membership.

**Validation**

- Deno unit tests čistého parseru a exchange orchestrace s fake dependencies:
  valid, malformed, unsupported version, resolver denial, generate/verify
  failure, response neobsahuje interní identity pole.
- Deno tests cancel orchestrace: cizí/starší registration denial, SQL-before-Auth
  ordering, Auth failure po úspěšném domain block, retry completion, global
  sign-out a žádný sensitive response/log payload.
- Flutter tests `loginWithQr`: session set, organization mismatch logout,
  společná finalizace přes password i QR; scanner debounce/resume a feature gate.
- Jedna lokální exploratory smoke kontrola přes task-specific `agent-browser`
  session pouze pokud už běží projektový dev server: camera action visibility a
  web no-camera/error path. Deterministické testy zůstávají CI kontraktem.

**Exit condition**

- Platný QR vytvoří plnohodnotnou session; neplatný/starý QR nikdy neidentifikuje
  uživatele a heslový login se chová beze změny. Nouzový cancel okamžitě zavře
  occasion membership/QR a prokazatelně se pokusí globálně zrušit refresh sessions.

### Wave 5 — Contract contraction, docs a standard validation

**Goal**

Obě datové větve a všechny vstupy používají cílový kontrakt, nejsou ponechány
bezpečnostní bypassy ani dočasné názvy.

**Changes**

- Doplnit `lib/components/users/README.md` o reception ownership, per-occasion
  roli, QR lifecycle, minimal duplicate disclosure, group/accommodation hranici,
  cancel ordering a zákaz UUID loginu.
- Aktualizovat případné app-config/client-sync test fixtures a source registry,
  aby nový field nebyl tichým rozdílem protokolů.
- Z `client_sync_sources_v1`, participant-facing RPC call sites a RLS policies
  sestavit bounded cancel-access matrix: po odstranění target membership musí
  každý private root a každý write command aktuální occasion vrátit deny/no
  private payload. Každý nalezený bypass opravit u jeho canonical SQL permission
  checku; nezavádět globální klientský blacklist jako náhražku.
- Projít přesné absence searches z deletion ledgeru; odstranit placeholdery,
  dočasné overloady a raw QR logging v novém flow.

**Migration/deletion**

- Žádný starý login contract se nemaže, protože feature je aditivní. Odstraní
  se pouze implementační duplicity vzniklé refaktorem post-login pipeline.

**Failure and compatibility**

- Produkční pořadí je schema/functions -> Edge Function -> Flutter klient ->
  explicitní enable feature. Klient nesmí být distribuován s enabled feature,
  dokud backend exchange není nasazen.

**Validation**

- Jedna standardní cílená dávka: nové/změněné SQL test files přes DB runner,
  Deno tests pro novou Edge Function a relevantní Flutter tests následované
  scoped `fvm flutter analyze` pro změněné Dart soubory. Plný
  `./automation/test_all.sh` až pokud jej vyžadují repo pravidla nebo release
  režim; neopakovat již úspěšné checks bez další změny pokrytého kódu.
- Absence check pomocí `rg`: žádný login path neakceptuje prosté UUID/ticket QR,
  žádný token/raw payload log, žádný direct client CRUD credential tabulky,
  žádný QR plaintext v mutation/audit ledgeru, žádný reception call do editor
  group roster RPC, žádná druhá post-login sync sekvence.
- Contract test po cancel použije stále neexpirovaný target JWT a prokáže deny
  private profile/program/inventory i participant writes; veřejný occasion
  katalog může zůstat shodný s anon přístupem.

**Exit condition**

- Definition of complete je splněna a deployment checklist přesně odděluje
  ještě neautorizované produkční kroky.

## Rollout and rollback

1. Lokálně implementovat a ověřit všech pět vln bez zásahu do produkce.
2. Po samostatném schválení aplikovat additive DB migration/functions. Feature
   zůstává defaultně vypnutá, takže nová role ani endpoint nejsou použitelné.
3. Nasadit `exchange-login-qr --no-verify-jwt` na projekt určený výhradně podle
   `automation/project.conf`; před produkčním krokem ověřit configured occasion
   podle `FORCE_OCCASION_LINK` dle `ai_context.md`.
4. Vydat Flutter klienta a teprve potom na vybrané occasion zapnout `reception`
   a přidělit první roli.
5. Rollback UI je vypnutí feature. To okamžitě zablokuje create i nové QR
   exchanges na backendu. Additive column/table lze ponechat; jejich drop není
   bezpečný rollback a vyžadoval by zvláštní destruktivní plán. Pokud je
   kompromitovaný QR, rotovat/revoke konkrétní credential. Při podezření na
   chybnou osobu použít cancel: nejprve membership/QR, potom refresh sessions.
   Access JWT může do expirace existovat, ale bez membership nesmí projít žádný
   private occasion root ani write command.

## Verification strategy

| Risk or invariant | Verification seam | Command/observation |
|---|---|---|
| Role/feature nelze obejít | SQL command boundary | Targeted reception permission SQL test |
| Create je atomický a retry-safe | SQL transaction + command ledger | SQL failure/replay/concurrency cases |
| Exact-name warning nefunguje jako roster oracle | Normalized bounded RPC/create 409 | SQL exact/partial/diacritics/cap/masked-field cases |
| Group/ubytování nelze podstrčit z jiné akce | Create command catalog validation | SQL cross-occasion/stale/escalation cases |
| QR plaintext není uložen/logován | Credential schema, audit, source absence | SQL assertion + `rg` absence check |
| QR plaintext není v replay ledgeru | Oddělené create a issue contracts | SQL ledger assertion + lost-response test |
| Starý/revoked credential nefunguje | Resolver | SQL rotate/delete/feature-off cases |
| Nouzový cancel fail-closed | Membership cleanup před Auth revocation | SQL cleanup + Deno partial-failure/retry tests |
| Starý JWT po cancel nemá private/write occasion přístup | Private roots, RPC/RLS membership gates | Cancel-access matrix contract test s původním JWT |
| Abuse není roster/QR oracle | Actor/anonymous rate limits + uniform errors | SQL 429 + Edge throttle/uniform-response tests |
| Client-sync a app config souhlasí | Payload factories + Dart model | Extended client-sync SQL test + Dart projection test |
| Edge nevydá session bez validního credentialu | Pure exchange orchestration | `deno test` new function modules |
| QR a password sdílejí finalizaci | `AuthService` contract | Targeted Dart unit test |
| UI respektuje feature/capability | RightsService + widgets/routes | Targeted Flutter widget tests |
| Generated routing je konzistentní | AutoRoute build | `fvm dart run build_runner build --delete-conflicting-outputs` |

## Definition of complete

- [ ] `reception` je default-disabled SimpleFeature a backend ji vždy ověřuje.
- [ ] `is_receptionist` je per occasion, admin-editable a shodně projektovaný
      klasickou i client-sync V1 cestou.
- [ ] Recepční nemá žádné obecné user-edit/admin oprávnění.
- [ ] Jeden idempotentní command atomicky vytvoří neprivilegovaný účet,
      membership, validovanou standardní skupinu/ubytování a auditní receipt;
      QR issue je oddělené, aby plaintext nebyl v replay ledgeru.
- [ ] Jméno, příjmení, e-mail a explicitní pohlaví jsou povinné; group a
      accommodation jsou volitelné, serverově occasion-scoped a neprivilegované.
- [ ] Exact-name warning je case/diacritics-insensitive, bounded a maskovaný;
      partial/fuzzy dotazy ani obecný roster recepční nedostane.
- [ ] QR payload neobsahuje identitu/heslo/session a plaintext není persistován
      ani logován.
- [ ] Rotace, revoke, membership delete a feature disable blokují nový login.
- [ ] Recepční může do 30 minut zrušit jen svou registraci; cancel nejdřív
      odebere membership/QR a potom globálně revokuje refresh sessions s retry.
- [ ] S původním neexpirovaným access JWT po cancel neprojde žádný private root
      ani participant write dané occasion; veřejný anon-equivalent obsah je jediná
      záměrná výjimka.
- [ ] Login scanner přijímá pouze verzovaný reception payload a vytváří stejnou
      session finalizaci jako password login.
- [ ] Ticket/profile UUID QR zůstává výhradně entry contract a login jej odmítá.
- [ ] Targeted SQL, Deno a Flutter standard checks projdou.
- [ ] Produkční migration/deploy/feature enable jsou buď schváleně provedeny,
      nebo přesně uvedeny jako pending; commit/push se bez pověření neprovádí.

## Residual risks

- Fyzicky zkopírovaný QR umožní přihlášení až do rotace/revoke; jde o záměrný
  password-equivalent trade-off opakovaně použitelného průkazu.
- Rotace QR neruší již vydané sessions. Cancel zruší refresh sessions, ale
  standardní Supabase sign-out neumí anulovat už vydaný access JWT před `exp`;
  okamžité omezení Festapp dat proto závisí na odstranění occasion membership.
- Exact-name kandidáti jsou omezený únik osobních údajů oprávněné recepci.
  Riziko je zmenšeno požadavkem celé shody, maskováním, limitem výsledků a
  absencí obecného vyhledávacího endpointu.
- Jednoduché ubytování nekontroluje ani nerezervuje konkrétní inventory kapacitu;
  pokud má být recepce autoritou i pro lůžka/spoty, je to samostatná kapacitní
  feature a command, nikoli bezpečný implicitní doplněk tohoto plánu.
- Rozpracovaný worktree se překrývá s několika plánovanými soubory, takže
  implementace vyžaduje opatrné sloučení a cílené testy obou feature sad.
