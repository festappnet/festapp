# Dokončení canonical zápisů skupin a aktivit

Datum: 2026-10-07  
Stav: autoritativní implementační plán; provozní contraction podmíněn gates  
Verification implementace: **standard** (auth, concurrency, veřejné RPC a migrace)  
Baseline: `main` a po fetch také `origin/main` = `eb1d94ac41b085218b8ed618814b9e0727525e62`  
Plánovací větev: `plan/canonical-mutation-cutover-20261007`  
Worktree: `/Users/miakh/source/festapp-canonical-mutation-plan`

## 1. Výsledek a hranice zadání

Uložení skupiny včetně členství a soukromého místa proběhne jedním doménovým příkazem. Publish aktivit uloží historii, live graf, verzi, audit a sync dopady v jedné transakci. Autosave zůstane history-only, ale bude používat vlastní úzký příkaz se stejnými receipts. Aktuální klient nebude vybírat persistence podle read capability. Po provozním gate nebude možné tyto operace provést starými veřejnými writery nebo přímým klientským DML.

Architekturu již určuje [mutations.md](../architecture/mutations.md). Tento plán řeší její konkrétní nedokončené části, nezavádí CRUD framework, dispatcher ani druhý mutation kernel. `client_sync_v1` a suffix existujících RPC jsou platné protokoly, nikoli názvy k plošnému přejmenování.

**V rozsahu:** save/delete skupiny, úplné nahrazení členství, dialog přidání uživatelů do skupiny, samostatný import přiřazení skupin, životní cyklus soukromého místa; publish/autosave/discard aktivit, obnova historie a předávání verzí; nutné lokální úpravy identity, aktivace odpovědí, registry a provozních gates. Import profilů, game guess, account/occasion user deletion a map place save/move jsou sousední write owners, které je nutné ověřit a opravit jen v dotčeném lock/version/sync seam.

**Mimo rozsah:** wizard `feat/occasion-setup-wizard-20261007`, celý mapový nebo schedule modul, celkový cutover všech domén, změna veřejného read modelu, nové image workflow, billing, rollout dalších tenantů. Provozní zjištění nenahrazuje oprávnění k deployi. Tento úkol neopravňuje k implementaci, commitům, pushům, migracím či produkčním zápisům.

První realizace je samostatný slice **skupina + soukromé místo + všechny současné Dart membership callers** (vlna 1). Aktivity následují ve vlně 2. Finální SQL revokace je samostatná vlna; lokálně fungující klient není důkaz dokončení provozního cutoveru.

## 2. Potvrzené důkazy a mapa vlastníků

Průzkum a druhá adversariální kontrola byly proti výše uvedenému `main`; při druhé kontrole nový fetch potvrdil stejnou SHA. Bez testů a bez live DB přístupu. Čísla řádků jsou orientační; symboly a cesty jsou kotvy.

| Uživatelský úmysl a UI | Současný klientský port / alternativní cesta | SQL vlastník, data a sync | Důsledek |
|---|---|---|---|
| Editace běžné/herní skupiny, správa členů; `UserGroupInfoModel.updateMethod`, `user_groups_tab.dart`, `game_user_groups_content.dart`, `participants_management_dialog.dart`, `group_place_dialog.dart` | `DbGroups.updateUserGroupInfo` -> `GroupCommands.save` jen při `isV1Selected`; jinak místo -> group DML -> delete/insert členů -> cleanup místa | `save_user_group_client_sync_v1`; `user_group_info`, `user_groups`, volitelně hidden `places`, `client_aggregate_versions`; union starých/nových členů -> `private_profile` | Canonical aggregate existuje; Dart legacy sekvence není atomická. |
| Přidání vybraných uživatelů do skupiny v admin seznamu | `users/views/users_tab_helper.dart:addToGroup` -> **vždy** `DbGroups.updateUserGroupParticipants` -> přímé DML | Obchází `save_user_group_client_sync_v1`, verzi, receipt a private revisions | Odstranit caller i helper, nikoli pouze `isV1Selected` větev. |
| Smazání skupiny | `DbGroups.deleteUserGroupInfo` -> `GroupCommands.delete` nebo tři samostatné delete požadavky | `delete_user_group_client_sync_v1`; editor-only, vlastní group verze; členové, group, private place; `private_profile` | Zachovat editor-only delete, leader save není oprávnění k delete. |
| Popis skupinové události pro vedoucího | `schedule/event_page.dart:_buildGroupDescription` -> `DbGroups.updateUserGroupInfo`; `loadEvent` a `auth_service.dart` načítají `get_user_group_info_with_users` | Read povoluje member/editor-view, ale nemá group/place version. Snapshot save v event page nevyplňuje `isAdmin`, klientský guard jej odmítne u leadera bez editor práv | Nutný samostatný leader edit read; celoseznamový editor bundle by leaderovi změnil oprávnění. |
| CSV group assignments | `DbGroups.replaceImportedUserGroups` -> `GroupCommands.replaceAssignments` nebo `import_user_group_assignments` | `replace_group_assignments_client_sync_v1` -> `import_user_group_assignments_internal_v1`; occasion advisory lock + skupiny; group verze a `private_profile` | Ponechat batch command, typed groups se nesmí změnit. |
| CSV profilů s group sloupcem, mazání uživatelů | `profile_commands.dart`, `db_users.dart` a SQL import pipeline | `import_profiles_client_sync_v1` -> `import_occasion_users_from_csv_internal_v1`; ten má ve zdrojovém `import_occasion_users_from_csv.sql` call na **veřejný** `import_user_group_assignments`; group versions a private heads ve vnějším commandu | Veřejný group facade nelze prostě dropnout, nejprve změnit interního volajícího na interní doménový handler. Nevytvářet vnořený nový receipt. |
| Herní checkpoint / odstranění vztahu uživatele | `game_navigation_page.dart` a user commands | Registry uvádí `game_guess_client_sync_v1`, import a user deletion; změny `user_group_info.data`, členů a verzí sdílejí group aggregate | Zachovat herní data při group save; ověřit konflikty s game guess a user deletion. |
| Běžné uložení/smazání místa | `DbPlaces.updatePlace/deletePlace` -> `MapCommands` **bez read-mode přepínače** | `save/delete_place_client_sync_v1`; map helper, place version, jen public-visible dopad do `map_catalog` | Celý mapový rewrite není nutný. |
| Posun group místa na mapě | `DbPlaces.saveLocation` stále přepíná `MapCommands.movePlace` / `save_place_location` | `move_place_client_sync_v1` zamyká place **před receipt**, zvyšuje place verzi; hidden místo vrací bez public dopadu, ale tento handler neuvádí `private_profile` impact | Nutná závislost slice: stale group DTO může přepsat novější souřadnice a členům chybí private invalidace. |
| Publish dobrovolnických aktivit | `activities_content.dart` -> `DbActivities.saveActivitiesForEdit` -> `ActivityCommands.publish` nebo history RPC + `update_activities` | `publish_activities_client_sync_v1`; live `activities`, `activity_assignments`, `activity_assignment_places/events`, history, aggregate `activities`; `private_activity` pro actor a staré/nové assignment users | Existuje transakční command, legacy dva HTTP calls mají partial success. |
| Autosave / zahození draftu | UI debounce, konflikt, stale draft reload -> `DbActivities.autosaveActivities/deleteAutosave` | `save_activity_history` / `delete_autosave_history`; per-actor `activity_history`; bez mutation receipt / auditu / sync | Nejsou canonical ani při zapnutém sync. Registry history nezahrnuje; potřebují vlastní ledger seam, nikoli veřejnou projekci draftů. |
| Odstranění účtu / service lifecycle | `database/functions/account_deletion/account_deletion_contract.sql` -> `record_account_deletion_sync_v1` před DML | Explicitně maže `user_groups`, `activity_assignments` a `activity_history`; anonymizuje audit a maže actor receipts | Zachovat existující service authority a privacy workflow, sjednotit pouze dotčené locks/versions/invalidation. Toto je další vlastník jiného úmyslu, nikoli kopie group save. |
| Načtení/obnova aktivit | `getForEdit`, `getAutosaveAndPublishInfo`, `getActivityHistoryVersion`, `_processBundle`, undo/redo | `get_activities_for_edit` poskytuje monotonic version; dva samostatné reads a více SQL statements neslibují společný snapshot; history reads vracejí vlastní metadata | Read kontrakty zachovat; editor nesmí použít historickou verzi jako aktuální token. |

