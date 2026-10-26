# Společníci: oddělené capabilities a administrátorské přiřazení účastníků

Date: 2026-08-05
Status: Ready for execution
Verification: standard

## Outcome

Feature `companions` zůstane jednou occasion-level feature, ale bude mít dvě
nezávislé capabilities:

1. uživatel si smí vytvořit nový technický účet společníka;
2. administrátor smí přiřadit existujícího účastníka jinému účastníkovi jako
   společníka.

Přihlášený vlastník pak z jednoho zařízení spravuje program svůj i svých
společníků. Každý společník zůstává samostatným účastníkem se svou skupinkou,
profilem a programovými rezervacemi. Administrátorské odpojení pouze odstraní
vazbu; nikdy nesmaže existující uživatelský účet, skupinku ani účast na akci.

Participantské vstupy jsou rozdělené podle účelu. Vytvoření technického
společníka patří výhradně do správy profilu a je dostupné jen při
`allow_user_create`. Akce nad programem společníka patří k programu/události a
vidí ji jen přihlášený vlastník, jehož aktuální privátní projekce obsahuje
alespoň jednoho společníka. Samotné zapnutí feature tedy nikdy nezobrazí
companion tlačítko všem účastníkům.

Administrátor při výběru a kontrole vazby vždy vidí celé jméno, kontaktní e-mail
a aktuální standardní skupinku. Účastnické UI zobrazuje celé jméno a skupinku,
ale nepotřebuje ukazovat e-mail. Skupinka se čte kanonicky z `user_groups` a
`user_group_info`; nekopíruje se do vazby společníka.

Pozorovatelný cílový stav pro CSM Ostrava 2026 je:

- `companions.is_enabled = true`;
- `allow_user_create = false`;
- `allow_admin_assign = true`;
- `max_companions = 1` (jeden přihlášený účastník může ovládat program jednoho
  dalšího účastníka; změna limitu zůstává konfigurovatelná);
- administrátor může z existujících účastníků přiřadit vlastníka ze skupinky
  `DISK 19` ke společníkovi ze skupinky `DISK 44` a obě skupinky jsou v dialogu
  zřetelné;
- přihlášený vlastník vidí společníka se skupinkou a může jej přihlásit nebo
  odhlásit z programové události;
- vlastník nemůže administrátorsky přiřazeného účastníka odpojit ani smazat.

## Scope

### In scope

- JSON konfigurace `occasions.features` pro `companions` a její administrační
  formulář.
- Occasion-scoped datový model vazby vlastník–společník v
  `public.user_companions`.
- Vytváření a mazání uživatelem vytvořených technických společníků.
- Administrátorské přiřazení a odpojení existujících occasion participants.
- Server-side feature a permission gates pro vytvoření, přiřazení, odpojení,
  smazání a správu programové účasti.
- Admin záložka Uživatelé: výběr vlastníka, kandidáti, skupinky a stav vazby.
- Participant UI: celé jméno, skupinka, původ vazby a bezpečné dostupné akce.
- Legacy i client-sync v1 čtecí a zapisovací adaptéry nad jedním kanonickým
  doménovým rozhodnutím.
- Offline-first projekce, identity isolation, atomické cache replacement a
  přesně vymezené online-only command chování.
- Private-profile invalidace při změně vazby, programu, jména nebo skupinky
  společníka.
- Migrace, testy, dokumentace, rollout a odstranění globálních/nebezpečných cest.

### Out of scope

- Vstupenky, objednávky, produkty, náramky a skenování.
- Změna skupinky během přiřazování společníka.
- Sdílení hesla, přepínání autentizovaných Supabase session nebo přihlášení jako
  jiný účet.
- Vytváření samostatného „rodičovského“ účtu, který není participantem occasion.
- Více vlastníků jednoho společníka v rámci stejné occasion.
- Vnořené vztahy (společník dalšího účastníka současně vlastní jiné společníky).
- Změna obecných pravidel kapacity, časových kolizí, exkluzivity nebo counseling
  limitů; tato pravidla se dál vyhodnocují pro cílové participant ID.
- Produkční migrace, deploy, změna feature konfigurace a konkrétní přiřazení
  reálných účtů bez samostatného oprávnění.

## Constraints

- Business rozhodnutí patří do explicitních SQL RPC; neimplementovat persistentní
  aplikační trigger.
- Každá `SECURITY DEFINER` funkce musí být v `public`, mít bezpečný `search_path`
  a explicitně kontrolovat actor, occasion, feature capability a membership.
- Feature konfigurace je per occasion a zůstává jedním JSON prvkem s kódem
  `companions`; nevytvářet druhý feature kód.
- `is_enabled` je master gate. Dílčí capabilities nemají účinek, pokud je master
  gate vypnutý.
- Chybějící nové klíče ve starém JSON musí zachovat vydané chování:
  `allow_user_create = true`, `allow_admin_assign = false`.
- `max_companions` omezuje celkový počet aktivních přímých vazeb vlastníka v dané
  occasion bez ohledu na jejich původ. Výchozí hodnota je `1`.
- `anon` ani `authenticated` nesmí mít na `user_companions` žádná table
  privileges, včetně `TRUNCATE`, `TRIGGER`, `REFERENCES` a `SELECT`; reads i
  writes vlastní permission-checked RPC/projections.
- Oba účastníci vazby musí být členy stejné occasion. Vazba se nikdy nesmí
  automaticky použít v jiné occasion.
- Jedna osoba smí mít v jedné occasion nejvýše jednoho vlastníka; vlastník nesmí
  být sám společníkem a společník nesmí vlastnit další společníky.
- Skupinka je live projection z `user_groups`/`user_group_info` s
  `user_group_info.type IS NULL`. Prázdná skupinka se zobrazuje jako
  „Bez skupinky“; více standardních skupinek se zobrazí jako seřazený seznam a
  nezamlčí se.
- Admin roster musí zůstat set-based. Nepřidávat per-user correlated/LATERAL
  dotazy do `get_occasion_users_for_edit`.
- Současný working tree obsahuje nesouvisející změny mimo tento plán, včetně
  `user_page.dart` a schedule souborů. Implementace je musí zachovat a změny
  skládat minimálně kolem existující práce.
- Live-data target se vždy odvozuje z `SUPABASE_URL` v
  `automation/project.conf` a ověřuje přes `FORCE_OCCASION_LINK`; `.env.local`
  neurčuje cílový projekt.
- V client-sync v1 je cached `occasion_config` jediný klientský zdroj feature
  policy a identity-scoped `private_profile` jediný klientský zdroj vlastnictví
  a seznamu společníků. Participant UI nesmí kvůli visibility tlačítka dělat
  přímý online dotaz ani držet druhou persistentní companion cache.
- Lifecycle a attendance mutations jsou online-only a nequeueují se
  optimisticky. Offline klient smí zobrazit poslední atomicky aktivovanou
  projekci, ale nesmí lokálně předstírat přiřazení, odpojení ani změnu programu.

## Current-state evidence

