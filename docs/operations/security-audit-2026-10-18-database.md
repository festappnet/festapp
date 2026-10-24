# Bezpečnostní audit Supabase a databáze - 2026-10-18

## Závěr

**Nalezeny dvě závažné cesty kolem současné autentizační a autorizační logiky a čtyři další mezery ve čtení dat. Nejdříve uzavřít staré RPC pro změnu hesla a vytváření účtů.**

Nejzávažnější nález: existující manažer akce projde starou kontrolou pro změnu hesla administrátora organizace, přestože současná kontrola stejnou dvojici odmítá. Jde o možnost eskalace oprávnění, nikoli důkaz proběhlého napadení. Hesla ani zákaznická data audit neměnil.

## Rozsah a metoda

- Datum podle Europe/Prague: 2026-10-18; dokončení kontrol přibližně 2026-10-17 22:06 UTC.
- Tenant `festapp`, organizace 1, kanonický endpoint `https://api.festapp.net`. Ověřeny konfigurace `prod/festapp`, živá aktivace na `https://live.festapp.net/backend-activation.json` (`tenantId=festapp`, `generation=1`, `backend=canonical`), SSH hostname, runtime databáze, `current_database()` a existence organizace 1. Chráněné target assertions odpovídaly.
- Vzdálený main při kontrole: `8b1420ea1da7349db68b4a293bb37da049fb9047`; `prod/festapp`: `0a8876868b8935d24231fafce599a22a8aadeb77`. Lokální HEAD `eb23047248d59bf86345b9e0b79db4a988275231`, větev `feat/occasion-setup-wizard-20261007`, rozsáhlé předchozí změny. Nálezy stojí především na živých definicích a oprávněních, nikoli na předpokladu shody checkoutu s produkcí.
- Katalogový průchod: 1 002 definic funkcí v `public/eshop/extensions`, 422 politik v `public/eshop/storage`, 174 relací včetně `auth`, výchozí granty a klientské role. Podrobná ruční kontrola vybraných rizikových funkcí, nikoli úplná sémantická revize všech funkcí.
- SQL výhradně v `BEGIN READ ONLY` s omezením času. Role `anon` a `authenticated` simulovány přes `SET LOCAL ROLE` a session-local JWT claims. U skutečných účtů zůstaly UUID uvnitř databáze; výstupy obsahují pouze booleany. Pro skupiny použit syntetický UUID bez členství, nikoli vytvořený nebo přihlášený účet.
- HTTP: tři omezené GET dotazy a dvě volání RPC s neplatným typem argumentu. Typová chyba nastane před tělem zapisovací funkce. Nebyly vytvářeny účty, měněna hesla, posílány emaily ani prováděny zátěžové testy.
- Použity skilly `security-best-practices` a projektový `festapp-backend-access`. První nemá přímou PostgreSQL/Supabase referenci; databázové závěry vycházejí z katalogu, projektových pravidel a oficiální dokumentace. [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) a [zabezpečení databázových funkcí](https://github.com/supabase/supabase/blob/master/apps/docs/content/guides/database/functions.mdx) popisují oddělenou úlohu grantů, politik a autorizace privilegovaných funkcí.

## Nálezy s vysokou prioritou

### DB01 - Staré RPC pro hesla obchází ochranu administrátorů

**Dopad: manažer akce může nastavit heslo privilegovanému účtu, který se účastní stejné akce, a tím získat jeho přístup.**

- Živá `public.set_user_password(usr uuid, oc bigint, password text)` je `SECURITY DEFINER` a má EXECUTE pro anon i authenticated. Anonym sám neprojde kontrolou manažera; útočník zde potřebuje oprávnění manažera/admina akce.
- Funkce kontroluje pouze práva volajícího na akci a členství cíle na stejné akci. Potom přímo aktualizuje `auth.users.encrypted_password`. Nevolá `get_can_reset_user_password`, neprovádí současné admission/rate kontroly ani zneplatnění sessions.
- Čtecí reprodukce našla skutečného manažera bez role administrátora organizace a skutečného administrátora jako cíl. Pro tutéž dvojici: `legacy_guard_allows=true`, `canonical_guard_allows=false`.
- Veřejný endpoint vrací na neplatné UUID HTTP 400 / `22P02`, takže tato RPC cesta je dostupná. Samotná změna hesla a následné přihlášení se neprováděly.
- Důkaz: [živá definice, ř. 5-29](security-audit-2026-10-18-db/live-definitions.sql#L5); [výsledky](security-audit-2026-10-18-db/probe-results.json), `legacy_password_hierarchy`. Kanonická ochrana: `database/functions/users/get_can_reset_user_password.sql:118` a `database/functions/users/reset_user_password.sql:43`.
- Náprava: po kontrole závislostí odstranit starou funkci, případně jí okamžitě odebrat EXECUTE od PUBLIC, anon a authenticated. Pokud existuje nezbytný klient, převést ho na jedinou současnou autorizační a resetovací cestu. Ověřit negativní scénáře pro admina organizace, privilegované účty a cizí akce i pozitivní reset běžného účastníka.

### DB02 - Anonymně dostupný historický zapisovač vytváří potvrzené Auth účty

- Živá `public.create_user_in_organization_with_data(org, email, password, data)` je privilegovaná a anonymně spustitelná. Načte `IS_REGISTRATION_ENABLED`, ale hodnotu vůbec nepoužije. Neověřuje identitu ani oprávnění volajícího a neprochází současnou registrací nebo abuse admission.
- Přímo vkládá do `auth.users`, `auth.identities` a `user_info`; `email_confirmed_at` nastaví na `now()`. Heslo určuje volající. Vlastník funkce má potřebná INSERT oprávnění.
- Dopad: cesta k vytváření účtů bez ověření vlastnictví emailu a bez registrační politiky cílové organizace; možné obsazování cizích emailových identit a obcházení aplikačních limitů. Nejde o prokázané převzetí již existujícího účtu nebo automatické přidělení administrátorských práv.
- Veřejný endpoint vrací na neplatný bigint HTTP 400 / `22P02`. Vložení účtu nebylo provedeno. U organizace 1 je registrace nyní zapnutá; obcházení jejího vypnutí plyne z definice, nikoli z testu změny produkčního nastavení.
- Důkaz: [živá definice, ř. 32-96](security-audit-2026-10-18-db/live-definitions.sql#L32), výsledky `legacy_owner` a `invalid_type_create_user_in_organization_with_data`. Aktuální samostatný kanonický soubor tohoto historického jména nebyl v `database/functions/users` nalezen.
- Náprava: odebrat klientské EXECUTE a odstranit historický endpoint po ověření závislostí. Vytváření účtů vést přes jediný podporovaný proces s ověřením identity, scoped oprávněními a admission. Samotné interní `*_pure` helpery běží jako invoker; jejich EXECUTE není samo o sobě důkaz možnosti zápisu do Auth.

## Nálezy se střední prioritou

### DB03 - Libovolný přihlášený uživatel čte skupiny a jejich členství

- `public.user_group_info` a `public.user_groups` mají permissive SELECT politiku `Enable select to all auth` s `USING (true)` a odpovídající tabulkové SELECT granty. Restrictive demo fence omezuje demo, nikoli běžné akce podle členství.
- Simulovaný authenticated uživatel bez členství na akcích organizace 1 viděl jak podrobnosti skupin, tak členství. Anonymní HTTP kontrola naopak nevrátila členství, což odpovídá omezení na authenticated.
- Zpřístupněné sloupce zahrnují `user`, `group`, `is_admin`, `leader`, `place`, `description` a `data`. Nebyl vypisován jejich zákaznický obsah. Dopad je odhalení účasti a rolí ve skupinách; citlivost volných polí může závažnost dále zvýšit.
- Zdroj: `database/policies/02_policies.sql:630` a `:665`; [živé politiky](security-audit-2026-10-18-db/catalog-evidence.json), výsledky `unrelated_authenticated_visibility`.
- Náprava: odstranit globální povolení a zachovat scoped přístup editorů a legitimních členů skupiny. Zkontrolovat také `exclusive_groups/exclusive_events`, kde katalog obsahuje obdobné globální authenticated čtení; jejich zákaznický dopad se samostatně neověřoval.

### DB04 - Anonym čte individuální záznamy o čtení novinek

- `public.user_news` má živou permissive politiku `select for all`, role PUBLIC, `USING (true)`. Anon má SELECT. Demo fence nechrání běžné akce.
- Anonymní SQL i veřejné HTTP GET vracejí existenci záznamu organizace 1. Tabulka obsahuje UUID uživatele, akci, poslední čtenou novinku a čas.
- Dopad: deanonymizovatelné údaje o aktivitě a účasti uživatelů. Veřejný souhrnný počet přečtení nevyžaduje přístup k individuálním markerům.
- Důkaz: [živá politika](security-audit-2026-10-18-db/catalog-evidence.json), výsledky `anon_visibility.user_news_visible` a `news_read_markers`. `supabase/migrations/20260803153000_restore_event_relations_and_news_views.sql:28` popisuje rozdíl mezi privátním markerem a veřejným agregátem. Samostatná definice této veřejné SELECT politiky není v aktuálním `database/policies/02_policies.sql`, jehož sekce začíná na ř. 699.
- Náprava: zrušit plošný SELECT; ponechat vlastní marker a oprávněné editory. Veřejně poskytovat jen zamýšlené agregáty. Ověřit i přímé REST/GraphQL čtení vedle RPC a synchronizace.

### DB05 - Skryté akce lze anonymně vylistovat přes REST

- `public.occasions` dovoluje PUBLIC SELECT přes `Enable read for all`, `USING (true)`. Tabulkový grant umožňuje anonymní čtení všech sloupců bez dalšího sloupcového omezení.
- `organization=eq.1&is_hidden=eq.true&select=id&limit=1` vrací HTTP 200 a řádek. SQL potvrzuje totéž. Nejde pouze o hypotetickou existenci budoucího skrytého záznamu.
- Dopad: odhalení existence a dostupných podrobností skrytých akcí. Veřejné RPC a publisher přitom `is_hidden` filtrují, takže přímá tabulková cesta obchází jejich viditelnost. Samotné `is_open=false` neinterpretuji jako univerzální požadavek utajení.
- Zdroj: `database/policies/02_policies.sql:513`; `supabase/migrations/20260803153000_restore_event_relations_and_news_views.sql:81`; výsledky `hidden_occasions`.
- Náprava: veřejný SELECT omezit na skutečně publikovatelné akce a vhodné sloupce; odděleně zachovat oprávněné editory a účastníky. Podobné `USING (true)` je na dalších obsahových tabulkách. Kontrola skrytých `information` v organizaci 1 nevrátila řádek; konkrétní únik jejich obsahu proto netvrdím.

### DB06 - Manažer libovolné akce má nescopované čtení emailových šablon

- SELECT politika na `public.email_templates` používá `get_is_manager_on_any_occasion() OR get_is_admin_on_organization(organization)`. První větev nemá žádnou vazbu na organizaci, jednotku nebo akci čtené šablony.
- Definice helperu vrací true podle libovolného manažerského členství. Přímé čtení tak povoluje i šablony mimo spravovaný rozsah, pokud je nevyloučí další restrictive demo fence. Současné `get_all_email_templates` naopak kontroluje konkrétní hierarchii.
- Dopad: širší dostupnost předmětů, HTML a interní komunikace jiných pořadatelů. Nález je potvrzený z politiky a helperu; v organizaci 1 se nepodařilo najít vhodnou dvojici manažer/cizí konkrétní šablona pro datovou reprodukci. Cizí tenant nebyl kvůli důkazu procházen.
- Zdroj: `database/policies/02_policies.sql:5`; [helper, ř. 99](security-audit-2026-10-18-db/live-definitions.sql#L99), `database/functions/others/get_all_email_templates.sql`. Negativní výsledek hledání dvojice je zachován jako `unscoped_template_manager.candidate_selected=false`.
- Náprava: použít oprávnění odvozená od scope konkrétní šablony, případně zrušit klientské čtení tabulky a používat jen autorizované RPC. Totéž globální manažerské rozhodnutí je také v registračních wrapperech `create_user_in_organization_with_data_ws.sql:19` a `create_user_from_registration.sql:26`; zahrnout do následné opravy scoped registrace.

## Co současné kontroly potvrdily

- Dříve kritické `migrate_users_to_org`, `update_spot`, `apply_allocations_claim_only` a `send_email_mailersend` v kontrolovaném živém katalogu nejsou.
- Tři externí synchronizační politiky jsou omezené na `service_role`.
- Žádná kontrolovaná tabulka bez RLS nemá klientské CRUD granty. V `public` má RLS 107 ze 109 tabulek, v `eshop` 32 ze 32, ve `storage` 10 ze 10. Samotná přítomnost RLS nepokrývá výše uvedené logické chyby.
- Na `public/eshop` není klientský TRUNCATE. Klienti nemají CREATE na těchto schématech. Nebyl nalezen klientsky spustitelný public SECURITY DEFINER bez explicitního search_path ani klientský EXECUTE pro dblink.
- Počet public SECURITY DEFINER je 679, z toho anon EXECUTE 218 a authenticated EXECUTE 431. Samotné počty nejsou nález.

## Další provozní dluh a limity auditu

Výchozí ACL vlastníka `postgres` nadále dávají novým tabulkám `public/eshop` široké klientské granty včetně TRUNCATE a novým funkcím klientský EXECUTE. Opravy existujících objektů proto samy nezabrání návratu problému při další migraci. Tři storage tabulky (`buckets`, `objects`, `buckets_analytics`) stále mají klientský TRUNCATE; není tím prokázána veřejná HTTP cesta k jeho spuštění. Řešit jako preventivní grant hardening s ohledem na podporu Storage.

Neověřovala se kompletní historie přístupů, kompromitace účtů, obsah souborů, kompletní GraphQL chování, bezpečnost všech Edge Functions, cloudový control plane, úplnost obnovy záloh ani zátěžové limity. Není zde prohlášení, že mimo uvedené nálezy je databáze bezpečná. Nové funkční testy a migrační nápravy mají běžet na izolované databázi, nikoli jako rollback fixtures v produkci.

## Doporučené pořadí nápravy

1. Uzavřít obě historická RPC z DB01/DB02, ověřit závislosti a všechna přetížení. Zkontrolovat další historické zapisovače do Auth podle stejného pravidla.
2. Opravit RLS pro skupiny, privátní markery novinek a skryté akce; při tom zachovat legitimní veřejné projekce a synchronizaci.
3. Omezit šablony a registrační oprávnění na scope konkrétního objektu.
4. Doplnit negativní testy přímé tabulkové cesty, RPC i GraphQL a kontrolu efektivních grantů po každé migraci. Upravit výchozí ACL, aby nové objekty nebyly automaticky klientsky dostupné.

Reprodukční dotazy, ověřené živé definice s SHA-256 a sanitizované výsledky jsou v [adresáři důkazů](security-audit-2026-10-18-db/). Audit přidal pouze tento report a důkazní artefakty; nic nenasazoval.