SQL canonical group/publish RPC jsou v `supabase/migrations/20260802234000_client_sync_v1_expansion.sql` (group od 3242, publish od 1892, import od 3956). Jejich změny autorovat nově pod `database/functions/groups/` a existujícím `database/functions/activities/`, následně nová forward migrace. Původní aplikovanou migraci neupravovat. Pozdější `20260827120000_harden_client_sync_rpc_search_paths.sql` opravuje řadu search paths; raw text expansion není automaticky konečný DB kontrakt.

### Důležité konkrétní mezery

1. **Neúplné převzetí group odpovědi.** Canonical větev v `DbGroups.updateUserGroupInfo` kopíruje version a persisted place bookkeeping, ale ne authoritative group ID, saved place ID/coordinates, účastníky a další data z `result.group`. Nově vytvořená group/private place tak nemusí být v modelu vyřešena; další save může poslat create znovu.
2. **Stale private place a dvě hodiny.** Group command přijímá vnořené místo bez expected place version. Group save zvyšuje place i group version; map move zvyšuje pouze place version. Group aggregate tedy nepozná souběžný move. Group place ownership odvozuje z hidden/type a group reference, delete nemá explicitní ochranu před dalšími vlastníky. Při existujících nekonzistentních sdíleních může mazání selhat nebo mít širší účinek - závisí na FK, nutno zjistit před contraction.
3. **Authorization před čekáním není závěrečná authorization.** Group save ověřuje admin membership před group lock. Souběžná revokace admina vyžaduje opakovanou kontrolu po zámku před DML. Replay musí znovu ověřit dnešní oprávnění před vydáním uložené odpovědi; již odebranému adminovi se private response nesmí vrátit.
4. **Ztráta activities version.** `_processBundle` vytváří `EditDataBundle` bez `aggregateVersion`; výchozí hodnota je 0. `_prepareActivityHtml` verzi naopak kopíruje. Jeho snapshot se po publish aktualizuje, ale není tím automaticky aktualizován původní `_bundle`. Undo/history/rebase musí zachovat aktuální live token oddělený od obsahu obnovované historie.
5. **Nespolehlivé publish no-op.** SQL porovnává pouze poslední `activities_data=p_history_data`, nikoli aktuální live graf; dvě klientem dodané reprezentace mohou nesouhlasit. Unchanged `historyId` vrací vstupní parent místo skutečné poslední publish row. Parent history nemá explicitní same-occasion validaci. Live handler `update_activities` obsahuje skip/continue a upsert, jeho raw public hranice nemá stejné validace jako wrapper.
6. **Autosave/publish race a cleanup.** Autosave porovnává parent bez společného activities locku, může doběhnout po publish. Publish UI volá delete autosave až druhým požadavkem. History save automaticky maže řádky starší 30 dní kromě jednoho parent; canonical publish toto nevolá. Retence není ekvivalentní a nesmí se při cutoveru ztratit ani náhodně smazat nejnovější publish či referencované rodiče.
7. **Identity a klientská aktivace.** `ClientCommandTransport.invoke` vytvoří UUID pro každou invokaci; zachová ho jen uvnitř dvou transport retries. `ClientCommandIdentity.claimIntent` existuje, ale group/activity porty ho nepoužívají. `ClientCommandResponse` nečte mutation metadata; group/activity nepropagují `mutationContextToken`. Aktivace je po jednotlivých replacements a runtime zahazuje jen nižší revision, ne stejnou. Nelze tvrdit command-level exactly-once aktivaci ani bezpečnost pozdní odpovědi po přepnutí identity.
8. **Registry checker nemodeluje konečný stav.** `check_client_sync_registry.mjs` parsuje pouze INSERT historické expansion, hledá declared functions a command string placement. Neskenuje úplně současné Dart DML ani neaplikuje následné registry UPDATE/migrace. Příkaz passing nezaručuje closure writers.
9. **Provozní preflight má starý target.** `client_sync_preflight.mjs --remote` i `release/client_sync_cutover.mjs:loadTarget` používají cloudový `SUPABASE_URL` a management query. To odporuje activation authority v `ai_context.md`; před live použitím je nutná oprava. Lokální preflight kontroluje zejména feedback a není samostatným group/activity gate.
10. **Aktivace není tenant-scoped revokace.** `buildActivateSql` revokuje DML všech source tables v aktuální registry a označí všechny řádky ready; `get_app_config_v219` také požaduje ready celou registry. Tabulková ACL je globální pro sdílenou DB. Přepnutí skupin a aktivit nedává právo aktivovat celý sync ani revokovat jiné domény/tenants.
11. **Další skutečný caller a leader read.** `event_page.dart` upravuje group description přes group save. Jeho snapshot nemá `isAdmin`, `DbGroups` má klientský guard podle této hodnoty. `get_user_group_info_with_users` a `private_profile` group projekce neposkytují aggregate version; `get_user_groups_editor_bundle_v1` je editor-view-only. Pouhé unconditional přepnutí editor read by leaderovi znemožnilo editovat.
12. **Další map writer.** `mutate_map_entity_internal_v1` umožňuje editorovi uložit existující hidden group place běžným map save; delete kontroluje reference, save ale není uzavřen podle group ownership. Opravit jen move nestačí. `get_private_profile_payload_v1` navíc vkládá placeData i pro shared place a companion ownerovi vrací group titles, takže invalidace pouze přímých členů nemusí pokrýt změněný payload.
13. **History read a časový formát.** `get_latest_autosave.sql` nemá explicitní editor permission check. History `ActivityAssignmentModel.toJson` serializuje již převedený occasion čas, live `_buildUpdatePayload` jej převádí zpět do UTC. Pouhá SQL rovnost timestamps dvou DTO může odmítnout validní request nebo uložit posunutý čas.
14. **Globální UUID race.** Activity/assignment IDs jsou globálně unikátní. Dva occasion locks nezamezí souběžnému vytvoření stejného dosud neexistujícího UUID v různých occasions; unguarded `ON CONFLICT DO UPDATE` smí změnit ownera. Same-occasion lock sám o sobě scope bezpečnost neprokazuje.

## 3. Rozhodnutí o cílovém kontraktu

### D1 - Oddělit výběr čtení od ukládání

Group a activities zápisy v podporovaném klientovi vždy používají typed port. Admin group editor vždy načítá version-bearing `get_user_groups_editor_bundle_v1`. Pro leader edit v `event_page.dart` přidat úzké `get_user_group_editor_bundle_v1(p_occasion bigint,p_group_id bigint)`, které z DB ověří editor-view nebo admin membership konkrétní group a vrátí plný save DTO, actor `is_admin`, group version a place version. Obyčejnému členovi neotevírá admin seznam ani celý catalog. Dosavadní member/public read RPC zachovat; edit token nezískávat z neversionované offline projekce. Před odesláním nesmí helper sám obnovit verzi a tím zamaskovat stale edit; token se načítá při otevření/rebase editoru. Klientský UX guard je podle autoritativně získaného oprávnění, nikdy podle snapshotu s vynechaným `isAdmin`; rozhoduje SQL. Při sync-off port stále přijme authoritative data a update editoru, ale neaktivuje neexistující cache. Nepřidávat capability `canonical_mutations_v2` ani fallback na DML při chybě RPC.

### D2 - Jedna autorita pro group a její soukromé místo

Použít existující `save/delete_user_group_client_sync_v1`, nikoli nový group CRUD. Save/delete/CSV import a sousední group writers dodržují dokumentované pořadí: receipt -> occasion group advisory lock (stávající namespace) -> group roots vzestupně -> jejich version rows -> vlastněné private places vzestupně -> place versions -> sorted private head dopady. Advisory lock zde záměrně omezuje paralelní group operace v jednom occasion, používá existující import seam a brání race creation vs import. Nikde nezavádět opačné pořadí place -> receipt -> group. Sousední multi-aggregate writers získají potřebný occasion advisory prefix před svými domain row locks; multi-occasion service deletion získává occasion locks vzestupně. Nepřidávat group lock až za existující place/occasion-user/event lock, dokud není v G0 ověřen celý dotčený pořádek a jeho concurrency test.