| Claim | Evidence | Consequence |
|---|---|---|
| Feature systém používá master `is_enabled` a subtype fields v jednom JSON prvku. | `lib/components/features/feature.dart`, `services_feature.dart`, `feature_form.dart` | Společníci dostanou dvě podvolby, nikoli dva feature kódy. |
| Dnešní `CompanionsFeature` ukládá pouze `max_companions`. | `lib/components/features/companion_feature.dart`, `feature_constants.dart` | Je nutné doplnit typed parsing, serialization, UI a explicitní backward defaults. |
| Uživatel si dnes sám vytváří společníka jen jménem a UI vždy nabízí smazání. | `lib/components/users/companion/companion_dialog.dart:_createCompanion/_deleteCompanion` | UI musí respektovat původ vazby a capabilities. |
| Self-create zakládá nový Auth/user_info/occasion_users účet a globální vazbu. | `database/functions/users/create_companion_in_organization.sql` | Původ vazby musí být uložen; self-created lifecycle se nesmí zaměnit s existujícím participantem. |
| `user_companions` není occasion-scoped a nemá původ ani autora. | `database/tables/tables.sql:public.user_companions` | Přidat `occasion`, `origin`, `created_by` a relační invarianty. |
| Současný v1 delete maže celý Auth účet a související data. | `supabase/migrations/20260802234000_client_sync_v1_expansion.sql:delete_companion_client_sync_v1` | Admin-assigned vztah nikdy nesmí tuto cestu použít. |
| Attendance autorizuje vztah bez occasion filtru. | `set_event_attendance_client_sync_v1`, `sign_user_to_event`, `sign_user_out_of_event` | Všechny kontroly musí zahrnout event occasion a enabled master gate. |
| Private profile obsahuje companion list a attendance invaliduje profil vlastníka. | `get_private_profile_payload_v1`, `set_event_attendance_client_sync_v1` | Projekce se rozšíří o surname/group/origin a invalidace musí pokrýt další změny. |
| Client-sync ukládá `occasion_config` v public scope, `private_profile` v identity scope a po aktivaci mění `ClientSyncRuntime.projectionEpoch`. | `client_sync_protocol.dart`, `client_sync_runtime.dart`, `client_sync_projection.dart` | Feature gate se čte z public projekce, ownership z private projekce a UI musí reagovat na replacement bez restartu. |
| Změna identity maže předchozí private scope a zvyšuje identity epoch. | `ClientSyncRuntime.identityChanged()` | Companion data ani tlačítka předchozího uživatele nesmí po logout/login nebo offline restore prosáknout další identitě. |
| Event, schedule a my-schedule dnes otevírají jeden dialog, který zároveň vytváří, maže a mění attendance. | `event_page.dart`, `schedule_page.dart`, `my_schedule_page.dart`, `companion_dialog.dart` | Lifecycle management se oddělí do profilu; event dialog bude pracovat jen s existujícími vztahy. |
| Timeline companion button dnes kontroluje jen login, podporu sign-in a master feature. | `advanced_timeline_day_list.dart:_shouldShowCompanionButton` | Přidat derived `hasOwnedCompanions` z private profile; uživatel bez vztahu tlačítko neuvidí. |
| Admin roster už set-based agreguje standardní skupinky do `group_title`. | `database/functions/users/get_occasion_users_for_edit.sql:standard_groups` | Kandidátní dialog může použít existující kanonický údaj bez CSV nebo nového dotazu na skupiny. |
| Flutter model admin řádku už obsahuje `groupTitle`. | `lib/components/users/occasion_user_model.dart`, `users_tab.dart` | Doplní se owner/origin metadata; skupinka se pouze prezentuje. |
| Client má legacy a v1 adaptéry. | `lib/components/users/companion/db_companions.dart`, `companion_commands.dart`, `ClientSyncRuntime.isV1Selected` | Oba runtime režimy musí vést ke stejným doménovým invariantům. |
| Companion v1 kernel a RPC jsou 2026-08-05 přítomné v produkci, ale capability selection je samostatný rollout gate. | Read-only `pg_catalog` kontrola projektu/occasion odvozených z `automation/project.conf` | Nová overlay migrace smí rozšířit v1, ale nesmí sama zapnout client-sync ani feature. |
| CSM occasion má feature `{is_enabled:false,max_companions:1}` a nulový počet vazeb. | Read-only kontrola occasion `FORCE_OCCASION_LINK=csmostrava2026` dne 2026-08-05 | Produkční rollout může začít bez companion dat; zapnutí a reálné přiřazení jsou oddělené kroky. |
| Zdrojové skupinky dvou cílových účastníků existují i v DB jako `DISK 19` a `DISK 44`. | Read-only join `user_groups` → `user_group_info` na správném projektu | Acceptance smoke musí ověřit zobrazení obou skupinek, ne odvozování z e-mailu. |
| Produkční schema obsahuje drift-only `create_companion(bigint,uuid,text)`, který důvěřuje caller-supplied `usr` a je executable pro `authenticated`. | Read-only `pg_proc` + `pg_get_functiondef` kontrola 2026-08-05; v repo je pouze security-lint `ALTER FUNCTION`, ne source definition. | Overlay migrace jej musí explicitně dropnout; nestačí opravit source files. |
| `anon` a `authenticated` mají na `user_companions` mimo jiné `SELECT`, `REFERENCES`, `TRIGGER` a `TRUNCATE`. | Read-only `information_schema.role_table_grants` kontrola 2026-08-05. | Revokovat všechna table privileges pro client roles a smluvně hlídat zejména TRUNCATE. |

Representative flow dnes:

1. `FeatureService.isFeatureEnabled('companions')` zobrazí companion tlačítka.
2. `CompanionDialog` zavolá `DbCompanions.create(name)` nebo `delete`.
3. Legacy režim volá `create_companion_in_organization`/`delete_user`; v1 volá
   typed receipted commands.
4. `get_user_companions_data` nebo private-profile projection vrátí jméno a
   event IDs.
5. `DbCompanions.signIn/signOut` předá companion ID attendance modulu.
6. SQL attendance povolí actorovi operaci, pokud existuje globální dvojice v
   `user_companions`.

Největší současný problém není UI, ale smíšení tří rozhodnutí v jedné globální
vazbě: scope, původ účtu a delete lifecycle.

## Target architecture and invariants

### Canonical owner and contract

Kanonickým vlastníkem rozhodnutí bude SQL companion lifecycle modul nad
`public.user_companions`. Vnější interface tvoří čtyři explicitní intenty:

- `create_companion_client_sync_v1(p_occasion, p_name, p_command_id)` —
  participant vytvoří technický účet; vyžaduje `allow_user_create`;
- `delete_owned_companion_client_sync_v1(p_occasion, p_companion,
  p_command_id)` — vlastník smaže pouze `origin=self_created` účet;
- `assign_existing_companion_client_sync_v1(p_occasion, p_owner, p_companion,
  p_command_id)` — manager/admin připojí existujícího participant usera;
- `unassign_existing_companion_client_sync_v1(p_occasion, p_owner,
  p_companion, p_command_id)` — manager/admin odstraní pouze vazbu
  `origin=admin_assigned`.

V1 commands jsou idempotentní přes `p_command_id`, auditované a vracejí
private-profile replacements pro dotčené vlastníky. Legacy RPC jsou pouze
occasion-aware adaptéry nad stejnými interními implementačními funkcemi; nesmí
duplikovat feature, permission, max-count ani lifecycle rozhodnutí.

Interní SQL interface:

- `get_companion_feature_policy_v1(p_occasion)` vrátí normalizované
  `{is_enabled, allow_user_create, allow_admin_assign, max_companions}`;
