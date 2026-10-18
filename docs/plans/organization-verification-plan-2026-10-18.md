# Ověření organizace a identita pod veřejným formulářem

Datum: 2026-10-18
Stav: Revize 2 implementována místně; evidence a omezení kontrol v `docs/operations/organization-verification/IMPLEMENTATION-2026-10-18.md`
Verification: standard - oprávnění, databázová migrace a veřejný kontrakt
Rozsah po výslovném zadání realizace: místní implementace a cílené kontroly, bez produkčních zásahů.

## Výsledek a závazný vzhled

Pod každým veřejným formulářem ověřeného pořadatele bude přímo jeho název s malou ověřovací ikonou. Kliknutí otevře právní a kontaktní údaje. Neověřeným pořadatelům se tento blok vůbec nezobrazí. Zobrazení se dědí automaticky pro všechny formuláře pořadatele, bez přepínače u jednotlivých formulářů.

**Poslední výslovné upřesnění uživatele má přednost:** žádný prefix „Prodejce:“, žádný viditelný text „Ověřená organizace“ v patičce. Jen název a UI ikona. Tento text smí sloužit jako přístupný popis ikony nebo vysvětlení v detailu.

Vizuální reference byla skutečně otevřena v izolovaném headless prohlížeči a zkontrolována screenshotem: [veřejný Google formulář](https://docs.google.com/forms/d/e/1FAIpQLSeI29Cq9i-DCGVBO311dh5LlZ4ViVDxvfndfJYkchnPhlnapw/viewform). Pod tlačítky je drobná, centrovaná identifikace organizace přímo na pozadí stránky, bez další karty; níže je značka Google Formuláře. Reference ukazuje umístění a vizuální hierarchii, nikoli ověřovací systém Google. Její celou vysvětlující větu do Festappu nepřebírat.

### Veřejná patička

- Umístění: po obsahu formuláře a jeho hlavních akcích, v běžném toku stránky, před případnou značkou platformy. Samostatný klidný řádek bez rámečku, karty nebo barevného panelu.
- Obsah: `Kulturní spolek Větřkovice` a těsně vedle standardní vektorová ikona ověření z používané sady. Žádné emoji, vlastní rastrový odznak ani doprovodná věta.
- Název a ikona tvoří jedno přístupné tlačítko s vizuálem textového odkazu, v HTML `type="button"`. Název může zabrat více řádků, poslední slovo držet s ikonou; neaplikovat nowrap na celý dlouhý název.
- Centrovat v šířce formuláře; odsazení 24 px nad blokem, mezera ikony 4-8 px. Text přibližně 14 px s dostatečným kontrastem; klikací plocha alespoň 44 px na výšku bez zvětšování samotné ikonky.
- Barvy a mezery z existujícího tématu. Ikona má rozpoznatelný tvar ověření; význam nesmí stát jen na barvě. Kontrast zachovat také u vlastních barev formuláře a tmavého režimu.
- Přístupný název tlačítka například „Kulturní spolek Větřkovice, ověřená organizace, zobrazit údaje“. Samotná ikona `aria-hidden`, aby ji čtečka neopakovala. Ikona přibližně 16 px, mezera 6 px. Viditelný focus. Pro myš lze doplnit tooltip, detail musí fungovat i bez hoveru. Při absenci/chybě identity nevykreslovat veřejný placeholder nebo chybový text.
- Kliknutí otevře detail bez odeslání formuláře, změny vyplněných odpovědí, resetu rezervovaných sedadel nebo ztráty osobního odkazu. Zavření vrací focus na název.

### Detail organizace

Kompaktní dialog, šířka nejvýše přibližně 480 px, mobilní okraje 16 px, na malém displeji přizpůsobený výšce a s vlastním scrollováním. Nadpis tvoří právní název s ikonou, stejný název neopakovat hned pod ním. Uvnitř označené hodnoty: IČO nebo zahraniční registrační číslo, DIČ pokud je vyplněné, strukturované sídlo, veřejný kontaktní e-mail, volitelný telefon a web. Prázdné volitelné údaje vynechat. Vysvětlení ověření například „Festapp ověřil identifikační údaje organizace.“ Ověření nemá slibovat kvalitu akce ani garantovat doručení vstupenek. Bez kopírovacích ikonek u každého pole a bez vlastních animací.

Odkazy používat jen pro bezpečné protokoly: HTTPS pro web, mailto pro e-mail, tel pro telefon. Veřejné údaje vykreslovat jako text, nikoli HTML. Ve Flutteru použít existující `AppDialog`/`AppDialogHeader`. JS `web_client/src/components/ui/modal.js` dnes neřeší Escape/focus trap/ARIA; nepovažovat jej za hotové přístupné řešení. Pro detail použít nativní `<dialog>` s `showModal()`, pojmenováním přes `aria-labelledby`, viditelným zavřením a explicitním návratem focusu. Styly převzít z aplikace; nepřestavovat ostatní modaly. Bez změny URL nebo přidávání nové historie.

## Rozsah a rozhodnutí

1. „Organizace“ ve smyslu pořadatele patří k **Unit**. `Organization` je tenant/platforma. Data se neukládají na jednotlivý formulář ani do globální konfigurace platformy.
2. Jedna Unit odpovídá jedné veřejné právní identitě. Formulář získá identitu přes `forms.occasion -> occasions.unit`. Nevyvozovat ji z bankovního účtu, autora formuláře, aktuálně přihlášeného uživatele nebo domény.
3. Právní název má vlastní pole s rozumným limitem, například 200 znaků. Současný název Unit má limit 30 znaků a není vhodný pro úplný právní název. V patičce bude ověřený právní název; přejmenování interní Unit ho nemění.
4. První verze má ruční ověřování správcem příslušné platformy. Automatické napojení na ARES, placené ověřování, upload dokumentů, notifikace a nové fakturační funkce nejsou součástí.
5. Nastavení i schvalování mají být dokončené v administraci. Nestačí přidat právní pole a nechat ověřování na ručních SQL změnách.
6. Patička bude v JS i Flutter veřejném formuláři včetně uzavřeného formuláře, odpočtu, vyprodaného stavu, čekací listiny, nabídky míst, rekapitulace a výsledku objednávky. U neznámého nebo nepřístupného odkazu se žádná identita neodhalí.
7. E-maily, PDF vstupenky, obecné katalogy akcí, historická identita smluvních dokumentů a přestavba obchodních podmínek jsou mimo tento krok. Patička nenahrazuje existující právní odkazy.

### Výslovné předpoklady pro implementaci

- Jeden pořadatel neprodává v rámci stejné Unit za více právnických osob. Pokud existující konkrétní použití tento předpoklad vyvrátí, zastavit jen návrh vazby identity a doplnit explicitní vztah prodejce; nevytvářet skrytý per-form JSON override.
- Správce platformy v `organization_users.is_admin` je důvěryhodný ověřovatel. Samotné oprávnění Unit manager/editor nestačí. Pokud má být ověřování vyhrazeno centrálnímu provozovateli napříč tenanty, je před implementací schvalování nutné určit jeho explicitní oprávnění; nepoužívat neexistující globální admin roli.
- Primární formulář údajů podporuje CZ a zahraniční subjekty: země řídí validaci identifikátoru. CZ IČO uchovat jako osmiznakový text včetně úvodních nul a ověřit formát/kontrolní součet na serveru; ten sám o sobě neznamená ověření identity. U zahraničních subjektů povolit registrační číslo dle země a ruční posouzení. Povinné: země, právní název, identifikátor, sídlo a kontaktní e-mail. DIČ, telefon a web jsou volitelné.
- Toto jsou produktové volby, nikoli právní posouzení povinných náležitostí prodeje.

## Ověřené výchozí body

Průzkum vychází z pracovního stromu na `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`. Strom obsahuje rozsáhlé cizí rozpracované změny. Plán je neopisuje ani nevrací; při realizaci zkontrolovat rozdíly oproti tehdejšímu stavu a sdílený kód směřovat na kanonický main podle pravidel repozitáře.

| Zjištění | Konkrétní zdroj | Důsledek |
|---|---|---|
| Hierarchie Organization > Unit > Occasion | `docs/architecture/ai_context.md`; `database/tables/tables.sql` | Profil právního subjektu patří Unit. |
| Nastavení skutečného pořadatele již existuje | `lib/components/unit/views/unit_settings_screen.dart`: `UnitSettingsScreen`, `_saveSettings`; `unit_settings_strings.dart` | Přidat oddělenou sekci do této obrazovky. |
| Jsou dva transporty běžného uložení Unit | `lib/components/unit/db_units.dart`: `updateUnit`; `unit_commands.dart`: `SupabaseUnitCommands.save` | Nová identita nesmí záviset jen na zachycení jednoho z nich. |
| Starý update nahrazuje celý `units.data` | `database/functions/units/update_unit.sql`; sync implementace v `supabase/migrations/20260802234000_client_sync_v1_expansion.sql`: `save_unit_client_sync_v1` | Citlivý stav nedávat do tohoto JSON ani pod obyčejný save Unit. Historické migrace neupravovat. |
| Veřejná data Unit již mohou opustit server | `database/functions/others/get_public_occasions.sql`: `'data', u.data` | Soukromý koncept a poznámky nesmějí skončit v `units.data`. |
| Veřejný form bundle má centrální builder | `database/functions/eshop_forms/get_form_by_link.sql`: `get_form_bundle_internal` | Jeden serverový resolver identity pro všechny odpovídající projekce. |
| Uzavřený formulář má redukovaný response code 400 | Tentýž builder; `web_client/src/components/forms/db_forms.js`; `lib/components/forms/db_forms.dart` | Identitu doplnit i do bezpečné redukované odpovědi. |
| Waitlist využívá builder s povoleným uzavřeným formulářem | `database/functions/eshop_waitlist/capabilities.sql` | Zachovat capability ochranu, nepřidávat anonymní bypass. |
| Přehled objednávky má vlastní projekci a předčasný návrat | `database/functions/eshop_waitlist/order_overview.sql`; `web_client/src/components/forms/form_page.js`: `init` | Doplnit identitu také tam a použít stejný footer shell. |
| JS a Flutter mají samostatné modely i vykreslení | `web_client/src/components/forms/form_models.js`, `form_renderer.js`, `form_page.js`; `lib/components/forms/models/form_bundle.dart`, `views/form_page.dart`; `packages/festapp_core/lib/src/forms/form_definition.dart` | Výslovně zajistit paritu, včetně modelových copy/serialize operací. |
| Platform admin guard již existuje | `lib/components/organization/organization_admin_guard.dart`; `database/functions/organization/check_is_admin_of_organization.sql` | Znovu použít navigační ochranu, autoritu vždy ověřit i v SQL. |
| Bundle a editor již oddělují čtení od zápisu | `form_bundle.dart`: `withDefinition`; `form_editor_draft.dart`: `fromBundle`, `toJson`, `toEditedJson` | Identitu ponechat na read-only bundle, nezvětšovat `FormDefinition` ani formulářový write kontrakt. |
| Command transport není obecný RPC klient | `lib/data_services/client_sync/client_command_transport.dart`: `invoke`; SQL `begin_unit_client_mutation_v1` | Transport přidává UUID/retry, receipt helper navíc vyžaduje Unit managera; review pouze platform adminem sem bez změny práv nepasuje. |
| Existující JS modal nemá správu fokusu a Escape | `web_client/src/components/ui/modal.js`: `Modal` | Pro nový malý detail použít nativní dialog, nerefactorovat všechny modaly. |

## Architektonické zúžení a rozhraní

Cíl je dokončená funkce s malým počtem míst, která implementátor musí měnit. Doménový modul má skrýt validaci, stavové přechody a souběh za pěti RPC; jednotlivé obrazovky znají jen read DTO, akci a výsledek. Server je jediným vlastníkem přechodů, UI pouze prezentuje stav a dostupné akce.

| Modul | Vlastní | Záměrně nevlastní |
|---|---|---|
| SQL `organization_verification/` | Profil, revizi, oprávnění, audit, přechody a whitelist veřejné identity | Objednávky, platební logiku, obecný sync a globální registry organizací |
| Flutter `components/unit/verification/` | `UnitLegalProfile`, úzké `DbUnitVerification`, editor sekce a review dialog | Obecnou repository vrstvu, service locator, nový stavový framework |
| `VerifiedOrganizationIdentity` u read modelu formuláře | Immutable veřejný DTO a parsování; sdílené i přehledem objednávky v tomto klientu | Editovatelnou definici formuláře, draft, nastavení Unit nebo soukromý audit |
| Patička a detail, jednou pro každý klient | Prezentaci předané identity a vlastní lifecycle | Fetch, odvození ověření, práva a přechody stavů |

Závislosti: SQL -> existující autorizované read RPC -> read model stránky -> patička/detail. Administrace -> `DbUnitVerification` -> doménová RPC. Komponenty nesmějí navzájem sahat na interní stav formuláře. Konkrétní služby použít přímo ve stávajícím stylu; další interface přidat jen tam, kde již existující testovací seam vyžaduje náhradu transportu.

Rozumný rozpočet nové struktury: dvě tabulky, pět externích RPC, jeden interní projekční helper; jeden malý Flutter doménový adresář a jedna veřejná komponenta na klienta. Žádný background job, receipt framework, nový globální stav nebo nový frontendový balíček. Případný vyšší počet souborů smí vycházet z existujícího oddělení modelů, překladů a testů, nikoli z abstrakce pro jeden use case.

## Datový a bezpečnostní kontrakt

### Jediný vlastník

Nový doménový celek `database/functions/organization_verification/` vlastní schéma, validaci, stavové přechody a veřejnou projekci. Všechny funkce v `public`; externí RPC a potřebný projekční helper `SECURITY DEFINER` s `search_path = public, extensions`, explicitními právy a přesným grantem. Čisté normalizační pomocné funkce použijí invoker, pokud vůbec potřebují samostatnou deklaraci. Žádné aplikační triggery.

- `public.unit_legal_profiles`: PK/FK `unit_id` s `ON DELETE CASCADE`; typovaná pole identity a kontaktů, monotónní `revision`, `status`, `submitted_at`, `submitted_by`, `reviewed_at`, `reviewed_by`, `reviewed_organization_id`. Oddělit `feedback_to_applicant` pro managera a interní `review_note`/`review_source` pro schvalovatele. Tenant se při každé operaci odvozuje z Unit. Nové Unit nemají automaticky ověřený profil.
- `public.unit_legal_profile_audit`: append-only historie skutečných změn a rozhodnutí s aktérem, revizí, časem, akcí, snapshotem a tehdejším organization ID. Historické `unit_id` uchovat bez blokujícího FK na smazanou Unit; audit se nepropaguje do klientského syncu. Auditní tabulka má klientské DML zakázané; poznámky a zdroj vidí pouze správný platform admin. Nepřidávat osobní doklady ani samostatný audit viewer do první verze.
- Přímé SELECT/INSERT/UPDATE/DELETE profilů i auditu pro anon/authenticated zakázat; RLS + granty. Čtení a změny pouze přes úzké RPC. Současný obecný save Unit nové tabulky neobsluhuje.
- Profil spravovat online přes samostatné RPC; neposílat koncept přes offline sync. Po uložení vrátit potvrzený profil a jeho revizi. Offline stav administrace výslovně vysvětlí, proč nejde uložit/odeslat.

### Stavový automat

`unverified -> pending -> verified | rejected`; `verified -> revoked` rozhodnutím správce. Z `rejected`/`revoked` lze opravit profil a znovu podat žádost. Profil bez řádku se v administraci chová jako `unverified`.

- Manager Unit může uložit návrh a odeslat úplnou žádost, nikoli měnit status libovolnou hodnotou. Odeslání je explicitní akce se sdělením, které údaje budou veřejné.
- Správce Organization může schválit nebo zamítnout pouze pending profil patřící jeho tenantovi, a odebrat platné ověření. Zadává důvod/zdroj ověření; ověřuje shodu subjektu i oprávnění žadatele jej zastupovat. Nevyvozovat ověření jen z existence IČO.
- Každá skutečná změna veřejných údajů zvýší revizi a vrátí stav na `unverified`, včetně změny při pending/verified. Patička zmizí až do nového schválení; před uložením na tento důsledek upozornit. Uložení shodných normalizovaných hodnot stav nemění.
- **Revize patří celému profilu včetně stavu:** zvýšit ji o jedna při každé skutečné změně údajů, submit, approve, reject i revoke. Beze změny normalizovaných hodnot save nic nezapisuje a nevytváří audit. Každý write vyžaduje `expectedRevision`. To brání například pozdnímu schválení po změně stavu bez změny údajů.
- Pořadí v každém write: najít a zamknout Unit, zkontrolovat aktuální tenant/oprávnění/demo omezení, zamknout profil, porovnat revizi, normalizovat/validovat, provést povolený přechod + audit, vrátit nový profil. Stejné pořadí pro všechny akce. Zámek Unit serializuje i první vytvoření; pro neexistující profil má klient revizi 0. Žádné automatické opakování na konflikt.
- **Retry bez další infrastruktury:** tato RPC nepoužívají `ClientCommandTransport` ani mutation receipts. Nemají externí side effect a kontrola revize zaručuje nejvýše jeden přechod/audit. Po timeoutu UI načte aktuální profil; ukáže potvrzený stav a zachová lokální draft. Neoznačí operaci za úspěšnou bez potvrzení a neposílá starou akci automaticky s novou revizí. Opakovaný starý požadavek vrací konflikt, nikdy znovu neobnoví odebrané ověření. Přesný replay historického response není požadován.
- Změna interního názvu Unit, času nebo tónu komunikace neovlivňuje profil. Změna vazby Occasion na Unit musí při dalším načtení použít nového vlastníka; kopie akce nepřenáší odznak mezi Unit.

### Navržená API

Konkrétní názvy držet konzistentní v SQL i klientech:

| RPC | Autorita a účel |
|---|---|
| `get_unit_legal_profile(p_unit)` | Manager Unit nebo admin její Organization; koncept + stav pro administraci. |
| `save_unit_legal_profile(p_unit, p_expected_revision, p_profile)` | Manager; whitelist polí, normalizace, validace, invalidace ověření při změně. |
| `submit_unit_verification(p_unit, p_expected_revision)` | Manager; úplnost a přechod do pending. |
| `get_unit_verification_queue(p_organization, p_status, p_cursor, p_limit)` | Odpovídající platform admin; seznam defaultně pending, volitelně verified pro revokaci, limit nejvýše 50; stabilní kurzor `(submitted_at, unit_id)`. Detail načíst prvním RPC. |
| `review_unit_verification(p_unit, p_expected_revision, p_decision, p_feedback, p_note, p_source)` | Odpovídající platform admin; approve/reject/revoke, zámek, audit. |
| `get_verified_unit_identity_internal(p_unit)` | Interní projekce bez klientského EXECUTE; pouze `verified`, jinak null. |

`get_unit_legal_profile` vrací pro managera whitelist veřejných polí + stav, revizi a feedback. Interní poznámku/zdroj přidá jen po samostatné kontrole platform admina. Manager nemá automaticky nárok na celý databázový řádek.

Výsledky write RPC: `{code: 200, outcome: applied|unchanged, profile: ...}`, konflikt `{code: 409, errorCode: REVISION_CONFLICT, profile: ...}` s oprávněnou projekcí a validační chyba `{code: 422, errorCode: ..., fieldErrors: ...}`. Práva se kontrolují před vrácením jakéhokoli profilu, SQL výjimka `insufficient_privilege` pro nepovolené volání. UI nedekóduje text databázových výjimek. `p_profile` přijímá jen whitelist údajů; podvržený status/revizi/auditní pole odmítá, neignoruje. Koncept může být neúplný; formát přítomných údajů a délky se kontrolují při save, úplnost při submit. Approve znovu kontroluje úplnost, reject/revoke vyžaduje neprázdný feedback; approve vyžaduje neprázdný ověřovací zdroj. Interní poznámka je volitelná. Pending nelze znovu submitnout; nejdřív uložit změnu nebo zpracovat existující žádost.

Veřejná projekce `organizationIdentity` obsahuje jen `unitId`, `revision`, `legalName`, `countryCode`, `registrationNumber`, volitelné `vatId`, strukturované `address`, `contactEmail`, volitelné `phone`, `website` a `verifiedAt`. Přítomnost objektu znamená schválenou aktuální revizi. Žádné `units.data`, soukromý důvod rozhodnutí, reviewer UUID nebo historie. Žádný klientský výpočet ověření podle vyplněných polí.

Interní helper volat z builderu formuláře a z existujícího capability readeru přehledu objednávky až po jeho úspěšné autorizaci. Nedělat samostatné veřejné RPC s libovolným ID Unit a nezvětšovat přístup ke skrytým formulářům. Kontrolovat vazbu Unit/Occasion/Organization a `reviewed_organization_id` na serveru; při nesouladu vrátit identitu null a zaznamenat diagnostiku bez soukromých údajů. Get profilu při nesouladu nezpřístupní poznámky/zdroj původního tenanta. Save/submit pod novým tenantem resetuje staré review metadata. Přesun celé Unit mezi tenanty nebyl v prozkoumaných doménových writerech nalezen a jeho zavedení je mimo rozsah; případná privilegovaná migrace musí před přesunem explicitně zrušit ověření a zvýšit revizi v téže transakci, aby ani přesun zpět neobnovil staré schválení. Samotná kontrola aktuálního tenant ID nenahrazuje tuto podmínku.

Starší server bez nového pole znamená skrytou patičku. Neznámá revize/status ani chyba čtení nesmí vést k falešnému odznaku. Pro veřejné čtení používat existující online RPC, žádný nový persistentní cache identity. Již otevřená stránka je snapshot; odebrání se projeví při novém načtení a existujícím refreshi formuláře/přehledu. Okamžité push odvolání na otevřených stránkách není v tomto kroku garantované.

## Implementační vlny

### 1. Backend identity a ověřovací autority

**Změny:** přidat kanonické `schema.sql`, `profile_commands.sql`, `review_commands.sql`, `public_identity.sql` do nové domény; sestavit jednu verzovanou migraci v `supabase/migrations/` z kanonických zdrojů. Needitovat baseline nebo již použité migrace. Úzká transakční RPC s revizí podle kontraktu výše; bez rozšiřování mutation receipts, client commits nebo sync fan-out. Profil se smaže FK cascade, audit uchová identifikaci subjektu bez závislosti na smazané Unit. Respektovat demo read-only omezení i pro nová definer RPC. Přidat CHECK pro povolené stavy/revizi a délky polí; povinnosti úplnosti nechat v submit/approve, aby šel uložit koncept.

**Migrace:** pouze nové tabulky/funkce/granty; existující organizace zůstávají neověřené. Žádný automatický backfill ověření z názvu, bankovního účtu nebo e-mailu.

**Ověření:** nové rollback SQL testy `database/tests/organization_verification/profile_test.sql` a `access_test.sql`: manager cizí Unit, editor, anonym, admin cizího tenanta bez Unit manager role, demo, přímé DML, pokus podstrčit status, souběžná revize včetně prvního vytvoření a review vs. save, retry po revokaci, atomický audit, shodné uložení, neúplný koncept vs. submit a kompatibilita s `delete_unit`. Přesuny Unit mezi tenanty nesmějí přenést ověření ani interní poznámky do neoprávněné projekce.

**Hotovo:** manager nedokáže vyrobit ověření, admin schválí přesnou pending revizi a žádná neschválená data neopustí povolenou hranici.

### 2. Nastavení pořadatele a schvalování

**Změny:** do `UnitSettingsScreen` přidat samostatnou sekci „Právní údaje a ověření“, model/DB službu pod `lib/components/unit/verification/`, načítání profilu nezávislé na běžném uložení Unit. Sekce bude za běžným nastavením, ale **mimo jeho stávající `Form(_formKey)`**, s vlastním Form/controllerem. Existující wrapper dnes zahrnuje i další obsah; upravit jen jeho rozsah, ne celou stránku. Rozpracovaná právní pole nesmějí blokovat běžné nastavení a chyba načítání profilu nesmí blokovat zbytek stránky. Nepřepisovat profil při ukládání ostatního nastavení. Formulář údajů: země, právní název, identifikátor, DIČ, sídlo, kontakty; na mobilu jedna kolona. Textová akce „Náhled údajů“ otevře stejnou prezentaci hodnot jako veřejný detail s označením náhledu a bez odznaku u konceptu. Nepodstrkovat neověřený draft jako `VerifiedOrganizationIdentity`; sdílet jen čisté vykreslení hodnot. Zobrazit sdělení „Tyto údaje budou po ověření veřejně dostupné u vašich formulářů.“

**Stavy:** nevyplněno, rozpracováno, čeká na ověření, ověřeno, zamítnuto s feedbackem, odebráno, loading/error/offline, nemám právo, konflikt revize. V administraci použít slovní stav, veřejný zákaz textového odznaku se na ni nevztahuje. Oddělit akce „Uložit údaje“ a „Požádat o ověření“; žádost je dostupná jen pro úplnou uloženou revizi. U neuložených změn vysvětlit „Nejprve uložte změny“, pending nenabízí opakovanou žádost, verified ukáže datum. Během requestu zakázat duplicitní akce s viditelným slovním popisem. Konflikt/timeout ponechá rozepsané hodnoty, nabídne načtení stavu, žádný tichý overwrite. Při editaci verified/pending ihned zobrazit dopad změny; při save potvrdit zrušení ověření nebo stávající žádosti, bez dalšího potvrzování u běžného konceptu.

Ve stávající platform administraci `organization_edit_page.dart` přidat jeden vstup „Ověření pořadatelů“, chráněný `OrganizationAdminGuard`. Jednoduchý seznam s filtry „Čekající“ a „Ověřené“, druhý umožní pozdější revokaci. Řádek: právní název, interní Unit, identifikátor, datum žádosti. Detail přesné revize s approve/reject/revoke a jasně odděleným feedbackem žadateli, interní poznámkou a zdrojem. Při konfliktu zastavit staré rozhodnutí a znovu načíst detail. Bez batch schvalování, metrik, nového admin dashboardu a veřejných formulářů pro ověřování. Lokalizaci doplnit přes příslušné `*_strings.dart` a existující překlady.

**Ověření:** cílený Dart analyzer změněných souborů a widget test stavu/konfliktu + oprávnění ke schvalování. Testovat přechody a následky, nikoli přesné znění českých popisků.

**Hotovo:** celý cyklus manager -> žádost -> admin -> schválení -> změna údajů -> nové ověření funguje z UI bez ručního SQL.

### 3. Veřejný datový kontrakt

**Změny:** doplnit `organizationIdentity` do otevřeného i redukovaného uzavřeného response `get_form_bundle_internal`; waitlist dědí tentýž objekt. Zjištění při implementaci: `get_waitlist_offer_form` v `capabilities.sql` vrací u ukončené nabídky předčasně `form: null`, bez builderu. Tato již autorizovaná redukovaná odpověď proto dostane stejnou `organizationIdentity` na kořeni; klient ji zachová i bez form bundle. Přidat stejnou projekci do autorizovaného `order_overview.sql`, kde form bundle nemusí být přítomný. Zachovat původní capability a availability kontroly.

JS: přidat parser read-only identity a vlastnost v `FormModel`. Flutter: malé immutable `VerifiedOrganizationIdentity` vedle `FormBundle` a nullable pole **na `FormBundle`, nikoli `FormDefinition`**; `fromJson` ho načte, `withDefinition` zachová. `FormBundle.toJson` dál vrací jen dosavadní definici pro formulářové zápisy a identitu neodesílá. `FormEditorDraft` ji nekopíruje do editovatelných dat; `festapp_core` se kvůli tomuto prezentačnímu DTO nemění. Přehled objednávky použije stejný parser/type z přiměřeně sdíleného místa v klientu, bez druhé sady polí. Veřejné preview dnes používá veřejný bundle; pokud aktuální caller editor preview vrací `get_form_for_edit.sql`, přidat projekci do read response bez změny write serializeru. Nepropagovat identitu do draftu jen kvůli domnělému budoucímu preview.

**Ověření:** SQL `public_projection_test.sql`: přesné povolené klíče, open/closed, waitlist/capability, overview, cizí tenant, změna Unit a null pro neověřené. JS/Dart test parsování a `FormBundle.withDefinition`; serialize/save přes bundle i draft identitu nesmí obsahovat. Chybějící nebo nevalidní objekt má výsledek null, bez domýšlení polí nebo náhradního názvu z Unit.

**Hotovo:** všechna uvedená čtení vrací jednu identitu téhož vlastníka; soukromý koncept ani audit nejsou v žádném veřejném payloadu.

### 4. Patička a detail v obou klientech

**Změny:** JS samostatný malý `organization_identity_footer.js` a styly; Flutter odpovídající widget pod `lib/components/forms/widgets_view/`. Jedna implementace komponenty na klienta. Integrace na úrovni page shellu, nikoli pouze `FormRenderer.render`, protože status/overview/waitlist/result větve mají vlastní vykreslení a early return. JS vytvoří dva stabilní sloty: body + footer, existujícím rendererům se předává jen body místo celého host. Wrapper ponechat transform/theme/overlay chování na stávající úrovni; nedělat souběžnou přestavbu rendererů. Flutter použije krátký builder/wrapper pro scrollovatelný obsah s footerem ve všech návratových větvích, při zachování existujících overlayů. Patička dostává jen nullable identitu; žádný fetch ani znalost formulářové session. V každém renderu právě jedna instance, v `clear()`/`dispose()` zavřít vlastní detail a odpojit listenery. Před novým načtením/změnou odkazu starou identitu vynulovat, aby při chybě nezůstala patička předchozí organizace.

Upravovat `form_page.js`, `form_component.css`, `form_strings.js`, odpovídající veřejné překlady a Flutter `form_page.dart`/strings. Rozkliknutí detailu se nesmí vnořit do submit logiky nebo rozbít historii overlayů. Překryvy sedadel, platby a rekapitulace nadále vlastní své akce; identita zůstává v shellu pod nimi a po návratu dostupná.

**Ověření:** cílený JS DOM test `web_client/tests/forms/organization_identity.test.js` + Flutter widget test: verified/null, jedna patička při změně stavu, bezpečný text, reset při změně odkazu, kliknutí nic neodesílá a zachovává hodnoty. Nativní dialog, fokus a inertnost podkladu ověřit v reálném izolovaném headless prohlížeči, DOM test je nedokazuje. Jeden průchod na lokálním testovacím tenantovi: 320 px, desktop, dlouhý název, keyboard/Escape a vlastní světlé/tmavé barvy. Screenshots jen pro vzhled; použít existující lokální E2E postup, nikoli produkční zkušební objednávky.

**Hotovo:** v každém platném stavu je pod formulářem pouze název s ikonou; neověření nemají blok; detail je čitelný na mobilu a bezpečný pro rozpracovanou objednávku.

### 5. Integrace a předání

**Změny:** aktualizovat Forms README a krátký interní postup pro ověřovatele: kontrola identity, oprávnění zastupovat subjekt, schválení konkrétní revize, zamítnutí a odebrání. Pojmenovat přesný ověřovací standard; žádné obecné „ověřeno“ bez popsaného postupu.

**Ověření:** shromáždit výsledky relevantních testů z vln 1-4; již prošlé kontroly bez následné změny příslušného kódu neopakovat. Ověřit, že nové tabulky nevstoupily do obecných veřejných Unit projekcí/sync publikace. Prohledání callers + runtime test jsou společně důkaz, samotné textové hledání nestačí.

**Hotovo:** projde cesta od vyplnění až po patičku a revokaci, uzavřené i osobní linky dodržují svá práva a není přidaný nepoužívaný flag, alternativní profil v JSON nebo nefunkční schvalovací tlačítko.

## Proporcionální validační příkazy pro realizaci

Původní plánovací fáze byla bez testů a buildů. Výsledky následné realizace jsou zaznamenány v uvedené implementační evidenci.

- SQL: `node web_client/scripts/run_db_tests.js organization_verification` pouze proti explicitně zvolenému disposable lokálnímu `DATABASE_URL`; runner může načíst `.env.local`, proto před spuštěním ověřit bezpečný lokální cíl. Scénář souběhu případně doplnit dvěma lokálními DB sessions.
- JS: `cd web_client && node --test tests/forms/organization_identity.test.js` a existující form loading/public link/waitlist testy dotčené změnou shellu.
- Dart: `fvm dart analyze` s konkrétními změněnými cestami; modelové testy read DTO/bundle a cílené Flutter testy podle aktuálního `CONTRIBUTING.md` a session runneru. `festapp_core` tento návrh nemění, jeho test suite se zbytečně nespouští. Nepoužívat vymyšlený globální test command místo aktuálního repo runneru.
- UI: použít `festapp-local-e2e` pro backend a `agent-browser` s izolovaným headless profilem; zavřít vlastní session po kontrole. Žádná změna uživatelova otevřeného Chrome.

## Rychlý a klidný postup realizace

1. Před editací pouze ověřit, zda se nezměnily výše uvedené konkrétní vstupy a produktové předpoklady. Neopakovat plošný architektonický průzkum. Zafixovat DTO a přechody podle plánu, pak dokončit backend jako jeden celek.
2. Nad stejným kontraktem připravit administraci a read-only projekce. Nevynucovat závislost schvalování na Unit manager roli kvůli sdílenému helperu. Nedělat souběžně cutover syncu, formulářových modelů ani modal systému.
3. UI/UX návrh této revize prošel **Astra Medium (`gpt-6-astra`, `reasoning_effort=medium`)** se skillem `ui-ux-pro-max` a cíleným čtením reálných komponent. Při implementaci konkrétních UI/UX částí použít stejný model/nastavení podle výslovného přání uživatele: načíst `ui-ux-pro-max` a `ux-designer`, dát mu přesný DTO a vlastnictví UI souborů. Backendová pravidla zůstávají v autoritativním plánu; další nezávislý audit ani další agenti nejsou potřeba. Při souběžné práci nepřidělovat stejný soubor dvěma agentům.
4. Ověření seskupit podle dokončených vrstev: backend security/projection batch, frontend model/widget batch, jeden skutečný UI průchod. Prošlé nezměněné části znovu netestovat. Vizuální kontrola musí zahrnout skutečné screenshoty, nikoli jen DOM strom.
5. Odevzdat změny s výsledky těchto kontrol a případným konkrétním neuzavřeným předpokladem. Žádný odhad počtu hodin jako záruka a žádné samovolné produkční kroky.

### Co první implementaci nezvětšuje

Součástí jsou neúplné drafty, ruční schválení/odebrání, obě veřejná UI a všechny existující form stavy. Odložené jsou ARES autofill, dokumentové úložiště, notifikace, auditní prohlížeč, hromadné review, sofistikované filtry, nové metriky, kopírovací tlačítka a nové animace. Žádná z odložených věcí není skrytou podmínkou schválení nebo funkční patičky.

## Zachování a odstranění

Jde o aditivní funkci: neodstraňuje se existující veřejná cesta ani se nepřepisují právní texty. Zachovat `update_unit` i `save_unit_client_sync_v1` pro současné nastavení; nový profil zůstává mimo jejich JSON. Nové payloady snášejí staré klienty a nový klient snáší chybějící pole. Nepřidávat alias `is_verified` do Unit/Organization/form data, per-form seller override, druhý registr identit, nový email sender ani periodický ověřovací job.

## Nasazení a návrat

Implementace a produkční nasazení jsou oddělené kroky. Tento plán neautorizuje migraci produkce, push nebo deploy.

Po samostatném zadání nasazení: vybrat právě jeden tenant, ověřit jeho kanonický backend, zálohu a kompatibilitu aktuálních revizí; nejdřív aplikovat aditivní schéma/RPC/projekce, poté klienty, nakonec ručně schválit první zkušební profil se skutečnými údaji a ověřit veřejný výsledek. Rutinní deployment delegovat dle AGENTS.md; lokální build a `automation/deploy_direct.sh`, bez GitHub Deploy workflow. Nešířit automaticky na jiné `prod/*` větve.

Rollback klienta nové tabulky neodstraňuje. Chybné ověření odebrat serverovým review příkazem; vypnutí celé projekce případně vrací null, bez zpřístupnění konceptů. Nedělat destruktivní down migraci smazáním auditní historie. U žádného stávajícího pořadatele nevytvářet ověření automaticky jen kvůli testu.

## Definice dokončení

- [x] Patička obsahuje jen název organizace a ověřovací ikonu; žádný prefix ani viditelný statusový text.
- [x] Kliknutí zpřístupní schválené právní a kontaktní údaje bez zásahu do formuláře.
- [x] Údaje mají jednoho vlastníka Unit, žádné kopie po formulářích nebo v tenant configu.
- [x] Manager umí údaje a žádost spravovat, platform admin umí bezpečně rozhodnout.
- [x] Změna údajů, souběžné rozhodování, retry a odebrání nemohou zachovat či obnovit neplatné ověření.
- [x] Otevřený/uzavřený formulář, čekací listina, nabídka, rekapitulace, výsledek i přehled objednávky mají shodnou identitu v JS a Flutteru.
- [x] Neověřené a cizí soukromé údaje se nikde veřejně neobjeví; cílené SQL/model/UI kontroly prošly. Úplný browser průchod otevřeným Flutter formulářem nebyl prokázán; viz implementační evidence.
- [x] Produkční migrace/nasazení jsou buď zvlášť autorizované a ověřené, nebo při předání výslovně neprovedené.