**Map move group místa musí používat stejný group-owned lock a při skutečné změně také zvýšit group aggregate version a private_profile heads všech členů.** To zachová existující payload group save bez nového veřejného argumentu. Shared public map place tím není group-owned a musí dál používat place verzi; pouze odkaz na něj patří group aggregate. Je-li hidden group place referencován více groups nebo jiným nečekaným agregátem, příkaz ho odmítne změnit/smazat; nevybírat náhodného vlastníka.

Běžný map `save_place_client_sync_v1` odmítne modifikaci group-owned private place i jeho převod na public/type change; tuto editaci vlastní group save. Group-private place creation běžným map save rovněž odmítnout, aby nevznikal druhý owner workflow. Group detach/delete/replacement nesmí provést cascade do live activities: kontroluje také `activity_assignment_places`, resources/events a další G0 reference; externě referencované private místo odmítne odstranit, jeho repointing je samostatný uživatelský úmysl. Public/shared place save/move zachová map kontrakt a navíc invaliduje `private_profile` dotčených group členů; group version se u pouhé změny shared place fields nezvedá, protože group vlastní jen reference.

Private profile impact se odvodí podle skutečných payload dependencies: starý/nový člen, člen zasažený názvem/popisem/místem/rolí a případný companion owner ve stejném occasion. Sorted heads odvodit z této union, ne z listu klienta. Nová registry source `private_profile/public.places` popíše tuto závislost a owning map/group commands. Shared reader DTO se nestává editorovým zdrojem tokenu.

Save vrátí authoritative group včetně ID, actor `is_admin`, place s `aggregate_version` a členů; Dart jej převezme do stávajícího modelu/reference gridu. `privatePlace` a `placeId` jsou vzájemně výlučné. NULL/empty participants není zkratka pro chybějící načtení: celý členový set musí být načtený a validní. Participant DTO odmítá neznámé klíče, null IDs, duplicity a foreign occasion; is_admin normalizovat před no-op porovnáním. Icon reference musí patřit povolenému occasion/unit scope, souřadnice musí být konečné a v geografickém rozsahu. Leader může měnit to, co umožňuje současný canonical save, editor může create/delete; nerozšířit práva na základě UI flags.

Dialog `addToGroup` načte group editor bundle, zachová existující admin flags, sestaví celý participant set a volá group save s jeho verzí. Stale edit vrátí konflikt a nová data; žádný automatický overwrite. Nepřidávat samostatnou členskou hodinu nebo helper provádějící delete/insert.

### D3 - Aktivity mají live hodiny a zvláštní per-actor draft

Zachovat `publish_activities_client_sync_v1` a jeho veřejnou signaturu/envelope. Přesunout DML z `update_activities` do `replace_activities_graph_internal_v1` bez klientského EXECUTE. Handler nepřeskakuje vadné assignments: doménová validace odmítne celý request, neočekávané SQL chyby rollbackují vše. Duplicity activity/assignment IDs a reference na jiný occasion/unit se kontrolují pod aggregate lockem před upsertem; validace před lockem sama nestačí při souběžném přisvojení ID. Reference patří k autoritativnímu occasion. Na global UUID collision musí samotné SQL INSERT/UPDATE fail-closed: nesmí měnit `activities.occasion` ani přesunout assignment z jiného occasion; conditional conflict predicate a kontrola počtu ovlivněných řádků chrání i ID, které při precheck ještě neexistovalo. Assignment může měnit parent uvnitř téhož occasion pouze v koherentním replace graph. Test dvěma různými occasion locks je povinný. Klientský history payload má uzavřený editor DTO, nikoli public projection.

Pro edit/rebase použít nové `get_activity_editor_session_v1(p_occasion bigint)` s explicitním editor/editor-view checkem. Vrátí `{editBundle, liveVersion, latestPublishId, draftId, draftParentHistoryId, draftData}` pro current actor z **jednoho konzistentního SQL snapshotu**, včetně relevantních master lists. Implementovat jedním SQL query/snapshot-safe STABLE readerem, ne wrapperem dvou volatile RPC. Stávající veřejné read RPC a jejich shapes zachovat; `get_latest_autosave` doplnit explicitní auth a same-occasion check, neměnit jeho response shape. History list/version reads nesmí cizímu actorovi zpřístupnit AUTOSAVE obsah; publish historie zůstává dostupná oprávněným occasion editorům. Restore si vezme current token z session read; undo stack obsahuje graf, **nikoli autoritu vrátit staré live/draft hodiny**.

Klientské canonical history DTO má časy UTC stejně jako live payload. Protokolově je odlišit uvnitř uzavřeného DTO, např. `schemaVersion: 1, timeBasis: 'UTC'`; top-level metadata se při content fingerprintu ignorují. Nová pole explicitně přijmout v SQL validatoru a reader modelu. Legacy history DTO bez markeru číst dosavadním occasion-time pravidlem a převést právě jednou. UTC/explicitní offset v uloženém stringu respektovat; u wall-time bez offsetu použít autoritativní `occasions.data.timezone` a dnešní default `Europe/Prague`, které používají `RightsService`/`TimeHelper`. Neřídit interpretaci DB session timezone; neexistující/nevalidní zone odmítnout nebo vyřešit podle doloženého současného defaultu, nikoli hádat. Volbu a zachování historicky nejednoznačné DST hodiny ověřit fixture; nikdy neoznačit staré bytes jako UTC bez převodu. Test na occasion s nenulovým offsetem a přes DST dokazuje časy po save/restore/publish. Nevytvářet druhý produktový timezone model.

Dvě reprezentace v existující signatuře musí po doménové normalizaci popisovat stejný graph. Odlišné => rejection bez live/history zápisu. SQL uloží normalizovanou history reprezentaci koherentní s aplikovaným grafem; zachová editorově potřebná data, časovou konverzi a poznámku. No-op vyžaduje rovnost požadovaného live grafu s authoritative live grafem a kompatibilní uloženou history; metadata typu parent nejsou fingerprint obsahu. Vrátí skutečný latest history ID. Conflict vrací live version a latest publish ID; editor použije existující read bundle pro explicitní reload, nikoli tiché přepsání.

Nové úzké příkazy:

- `save_activity_draft_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_history_data jsonb, p_parent_history_id bigint)`.
- `discard_activity_draft_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_draft_id bigint)`; null očekávaný ID znamená očekávání neexistujícího draftu, nikoli unrestricted delete.

Oba mají typed `ActivityCommands` metody a standard envelope. Draft save zamyká stejnou `activities` version row jako publish, ověří současný live version + parent latest publish ID, vlastní nejvýše jeden current draft na occasion/actor a vrátí draft ID + base version + latest publish ID. Stejný actor ve více tabs používá společný aggregate lock; poslední explicitní save při stejném live základu vítězí. Nevytvářet novou draft merge/CRDT politiku. Discard smaže jen current actor draft přesně očekávaného ID; nový draft z jiné tab vrací conflict. Žádný z nich nemění live version či private_activity revisions; skutečná history změna vytváří jeden redigovaný audit commit, bez editor DTO v auditu nebo public artifacts. Stejný obsah draftu => unchanged bez auditu.

Publish atomicky odstraní actorův draft založený na publikovaném základu a vrátí live version/history ID. Při již současném unchanged publish lze cleanup vlastního draftu provést ve stejné transakci, ale pak jde o **applied history-only změnu**, audit bez live bump; response musí tuto situaci pravdivě vyjádřit. Drafty ostatních editorů se nemažou - stanou se stale. UI nevolá post-publish `deleteAutosave`. Před publish zastaví debounce/new autosaves, nastaví publishing single-flight, dokončí běžící autosave a zmrazí edit snapshot. Starý load/history/HTML-preparation callback nesmí po dispose, context switch nebo novější edit generation přepsat session metadata. Konflikt „continue/rebase“ přebírá i aktuální live version, ne jen parent ID; po skončení stávající `_autosaving` skutečně naplánuje nový autosave.