- `check_companion_relation_invariants_v1(...)` nebo ekvivalentní jedna interní
  implementace uzamkne vlastníka i cílového participanta, ověří membership,
  limit, uniqueness a zákaz chain/cycle;
- interní create/assign/unassign/delete implementace provedou jednu transakci;
  klient neskládá DML ani více RPC.

`public.user_companions` v cíli:

```text
occasion    bigint      NOT NULL
user        uuid        NOT NULL   -- vlastník/controller
companion   uuid        NOT NULL   -- spravovaný participant
origin      text        NOT NULL   -- self_created | admin_assigned
created_by  uuid        NULL
created_at  timestamptz NOT NULL DEFAULT now()

PRIMARY KEY (occasion, user, companion)
UNIQUE (occasion, companion)
CHECK (user <> companion)
CHECK (origin IN ('self_created', 'admin_assigned'))
FOREIGN KEY (occasion, user)
  REFERENCES occasion_users(occasion, user) ON DELETE CASCADE
FOREIGN KEY (occasion, companion)
  REFERENCES occasion_users(occasion, user) ON DELETE CASCADE
FOREIGN KEY (created_by)
  REFERENCES user_info(id) ON DELETE SET NULL
```

Skupinka se do tabulky nepřidává. Admin roster a private profile ji sestavují
z aktuálních `user_groups` a `user_group_info`.

Flutter companion module prezentuje malý typed interface:

```text
CompanionModel:
  id, name, surname, groupTitle, origin, eventIds, canOwnerDelete

ParticipantCompanionCommands:
  createSelf(occasionId, name)
  deleteSelf(occasionId, companionId)

AdminCompanionCommands:
  assignExisting(occasionId, ownerId, companionId)
  unassignExisting(occasionId, ownerId, companionId)
```

`FeatureService` poskytne typed getters, aby callers neinterpretovali JSON:

- `getCompanionsFeature(...)`;
- `isCompanionsEnabled(...)`;
- `allowsUserCompanionCreation(...)`;
- `allowsAdminCompanionAssignment(...)`;
- `getMaxCompanions(...)`.

### Invariants

1. Každá vazba patří přesně jedné occasion a oba účty jsou jejími participanty.
2. Disabled master feature znemožní create, assign i attendance správu cizího
   participant ID; data zůstanou zachována pro pozdější opětovné zapnutí.
3. `allow_user_create=false` zakáže self-create v UI i SQL.
4. `allow_admin_assign=false` zakáže admin UI i SQL assignment commands.
5. `max_companions` se kontroluje pod occasion+owner lockem proti všem původům.
6. Společník má v jedné occasion nejvýše jednoho vlastníka.
7. Vztahový graf má hloubku jedna: žádné self-linky, cykly ani chainy.
8. Admin assignment nemění profil, e-mail, heslo, skupinku, program ani
   occasion membership žádného účtu.
9. Admin unassignment maže pouze řádek vazby.
10. Participant deletion smí odstranit Auth/profile data pouze u
    `origin=self_created` a pouze přes explicitní self-created delete command.
11. Starý klient, který se pokusí smazat `admin_assigned` účet, dostane bezpečné
    rejected response; účet ani vazba se nezmění.
12. Attendance command ověřuje relation occasion proti occasion cílové události
    a všechna stávající kapacitní/časová/exkluzivní pravidla vyhodnocuje pro
    `p_participant_id`.
13. Jméno a skupinka ve companion UI jsou živá data. Změna profilu nebo standardní
    skupinky invaliduje private profile vlastníka.
14. Admin výběr vždy zobrazuje jméno, příjmení, e-mail a skupinku; participant UI
    zobrazuje jméno, příjmení a skupinku, nikoli kontaktní e-mail.
15. `anon` ani `authenticated` nemá žádné table privilege na
    `user_companions` (`SELECT/INSERT/UPDATE/DELETE/TRUNCATE/TRIGGER/REFERENCES`);
    RLS zůstává zapnuté a veškerý přístup vlastní explicitní RPC/projections.
16. Žádný persistentní trigger nekóduje feature, permission, lifecycle ani
    invalidation rozhodnutí.
17. `occasion_config` a `private_profile` se aktivují jako úplné replacementy,
    ne merge po jednotlivých companions. Unassign proto odstraní companion i
    jeho odvozený program ze zobrazení bez ručního cache purge.
18. Companion data jsou private-identity data. Logout, změna uživatele nebo
    změna occasion nesmí ponechat viditelnost vztahu z předchozího private scope.
19. Admin command nesmí vložit ownerův private payload do cache přihlášeného
    admina. Zapíše owner impact/head; admin reloadne editor roster a owner získá
    novou `private_profile` při nejbližším private sync refreshi.
20. Participant command, jehož actor je zároveň owner, smí vrátit a atomicky
    aktivovat vlastní private replacement. Po aktivaci se UI přepočítá přes
    `projectionEpoch`; nečeká na restart ani relogin.

### Offline-first ownership and delivery

| Data/intent | Canonical client source | Offline behavior | Invalidation/delivery |
|---|---|---|---|
| Master gate, sub-capabilities, limit | cached public `occasion_config` | poslední atomicky aktivovaná config projekce | změna feature zvýší `occasion_config`; nový manifest nahradí celý payload |
| Ownerův companion list, identity, groups, origin, attendance IDs | identity-scoped `private_profile` | lze číst a zobrazit; nesmí se doplňovat přímým table/RPC readem jen pro UI visibility | create/delete/assign/unassign, companion profile/group změna a attendance zvýší owner `private_profile` |
| Companion program detail | public `program_catalog` + owner `private_profile` event IDs; cílové private sign-ins zůstávají serverovým command stavem | poslední konzistentní projekce je čitelná | attendance atomicky impactuje owner `private_profile`, target `private_program` a `live_public` |
| Admin roster a assignment editor | online editor bundle | při offline stavu nepřístupné/disabled se standardní hláškou | po commandu reload jednoho set-based roster bundle; žádná admin-side kopie owner private payloadu |
| Lifecycle/attendance command | explicitní online RPC | disabled při offline; žádná offline queue ani optimistic relation write | applied response aktivuje jen payloady, ke kterým má actor právo; rejection zachová poslední aktivní generaci a vyžádá refresh |

`ClientSyncProjection.companions()` zůstává jediný překlad private JSON do
`CompanionModel`. UI, `AuthService` ani `DbCompanions` nesmí držet druhý
dlouhodobý seznam, podle kterého by se po identity/config změně rozhodovalo o
visibility. Obrazovky s companion akcemi poslouchají existující projection
epoch/profile reload seam a znovu odvodí `hasOwnedCompanions`.

Feature disable data nemaže. Cached private profile může vazbu nadále obsahovat,
ale participantské vstupy se skryjí přes master gate z `occasion_config`.
Opětovné zapnutí je zviditelní bez rekonstrukce vztahu. Aplikace nevyžaduje
Realtime ani push; owner se k adminem provedené změně dostane standardním
foreground/private refresh mechanismem.

### UI placement and visibility matrix

