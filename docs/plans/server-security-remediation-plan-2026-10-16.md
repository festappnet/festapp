# Oprava zabezpečení a provozních limitů serveru Festapp

Datum: 2026-10-16  
Stav: Balíky A/B lokálně implementované a cíleně ověřené; C má hotové provozní nástroje, sizing a skutečný recovery důkaz čekají. Produkce nezměněna.  
Ověření: standard - bezpečnost, autentizace, migrace a sdílený produkční backend

Aktuální revize 2026-10-16 12:06 UTC: [PR #459](https://github.com/festappnet/festapp/pull/459) je sloučené do main `a95067e26d7b1d17009fa6100145708750833133` a abuse ochrana je již nasazená. Nezávislý read-only katalog potvrdil migraci `20261016100000` i abuse_policy_rules. Live Auth má trusted IP header i aktivní password hook; live Caddy má origin allowlist, trusted header, timeouty a body capy. Sousední session oznámila hotový web vstupenky.online `0.20.247+731`. Tři P0 RPC mají stále anon/authenticated EXECUTE a sync politiky stále PUBLIC ALL. Navazující práce začíná chybějícím SQL z aktuálního main, ne čekáním na release nebo přenosem starého diffu. Obecný 32MB cap stále potřebuje sladit s 50MiB Storage kontraktem. Podrobnosti vlastní [sjednocení prací](security-work-reconciliation-2026-10-16.md).

## Pokračování nasazení

Navazující pokyn uživatele „Pokračuj, dokud to nebude hotové komplet“ autorizuje publikaci a nasazení připraveného opravného balíku včetně ověření. Upstream main se posunul na `a849430662023c08517b1a7ffece0c89a6148820`; oba příchozí commity se týkají UI/reportů a byly začleněné bez konfliktu. Produkce již má jejich migrace 150000/153000. Bezprostřední pre-push fetch dále přinesl `cf699e154` (image-worker upload policy a report microcopy), bez překryvu s backendovým balíkem; změna byla začleněna rebasem. Dosud nepublikované bezpečnostní migrace byly proto před první aplikací přesunuty na `20261016170000`, `20261016171000`, `20261016172000`. Nová čistá PG17 dávka se všemi migracemi z aktuálního main prošla (12 Node testů, 6 SQL sad, 28 scan kontrol). Původní abuse migrace zůstává nezměněná. GitHub branch protection má review count 1, ale enforce_admins=false; ověřený přihlášený účet miakh má admin=true. Pro tento účet není review vynucené. Podle uživatelského výchozího postupu proto publikace používá ověřený přímý push na main, bez změny pravidel repozitáře.

## Lokální realizace 2026-10-16 - aktuální stav

Tato sekce nahrazuje starší plánovací formulace o neautorizované implementaci. Navazující zadání autorizovalo lokální kód, cílené testy a read-only diagnostiku, nikoli commit/push ani produkční změny. Vlastní čistý worktree je `/private/tmp/festapp-server-security-20261016`, větev `fix/server-security-remediation-20261016`, main při jediném fetchi `a95067e26d7b1d17009fa6100145708750833133`. Původní checkout zůstal zachován; přeneseny pouze tento plán, prompt, reconciliation a audit.

**Hotový balík A:** nová nezávislá P0 migrace `20261016170000_server_security_containment.sql`; navazující `20261016171000_server_security_authorization.sql` odstraňuje bez CASCADE tři mrtvá RPC i legacy MailerSend sender, opravuje každou položku inventory batch a uzavírá všechny klientské CRUD/čtení sync tabulek i jejich sekvenci. Zůstává pouze service policy a service writer `add_sync_map`. `apply_allocations` nebylo přesměrováno ani měněno. Autorizační kontrola je `IS NOT TRUE`; kontroluje obě místa, jejich kontext/pool/akci, předchozí resource, slot a cílový resource. Zámky řadí cílové resource; překročení resource/slot kapacity vrací celou dávku zpět. Klient nadále posílá existující `inventory_context_id`.

**Hotový balík B:** `20261016172000_server_security_hygiene.sql` nastavuje cestu 79 konkrétním aplikačním signaturám z live katalogu, nezasahuje do těl extension funkcí a odnímá klientské TRUNCATE/REFERENCES/TRIGGER i EXECUTE na http/dblink. Kanonické aplikační zdroje již správný search_path měly; nová migrace opravuje jejich živý drift. Extension ACL skutečně vlastní `supabase_admin`, proto se hygienická migrace spouští tímto účtem a fail-closed odmítá nesprávného uživatele. Lokální bootstrap nyní používá stejný účet pro dopředné migrace a zachovává postgres vlastníky baseline. `RESET ROLE` vrací migrační CLI z jím nastavené role postgres k přihlášenému extension adminovi.

Storage má samostatný 52MiB Caddy limit před běžným API matcherem. Úzký `apply-security-config.sh` validuje uzamčený a otiskem ověřený kandidát v root-only evidenci, zachová předchozí soubor, reloaduje pouze Caddy a porovná skutečnou admin API konfiguraci. Čtecí `audit-security-state.sql` ověřuje nepřítomnost všech overloadů mrtvých jmen, efektivní práva včetně PUBLIC dědičnosti, skutečné service policies, extension ACL, search_path, monitoring credential hranici a bezpečně vybraná per-role nastavení. Manifest je `database/functions/security/server_security_acl_manifest.json`; CI policy gate prochází všechny kanonické SQL zdroje; 504 existujících hlaviček má kompatibilní snapshot v `definer_contracts.json` (není to nový audit). Každá nová nebo změněná definer hlavička vyžaduje deklarovanou přesnou signaturu, role ACL, search_path a explicitní REVOKE ve zdroji. Test rovněž prokazuje zamítnutí nedeklarovaného nového defineru.

**Hotová lokální část C:** existující host monitor a jeho stejný `agent` heartbeat nyní detekují OOM, zastavený/restartovaný kontejner, transakci přes 15 minut a zastaralou off-host backup/log evidenci. Root-only `ExecStartPre` sbírá pevné diagnostické dotazy a předává pouze sanitizované počty, stavy a časy; nevytváří druhý monitor, token, sender ani službu. Pozorovací hranice 26 hodin pro denní backup a 2 hodiny pro hodinový log upload nejsou kapacitní hard capy. `collect-resource-budget.sh` je jednorázový čtecí sběr RAM/CPU/PIDs/DB connection dat pro reprezentativní špičku a zálohu. Numerický součet hard limitů zatím není určen, protože reprezentativní vzorky nejsou k dispozici; žádné libovolné limity nebyly zavedené.

`restore/drill-online-backup-local.py` podporuje skutečný online manifest v1, všechny čtyři šifrované artefakty a nový lokální PG17 kontejner s `--network none`, bez portů, host mountů, aplikačních služeb a vykonávání runtime archivu. Cron metadata, která nelze bezpečně obnovit mimo scheduler DB, jsou explicitně vynechána. Ověřuje šifrované digesty, dešifrování, archive path safety, obnovu globals/DB a čtecí DB smoke. Kontejner i dešifrované soubory odstraní; při chybě ponechá jen chráněný diagnostický log. Historický koordinovaný drill nově defaultuje na chráněný SSH alias, nikoli veřejnou IP. Provozní backupy, jejich retence ani klíče nebyly měněny.

**Cílená evidence:** izolovaný Supabase PostgreSQL 17.6, standardní baseline a celé dopředné pořadí včetně nezměněné abuse migrace. Prošlo 10 Node RPC/sync testů, 1 skutečný dvouspojení inventory souběh a 1 test transakčních deployment driverů. Původní batch chyba se skutečně reprodukuje nad dvěma tenanty uvnitř rollbackované fixture; následně projde opravená varianta včetně NULL permission, mixed-batch rollbacku a service upsertu. Prošlo 6 SQL sad (`rpc_object_authorization`, `full_deposit_flow`, `on_site_surcharge_flow`, `overpayment_flow`, `get_inventory_pools_tenant_scope`, `event_attendance_summary`) a 28 scan/attendance assertions. Skutečný pinned Caddy prošel 50MiB+overhead uploadem na object/resumable/copy cestách, fixed/chunked 413 testy, trusted IP a websocket handshake/echo. Šlo o proxy transport s izolovaným echo upstreamem, nikoli o nový end-to-end Storage/Auth test.

Prošly stávající infrastructure/backup testy, abuse policy a assembler parity, migration layout, nové package/activation guardy a 4 host-monitor metrické testy. Sanitizace root observeru má 2 unit scénáře. Syntetická šifrovaná obnova do pinned PG17 prošla za 4.03 s; tento čas není produkční RTO. Sanitizovaný výsledek je v `docs/operations/security-remediation-20261016/synthetic-restore-result.json`, souhrn v `verification.json`. Reálný nejnovější produkční backup nebyl exportován/obnoven a key-loss recovery ani PITR tím nejsou doložené. Web/Flutter ani celé historické Deno/worker sady se beze změny klienta neopakovaly.

**Live read-only důkaz:** tenant festapp na `https://live.festapp.net/backend-activation.json` je canonical generation 1, organizace 1; hostname, runtime .env DB a `current_database()` souhlasí. Potvrzeno PUBLIC/anon/authenticated EXECUTE všech tří RPC a senderu, PUBLIC ALL všech tří sync politik, žádný uložený caller ani pg_depend závislost. Kontrola správného control-plane `postgres.cron.job` našla 0 callerů těchto jmen; cílová aplikační DB cron schéma nemá. Dostupná agregovaná klientská access log historie nebyla analyzována, takže nelze slíbit absenci historického mobilního klienta; nechráněný zápis se přesto nezachovává. Aktivní password hook i trusted header byly potvrzené; ostatní efektivní Auth defaulty nejsou odvozené z absence env proměnné.

### Připravený deployment balík - až po navazujícím pokynu

Autoritativní soubory, pořadí, účty a SHA-256 vlastní `automation/hetzner-supabase/runtime/server-security-release.json`. Generátor `python3 automation/assemble-server-security-migrations.py --check` ověřuje parity zdrojů, migrací, self-contained psql driverů i runtime digestů. Žádná z těchto nových migrací není v produkci aplikovaná.

1. Před publikací obnovit upstream main a vyřešit případný drift; publikaci provést až v rozsahu nového pověření. Před nasazením ověřit canonical target a aktuální ledger/ACL, poslední off-host backup receipt a runtime digesty. Do root-only evidence zachovat původní definice/ACL čtyř odstraňovaných funkcí. Neobnovovat secrets z root checkoutu a neměnit abuse migraci.
2. Ze schváleného checkoutu použít samostatně driver `automation/hetzner-supabase/runtime/apply-server-security-containment.sql` přes `ssh festapp-backend-agent 'docker exec -i supabase-db psql -X -U postgres -d festapp_rehearsal_20260909220601 -v ON_ERROR_STOP=1' < <driver>`. Driver má explicitní cílový guard, transakční lock, SQL i ledger v jedné transakci a NOTIFY PostgREST. Po něm katalog všech tří přesných signatur musí mít efektivní anon/authenticated EXECUTE false.
3. Stejně aplikovat `apply-server-security-authorization.sql` jako postgres, následně `apply-server-security-hygiene.sql` jako **supabase_admin**. Driver odmítá replay již evidované verze. Každý je self-contained, nevyžaduje kopírování SQL souborů do kontejneru. Finální readback: do stejného psql připojení poslat `BEGIN READ ONLY;`, obsah `audit-security-state.sql`, `COMMIT;`. Passing výsledek nevychází pouze z ledgeru. Nespouštět produkční fixture nebo zapisovací smoke bez zvlášť určených testovacích dat.
4. Caddy změnu oddělit od SQL. Root-only staging ze schváleného checkoutu, ověření všech runtime digestů manifestu; na ověřeném hostu `FESTAPP_SECURITY_CONFIG_ACK=reload-approved-storage-body-cap ./apply-security-config.sh /root/<staging>/Caddyfile <Caddyfile-SHA256-z-manifestu>`. Skript reloaduje pouze Caddy; následují povolené čtecí API/websocket canaries a kontrola aktivního digestu. Žádná historická promotion, nový Auth hook, restart všech služeb ani web release.
5. Pro monitoring zabalit existující pinned `sdk.mjs`, `LICENSE` a chráněný token se změněnými `agent.mjs`, `metrics.mjs`, `runtime-evidence.py`, unit/timer a installerem; vytvořit nový SHA256SUMS a použít existující install workflow. Beze změny identity/tokenu ověřit timer, přesně 4 přijaté heartbeaty a doručení alertu. Reprezentativní vzorky resource collectoru přes špičku a backup převést na schválený číselný Compose budget s rezervou OS/DB/backup. Teprve pak vynucovat capy; případné navýšení placené kapacity vyžaduje rozhodnutí.
6. Po zvlášť povoleném zpřístupnění skutečné šifrované backup sady a existujícího identity souboru spustit lokální `python3 automation/hetzner-supabase/restore/drill-online-backup-local.py --backup-dir <protected-set> --identity <protected-existing-key> --evidence <new-protected-result.json>`. Nekopírovat produkční data/klíče do repozitáře. Odděleně doložit key-loss recovery, aplikační/cross-store konzistenci a přijmout RPO/RTO: denní online dump není PITR. Pro RPO 15 minut je nutný podporovaný base backup + šifrované off-host WAL, retenční sizing a skutečná point-in-time obnova, nikoli pouze archive_mode.

**Rollback:** před commitem selhání abortuje danou SQL transakci včetně ledgeru. Po commitu pouze dopředná oprava oprávněné cesty; žádný návrat veřejných destruktivních grantů, PUBLIC ALL ani přímého senderu/importeru. Neočekávaná DROP závislost zastaví kontrakci, P0 zůstává. Proxy má chráněnou předchozí konfiguraci, návrat je povolen jen na prokazatelně bezpečnou variantu. Monitoring lze vrátit k předchozímu podepsanému balíku při zachování stávajících alertů/tokenu. Restore drill není automatická obnova produkce.

**Zbývající provozní důkazy:** schválené nasazení a live ACL/config readback; skutečné doručení alertů; reprezentativní resource budget a jeho burst test; provider firewall včetně IPv6, konkrétní Access MFA/session policy a efektivní Auth defaulty; skutečný backup/key-loss/consistency drill; recovery cíl/PITR a případné servisní okno/restart. Billing/provider evidence zůstává u původní abuse práce. Tyto body neblokují připravené samostatné P0 SQL a nejsou označené jako opravená produkce.

## Výsledek a rozsah

Uzavřít potvrzené neautorizované zápisy, sladit skutečné oprávnění s kanonickými zdroji, nasadit ověřenou síťovou ochranu a zavést měřené provozní limity a doloženou obnovu. Legitimní přihlášení, nákup, rezervace, platby, skenování a doručování vstupenek musí fungovat po každé vlně.

Autoritativní podklad: [audit živého serveru](../operations/security-audit-2026-10-16.md). Tento dokument určuje pořadí a dokončení oprav jeho nálezů. [Plán ochrany proti zneužití](abuse-prevention-plan-2026-10-16.md) zůstává vlastníkem širších aplikačních budgetů a fair use; nevytvářet jeho druhou implementaci. Potvrzená kritická RPC nesmějí čekat na dokončení obecného limiteru. [Starší plán](security-remediation-plan-2026-10-09.md) je historický podklad; jeho stav nasazení ověřovat podle nového auditu a aktuálního katalogu, nikoli kopírovat.

Rozsah: sdílené SQL/RLS/ACL, infrastruktura canonical API, Auth, kontejnery, monitoring, zálohy a provozní důkaz. Nevydávat automaticky jiné tenantové větve ani Android/iOS. Web Festappu vydat pouze tehdy, pokud oprava skutečně vyžaduje změnu klienta; cílová větev je `prod/festapp`. Změna sdíleného backendu přesto ovlivňuje všechny jeho tenanty, což musí pokrýt izolované testy.

Uživatel nyní objednal plán. Tento krok neautorizuje implementaci, produkční zápisy, restart, nákup kapacity, změnu Cloudflare/Hetzner pravidel, commit ani push. Při navazujícím pověření posoudit již udělený rozsah a nevyžadovat opakovaně totéž schválení.

## Výchozí bod a důkazy

Pracovní větev při plánování: `feat/occasion-setup-wizard-20261007`, HEAD `eb23047248d59bf86345b9e0b79db4a988275231`, s rozsáhlými cizími i souvisejícími necommitnutými změnami. Pro implementaci použít čistý checkout/worktree z aktuálního autoritativního main; potřebné rozpracované soubory porovnat a převzít výslovně, nikoli celý pracovní diff.

| Fakt | Důkaz | Rozhodnutí |
| --- | --- | --- |
| `migrate_users_to_org` je veřejný definer bez autorizace a mění všechny auth emaily | Živý katalog, tělo a SHA-256 v auditu; bezpečný HTTP důkaz dosažitelnosti | První samostatný bezpečnostní balík, bez čekání na infra |
| `update_spot` a `apply_allocations_claim_only` dovolují anonymní privilegované zápisy | Živé definice a ACL v auditu | Uzavřít přímé vstupy; zachovat pouze prokázané klientské/interní kontrakty |
| V aktivních Dart/JS/Edge a kanonických funkcích nebyli textově nalezeni volající těchto tří jmen; definice jsou v baseline | Cílené rg, `supabase/baseline/20260805230000_production_schema.sql` | Kandidáti k odstranění, nikoli automatický důkaz nepoužívání starými klienty nebo dynamickým SQL |
| Aktuální batch náhrada kontroluje akci jen v první iteraci | `database/functions/inventory/update_spots_assignments.sql`: `update_spot_assignments` | Neoznačit ji automaticky za bezpečnou náhradu; ověřit každý cílový objekt a NULL výsledek permission helperu |
| `apply_allocations` má odlišné chování včetně uvolňování míst a lock helperu | `database/functions/inventory/apply_allocations.sql` | Nenahradit claim-only pouhým přesměrováním bez testu sémantiky |
| Tři sync tabulky mají PUBLIC ALL true politiku a klientské CRUD granty | Živý katalog a čtecí HTTP kontroly v auditu | Omezit skutečné politiky a granty, ne jen přejmenovat policy |
| Úložiště má pouze restrictive policy, která sama nepovoluje přístup | Živé pg_policies a čtecí kontroly v auditu | Nepřidávat permissive policy a neřešit domnělý únik plošným přepisem Storage |
| Připravené Caddy/Compose ochrany nejsou živou konfigurací | Audit a pracovní `runtime/Caddyfile`, `docker-compose.festapp.yml` | Nasadit až schválený a kompatibilní soubor z main |
| Runtime upgrade skript jen instaluje kandidáty, promotion skript řeší historický cutover a write barrier | `upgrade-installed-production-runtime.sh`, `promote-production-runtime.sh` | Samotný upgrade není deploy; neopakovat historickou promotion kvůli proxy opravě |
| 13 kontejnerů bez RAM/CPU/PID limitů, host cca 4 GB bez swapu | Živé inspect/stats v auditu | Rozpočet podle spotřeby, žádná vymyšlená garance počtu uživatelů |
| Záloha je aktuální, šifrovaná a off-host; PITR není doložen | Receipt a archive_mode=off v auditu | Nejprve ověřit obnovu, potom rozhodnout o kontinuitě WAL |

## Cílové invarianty

1. Veřejná zapisovací operace nejprve ověří identitu nebo podporované tajné oprávnění a odvodí tenant/akci z uložených objektů. Klientem tvrzená role ani libovolné ID nestačí.
2. `SECURITY DEFINER` není náhradou autorizace. Každá měněná funkce má explicitní bezpečný search_path a kvalifikované eshop tabulky; výsledek permission helperu NULL musí zamítnout.
3. Interní helper může být volán vlastníkem z autorizovaného commandu, ale nemá přímý EXECUTE pro PUBLIC/anon/authenticated. Nevkládat service-role JWT podmínku do helperu, který oprávněně volá uživatelský definer se zachovaným JWT uživatele.
4. Změny místa, resource, slotu a objednávky nesmějí propojit cizí akce. U batch vstupu se ověřuje každá položka; odmítnutí jedné nezanechá částečný zápis.
5. RLS i ACL platí pro přímý REST a všechny overloady, staré RPC a vnitřní alternativy. Klientská UI ochrana nestačí.
6. Pořadí zámků, atomické objednávky, retry a stávající emailová fronta zůstávají u současných vlastníků; žádný druhý sender, quota framework ani aplikační trigger.
7. Nasazení má strojově ověřený readback definic, efektivních grantů, politik a běžící konfigurace. Ledger není jediný důkaz.
8. Rollback nikdy automaticky neobnoví veřejné destruktivní granty ani neotevře origin/administraci. Při regresi se opraví konkrétní legitimní cesta.
9. Zachovat výslovně potvrzené trvalé opakovaně použitelné šestimístné heslo. Již implementované omezení pokusů a rozesílání není povolením změnit jeho platnost nebo invalidovat existující účty/session.

## Rozhodnutí, předpoklady a vnější závislosti

**Rozhodnutí:** prioritou je P0 SQL containment, pak úplné odstranění bypassů, poté síť a dostupnost. Žádná datová migrace identit ani hromadná rotace přihlašování není součástí nápravy zranitelného migrátoru. Audit nepotvrdil incident; před mazáním historických funkcí zachovat jejich definice a ACL v chráněné evidenci.

**Předpoklad:** tři stará RPC nejsou podporovaným veřejným kontraktem. Implementátor to ověří cíleně v aktivním main, DB závislostech, SQL/cron/Edge callerech a dostupných aggregate access logs bez zákaznických payloadů. PL/pgSQL a dynamické SQL nemusí mít úplné pg_depend. Pokud aktivní klient existuje, zachovat jeho signaturu pouze jako autorizovanou fasádu; migrátor identity se veřejným kontraktem nestane. Chybějící telemetrie není důvod ponechat nechráněný veřejný zápis.

**Vnější závislosti:** přesná Cloudflare Access/WAF a provider firewall pravidla nejsou ověřena. Jejich čtení musí použít oprávněný účet; pokud přístup chybí, dokončit kód a testy a uvést konkrétní chybějící důkaz. Změna kapacity s cenou, řízený restart a přijatelná ztráta dat vyžadují provozní rozhodnutí. Navržený recovery cíl pro ocenění variant je RPO do 15 minut a RTO do 2 hodin, zatím nikoli schválené SLA.

## Vlny realizace

### Závazný postup rychlé realizace

Následující vlny jsou technický rozpis, nikoli požadavek na sedm průzkumů, sedm release nebo samostatné schválení každého souboru. Bezpečnostní ověření zůstává standard; šetří se opakováním a rozsahem práce, nikoli vynecháním autorizace a testů.

1. **Jednou obnovit výchozí stav:** aktuální main/release, vlastník běžícího deploye a jeden úzký read-only katalog opravovaných RPC/politik. Výsledek zapsat a dál kontrolovat jen konkrétní nový rozpor nebo stav před nasazením. Neopakovat celý audit, inventář endpointů, všechny session logy ani historii plánování.
2. **Balík A - skutečně chybějící bezpečnostní opravy:** spojit práci vln 0-2 do jednoho souvislého implementačního celku. P0 zachovat jako malou samostatně použitelnou migraci; související autorizaci inventáře a sync ACL doplnit ve stejném tasku. Začít hotovým kódem z main, dohledat jen přímé callery/dependence opravovaných signatur. Připravit jeden reviewovatelný balík bez čekání na obecnou hygienu všech funkcí, metriky kapacity nebo PITR. Pokud jiná část zadrhne, P0 již musí být konkrétně hotové a ověřitelné.
3. **Balík B - rozdíl proti živému runtime:** z vln 3-4 implementovat pouze dosud chybějící ochrany a související drift kontrolu. Neopravovat znovu již začleněný limiter, monitoring, transport ani Auth hook. Hotovou hygienu přímo dotčených symbolů připojit k balíku A; plošnou hygienou neblokovat potvrzené exploity. Žádný Flutter/web build, pokud se nemění klientský kód nebo jej nevyžaduje skutečná release brána.
4. **Balík C - provoz:** vlny 5-6 připravit jako konkrétní konfiguraci a runbook, využít existující monitoring a restore tooling. Čekání na reprezentativní metriky, servisní okno, provider přístup nebo rozhodnutí o RPO/PITR evidovat přesně a pokračovat nezávislou prací. Tyto závislosti neblokují hotové bezpečnostní SQL a nejsou důvodem vytvářet nový framework.
5. **Ověřovat po souvislém celku:** jedna cílená validační dávka pro balík, ne po každé editaci. Pro A skutečné negativní/pozitivní role, dvoutenantový inventory/sync a relevantní objednávkové regrese v jednom izolovaném prostředí; pro B pouze změněná konfigurace/komponenty. Passing důkazy navázat na source SHA a používat je dál, dokud se nezmění pokrytý kód, závislosti, cílový runtime nebo relevantní upstream. Povinné CI/release gates zůstávají.
6. **Krátká předávka:** aktualizovat stav těchto existujících dokumentů, nezakládat další obecný plán, audit nebo checklist. Stručně uvést hotový balík, výsledek testů, přesné nasazovací soubory a konkrétní blokovaný provozní krok. Produkční approval řešit až nad tímto výsledkem a nevyžadovat znovu již udělenou autoritu. Nečekat ani nezasahovat do cizího deploye, pokud lze mezitím dokončit izolovaný P0 follow-up.

### 0. Uzamknout rozsah a připravit samostatný balík

**Změny:** přečíst CLAUDE/ai_context, tento plán, audit a backend-access skill; zaznamenat current main SHA a seznam převzatých změn. Zopakovat pouze cílený read-only katalog dotčených signatur a ACL a ověření canonical aktivace, hostname, databáze a organizace. Uložit bezpečnou evidenci před opravou bez klíčů a zákaznických řádků. Při rozdílu otisků aktualizovat předpoklady plánu.

Abuse balík je již na main a nasazený. Použít čistý taskový worktree z aktuálního main; není třeba přenos abuse zdrojů ani opětovná aktivace. Root rozpracovaná kopie není novým zdrojem implementace. Přenést pouze tento plán, prompt a audit, pokud na main chybí. Jednou ověřit aktuální head a cílené ACL; oprava pokračuje přímo novou dopřednou migrací po skutečně aplikovaných verzích.

**Ověření/výstup:** seznam přesných signatur, vlastníků, grantů PUBLIC a rolí, relevantních callerů a stavu vůči main. Žádná obnova cloudového zdroje, zásah do cizího worktree nebo produkční fixtures. Tato vlna nemá blokovat P0 obecným inventářem celého projektu.

### 1. P0: uzavřít veřejné destruktivní RPC

**Změny:** doplnit kanonický retirement/ACL soubor v `database/functions/security/` a novou dopřednou migraci pojmenovanou `*_server_security_containment.sql`; timestamp zvolit podle aktuální migrační řady. Explicitně REVOKE od PUBLIC, anon a authenticated pro přesné signatury `migrate_users_to_org(bigint)`, `apply_allocations_claim_only(bigint)` a `update_spot(jsonb)`. Případný prokázaný veřejný caller `update_spot` musí dostat ve stejném balíku autorizovanou fasádu, nikoli odklad zabezpečení. Interní vlastník si zachová potřebné volání.

**Migrace/kompatibilita:** neměnit již aplikovanou baseline ani starou migraci. Zachovat definice pro chráněnou evidenci; odstranění objektů je až ve vlně 2. Nevypínat objednávky a neodnímat blanketem všechny granty všem funkcím. Změny a ledger atomicky, bez vnitřního COMMIT v migračním souboru.

**Validace:** nový `database/tests/security/server_rpc_security_test.sql` nebo skutečný Node/pg integrační test ověří efektivní ACL včetně PUBLIC, odmítnutí anon/authenticated a absenci vedlejších zápisů. Před opravou musí stejný test na izolované kopii prokázat chybu; nikdy nespouštět migrátor nad produkčními uživateli. Přidat pozitivní interní/objednávkový průchod, pokud má helper callera.

**Výstup:** žádná ze tří signatur není přímo neautorizovaně zapisovatelná. P0 balík je samostatně reviewovatelný a nasaditelný bez runtime upgradu či frontendu.

### 2. P1: dokončit autorizaci inventáře a uzavřít sync tabulky

**Změny:** pro nepoužívané legacy funkce provést DROP bez CASCADE v samostatné dopředné migraci `*_server_security_authorization.sql`; závislosti vyřešit předem. Používané fasády musí kontrolovat skutečného aktéra a cílovou akci před zápisem. Prověřit `update_spot_assignments` v `database/functions/inventory/update_spots_assignments.sql`: staré i nové spot ID, resource, resource_slot a inventory context musí náležet povolené akci a kompatibilnímu rodiči u každé položky. Nekopírovat obecné tvrzení „první položka autorizována“ na zbytek batch. `apply_allocations` zachovat jako vlastníka současné alokační logiky; neměnit claim-only sémantiku implicitním přesměrováním.

Omezit `external_sync_sources`, `external_sync_maps`, `external_occasions_cache` na ověřené servisní writery. Politiky výslovně TO service_role, odebrat klientské INSERT/UPDATE/DELETE a další nepotřebné granty; veřejný SELECT zachovat pouze při doloženém produktovém kontraktu a s projekcí bezpečných dat. Pro současné tři interní tabulky je výchozí rozhodnutí klientské čtení také zakázat. Převést případného přímého klientského čtenáře na existující autorizované doménové čtení před odebráním jeho kontraktu. Nepřesouvat konfiguraci do nových duplicitních tabulek.

Abuse implementace již vyřazuje neaktivní neomezený SQL HTTP importer i setup před IO. Zachovat tento stav; pozitivní service test tabulek neznamená znovu zapnout importer. Retirement funkce a uzavření tabulkových grantů jsou dvě odlišné ochrany.

**Validace:** na fixture dvou tenantů a dvou akcí testovat anon, běžného uživatele, editora cizí akce, oprávněného order editora a skutečný servisní vstup. Zahrnout mixovaný batch, NULL identitu/permission výsledek, cizí slot, částečné selhání, platnou změnu, zachování kapacity a souběžnou rezervaci. Testovat výsledek a stav, ne jen zavolání helperu. Sync testy odmítnou všechny klientské CRUD a prokáží potřebný service upsert. Produkční smoke pouze čtení/katalog, legitimní zápis jen s výslovně určenými testovacími daty.

**Výstup:** opravované operace nemají druhý nechráněný vstup; RLS a granty odpovídají cílové matici, legitimní rezervace zůstávají funkční.

### 3. P1: nasadit kompatibilní síťovou hranici a doložit Auth limity

**Změny:** kanonické soubory `automation/hetzner-supabase/runtime/Caddyfile`, `docker-compose.festapp.yml`, relevantní Envoy konfigurace/generátor a infrastruktura `automation/hetzner-supabase/terraform/firewall.tf`. Ověřit skutečně používaný zdroj Envoy souborů; nevytvářet druhou neudržovanou konfiguraci. Admin Studio zůstává loopback + Cloudflare Access, machine SSH aplikace je oddělená a nezíská přístup do Studia. Zjistit konkrétní MFA/allow/session policy a skutečná provider pravidla včetně IPv6. UFW inactive není samo o sobě důvod zapnout další firewall bez mapování ochrany poskytovatele.

Caddy přepisuje klientské IP hlavičky z důvěryhodného síťového kontextu; nesmí věřit klientskému X-Festapp-Client-IP/X-Forwarded-For. Auth i Edge používají stejný ověřený zdroj. Pracovní allowlist a timeouty převzít až po ověření ACME/TLS, Cloudflare provozu a chráněného operačního přístupu.

Výchozí kompatibilní body návrh: Auth 64 KiB, běžné REST/Functions 32 MiB, Storage zvlášť alespoň 52 MiB včetně overheadu pro dnešní 50MiB upload; ověřit multipart/resumable/copy cesty. Ticket font limit 8 MiB zůstává. Pokud se má povolený upload skutečně snížit, jde o samostatnou změnu kontraktu, nikoli tichý důsledek obecného proxy limitu. Zakázat obcházení stropů chunked nebo chybějícím Content-Length. Preserve Realtime websocket spojení; 30s upstream timeout nesmí zavřít podporované dlouhé operace bez jejich inventury.

Z konkrétního GoTrue image zjistit efektivní limity password, signup/OTP, recovery a refresh, refresh rotaci, minimum hesla a CAPTCHA. Do výsledného manifestu uložit explicitní hodnoty a původ každé hodnoty. Výchozí nastavení není totéž co vypnuto. Nestanovovat čísla pro refresh bez počtu aktivních session; neinvalidovat existující hesla/session. Chybějící veřejné API limity doplnit ve vrstvě popsané abuse plánem, pro RPC i přímé REST vstupy; žádný paralelní limiter zde.

Native password admission a trusted-header config jsou podle live readbacku již aktivní. Znovu je nezapínat ani neměnit existující secret/usage. Zde provést jen zbývající efektivní limit readback a konkrétní config opravy, zejména rozdíl Storage body capu. Zachovat dosavadní pozitivní test starého šestimístného hesla; plošné vynucení nového minima na existující hesla by porušilo potvrzený kontrakt.

**Nasazovací mechanismus:** rozšířit vhodný existující in-place runtime postup nebo doplnit úzký `runtime/apply-security-config.sh`, který drží zámek, ověří target a digesty, uchová root-only předchozí konfiguraci, validuje Caddy/Compose a restartuje/reloaduje jen dotčené služby. `upgrade-installed-production-runtime.sh` samotný kandidáty neaktivuje. Nespouštět `promote-production-runtime.sh` s historickými import/cutover gates a nezavírat běžné produkční zápisy kvůli běžné proxy změně. Nevypisovat plný `docker compose config` s tajemstvími.

**Validace:** `node --test automation/tests/hetzner_supabase_infrastructure.test.mjs` s relevantním doplněním; izolovaný runtime test skutečně odmítne podvržené hlavičky a nadlimitní/chunked body, přijme 50MiB upload a udrží websocket. Auth negativní a recovery pozitivní scénáře jen izolovaně. Pro live ověřit veřejné/neveřejné porty z vnějšího bodu, Access 302, admin/meta 404 na veřejném API a běžné API canaries; skutečný přístup administrátora neměnit simulovaným sdíleným loginem.

**Výstup:** uložený důkaz živé síťové konfigurace, důvěryhodné IP a efektivních Auth/API limitů; otevřené chybějící control-plane důkazy se nesmějí označit za hotové.

### 4. P2: zúžit zbývající granty a zavést důkaz proti driftu

**Změny:** pro 88 funkcí bez search_path rozlišit aplikaci a rozšíření, callery, vlastníka a potřebné role. Aplikační funkce opravit v kanonických souborech i nové migraci; eshop názvy kvalifikovat. Extension-owned funkce neupravovat slepě jednotlivými definicemi; řešit podporované schéma/ACL s ohledem na upgrade. Ne všechny anonymně volatelné funkce zakazovat - veřejné formuláře a scan s platným tajným kódem jsou legitimní.

Odebrat nepotřebný TRUNCATE a další neproduktové granty na zjištěných 61 tabulkách od skutečných grantorů/PUBLIC, pokud je tam děděná cesta. Dblink/HTTP rozšíření zpřístupnit pouze doloženým interním rolím; zachovat existující schválené integrace. Odstranit `send_email_mailersend(jsonb,jsonb)` bez CASCADE po ověření callerů; neposkytovat mu nový token. Odesílání výhradně přes existující email queue.

Doplnit čtecí nástroj `automation/hetzner-supabase/runtime/audit-security-state.sql` a testovaný manifest očekávaných signatur/ACL/politik. Nevystavovat další veřejný diagnostický endpoint a nezřizovat slibovaný, ale neaktivní restricted broker. Kontrola musí zahrnout efektivní oprávnění, PUBLIC, overloady, skutečné `pg_policies.permissive` a per-role konfiguraci, ne jen text GRANT nebo ledger. Nový definer/interní helper bez deklarovaného ACL musí selhat v CI. Plošné ALTER DEFAULT PRIVILEGES zavádět pouze po ověření vlastníků a explicitních grantů všech dotčených tvůrců; žádný neočekávaný výpadek při další migraci.

Aktuální release již odstranil předchozí paralelní monitor capability: rozšiřuje existující `get_festapp_monitoring_health_v1` a zachovává `festapp_monitoring_credentials`, worker i heartbeat. Nepřenášet starší `get_abuse_monitor_v1`/`abuse_monitor_key` z root kopie ani generovat náhradní secret jen podle starého přehledu. Ověřit scope a ACL existujícího monitoru; nesmí přerůst v obecný katalogový nebo zapisovací kanál.

**Validace:** izolovaná skutečná DB na produkčně odpovídajícím PostgreSQL 17 a aplikačních schématech. Test nevytvoří falešný nález pro jedinou restrictive Storage policy, odhalí PUBLIC grant a odchylku i při existujícím ledger řádku. Zachovat opravy scan/attendance z října 9 a centrální email gate. Ověřit, že používaná integrační cesta funguje po zúžení extension ACL.

**Výstup:** žádný nevysvětlený chybějící search_path v aplikačních definerech, neautorizovaný TRUNCATE ani veřejný legacy sender; explicitně evidované extension výjimky mají vlastníka a minimální granty. Release readback selže při návratu opravovaných chyb.

### 5. P2: rozpočty prostředků a provozní údržba

**Změny:** sbírat paměť/CPU/pids, souběh Edge workerů a DB connection peak v reprezentativním provozu bez payloadů; první snapshot z auditu nestačí na sizing. Sepsat součet hard limitů, rezervu OS, DB a souběžné zálohy. Úpravou stejného Compose zavést skutečně vynucené RAM/PID/CPU limity tam, kde omezení jedné služby nevyhladoví kritickou cestu; nezaměňovat CPU shares za hard limit nebo 512MB worker za kontejnerový strop. Pokud host nemá bezpečnou rezervu, připravit oceněnou variantu navýšení RAM před omezováním produkce.

Začít nepovinnými/administrativními službami a Edge souběhem, pak Auth/REST a databází podle měření. Nedělat současně upgrade všech image, přepočet DB paměti a přísné capy. Zachovat diskovou rezervu, rotaci logů a funkční zálohy. Případný swap je doplněk po rozhodnutí o latenci a ochraně dat, nikoli náhrada RAM.

Z existujícího host monitoringu prokázat doručení alertu; rozšířit alerty na OOM/restart loop, disk, dlouhá DB spojení, selhání/stáří backupu a nefunkční log upload. Aktualizace provést podle `docs/operations/supabase-self-hosted/version-policy.md` a pins; známá dostupná verze sama neznamená povinný okamžitý major upgrade. Kernel/libc restart oddělit do odsouhlaseného okna s dostupnou konzolí/recovery přístupem.

**Validace:** statické infrastrukturní testy plus izolovaný omezený burst potvrzující capy, frontu/backpressure a zotavení. Žádný produkční DoS test. Po autorizované změně inspect ukazuje konkrétní limity, služby nemají OOM/restart loop, canaries a záloha fungují. Restart má ověřené autostarty, chráněný SSH i API; během změny zachovat druhou ověřenou přístupovou cestu.

**Výstup:** verzovaný číselný rozpočet s rezervou a metrikami, vynucené limity a prokázané upozornění. Pokud chybí rozhodnutí o placené kapacitě, uvést konkrétní variantu/cenu a blokovanou část, nikoli nastavit náhodné nízké limity.

### 6. P2: ověřit obnovu a rozhodnout o PITR

**Změny:** vyjít z `automation/hetzner-supabase/backup/` a `restore/drill-encrypted-rehearsal-backup.sh`. Před použitím ověřit jeho target guardy - historický rehearsal název nesmí dovolit obnovu přes živý canonical DB nebo jeho volume. Obnova jde do nového izolovaného prostředí s blokovanými skutečnými emaily, webhooky, cron side effects a platebními integracemi. Ověřit samostatně dostupnost dešifrovacího klíče při ztrátě workstation/serveru bez exportu klíče do evidence.

Ověřit poslední úplnou šifrovanou sadu včetně globals/storage/runtime, integritu a aplikační read smoke, změřit skutečný čas obnovy a stav konzistence. Zdokumentovat, co se může lišit mezi online dumpem, storage archivem a externím R2 obrazovým úložištěm. Existující retenci 14 dní + 4 týdenní kopie neměnit, neprořezávat backupy ani nekopírovat zákaznický obsah do repozitáře.

Pro navržené RPO <=15 minut/RTO <=2 h připravit porovnání současného denního dumpu a standardního podporovaného base-backup + WAL řešení s šifrovaným off-host uložením. Periodické logické dumpy nejsou PITR; WAL archivace bez obnovitelného base backupu také nestačí. Implementace PITR následuje až po výběru cíle, kapacity a schválení provozní změny; musí prokázat obnovu do zvoleného času a alert při přerušení archivu. Pokud uživatel přijme denní RPO, zůstává výslovně zapsané přijaté riziko, nikoli falešný stav „PITR hotovo“.

**Validace:** `node --test automation/tests/hetzner_supabase_backup.test.mjs` při změně nástrojů a skutečný izolovaný restore drill se sanitizovaným result.json. Výsledek obsahuje čas zálohy, obnovovací bod, změřené RPO/RTO, digesty a funkční read smoke bez osobních údajů.

**Výstup:** doložená obnova a výslovný recovery cíl. Pokud cíl vyžaduje PITR, musí být implementované a ověřené, jinak tato část zůstává otevřená.

## Evidence odstranění a zachované hranice

| Artefakt | Cílový stav | Důkaz |
| --- | --- | --- |
| `migrate_users_to_org(bigint)` | Odebrat veřejná práva v P0, poté odstranit funkci; historické migrace pouze jako historie | pg_proc absence po vlně 2, žádný aktivní registr/caller |
| `apply_allocations_claim_only(bigint)` | Odstranit, pokud bez callerů; jinak uzavřený interní helper se zachovanou claim-only sémantikou | Efektivní ACL, interní pozitivní scénář, absence veřejného bypassu |
| `update_spot(jsonb)` | Odstranit bez callerů; jen prokázanému podporovanému klientovi ponechat autorizovanou fasádu | Mapa callerů, cross-tenant negativní test a readback |
| `send_email_mailersend(jsonb,jsonb)` | Odstranit po kontrole závislostí | pg_proc absence a všechny podporované producenty vlastní fronta |
| PUBLIC ALL politiky sync tabulek | Nahradit skutečnou service-only hranicí | pg_policies + has_table_privilege + skutečné role |
| Nezabezpečená batch autorizace | Všechny prvky a rodiče ověřené před změnou | Smíšený batch nezmění žádný řádek |
| Nenasažené lokální konfigurace | Jediný schválený main zdroj, shoda s aktivní konfigurací | Digesty kandidáta i běžícího stavu, runtime canaries |
| Veřejný scan a zákaznické rezervace | Zachovat podporovaný tajný kód/ownership, bez povinného editor loginu | Pozitivní scan a order flow testy |
| Živá restrictive Storage policy a lokální abuse Storage změny | Zachovat default deny; případné již implementované scoped read/delete a write cutover převzít pouze s doloženým vlastnickým kontraktem a compat gate | Žádné plošné povolení; pozitivní/negativní role testy a důkaz kompatibility |
| Historické auditní dokumenty a aplikované migrace | Zachovat jako historii, doplnit aktuální stav nového auditu | Žádné přepisování již aplikovaných SQL za účelem „opravy“ |

## Ověření a nasazení

Plánování nespouští testy ani mění produkci. Při implementaci rozšířit `database/tests/security/run-local.sh` nebo vytvořit úzký taskový runner podle jeho izolačního kontraktu: jedinečný project ID/porty, odmítnutí obsazeného projektu, cleanup pouze vlastního prostředí, žádná produkční DATABASE_URL. Současný runner nové testy automaticky nevybírá a defaultní lokální verze PG nemusí odpovídat produkční PG17; obojí výslovně upravit/ověřit. Způsob sestavení baseline + celého pořadí migrací musí odpovídat novému migration timestampu, ne ručně vynechávat pozdější migrace.

Existující testovací infrastrukturu z main využít místo druhého abuse runneru. Abuse migrace je již aplikovaná, její pořadí/hash neměnit. Testovat současnou baseline včetně abuse migrace a novou follow-up migraci; historická varianta „P0 před abuse“ se už nemusí znovu simulovat. Znovu spustit pouze regrese zasažené follow-up diffem a povinné gates, ne všechny passing abuse/Deno/worker sady. Důkaz původního nasazení nenahrazuje nový readback po opravě ACL.

Základní DB batch: nové RPC/sync/ACL regrese plus stávající `rpc_object_authorization`, `full_deposit_flow`, `on_site_surcharge_flow`, `overpayment_flow` a scan/attendance kontroly; přidat skutečný inventory souběh a batch rollback. Testy nad PG17 musí ukázat odmítnuté i povolené skutečné role. Infra a backup Node sady spustit jen pro změněné komponenty. Browser použít jen při změně klientského průchodu, izolovaně na lokálním tenantovi podle příslušného skillu. Passing check neopakovat bez nové změny nebo odůvodněného rizika.

**Produkční postup po příslušném pověření:**

1. Dokončit konkrétní balík, cílené testy a repository review gates; zjistit aktuální branch protection. Dokumentovaný starší požadavek review nepovažovat za ověřenou současnou konfiguraci. Před publikací větve/PR fetch autoritativního targetu, porovnat aktuální head, vyřešit překryvy a ověřit dotčené změny. Preferovat přímý merge/push jen pokud jej skutečná pravidla dovolují.
2. Použít schválený main SHA, obnovit read-only target assertion, aktuální backup receipt a předmigrační readback. SSH přes `festapp-backend-agent`, bez načítání service-role klíčů a bez veřejného SSH. Pokud nová evidence indikuje aktivní zneužití, uchovat logy a eskalovat konkrétní incident; neprovádět neautorizované mazání/rotace.
3. Nasadit nejprve samostatný P0 SQL balík atomicky s ledgerem a ověřit efektivní ACL. Pak další SQL vlny. Nekombinovat první containment s restartem, full runtime promotion, PITR nebo plošným frontend releasem.
4. Po SQL zavést schválené runtime/proxy změny jednotlivě, s canaries a chráněnou zálohou konfigurace. Firewall změna nesmí zrušit chráněné SSH; SSH/provider recovery musí být ověřeny předem. Nový requestSecret/klíč není součástí této konfigurace, pokud jej oprava výslovně nepotřebuje.
5. Pokud je nutný web release, pouze `prod/festapp`, lokální Flutter/web build a `automation/deploy_direct.sh` podle repository pravidel. Žádný automatický GitHub-hosted build ani rollout ostatních prod větví.
6. U každé vlny zaznamenat main SHA, migration verzi a hash, skutečný readback, běžící runtime/config digest a canary výsledek. Audit označit opravený až po live důkazu; rozlišit lokálně hotové, publikované a nasazené.

**Rollback:** SQL chyby před commitem rollback celé migrační transakce; po commitu preferovat malou dopřednou opravu povolené cesty. Neobnovovat neautorizovaný EXECUTE nebo PUBLIC ALL politiku. Při závislosti nalezené před DROP se kontrakce odloží, P0 ACL zůstává. Proxy rollback může obnovit poslední prokázaně bezpečnou konfiguraci; starou slabší konfiguraci nevracet automaticky v rozporu s nově potvrzenou hrozbou. Limity zvyšovat v rámci schválené kapacity při validní zátěži, nikoli odstraňovat všechny ochrany. Obnova produkce ze zálohy je incidentní krok s vlastním rozhodnutím o ztrátě nových dat.

## Dokončení a předávka

- [ ] Kritický migrátor je odstraněn; inventářové vstupy nemají neautorizovaný zápis, každý zachovaný helper má doloženého callera a minimální ACL.
- [ ] Sync tabulky jsou uzavřené a jejich legitimní servisní cesta funguje; potvrzené drift nálezy nejsou přítomné v živém katalogu.
- [ ] Opravené funkce mají bezpečný search_path a cílenou autorizaci; zbytečné TRUNCATE/extension/sender vstupy jsou odstraněné nebo výslovně zdůvodněné.
- [ ] Proxy/IP/Auth/API hodnoty jsou ověřené v živém runtime; legitimní upload, websocket, login/recovery a placené objednávky fungují.
- [ ] Prostředky mají měřený rozpočet, vynucené limity a prokázané alerty; restart/upgrade je provedený, nebo přesně evidovaný jako dosud neautorizovaný provozní krok.
- [ ] Existuje aktuální izolovaný restore důkaz a přijatý recovery cíl; případně nezbytné PITR je skutečně obnovitelné.
- [ ] Testy a live readback dokazují chování i nepřítomnost bypassů; audit obsahuje přesný stav jednotlivých vln a reziduální rizika.

Při předávce uvést dosažené invarianty, odstraněné funkce/granty, výsledky testů a live důkazů a jediný konkrétní další krok. Neoznačovat celý plán za hotový pouze proto, že je vyřešené P0 nebo existuje commit. Širší fair use a dosud neověřené plochy mimo audit zůstávají v abuse plánu; tento balík neslibuje úplný penetrační test celé aplikace.