Historie se nesmí plošně přepsat. Retence zachová 30denní práh současného workflow, ale ochrana aktuálního publish/draft parent closure je výslovné nové rozhodnutí o integritě, ne tvrzení o dnešním chování. Chronologický parent chain může chránit celou historii: v rámci tohoto cutoveru se starší chráněné řádky nemažou, nepotřebují agresivní prunovací návrh. Pokud to překročí provozní kapacitu, retenci zastavit a předložit samostatný návrh namísto tichého odřezání historie. Záměrné account deletion a jeho FK `ON DELETE SET NULL` zůstávají nadřazené privacy lifecycle; retention protection nesmí obnovit smazaná osobní data/receipts. Výpočet chráněného parent řetězu je cycle-safe a omezený; cizí scope ani vadná historická reference nesmí rozšířit cleanup. Je to explicitní doménový interní krok pod activities lockem, bez triggeru; expirace samotných mutation receipts zůstává ve stávajícím retention kernelu. Dodatečné FK/index/check změny až po read-only inventáři skutečného schema a dat. Žádná nová history tabulka není výchozí nutnost.

### D4 - Identity přes celý pokus a bezpečná odpověď

Pro group/activity a dotčený group-place map move slice rozšířit transport o volitelný explicitní `commandId` (dosavadním ostatním portům ponechat chování), group/activity a dotčený map move port přijímají immutable intent vytvořený před síťovým requestem. Stejný pokus po timeout/ambiguous network failure drží UUID i **původní snapshot včetně expectedVersion**; změněný payload nebo potvrzený conflict/rebase je nový úmysl. Nesmí se recyklovat UUID s nově sestaveným payloadem. Blokovat paralelní double-click téhož save/publish. Terminal business outcome uzavírá write intent. Neznámý transport výsledek jej neuzavírá; potvrzený DB úspěch s lokální cache chybou uzavírá write a vede jen k replay/refresh opravení cache se stejnou identity, nikoli k novému mutation. Offline mutation fronta ani automatické cross-restart pokračování nejsou v rozsahu; po restartu nově načíst authoritative stav, ne předstírat exactly-once opakování bez dochovaného UUID. `claimIntent` podle samotného payload fingerprintu není bez actor/scope namespace a lifecycle kompletní řešení.

Port zachytí `ClientSyncRuntime.mutationContextToken` **před** odesláním a předá jej aktivaci; pozdní odpověď se nepropíše do jiné identity/occasion ani do stale editoru. Envelope parser musí uchovat/validovat command/receipt/commit identity a rozlišit serverový úspěch od lokální chyby cache. Replay je uložená odpověď, nepřepisovat `replayed` flag a nevyžadovat jeho změnu oproti originálu. Stejná command replacement identita `(context, receiptId, component, revision, canonical payload digest)` se aktivuje nejvýše jednou; marker zapsat až po úspěšné cache aktivaci a jeho in-flight claim serializovat. Evidence deduplikace je bounded a patří k current context, po jeho změně se resetuje. Nižší revision se ignoruje. Nezavádět globální zákaz odlišných payloadů při stejné revision: existující `patchPrivateComponent` má legitimní lokální same-revision reconciliation. Detekci rozporu provádět v command replacement seam, rozpor řešit refresh/diagnostikou bez nového write. Rovnost JSON musí být canonical structural equality, ne pořadí map klíčů. Cache repair nesmí vytvořit nový DB write. Replay odpověď se starší aggregate version nesmí přepsat novější editor stav; reconciliation kontroluje actor/scope/session i monotonic aggregate version. Při známém DB úspěchu UI nesmí tvrdit „save selhal“ jen kvůli cache, aby nevyvolalo nový create/publish.

Group/publish zatím vrací nejvýše jednu actor-private replacement; group-owned move vrací private_profile actor replacement, pokud actor patří do impact setu. Shared public place move/save může současně vrátit map_catalog i actor-private replacement. Pro tuto nutnou odpověď aktivovat public a private třídu s jejich vlastními guards a dát jednu finální UI notifikaci; nejde předstírat jeden atomický storage pointer napříč třídami. Failure jedné třídy vede k opravení neaktivované třídy ze stejného receipt. Role/occasion token navíc nestačí pro sync-off editor: před reconciliation ověřit captured actor ID, occasion ID a editor-session generation, protože sync runtime může mít null scopes. Nepřepisovat celý runtime do obecného batch systému. Pro současné scoped odpovědi musí test prokázat guarded activation a jednu notifikaci. Pro více komponent jedné freshness class použít její guarded batch activation, pokud je skutečně potřeba; pro dvě různé třídy zachovat výše popsaný receipt-aware postup. Nikdy nevracet adminovi private payload jiného člena jen kvůli jeho invalidaci.

### D5 - Kompatibilita a bezpečnost closure

Stará přímá group DML nemá facade, kterou lze přes HTTP sloučit do jedné transakce. Ani staré `save_activity_history(PUBLISH)` + `update_activities` nelze korektně emulovat dvěma facades tak, aby šlo o jeden atomic publish. Proto je nutný force-upgrade/usage gate před konečným odstraněním těchto write oprávnění. Serverem generované nové UUID v legacy facade negarantuje retry identity starého klienta.

Dočasně vydané kontrakty zachovat v compatibility části stejného doménového souboru s jasným gate, nesmí vzniknout druhá DML implementace. `update_activities` může delegovat na stejný internal graph handler, ale před gate zůstává explicitní **bypass kernelu**, nikoli hotový canonical cutover. Samostatný import facade také nyní jen deleguje do internal, nikoli do receipt commandu. Po gate ho revokovat/dropnout; SQL import callers předem změnit na internal seam a outer canonical owner drží jeden receipt/commit.


Kompatibilní období není důkaz concurrency bezpečnosti: old direct DML nemá receipts ani aggregate clocks a old split publish není atomický. Nové canonical editory nelze bezpečně provozovat souběžně s aktivními starými bypass writery. Release návrh musí buď doložit, že dané bypassy jsou již nedostupné, nebo použít schválené krátké omezení **dotčených editor writes** během posledního upgrade/ACL přepnutí. Scope takového omezení odpovídá reálné shared DB hranici. Legacy source/facade může do G3 zůstat v repozitáři, ale to není souhlas s jeho souběžným runtime použitím. Nelze-li takové pořadí zajistit, zůstává production write release blokovaný, nikoli jen závěrečný úklid.

## 4. Gates, předpoklady a provozní evidence

**G0 - Baseline/schema před implementací:** fetch main, ověřit diff proti této SHA a aplikovaný konečný lokální schema chain. Zjistit exact signatures, table/column ACL, inherited/PUBLIC grants, policies, FK/cascade references private places, indexy activity_history a funkční callers v novějších migracích. Source schema anchors jsou `database/tables/tables.sql` (activity history má parent FK `ON DELETE SET NULL`, assignment place FK má `ON DELETE CASCADE`) a `database/policies/02_policies.sql`; deployed chain může jejich stav změnit. Pokud se baseline změnila, aktualizovat tento plán, nepřepisovat wizard.

**G1 - Lokální funkční closure:** všechny podporované Dart callers dotčených úmyslů používají typed příkazy při sync on i off, negative tests pro bypass a concurrency jsou zelené. Bez G1 nepřipravovat release.

**G2 - Read-only provozní inventář před release:** pro konkrétně vybraný tenant ověřit `BACKEND_ACTIVATION_PHASE=canonical`, jeho živý `WEB_LINK/backend-activation.json`, canonical organization/generation a occasion podle `ai_context.md`. Teprve pak přes `festapp-backend-access` sebrat seznam applied migrations, hashes dotčených function definitions, effective grants, enabled occasions a registry readiness. Tento plán žádný tenant nevybírá a žádnou live DB nepřezkoumal.

**G3 - Legacy usage/force-upgrade před SQL contraction:** archivovat pro dotčené DB role a sdílené tabulky matici tenant -> platform -> podporovaná release/min version -> bootstrap route -> write route; zahrnout Flutter web/PWA cache, Android/iOS, JS, service/Edge/import/cron integrace. Prověřit skutečně vynucený minimum build pro **editor/write** přístup, ne pouze informační update dialog. `v217/v218` bootstrap nemá dnešní capability stejnou jako v219. Síťově aktivní upgrade gate není důkaz, že starý autorizovaný klient nemůže dál volat PostgREST.