| Surface | Action | Visibility | Explicitly forbidden |
|---|---|---|---|
| Profil / Správa společníků | „Vytvořit společníka“ | přihlášený occasion participant, master enabled, `allow_user_create=true`, owner je pod limitem; může být vidět i při nule vztahů, protože je to vstup k prvnímu vytvoření | event card/dialog; admin-only occasion; uživatel nad limitem |
| Profil | karty aktuálních společníků | master enabled a ownerův `private_profile.companions` není prázdný | prázdná sekce pro všechny účastníky; seznam cizích vazeb |
| Událost, Program, Můj program | „Program společníků“ / přihlásit či odhlásit konkrétního společníka | master enabled, login, event podporuje sign-in a `hasOwnedCompanions=true` z private profile | pouhé `is_enabled`; create/delete input; uživatel bez společníka |
| Admin → Uživatelé | „Spravovat společníky“ | `allow_admin_assign=true`, manager/admin update právo a přesně jeden vybraný owner row | participant profil/program; admin bez práva; nula nebo více owner selections |

Event companion dialog je attendance-only: ukáže pouze existující společníky a
jejich programový stav. Self-created delete je v profilové správě a jen pro
`origin=self_created`; admin-assigned vazba nemá v participant UI žádné
odpojení. Tím se slovem „přidat“ nesměšuje založení účtu, admin assignment a
přihlášení na událost.

Implementačně použít dva zřetelné widget contracts (například
`CompanionManagementDialog` a `CompanionAttendanceDialog`), ne jeden dialog s
volitelným `eventId` a skrytými mode flags. Schedule obrazovka načte ownerův
companion projection jednou na úrovni controller/page state a předá
`hasOwnedCompanions` všem event cards; nesmí kvůli každé kartě nebo každému
build volat private RPC/projection read.

### Entry points and forbidden bypasses

Povolené vstupy:

- Occasion feature editor přes `save_occasion_client_sync_v1`.
- Participant companion dialog přes participant command adapter.
- Admin Users tab přes admin command adapter.
- Event attendance přes stávající attendance module s occasion-scoped relation
  checkem.
- Account/occasion deletion přes existující explicitní deletion workflows,
  rozšířené o relation cleanup a owner invalidation.

Zakázané cesty:

- přímé DML z Dart/JS do `user_companions`;
- globální lookup vztahu pouze podle `(user, companion)`;
- admin assignment implementovaný vytvořením nového účtu;
- unassignment přes `delete_user` nebo account-deletion module;
- odvozování identity podle e-mailového prefixu, přihlašovacího kódu nebo CSV;
- kopie `group_title` v relation row;
- UI-only feature gate bez server-side kontroly;
- generický mutation dispatcher.

## Decisions, assumptions, and blockers

### Decisions

- **D1:** Jedna feature, dvě podřízené capabilities. Odpovídá existujícímu
  `ServicesFeature` vzoru a zachovává jeden master gate.
- **D2:** JSON klíče jsou `allow_user_create` a `allow_admin_assign`. Jsou krátké,
  explicitní a mapují přímo na product rozhodnutí.
- **D3:** Chybějící klíče zachovají staré chování (`true/false`), aby existující
  enabled occasion nepřišla o self-create a nezískala admin assignment.
- **D4:** Limit se počítá přes všechny aktivní přímé vazby. UI a server tak
  používají jednu srozumitelnou hodnotu.
- **D5:** Jedna osoba má v occasion nejvýše jednoho vlastníka a vztahy se
  neřetězí. Zabrání to nejasnému oprávnění a nekonečným/cyklickým projekcím.
- **D6:** Admin dialog pracuje nad už načteným occasion roster bundlem. SQL roster
  se rozšíří set-based o owner/origin metadata; nevznikne další 6k-user request.
- **D7:** Skupinka je informační live field, ne součást assignment command.
- **D8:** Admin-assigned vazbu může odstranit pouze manager/admin. Participant ji
  může používat pro program, ale nemůže ji měnit.
- **D9:** Self-created a admin-assigned lifecycle mají explicitně rozdílné delete
  intenty. Žádná funkce rozhodující podle existence samotné vazby nesmí mazat
  účet.
- **D10:** Legacy režim je podporovaný adapter, ne druhá business implementace,
  dokud occasion capability nepřejde na v1. Neoccasion-aware legacy overloady
  se odstraní.
- **D11:** CSM se zapne až po server migration a nasazení podporovaného klienta.
  Staré klienty chrání SQL rejection, ale nejsou považovány za plnohodnotné UI.
- **D12:** Schedule tlačítko se odvozuje z master gate a neprázdného owner
  companion listu v private profile, nikoli jen z feature enablement.
- **D13:** Self-create management je v profilu; event dialog je attendance-only.
  Uživatel bez vztahu proto v admin-only konfiguraci neuvidí žádný companion
  vstup, zatímco self-create occasion stále umožní založit první vztah z profilu.
- **D14:** Relation a attendance writes se offline nequeueují. Server musí pod
  lockem vyhodnotit aktuální membership, capability, limit a konkurenci.
- **D15:** Admin assignment invaliduje privátní projekci ownera, ale odpověď
  adminovi neprozradí ani neaktivuje cizí private payload.

### Assumptions

- **A1:** Pro požadovaný shared-device scénář stačí participant účet jako
  vlastník dalšího participant účtu; samostatný guardian-only účet není potřeba.
  Impact if false: datový model `occasion_users` by potřeboval nový non-participant
  controller role. Resolve by: product decision před rozšířením scope.
- **A2:** Standardní skupinka je `user_group_info.type IS NULL`, shodně s admin
  rosterem. Impact if false: dialog by mohl ukazovat nesprávný druh skupiny.
  Resolve by: potvrdit proti Users/Groups UI před implementací widgetu.
- **A3:** Všechny podporované CSM clients lze aktualizovat před zapnutím feature.
  Impact if false: starší klient ukáže self-create/delete prvky, které server
  bezpečně odmítne. Resolve by: release gate a kontrola distribuované verze.
- **A4:** Mimo CSM mohou existovat staré relation rows. Impact: přidání NOT NULL
  occasion může selhat. Resolve by: před migration provést klasifikační query a
  požadovat právě jednu společnou occasion pro owner+companion; nejednoznačné
  řádky jsou blocker, ne automatické smazání.

### Blockers

- Žádný implementační blocker.
- Produkční migrace, deploy, zapnutí feature a přiřazení konkrétních účtů
  vyžadují samostatné oprávnění.
- Pokud preflight na libovolném cílovém projektu najde starou vazbu bez právě
  jedné společné occasion, contraction migrace se nesmí aplikovat, dokud není
  vztah ručně klasifikovaný vlastníkem dat.

## Deletion ledger

| Artifact | Current role | Final action | Removal proof |
|---|---|---|---|
| Globální PK `user_companions(user, companion)` | Ukládá vztah bez scope. | Nahradit PK `(occasion,user,companion)` a unique `(occasion,companion)`. | `information_schema`/pg constraint assertions. |
| Relation rows bez `origin` | Self-created a future existing users jsou nerozlišitelní. | Backfill jako `self_created`; nové assignmenty zapisují explicitní origin. | `origin IS NULL` count = 0 a CHECK constraint. |
| `get_user_companions_data()` bez occasion parametru | Legacy globální reader. | Nahradit `get_user_companions_data(p_occasion)`; drop no-arg overload po caller migration. | `to_regprocedure('...()') IS NULL`; rg absence. |
| `create_companion_in_organization(org,oc,usr,name)` důvěřující `usr` | Released legacy writer. | Facade musí vyžadovat `usr=auth.uid()` a volat canonical self-create; po telemetry/cutover odstranit nebezpečný caller parametr nebo celý overload. | SQL auth test a function-definition assertion. |
| Drift-only `create_companion(bigint,uuid,text)` | Produkční RPC mimo současný source tree; dovoluje caller-supplied ownera. | Explicitně `DROP FUNCTION public.create_companion(bigint,uuid,text)` v overlay migraci; neobnovovat alias. | `to_regprocedure(...) IS NULL` v contract testu a production post-checku. |
| `delete_user(usr,oc)` jako companion delete | Maže účet na základě existence globální vazby. | Odstranit companion caller; account deletion zůstane samostatný workflow. Drop facade, pokud nemá jiné callers. | `rg` nenajde caller; `to_regprocedure` podle finálního caller map. |
| `DbUsers.deleteUser` z companion modulu | Legacy UI cesta k account delete. | Nahradit explicitním `deleteSelf`; z companion modulu odstranit import/call. | `rg "DbUsers.deleteUser" lib/components/users/companion` prázdné. |
| `delete_companion_client_sync_v1` nevyjadřující původ | Maže celý účet. | Přejmenovat/nahradit `delete_owned_companion_client_sync_v1`; starý název dočasně pouze safe facade, která odmítne admin origin, poté drop. | SQL tests obou originů + absence po cutover gate. |
| Unscoped relation checks v attendance a user RPC | Propůjčují oprávnění napříč occasions. | Všechny joiny doplnit o target occasion a master feature gate. | `rg` + SQL cross-occasion negative tests. |
| Companion UI unconditional create/delete | Nerozlišuje capabilities ani origin. | Renderovat create pouze pro allowed self-create; delete pouze pro self-created ownership. | Widget tests. |
| Companion model pouze `id,name,event_ids` | Neumí surname/group/origin. | Rozšířit typed model; odstranit ad-hoc string rendering. | Model/projection tests. |
| Private profile bez group/origin | Neřekne skupinku ani lifecycle. | Rozšířit canonical payload a projection parser. | SQL JSON contract + Dart parser test. |
| Roster bez relation metadata | Admin nevidí existující přiřazení. | Set-based `companion_owners` CTE a read-only owner/origin fields. | Editor bundle SQL test a grid model test. |
| Stará lokalizace o náramku/vstupu | Mimo scope a matoucí pro CSM. | Nahradit neutrálním popisem správy osoby bez vlastního zařízení; doplnit admin/group/attach/detach copy ve všech podporovaných jazycích. | Translation key parity check; žádný starý text v rg. |
| Client-sync source registry writer list bez admin assign/unassign | Neúplný canonical writer inventory. | Přidat nové explicitní writers a updated relation columns. | Registry checker a contract SQL. |
| Client-role table grants na `user_companions` | Obsahují i `TRUNCATE`/`TRIGGER` a obcházejí zamýšlený RPC seam. | `REVOKE ALL ON TABLE public.user_companions FROM PUBLIC, anon, authenticated`; žádný direct grant nevracet. | `has_table_privilege` assertions pro všechny privileges. |

## Implementation waves

### Wave 1 — Typed feature policy a schema expansion

**Goal**

Získat jednoznačný konfigurační kontrakt a occasion-scoped persistence ještě bez
zapnutí feature nebo změny participant UI.

**Changes**

- `lib/components/features/feature_constants.dart` — přidat
  `companionsAllowUserCreate = 'allow_user_create'` a
  `companionsAllowAdminAssign = 'allow_admin_assign'`.
- `lib/components/features/companion_feature.dart` — přidat non-null bool fields,
  backward defaults, JSON serialization a dva checkboxy pod master feature.
- `lib/components/features/feature_service.dart` — přidat typed getters; callers
  nesmí číst raw JSON.
- `lib/components/features/features_strings.dart` a `assets/translations/*.json`
  — popsat master feature, obě capabilities, limit a bezskupinkový stav.
- `database/tables/tables.sql` — aktualizovat cílovou definici
  `user_companions`.
- Nová overlay migrace v `supabase/migrations/` — přidat nullable columns,
  preflight/backfill, constrainty, composite foreign keys, nový PK/unique a RLS
  assertions. Neupravovat již aplikovanou expanzní migraci z 2026-08-02.
- V overlay migraci explicitně dropnout drift-only
  `public.create_companion(bigint,uuid,text)` a revokovat všechna table
  privileges na `public.user_companions` od `PUBLIC`, `anon` a `authenticated`.
- Přidat internal `get_companion_feature_policy_v1(p_occasion)` s revoked direct
  execution pro client roles.

**Migration/deletion**

- Backfill každé staré vazby na jedinou společnou occasion ownera a companion.
- Backfill `origin='self_created'`, `created_by=user`.
- Pokud není společná occasion právě jedna, migrace vyhodí popisnou výjimku před
  constraint contraction; nic nemaže.
- Po backfillu nahradit globální PK a zakázat NULL hodnoty.

**Failure and compatibility**

- Feature JSON bez nových keys zachová staré chování.
- Schema je additive až do úspěšného backfillu; migration musí být transakční.
- Žádný config update na produkci v této vlně.

**Validation**

- Nový Dart test `test/components/features/companion_feature_test.dart` — old JSON,
  new JSON, master/sub-capability gating, round-trip a defaults.
- Nový SQL test `database/tests/companion_contract_test.sql` — columns,
  constraints, RLS, žádná client-role table privileges (včetně TRUNCATE),
  absence drift RPC a deterministic backfill fixture.
- `git diff --check` pro změněné soubory.

**Exit condition**

Jedna typed policy existuje v Dart i SQL, všechny relation rows mají occasion a
origin a žádný enabled stav se produkčně nezměnil.

### Wave 2 — Kanonické lifecycle commands a authorization

**Goal**

Všechny writes a attendance oprávnění respektují occasion, capability, origin a
transakční invarianty.

**Changes**

- Přidat interní SQL implementation helpers pro self-create, self-delete,
  admin-assign a admin-unassign. Helpers nejsou executable pro client roles.
- Pro owner a companion získat participant advisory locks v lexikografickém
  pořadí UUID v rámci occasion; teprve poté ověřit limit, unique owner, no-self
  a no-chain. Tím se serializují i souběžné `A→B`/`B→A` pokusy bez deadlocku.
- `create_companion_client_sync_v1` — použít policy helper, explicitní actor
  membership a zapisovat `origin=self_created`, `created_by=actor`.
- Přidat `delete_owned_companion_client_sync_v1` — odmítnout jiný origin a
  cross-occasion membership; zachovat idempotency/audit/private replacements.
- Přidat `assign_existing_companion_client_sync_v1` a
  `unassign_existing_companion_client_sync_v1` — manager/admin only,
  `allow_admin_assign`, oba existing occasion members, žádný account/profile/group
  side effect.
- Aktualizovat legacy RPC v `database/functions/users/` na occasion-aware thin
  facades nad stejnými helpers. `usr` nikdy nesmí určit jiného actora.
- Aktualizovat `set_event_attendance_client_sync_v1`, `sign_user_to_event.sql` a
  `sign_user_out_of_event.sql`: relation join přes event occasion + enabled
  policy. Neměnit kapacitní a programová error codes.
- Aktualizovat `delete_occasion_user_client_sync_v1`, account deletion contract a
  occasion deletion cleanup tak, aby cascade relation invalidovala profil
  vlastníka ještě před odstraněním řádku.
- Aktualizovat `client_sync_component_sources` pro columns/writers a companion
  audit entity names.