Pro usage důkaz použít retained gateway/PostgREST request logs a DB audit, které rozliší RPC jméno, direct table write, čas, actor/scope a supported build. Neexportovat tokeny ani request bodies. Délka observation window se odvodí od podporovaných release, maximálního offline/idle návratu a intervalu scheduled writers, nikoli od 30denní receipt retention (ta řeší replay již provedených commands, ne stáří legacy klienta). Evidence pokryje všechny scheduled writers a jednu úplnou supported release distribuci; konkrétní pozorovací okno musí být před začátkem zaznamenané a odpovídat delšímu podporovanému režimu, pokud existuje. Nulový traffic bez pokrytí logů nebo bez serverového vynucení není důkaz. Není-li build identifikovatelný, připravit minimální měření před začátkem okna; nevyvozovat mrtvost z `pg_stat_statements`.

Před revokací provést na izolované DB negativní test se starým authenticated tokenem: direct group DML i old publish RPC musí být po contraction odmítnuté. Table grants/FUNCTION EXECUTE jsou globální; **G3 musí pokrýt všechny consumers sdílené canonical DB dotčené konkrétní revokací**, i když release je pouze jeden tenant. Neopravňuje to k jejich rolloutům. Pokud jiný tenant potřebuje staré writery, table-level contraction zůstane blokovaný. Nezavádět bez samostatného návrhu RLS hack, další persistentní trigger ani fake tenant ACL.

**G4 - Produkční authority a pořadí:** samostatně schválený tenant/occasion release a každá migration/revocation. Nejprve schema expansion/handler corrections kompatibilní s ještě podporovanými klienty, pak distribuce klienta/usage gate, případné schválené omezení editor writes a contraction před otevřením souběžného canonical provozu. Vydaná canonical RPC signatura/envelope ani accepted staré DTO se v additive fázi nesmí bez G3 zúžit; legacy timestamp normalization je explicitní kompatibilní čtení stejného doménového handleru, nikoli druhá DML cesta. Zapnutí celé sync capability je zvláštní aplikačně širší gate; tento slice nesmí nastavit všechny `cutover_ready` nebo spustit nynější globální activation.

**Předpoklady a odpovědnost:**

| ID | Co není potvrzené | Dopad a přesné vyřešení |
|---|---|---|
| A1 | Canonical RPC z main jsou skutečně nasazené ve zvoleném tenant targetu. | Vlastník release zjistí G2 signatures/hashes a migration history; chybějící RPC je forward expansion před klientem. |
| A2 | Hidden group place má jednoho ownera a nemá externí reference. | Implementátor v G0/G2 vyjmenuje FK + group counts a ostatní referenced rows; nejasné sdílení => reject, historická oprava samostatně schválenou migrací. |
| A3 | Produktově platí současná per-actor draft politika a 30denní history retention. | Tento plán zachovává je s ochranou živých rodičů; jiná politika vyžaduje explicitní změnu plánu před destructive cleanup. |
| A4 | Veřejné web/JS a background writers nemají mimo nalezené textové callers vlastní group/activity DML. | G0 bounded scan dotčených relations ve `lib`, `web_client/src`, `supabase/functions`, `database/functions`, `workers`, `automation`; G2 DB definitions/cron inventory. Nečekaného writer ownera klasifikovat, nezvětšovat celý rewrite automaticky. |
| A6 | Historické wall-time snapshoty mají dostatečně určitelnou occasion timezone/DST interpretaci. | Implementátor ověří `TimeHelper`, `RightsService`, `occasions.data.timezone` a UTC/offset/wall-time fixtures; nedoložitelný čas se nesmí hromadně přepisovat. |
| A5 | Supported releases a log coverage dovolí G3. | Vlastník release doloží matrix/force-upgrade/log coverage. Bez ní implementace může být lokálně hotová, veřejné kontrakty se neruší. |

**Blockery:** žádný pro začátek lokální implementace. Pro produkční dokončení chybí vybraný tenant, runtime evidence G2/G3 a explicitní oprávnění G4. Jsou to provozní gates, nikoli domnělý souhlas daný čekáním.

## 5. Implementační vlny

### Vlna 0 - Pevný výchozí bod a efektivní kontrakt

**Cíl:** ohraničený inventář, podle kterého lze bezpečně psát migrace a testy.

**Změny:** pracovat z čerstvého main v izolovaném checkoutu. V plánu doplnit výsledky G0 a přesnou lock order tabulku pro group save/delete/import/profile import/game guess/user deletion/account deletion/map save/move, activities publish/draft/discard. Explicitně zahrnout read-ownery `get_user_group_info_with_users`, `get_latest_autosave`, history version/list a source `get_private_profile_payload_v1` plus `ClientSyncProjection.groups`. Vyjmenovat exact RPC overloads a dnešní FK dependencies; ověřit schema load pořadí. Neměnit history ani produkční data.

**Validace:** read-only symbol/caller inventory a lokální schema introspection, žádné production runner volání. Pokud branch před publikací zastará, nový fetch a ověření ovlivněných změn podle repo pravidel.

**Exit:** není neklasifikovaný writer dotčených relations; je znám scope revokací. Nalezené širší domény jsou named external boundary, ne tiché doplnění zadání.

### Vlna 1 - Samostatný group slice včetně private place

**Cíl:** jeden podporovaný klientský save/delete/import a žádné membership DML mimo SQL command.

**Změny:**

- `group_commands.dart`, `db_groups.dart`, `user_group_info_model.dart`: výsledek/identity/context podle D1/D2/D4, unconditional command writes a version-bearing editor reads, authoritative reconciliation; použít command result pro konflikty.
- `schedule/event_page.dart` a potřebný group reader: zahrnout `_buildGroupDescription/loadEvent` leader flow, převzít actor oprávnění a version z narrow editor read; `auth_service.dart` member read nemigrovat na admin-only bundle. Opravit snapshot vynechávající `isAdmin`; SQL vždy rozhoduje oprávnění.
- `users/views/users_tab_helper.dart:addToGroup`: přenést celý set členů s verzí do group save. Zachovat admin flags a zabránit group save neúplně načteného modelu.
- `db_places.dart`: odstranit `updateLegacyPrivateGroupPlace` a `deleteLegacyPrivateGroupPlace`; `saveLocation` group-place caller používá canonical move vždy. Nedělat plošný cutover path/type/icon editors. `map_commands.dart` a place-save SQL seam odmítají editaci group-owned private místa běžným save, shared place save/move doplňuje odvozené group private invalidace.
- Nové scoped `database/functions/groups/` canonical zdroje + forward expansion/correction migrace pro group RPC a group-owned část move; dotčené map/source body umístit do explicitního doménového souboru, ne editovat historickou expansion.
- Opravit DTO validation, owner checks, zamykání a post-lock auth; map move invaliduje group version a private heads. Zahrnout companion-owner profile dependency a narrow/private read version reconciliation. Batch import odlišuje skutečné membership/title změny od no-op před zvýšením verzí a finalize-applied; nezměněná data vrátí unchanged receipt. Sousední import/game/user-deletion/account-deletion writers pouze sjednotit potřebný lock pořádek a zajistit, že verze nezůstává stale.
- Společné `client_command_transport.dart`, `client_command_response.dart`, potřebný runtime equality/context seam: implementovat minimum D4, ostatní porty nemigrovat plošně. Změněné strict envelope fixture opravit pro skutečné public contract, bez falešného mutation stubu.

**Odstranění:** Dart legacy group branches, `updateUserGroupParticipants`, `buildUserGroupUpsert` a jejich obsolete comments/tests; private place legacy DML helpers. Public SQL facades do G3 mohou zůstat explicitně bounded.

**Failure/kompatibilita:** DB command error nikdy nepřepne na direct DML. Sync-off save převezme authoritative result bez cache. Removed admin nedostane replay, unknown save outcome drží intent identity. Nové group místo se uloží jedině v group transakci.

**Validace:** targeted Flutter group/model/dialog/addToGroup/transport/response tests; nové SQL `database/tests/groups/canonical_group_commands_test.sql` a dvouconnection concurrency seam. Scénáře v sekci 7. Legacy SQL removal testy zatím patří do contraction fixture, ne additive stavu.