**Migration/deletion**

- Odstranit companion caller na generic `delete_user`.
- Starý `delete_companion_client_sync_v1` může v jedné vydané kompatibilní fázi
  volat pouze self-delete a musí admin origin odmítnout; finální contraction jej
  dropne po client caller migraci.

**Failure and compatibility**

- Repeated assign stejné trojice vrátí `unchanged`; target s jiným ownerem vrátí
  conflict/rejected bez přepsání.
- Souběžné assignmenty stejného targetu nemohou oba uspět.
- Disabled feature pouze zablokuje používání/změnu vazby; nemaže data.
- Old client delete proti admin-assigned origin nesmí nic změnit.

**Validation**

- Rozšířit `database/tests/companion_contract_test.sql` o positive/negative auth,
  oba flags, limit, cross-occasion, self/cycle/chain, duplicate/retry, origin-safe
  delete/unassign, disabled attendance a owner invalidation.
- Rozšířit `database/tests/client_sync_v1_contract_test.sql` o nové command names,
  grants, registry writers a occasion-scoped function-definition assertions.
- Spustit pouze proti izolované Supabase/Postgres test DB:
  `node web_client/scripts/run_db_tests.js database/tests/companion_contract_test.sql`.

**Exit condition**

Neexistuje serverová cesta, která by založila, přiřadila, použila nebo smazala
companion relation bez správné occasion, capability a origin kontroly.

### Wave 3 — Čtecí projekce, skupinky a invalidace

**Goal**

Admin i participant dostávají aktuální jednoznačnou identitu a skupinku bez
kopírování group data.

**Changes**

- `get_occasion_users_for_edit.sql` — přidat set-based
  `companion_owners` CTE a do každého row `companion_owner_id`,
  `companion_owner_name`, `companion_origin`. Reuse stávající
  `standard_groups.titles`.
- `get_occasion_users_editor_bundle_v1` zachová aggregate version a nový row
  contract.
- `get_private_profile_payload_v1` — companions filtrovat přes `occasion`, přidat
  `surname`, živý `group_title`, `origin` a `can_owner_delete`.
- Zachovat companions výhradně uvnitř úplného `private_profile` replacementu;
  nepřidávat companion-specific store, key ani incremental merge. Rozšířit
  `ClientSyncProjection.companions()` o nový typed DTO.
- Occasion-aware legacy `get_user_companions_data(p_occasion)` vrátí stejný
  companion DTO; odstranit no-arg variantu po caller migration.
- `CompanionModel` a `OccasionUserModel` — typed parse/serialization nových fields.
- Profile/group writers (`save_profile_client_sync_v1`, group assignment/import,
  user import a relevant deletion commands) — pokud mění jméno, surname nebo
  standard group společníka, přidat jeho ownera do `private_profile` impacts.
- Attendance mutation dál invaliduje owner private profile, nyní přes
  occasion-scoped lookup.
- Assign/unassign provedený adminem zvýší owner private head/impact, ale command
  response aplikačně nesmí aktivovat cizí `private_profile` v adminově
  identity scope. Admin po applied/unchanged odpovědi reloadne editor bundle;
  owner změnu převezme při standardním foreground/private refreshi.
- Self-create/delete a attendance provedené ownerem vrátí jeho vlastní private
  replacement a aktivují jej atomicky. UI sledující
  `ClientSyncRuntime.projectionEpoch` znovu načte companion projection.
- Identity change/logout test musí prokázat vyčištění starého private scope a
  absenci companion cards/actions po přihlášení jiné identity i při offline
  bootstrapu.
- `docs/architecture/mutations.md` a `lib/components/users/README.md` — zapsat
  projection ownership a fan-out pravidla.

**Migration/deletion**

- Odstranit globální companion readers a DTO, které neobsahují occasion/origin.
- Nezakládat group snapshot column ani cache vedle private profile projection.

**Failure and compatibility**

- Participant bez standardní skupinky zůstává volitelným kandidátem, ale UI
  zobrazí varování „Bez skupinky“.
- Více standardních skupin se nesmí náhodně zredukovat na první položku.
- Admin bundle zůstane jedním set-based roster requestem.

**Validation**

- SQL test: admin row a private profile obsahují očekávané group/owner/origin;
  změna group assignment zvýší/replaces owner private profile.
- `test/components/users/occasion_editor_data_test.dart` — parse nových row fields.
- Rozšířit `test/components/users/companion_commands_test.dart` nebo přidat
  `companion_model_test.dart` pro DTO round-trip a missing-group behavior.
- EXPLAIN/representative load observation na izolované DB potvrdí set-based
  roster bez per-user correlated lookupu.

**Exit condition**

Oba adaptéry vracejí stejné occasion-scoped companion DTO a jméno/skupinka se po
kanonické změně projeví vlastníkovi bez reloginu nebo ručního cache purge.

### Wave 4 — Administrátorské přiřazování v Users tab

**Goal**

Manager/admin bezpečně přiřadí existujícího účastníka a před potvrzením vidí,
koho vybírá a do jaké skupinky patří.

**Changes**

- `lib/components/users/views/users_tab.dart` — při
  `allowsAdminCompanionAssignment()` přidat header action
  „Spravovat společníky“, aktivní pouze pro přesně jeden checked owner row a
  `RightsService.canUpdateUsers`.
- Přidat companion admin dialog/widget v
  `lib/components/users/companion/`:
  - nahoře vlastník: celé jméno, e-mail, skupinka;
  - seznam aktuálních společníků;
  - searchable candidates z už načteného rosteru;
  - candidate row: celé jméno, e-mail, group chip nebo „Bez skupinky“;
  - explicitní potvrzení „Přiřadit“/„Odpojit“ s oběma identitami a skupinkami;
  - candidates, které porušují one-owner/no-chain/limit, zobrazit disabled s
    důvodem, server zůstává autoritativní.
- Přidat read-only grid column „Společník uživatele“ při enabled admin capability,
  aby byl vztah vidět i bez otevření dialogu.
- `AdminCompanionCommands`/DB adapter — typed assign/unassign calls, response
  handling přes `ExceptionHandler.guard`, reload jediného roster bundle po
  úspěchu.
- Přidat lokalizace ve všech podporovaných jazycích; nepoužívat raw strings.

**Migration/deletion**

- Nepřidávat druhý seznam účastníků ani samostatný group fetch.
- Nepoužívat generic `DialogHelper.chooseUser`, pokud neumí zobrazit group a
  assignment stav; nový dialog má vlastní přesný interface.

**Failure and compatibility**

- Stale roster/conflict zobrazí odmítnutí a force reload; nesmí optimistic
  přepsat jiného ownera.
- Zavření dialogu bez potvrzení nic nezapisuje.
- Admin assignment nikdy nevolá self-create ani password/email operaci.

**Validation**

- Widget tests: capability gating, exactly-one selection, identity/group render,
  missing group, current owner state, conflict reload a detach wording.
- Command tests ověří přesný RPC name/params a idempotent response handling.
- Targeted local browser smoke pomocí `agent-browser` v pojmenované session:
  Users → vybrat ownera → otevřít dialog → najít kandidáta podle jména → ověřit
  skupinku → zrušit bez zápisu. Session na konci zavřít.

**Exit condition**

Admin dokáže před každým zápisem jednoznačně identifikovat ownera i companion
včetně skupinek a všechny změny jdou jen přes typed commands.

### Wave 5 — Participant UI a bezpečný lifecycle

**Goal**

Uživatel z jednoho zařízení spravuje program přiřazené osoby, ale nemůže měnit
admin assignment ani smazat existující účet.

**Changes**

- `companion_dialog.dart` — self-create input a tlačítko renderovat pouze při
  `allowsUserCompanionCreation`; lifecycle variantu přesunout do profilové
  „Správy společníků“ a list zobrazí celé jméno a group subtitle.
- Rozdělit dnešní víceúčelový `CompanionDialog` na profilový lifecycle widget a
  eventový attendance-only widget s oddělenými required parametry; event widget
  vůbec nedostane create/delete callbacks.
- Delete action renderovat pouze pro `origin=self_created && canOwnerDelete` a
  volat `deleteSelf`; pro admin assignment nezobrazovat remove action.
- `user_page.dart` — companion card zobrazí surname/group/origin-safe actions;
  odstranit unconditional call na `DbCompanions.delete`.
- Schedule/event/my-schedule call sites — attendance-only companion program
  action renderovat jen při master feature + neprázdném owner companion listu z
  private profile. Max limit se nepoužívá jako capability ani ownership check.
- `advanced_timeline_day_list.dart` a jeho controller interface — předat derived
  `hasOwnedCompanions`; `_shouldShowCompanionButton` nesmí rozhodovat pouze z
  login/sign-in support/master feature.
- Companion projection načíst jednou na úrovni každé schedule page/controller a
  sdílet ji s event cards. Neprovádět async read/RPC v item builderu ani jeden
  dotaz na každou událost.
- `user_page.dart` — při self-create capability poskytne profilový vstup i při
  nule vazeb; v admin-only konfiguraci ukáže companion sekci pouze skutečnému
  ownerovi. Žádný participant nesmí vidět management cizí vazby.
- `DbCompanions` — rozdělit participant/admin command adapters, odstranit
  `DbUsers.deleteUser` a occasion-less legacy calls.
- `UserStrings`/translations — neutrální text bez vstupenek/náramků; vysvětlit,
  že společník je samostatný účastník bez vlastního zařízení.

**Migration/deletion**

- Odstranit unconditional create/delete UI a staré zavádějící texty.
- Odstranit starý `delete` method, jehož interface nerozlišuje self-delete a
  unassign.

**Failure and compatibility**

- Offline UI čte cached `occasion_config`, identity-scoped private-profile
  assignment a public program. Lifecycle i attendance writes vyžadují síť,
  nejsou optimistické ani queueované a používají standardní offline disabled
  state/message.
- Server rejection kvůli disabled feature/stale assignment obnoví private
  profile a nezanechá lokální falešný stav.
- Full replacement po unassign odstraní kartu, event akci i odvozený companion
  program. `projectionEpoch` musí překreslit otevřené relevantní surface bez
  restartu; identity change nesmí ukázat data předchozího ownera.

**Validation**

- Widget tests pro dva oddělené dialog contracts, self-create on/off a správné umístění v profilu,
  admin-assigned no-delete, self-created delete, full-name/group rendering,
  event sign-in target ID a schedule/event button viditelný pouze při
  `hasOwnedCompanions`.
- Projection/runtime tests: config enabled + prázdný private list tlačítko skryje;
  private replacement jej přidá/odebere; feature disable přebije cached relation;
  identity switch/offline restore neprosákne předchozí private companion data.
- `fvm flutter test` pouze pro dotčené companion/feature/users/schedule test
  soubory.
- `fvm flutter analyze` na dotčených Dart souborech nebo repository-supported
  targeted analyzer command.

**Exit condition**

Nový klient neposkytuje participantovi žádnou UI ani command cestu ke změně
admin assignmentu nebo ke smazání existujícího participant účtu.

### Wave 6 — Contract contraction, absence proof a dokumentace

**Goal**

Po migraci callerů zůstane jedna occasion-scoped implementace bez globálních a
nebezpečně pojmenovaných alternativ.

**Changes**

- Dropnout no-arg `get_user_companions_data()` a nepoužívaný generic
  companion-only `delete_user` facade podle ověřené caller map.
- Dropnout starý `delete_companion_client_sync_v1` po migraci všech clients;
  canonical name je `delete_owned_companion_client_sync_v1`.
- Aktualizovat `docs/architecture/database.md`, `mutations.md`, Users README a
  feature README/metadata.
- Aktualizovat registry checker/contract expectations a odstranit obsolete test
  fixtures, strings a comments.
- Přidat absence searches do contract testu nebo automation checkeru pro
  occasion-less writers/readers a generic delete caller.

**Migration/deletion**

- Provedení všech řádků deletion ledgeru nebo explicitní doložení dočasně
  podporované released-client hranice s telemetry a termínem odstranění. Pro CSM
  enablement nesmí zůstat cesta, která dovolí zakázaný write; safe rejecting
  facade je povolen pouze během rollout okna.

**Failure and compatibility**

- Contract drop až po potvrzení, že distribuovaný CSM client používá nové
  interface. Web je auto-update; iOS build/release je samostatný gate.
- Rollback klienta nesmí znovu povolit account delete; master feature se při
  rollbacku nejprve vypne.

**Validation**

- `rg` absence pro `DbUsers.deleteUser` v companion modulu, no-arg reader,
  unscoped `user_companions` attendance checks a staré translation copy.
- Targeted SQL companion + client-sync contract tests.
- Targeted Flutter tests a analyzer.
- `node automation/check_client_sync_registry.mjs`.
- `git diff --check`.

**Exit condition**

Nové chování i absence starých bypassů jsou strojově doložené; dokumentace a
registry popisují stejný canonical contract jako runtime.

## Rollout and rollback

### Local/repository implementation

1. Dokončit Waves 1–6 na aktuální větvi bez přepisování nesouvisejících změn.
2. Spustit pouze standard targeted validation uvedenou níže.
3. Neprovádět production query mutation, migraci, deploy, commit ani push bez
   samostatného pokynu.

### Authorized production ordering

1. Znovu odvodit project ref z `automation/project.conf` a ověřit
   `FORCE_OCCASION_LINK`.
2. Read-only preflight:
   - schema/migration head;
   - všechny staré companion rows a počet společných occasions;
   - current feature JSON;
   - current relation count;
   - backup/restore availability.
3. Feature ponechat disabled.
4. Aplikovat DB overlay migration a ověřit constraints, grants, RPC definitions
   a nulový/čekaný relation count.
5. Nasadit podporovaný web client a připravit/publikovat podporovaný iOS build
   podle samostatných release oprávnění.
6. Před produkčním enablementem dokončit mutační smoke na izolované test DB nebo
   staging occasion se stejným schema/buildem: admin assign/unassign, group
   display, participant attendance a safe rejection self-create. Produkční
   feature ponechat při tomto kroku disabled.
7. Pokud předchozí gates prošly, uložit CSM config:
   `{code:'companions', is_enabled:true, max_companions:1,
   allow_user_create:false, allow_admin_assign:true}`.
   V tomto mezistavu participant bez vztahu neuvidí companion vstup, protože
   self-create je vypnutý a programová akce vyžaduje neprázdný private list.
8. Po samostatném oprávnění přiřadit konkrétní existující účastníky canonical
   admin commandem. Před potvrzením lidsky ověřit celé jméno, e-mail a obě
   skupinky. Při selhání feature ihned vypnout; neobcházet gate přímým DML.