**Exit:** create group/private place -> druhý save stejného modelu používá jejich vrácená IDs; addToGroup i sync-off route mají jeden receipt a atomic result; concurrent map move způsobí stale group conflict; forced failure nezanechá místo, group ani část členů.

### Vlna 2 - Celý activities draft/publish lifecycle

**Závislost:** minimální transport/context seam vlny 1. Nepotřebuje production G3.

**Změny:** nové canonical SQL sources a forward migrace pro D3. Nové funkce dostanou explicitní REVOKE od PUBLIC/anon a minimum authenticated grant, interní helpers žádný klientský EXECUTE. DB contract tests ověří chování i skutečné ACL, nejen search-path text. `update_activities.sql` nahradit jediným internal handler source; pokud je facade ještě nutný, je definovaný vedle stejného handleru bez další DML kopie. `save_activity_history.sql` / `delete_autosave_history.sql` připravit k pozdějšímu contraction, současné return shapes neměnit in-place pro staré callers.

Přidat konzistentní session read a auth-safe legacy reads podle D3. V `activity_commands.dart` přidat typed draft/discard výsledky + transport seam test injection; v `db_activities.dart` odstranit legacy publish orchestration a raw draft RPC calls. V `activity_model.dart`, `activity_history_helper.dart` a `activities_content.dart` zavést konzistentní kopírování live version, parent/draft ID a reconciliation výsledku do skutečného editoru. `_processBundle`, undo/redo, history restore a stale draft rebase nesmí resetovat live version na nulu. Historical graph lze obnovit, ale před save je potřeba aktuální live version z editor read; konflikt nikdy neznamená automatický retry s novou version.

Odstranit client-side delete autosave po publish, zajistit single-flight snapshot a autosave drain. Explicitní „zahoď draft“ dál používá discard command s current draft ID. Zachovat image preparation mimo DB a `_htmlSave.markSaved()` volat až po potvrzeném applied/unchanged výsledku; neopakovat media upload při transport retry stejného intentu.

**Odstranění/migrace:** žádná plošná data backfill; staré history řádky načíst tolerantně, nový canonical DTO normalizovat a historické řádky nepřepisovat. Nové constraints se aplikují jen po inventáři a named data repair, pokud je nutný. Nevynášet editor DTO do sync registry public komponent.

**Failure/kompatibilita:** injected graph/history/audit failure => úplný rollback. Empty graph je validní publish i draft (současný early-return prázdných aktivit odstranit). Neznámý failure nepovede k novému UUID. Stale parent/foreign IDs => bezpečný conflict/reject, ne částečné skip. Facades před G3 zůstávají named risk, ne proof closure.

**Validace:** `database/tests/activities/canonical_activity_commands_test.sql`, nové Flutter `activity_commands_test.dart`, session/legacy UTC/DST normalization a editor state/lifecycle testy a concurrency suite. Retention test musí ochránit latest publish i parent chain.

**Exit:** autosave nezmění live graf/revision, publish vlastní history a cleanup v jedné transakci; edit po prvním publish používá novou verzi, undo/restore token neresetuje, dva editors nemohou bez konfliktu publishnout stejný base.

### Vlna 3 - Registry, source parity a lokální absence důkaz

**Změny:** registry aktualizovat novou migrací pouze pro dotčené sources/writers. History-only command ownership zaznamenat do explicitního mutation deletion/contract ledgeru a grant testů, **ne** vytvářením fiktivní public sync component. Přidat současný machine-readable inventory pod `automation/client-sync/` pro dotčený slice (RPC signature, canonical SQL source, source relation, legacy boundary, removal gate, contract test). Jde o build-time metadata, ne runtime routing a ne generovaný CRUD.

`check_client_sync_registry.mjs` má z této metadata zkontrolovat dnešní zdroje a scoped forbidden callers; DB contract test ověří effective registry po migracích. Historický migration INSERT může sloužit jako baseline fixture, nikoli jediný aktuální source. Statický text scan je alarm; DB effective privileges/callers a doménové testy jsou důkaz. Změna checkeru musí mít test následné registry změny, která by původním parserem zůstala neviditelná.

Přepsat současný activity README flow, source ownership v `docs/architecture/database.md`, runbook a komentáře související s group place. Neopisovat celé mutations.md; uvést implementované/pending gates.

**Validace:** registry + lokální preflight bez `--remote`, JS checker tests a SQL contract/runtime tests na disposable DB. Contract fixture rozlišuje additive a contracted stav; dosavadní assertion „additive migrace nesmí dát ready“ neodstranit kvůli green výsledku.

**Exit:** Dart forbidden membership/private-place/history calls nejsou aktivní; dotčený writer inventory je úplný, schema sources odpovídají forward migrated DB. Zbývající runtime public facades mají owner a G3, žádný neoznačený bypass.

### Vlna 4 - Připravit provozní gate bez jeho provedení

**Změny:** odstranit starý management target výběr z live group/activity preflight a dotčené release control seams. Použít již existující canonical activation/access boundary a explicitní typed SQL query executor; ověřit organization/occasion/generation před jakýmkoli SQL. Žádný nový fallback na former cloud. Opravit dotčené runbook pokyny, které považují compiled `SUPABASE_URL` za live authority.

V `automation/release/client_sync_cutover.mjs` odlišit stávající **full registry/global ACL activation** od tohoto bounded contraction. Nepouštět ho k group slice ani automaticky přepínat `client_sync_v1`. Připravit dry-run contraction manifest s exact functions/grants, affected shared DB consumers a explicitním G3 evidence reference; apply pouze s G4. Gate nesmí být jen operator boolean `--legacy-writer-gate-confirmed`; validuje příslušný dated evidence artifact a zakreslený scope. Nespoléhat pouze na `role_table_grants`: test effective table/column privileges, PUBLIC a role inheritance i function EXECUTE.

**Validace:** `automation/tests/client_sync_cutover.test.mjs` rozšířit na activation mismatch, cloud fallback rejection, bounded revoke set a missing usage evidence rejection; remote execution jen pod samostatnou authority. Suchý návrh SQL ověřit na lokálním contracted fixture.

**Exit:** je reviewable rollout/ACL manifest včetně ochrany mixed-client období, nástroje fail-closed na chybný target a chybějící evidence. Provozní kroky zůstávají pending, dokud nejsou splněné G2-G4.

### Vlna 5 - Gated veřejná contraction a dokončení

**Závislost:** G1-G4; zdrojovou migration připravit a lokálně otestovat před žádostí o release authority. Do běžně nasazované unconditional expansion migrace nevložit předčasný DROP.

**Změny:** po upgrade/usage gate explicitně revokovat direct INSERT/UPDATE/DELETE pro scoped group a activities tables a EXECUTE přesných old RPC overloads, včetně PUBLIC/inherited cest. `places` ACL je sdílená map boundary; žádný globální revoke bez closure všech jeho writers/consumers. Internal graph/import helpers nemají EXECUTE pro klientské role. Read SELECT a potřebná oprávnění service lane zůstávají podle již platné smlouvy, nikoli blanket grant.

Nejdříve přesměrovat interní CSV import na internal group handler; pak odstranit old callable functions, jejich sources/facades a aktuální registrace podle ledgeru. Vznikne jedna canonical DML implementace; nové kernel receipt/audit/tabulky a editor read/history readers se nemažou. Drop function bez CASCADE, neznámou závislost vyřešit explicitně.

**Validace:** lokální contracted schema, exact absence + effective ACL tests, pokus starého authenticated/anon klienta o DML a old RPC, canonical positive regression. Při schváleném deployi G2 postcheck hashes/ACL a doménové receipts/private heads bez syntetického produkčního loadu.

**Exit:** odstraněné public bypassy pro celou dotčenou ACL hranici, interní callers fungují, všechny ledger items uzavřené. Pokud gate nedovolí část global ACL, stav je „lokální implementace dokončena, contraction blokován“, nikoli „cutover hotov“.

## 6. Konkrétní removal ledger