9. Post-check: relation origin/scope, owner private profile, attendance a audit
   commit; žádná změna group membership/profile/Auth dat.

### Authorized acceptance pair requested on 2026-08-05

Read-only preflight na správném projektu a occasion `csmostrava2026` našel:

- owner `9+bujnmi@gmail.com` — Michael Bujnovský, standardní skupinka `0DISK`;
- companion candidate `9+b.ujnmi@gmail.com` — Michael B, bez standardní
  skupinky;
- oba jsou členové occasion ID `643` a ani jeden aktuálně není owner ani
  companion v existující vazbě.

Po implementaci, autorizované migraci/deployi a bezprostředně po bezpečném
zapnutí podporovaného klienta použít tuto dvojici jako explicitně vyžádaný
produkční acceptance scénář: přes admin command přiřadit druhý účet prvnímu s
`origin=admin_assigned` a výslednou vazbu ponechat aktivní podle zadání (nejde o
dočasnou fixture určenou k automatickému cleanupu). Účty se vždy znovu
resolveují přes přesný e-mail + occasion membership; UUID se do plánu ani UI
nehardcoduje. Potvrzovací dialog musí před zápisem ukázat obě identity, `0DISK`
a „Bez skupinky“.

Tento krok se nesmí simulovat přímým insertem do dnešní globální tabulky. Před
provedením musí být nasazen occasion-scoped schema, canonical admin RPC,
capability policy a supported client. Post-check navíc ověří, že ownerův
`private_profile` obsahuje přesně tohoto společníka, adminova private cache
neobsahuje cizí payload a po foreground refreshi owner vidí programovou akci.
Automatizované SQL/widget testy používají výhradně syntetické fixture identity;
produkční e-maily patří pouze do explicitně autorizovaného rollout acceptance
kroku.

### Rollback

- První a bezpečný rollback je `companions.is_enabled=false`; data vazeb se
  nemažou.
- Při UI regresi rollbacknout client až po vypnutí feature.
- Při command regresi nasadit forward SQL fix; neobnovovat globální relation
  checks ani generic account-delete cestu.
- Admin-assigned relation lze samostatně odpojit bez smazání účtů.
- Schema contraction nevracet na globální PK. Obnova backupu je pouze pro
  skutečnou data-corruption událost a vyžaduje production authority.

## Verification strategy

| Risk or invariant | Verification seam | Command/observation |
|---|---|---|
| Feature JSON backward compatibility | Dart feature model | `fvm flutter test test/components/features/companion_feature_test.dart` |
| Occasion/origin schema a grants | Isolated SQL contract | `node web_client/scripts/run_db_tests.js database/tests/companion_contract_test.sql` |
| Capability + permission enforcement | Explicit RPC SQL tests | Stejný companion contract test s actor claims. |
| Cross-occasion denial | Attendance/assignment RPC | SQL negative fixture se dvěma occasions. |
| Safe admin unassign vs account delete | Lifecycle RPC | Assert relation removed, Auth/user_info/group/event rows retained. |
| Concurrency/uniqueness | Relation constraints + command locks | Dvě souběžné assign transakce; právě jedna applied. |
| Admin roster group/owner projection | `get_occasion_users_editor_bundle_v1` | SQL JSON assertions + `occasion_editor_data_test.dart`. |
| Owner private-profile freshness | client-sync private revision | SQL assertions po assignment, attendance, profile a group change. |
| Offline replacement a identity isolation | Client sync store/runtime/projection | Runtime tests pro add/remove replacement, feature-disable precedence, logout/login a offline restore. |
| Participant UI actions podle origin | Widget seam | Targeted companion dialog/user page tests. |
| Participant action visibility | Profile + schedule/event surfaces | Matice testů: self-create profile gate, owner/non-owner, empty/nonempty private list, master disabled. |
| Admin identity/group UX | Admin dialog widget | Widget tests + named `agent-browser` smoke. |
| Absence globálních bypassů | Source/pg_catalog contract | `rg` checks + `client_sync_v1_contract_test.sql`. |
| Registry completeness | Registry checker | `node automation/check_client_sync_registry.mjs`. |
| Dart integrity | Targeted tests/analyzer | `fvm flutter test test/components/features/companion_feature_test.dart test/components/users/companion_commands_test.dart test/components/users/companion_admin_dialog_test.dart test/components/users/companion_dialog_test.dart test/components/users/occasion_editor_data_test.dart` + targeted analyze. |

Neprovádět SQL test runner proti produkci. Produkční ověření je read-only nebo
explicitně autorizovaný smoke podle rollout kroku.

## Definition of complete

- [ ] Feature má master gate a dvě nezávislé typed capabilities se zpětně
      kompatibilními defaults.
- [ ] `user_companions` je occasion-scoped, má origin a vynucuje one-owner,
      no-self a membership constraints.
- [ ] Self-create, self-delete, admin-assign a admin-unassign mají oddělené
      explicitní commands a jeden canonical SQL implementation owner.
- [ ] Admin assignment ani unassignment nikdy nemění Auth/profile/group/program
      data existujícího účastníka.
- [ ] Attendance oprávnění je omezené na target event occasion a enabled master
      feature.
- [ ] Admin dialog zobrazuje celé identity a aktuální skupinky z kanonických dat.
- [ ] Participant UI zobrazuje celé jméno/skupinku a nenabízí delete/unassign pro
      admin-assigned origin.
- [ ] Self-create je pouze v profilové správě; event/program companion tlačítko
      vidí pouze owner s alespoň jedním společníkem v aktuální private profile.
- [ ] `occasion_config` je zdroj feature policy, identity-scoped
      `private_profile` zdroj vztahu a žádná druhá companion cache nerozhoduje o
      UI visibility.
- [ ] Full replacement, projection epoch, feature disable a identity switch mají
      testy pro přidání/odebrání tlačítek bez restartu a bez private-data leaku.
- [ ] Profile a group změny společníka invalidují owner private profile.
- [ ] Legacy a v1 adaptéry sdílejí business invarianty; neoccasion-aware a
      generic delete bypassy jsou odstraněné nebo během přesně ohraničeného
      rollout okna pouze bezpečně rejectují.
- [ ] Deletion-ledger items mají absence proof.
- [ ] Targeted SQL, Dart, registry, analyzer a diff checks projdou ve standard
      verification režimu.
- [ ] Production migration/deploy/config/real assignment jsou buď autorizovaně
      dokončené a ověřené, nebo přesně uvedené jako pending operational steps.

## Residual risks

- Starý distribuovaný klient nerozumí sub-capabilities. SQL zabrání zakázané
  mutaci, ale UI může do aktualizace nabídnout nefunkční create/delete. Proto je
  client rollout tvrdý gate před `is_enabled=true`.
- Databáze dnes nevynucuje právě jednu standardní skupinku na participantovi.
  UI musí korektně ukázat nulu nebo více skupinek; companion feature tento širší
  group-domain problém neřeší.
- Self-created companion stále vytváří Auth účet. Tento plán lifecycle izoluje a
  zabezpečuje, ale nemění základní produktové rozhodnutí vytvářet technickou
  identitu.
- Adminem provedené přiřazení není push. Owner offline uvidí poslední platnou
  private generaci a změnu obdrží při standardním private refreshi; UI nesmí
  tvrdit okamžité doručení na jiné zařízení.