| Artefakt | Finální akce a gate | Důkaz |
|---|---|---|
| `DbGroups` legacy save/delete/import branches, `updateUserGroupParticipants`, `buildUserGroupUpsert` | Smazat ve vlně 1 po přesunu addToGroup | Scoped `rg` nemá aktivní callers ani `.from(...).insert/update/delete` group zápis; sync-off test používá port. |
| `DbPlaces.updateLegacyPrivateGroupPlace/deleteLegacyPrivateGroupPlace` | Smazat společně s group větví | Žádná reference v Dart; atomic place test. |
| `DbPlaces.saveLocation` group legacy branch + `save_place_location` public route | Caller vždy canonical v první slice; server route až G3, pokud ostatní callers jsou pokryté | Map owner a effective EXECUTE/receipt tests; případný jiný caller explicitně blokuje DROP. |
| Legacy activities publish history+update orchestration, raw autosave/discard calls, prázdný-draft early return | Smazat ve vlně 2 | UI save/restore/empty graph tests, absent forbidden RPC literals mimo port. |
| `public.update_activities(bigint,jsonb)` a `database/functions/activities/update_activities.sql` starý public writer | Extrahovat jediný internal handler; facade po G3 revoke/drop, source přesunout k internal a compatibility později smazat | Function dependency + privilege inventory; žádná public route; canonical publish nemá call na deleted name. |
| `public.save_activity_history(bigint,jsonb,text,bigint,text)` a všechny další živé legacy overloads z G0 | Po G3 zrušit, až draft/publish callers canonical | SQL exact signature absence, negative RPC test. |
| `public.delete_autosave_history(bigint)` | Po G3 zrušit, explicitní discard caller canonical | Totéž; neodstranit history read funkce. |
| `public.import_user_group_assignments(bigint,jsonb)` facade | Interní CSV caller přesměrovat; G3 revoke/drop, interní handler zachovat | Import profiles regression + žádný SQL runtime call na public facade. |
| group/activity table grants; `places` grant sdílený s map | G3/G4 contraction jen podle dotčené shared DB boundary | `has_table_privilege`, `has_any_column_privilege`, effective role + negative PostgREST tests. |
| Registry `legacy_writers`, nový private_profile places source, contract tests, current docs/comments | Nová migration/current ledger a bounded scan; ready neznamená globální done | DB registry effective state a checker tests následných migrací. |
| Stará cloud target resolution v dotčených preflight/control nástrojích | Nahradit canonical activation ve vlně 4 | Wrong generation/tenant/cloud target fail-closed tests. |
| Historické expansion/hardening migrace, `activity_history`, current receipts/tombstones, aggregate versions, `get_*` read RPC, `client_sync_v1` read flag, ostatní tenant konfigurace | **Zachovat** jako historii/data/platné kontrakty mimo removal set | Nová instalace i upgrade chain fungují; žádný rewrite historie nebo plošný rename. |

Neprovádět drop herních/profile RPC, interních importů nebo celé map registry jen kvůli přítomnosti slov legacy/v1. Absence se ověřuje na současném executable code a deployed schema; historická migrační definice musí zůstat dohledatelná.

## 7. Validace a přiměřené repository gates

Plánování nespouští testy. Implementace používá **standard**, targeted checks po koherentních vlnách. Úspěšné nezměněné testy neopakovat bez nové změny; plný release/build až pro explicitní release.

**DB runner je destruktivní pro sekvence mimo test rollback:** `web_client/scripts/run_db_tests.js:runAll` resetuje sekvence globálně a načítá `.env.local`, není-li DATABASE_URL nastavené. Před každým DB runnerem explicitně nastavit URL z disposable lokálního Supabase, ověřit loopback endpoint a disposable DB identity. Nepřebírat produkční env, nic netisknout. Použít repo local schema/bootstrap workflow; je-li k UI potřeba backend, přečíst `festapp-local-e2e`. Testy nikdy nepatří na live canonical ani former cloud.

Příklad targeted batch po vytvoření nových test files, v checkoutu s instalovanými dependencies/FVM:

```bash
node automation/check_client_sync_registry.mjs
node automation/client_sync_preflight.mjs
node --test automation/tests/client_sync_cutover.test.mjs
fvm flutter test test/components/groups test/components/map/map_commands_test.dart test/data_services/client_sync/client_command_transport_test.dart test/data_services/client_sync/client_command_response_test.dart
fvm flutter test test/components/activities
node web_client/scripts/run_db_tests.js database/tests/groups/canonical_group_commands_test.sql database/tests/activities/canonical_activity_commands_test.sql database/tests/users/import_user_group_assignments_test.sql database/tests/client_sync_v1_contract_test.sql database/tests/client_sync_internal_function_contract_test.sql database/tests/client_sync_v1_runtime_test.sql database/tests/client_sync_production_hardening_test.sql
```

Nový checker metadata test přidat do JS batch podle vytvořeného konkrétního filename. `fvm dart analyze` cílit na změněné Dart soubory. DB runner filtruje jména a může skončit 0 při žádném match: ověřit nenulový očekávaný počet testů, nepovažovat „No test files found“ za pass. Jsou-li se změnou sdíleného response/runtime parseru dotčené další porty, přidat jejich owning tests z `test/components/*/*commands_test.dart` a sync service/store tests; není to důvod k celému Flutter build.

| Riziko / invariant | Nutný test a očekávání |
|---|---|
| Group aggregate rollback | Vynutit constraint/handler failure po place a před členy/finish; žádná změna place/group/membership/version/receipt/commit/revision. |
| Ownership a auth | Editor create/save/delete; leader existing save, leader delete denied; nonmember denied; foreign occasion group/users/place/icon denied; leader-only description edit funguje bez admin seznamu; cizí draft read denied; leader revocation souběžně i před replay. |
| Lifecycle private place | create, edit, private -> shared -> none, delete; public place se nemaže; shared/foreign hidden owner se odmítne; generic map save nemění group-owned place a deletion neprovede assignment cascade; nový ID/version se dostane do grid modelu. |
| Členové a import | Zachovat is_admin při addToGroup a reimportu, prázdný set smazat atomicky, typed groups untouched, duplicate/null/foreign users reject; removed i retained members a příslušní companion owners dostanou nové heads, admin nedostane jejich payload. |
| Mixed clients / kompatibilita | Additive migrace přijme podporované dosavadní canonical payloady, read shapes zůstanou zachované; provozní gate nedovolí souběžný canonical write release s neversionovaným legacy DML. |
| No-op | Group/private place stejná data => receipt bez commit/version bump; draft same content totéž; import bez skutečné změny nesmí uměle bumpnout verze/audit - dnešní import vždy finalize-applied je třeba odlišit podle doménového delta. |
| Idempotence | Same UUID+payload po ztracené odpovědi = přesně stejný JSON a jeden history/group/commit; jiný payload stejný UUID denied; permanent expired tombstone neumožní re-execute. |
| Group concurrency | Dvě save stejné version: jedna applied, druhá conflict; save vs import/game guess/user deletion/private move; deadlock/timeout bounded, žádné tiché přepsání či duplicitní normalized title. |
| Activities atomic publish | Selhání v graph, history insert, audit/receipt finalize => nic se nepublikuje; empty graph opravdu vymaže live owned graph a vytvoří validní publish. |
| Graph/history koherence | Odlišné dvě DTO reprezentace, duplicate assignment/activity IDs, malformed UUID, foreign unit/occasion/parent reject; saved history odpovídá saved graph; unchanged vrací skutečný latest publish ID; současné nové stejné UUID ve dvou occasions nepřesune ownership; UTC/occasion/DST roundtrip beze změny okamžiku. |
| Draft race | Autosave vs publish z různých connections, publish vs publish, discard starého draft ID vs nový draft; stale base conflict, live verze se draftem nezvedá, jiné actor drafts zůstávají. Session read během publish nikdy nespojí starý graph s novou version. Account/occasion user deletion soupeří pod kompatibilními locks a neobnoví smazaný membership/assignment. |
| History + retence | Restore/undo/rebase zachová current live token, staré nullable DTO je čitelné; 30denní cleanup neodstraní latest publish ani protected parent closure. |
| Sync apply | Scope switch během requestu nic nepřepíše; actor private replacement jen jemu; retry/equal revision neduplikuje effect/notification; lower revision ignored, command-payload divergence diagnosed, legitimní same-revision private patch zachován; cache failure nevyvolá nový write. |
| Contract closure | Exact signatures a všechny live overloads, search_path `public, extensions`, minimum grants, internal helper ungranted, complete registry + absence direct callers; additive a contracted schema zvlášť. |

Concurrency nelze prokázat dvěma voláními v jediném `DO`/transaction. Přidat úzký deterministický **lokální** Node/pg dvouconnection integration test s barriers, bounded statement_timeout a izolovanými fixture IDs (např. `automation/tests/canonical_mutation_concurrency.test.mjs`); zahrnout jeho přesný příkaz do batch při implementaci. Žádné sleep-only flaky dokazování.

UI regresní minimum: create/edit/delete skupiny s custom/public/no place, leader-only group event description, role admina, addToGroup, import; activities load, autosave recovery, reload/continue konflikt, první a druhý publish, empty publish, undo/restore historie, návrat po síťové chybě. Využít widget/controller tests. Případný skutečný browser check jen isolated headless session s `agent-browser` a disposable tenant podle repo skillu, ne uživatelské okno.

## 8. Rollout, rollback a definice hotového

**Pořadí schváleného nasazení:** ověřený canonical target + ACL scope -> schema expansion/corrections bez revokací -> distribuce jediného výslovně určeného tenant klienta -> G3 pozorování a force-upgrade -> případné schválené omezení editor writes -> explicitně schválená scoped contraction -> otevření canonical editace a ověření canonical callers, hashes, receipts a private heads. Shared SQL apply může ovlivnit celou DB; jeho dopad se nesmí vydávat za tenant-only. Další tenant release je nové oprávnění.

**Rollback:** před contraction lze opravit/přerušit rollout nového klienta při zachované compatibility, ale neoznačit starý split writer za bezpečný cílový stav. Po contraction se nevrací direct grants ani old split publish. Oprava je forward SQL/client patch kompatibilní s canonical contract, případně dočasné vypnutí dotčené editor akce. Read capability disable neopravňuje reinstalovat legacy writes. Sync pointers nikdy neregresovat; oprava vydá vyšší revision. Data repair/retention deletion je samostatný schválený krok.

Hotovo znamená:

- [x] Group save/delete/import/addToGroup, leader description editor a group-private-place move mají canonical owner, stable intent identity a potřebné společné clocks/locks.
- [x] Draft/publish/discard zachovají historii, scope a concurrency; UI nepřepisuje live version nulou ani nedělá druhý publish cleanup write.
- [x] Atomic rollback, replay/auth, no-op a guarded response tests skutečně prošly v lokálním izolovaném prostředí.
- [ ] Dotčené sources/current registry/contract docs mají jedinou doménovou implementaci; explicitní removal ledger je uzavřen; jediná implementace znamená jeden owner každého úmyslu, nikoli zákaz legitimních odlišných lifecycle commandů zapisovat stejnou tabulku.
- [ ] G2-G4 jsou doložené pro reálný ACL scope; old public writers a effective DML bypass jsou odstraněné. Není-li splněné, handoff musí vyjmenovat přesné pending kontrakty/grants.
- [x] Wizard zůstal mimo main, žádný nevyžádaný multi-tenant release či production write neproběhl.

Zbytkové riziko tohoto plánu je provozní: neznámá distribuce starých klientů, log coverage, sdílené ACL a live drift. Jejich zjištění má konkrétní gate; nebrání začít lokálním group slice, ale brání poctivě prohlásit finální cutover.


## G0 implementation evidence (2026-10-07)

Fetched origin/main = eb1d94ac41b085218b8ed618814b9e0727525e62. Isolated implementation branch: feat/canonical-mutation-cutover-20261007. Wizard branch/worktree excluded. Disposable Supabase project festapp-canonical-mutation-pg15, loopback port 55452, baseline plus every forward migration through 20261006204500 loaded successfully. Effective definitions, overloads, function/table ACL, history indexes and all seven place FKs are recorded in evidence/canonical-mutation-g0-schema.json. This is local schema evidence, not deployed G2 evidence.

G0 corrects the original writer inventory: create_reception_user_v1 owns registration and inserts group membership without advancing its clock; companion deletion delegates through delete_occasion_user_companion_internal_v1 and delete_owned_companion_internal_v1. These are adjacent lifecycle owners included only for compatible locking/versions/private impact. shift_occasion_schedule_backward is a separate operational schedule owner (activities timestamps), delete_occasion_internal_v1 is aggregate teardown, and automation/image-migration/rewrite-urls.js is an operational HTML repair boundary. None authorizes a production operation. Their runtime reachability and exclusion must remain explicit in G3. Profile CSV has a later apply_v1 handler behind internal_v1; patch the effective apply handler, not the superseded source alone.

Lock order after wave 1: receipt -> occasion advisory (pg_advisory_xact_lock(occasion), ascending for multi-occasion lifecycle) -> group roots ascending -> group versions -> private places ascending -> place versions -> sorted private heads. Registration takes occasion prefix before its organization/email lock; companion/account deletion takes it before user/event/domain locks. Activities lifecycle additionally takes activities version before its graph/history DML, after group prefix when touching both. Public map fields own place version; hidden group move owns both group and place clocks. Replay rechecks permission after waiting on occasion prefix. Direct legacy DML and split publish remain G3 bypasses, never a safe mixed-client lane.

G0 follow-up: the effective baseline registry contains only its later images row;
the historical expansion rows are absent from the baseline snapshot. The slice
registry migration therefore uses bounded INSERT/ON CONFLICT, not UPDATE alone.
This does not establish completeness/readiness of the global registry. An extra
`update_activities(bigint)` overload is a read-only obsolete editor reader, not
the graph writer; it remains explicitly outside writer contraction. Exact live
writer overload discovery must reject any additional signature at G2.

Local completion evidence is in canonical-mutation-cutover-HANDOFF-2026-10-07.md.
Effective writer scan additionally classifies occasion duplication as an existing
aggregate-creation owner, and ticket auto import/registration cancellation as
adjacent lifecycle boundaries. Their raw operational reachability remains G2/G3
inventory, not a license for service bypasses. Account private heads now follow
component order (private_activity before private_profile). Shared place deletion
rejects assignment links to prevent unversioned activity cascades.

Follow-up G2 (CSM Ostrava selected by user): live generation 1 and organization
12/occasion csmostrava2026 were verified using the existing protected SSH
identity and an explicit read-only transaction. Inventory and hashed proposal
are in evidence/canonical-mutation-csm-g2-inventory.json and
evidence/canonical-mutation-csm-rollout-proposal.json. The live database retains
all nine legacy writers and direct activity_history grants; the three prepared
migrations are absent. G2 correction parity, G3 usage closure and G4 production
authority remain pending. The target executor was corrected to use api.festapp.net,
derived tenant profiles and the verified active runtime database rather than
Studio origin or a hardcoded postgres database. No production write was made.

G2 deployment correction: the real shared registry has 41/41 ready rows and
11 enabled occasions. The prepared registry metadata INSERT would cause
get_app_config_v219 to disable read sync for all enabled consumers. Its source
and unapplied forward migration now fail closed before changing active shared
readiness. Deploy domain correction migrations 110000/120000 separately; defer
130000 until a coordinated registry transition is approved. This supersedes the
assumption that all three migrations are harmless additive production changes.
Two disposable tests prove active rejection with unchanged rows and inactive
additive installation. User subsequently authorized publication and CSM Ostrava
deployment; main requires one approving PR review. No contraction authority or
G3 observation evidence is inferred.

## G0/G2 update: 2026-10-07 order consumers

Live current function bodies disproved closure of `delete_occasion_user_ws`: both
order deletion entrypoints still called it. The scoped correction is documented
in [canonical-mutation-order-consumers-2026-10-07.md](canonical-mutation-order-consumers-2026-10-07.md).
Apply additive migration 20261007170000 before final contraction. The final
operation now rejects surviving legacy SQL callers before DROP. Registry writer
metadata includes the canonical order command; active readiness is preserved.
The surviving source contract grows from 53 to 56 owners. No extra tenant/mobile
release or global activation is authorized by this finding.
