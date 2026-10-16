# Sjednocení bezpečnostních prací Festapp - 2026-10-16

## Follow-up nasazený - aktuální stav

Main obsahuje opravný commit `9b2064fb796f7ec12f8271f80fbc03b9b0306e61` a test-only CI opravu `89639ea9172cadd2bfb456ab55aae6bc9695249c`; jejich povinné CI prošlo. Po navazujícím pokynu uživatele jsou všechny tři migrace `20261016170000`, `20261016171000`, `20261016172000` aplikované. Čtecí failure gate ověřil odstranění čtyř mrtvých funkcí, service-only sync a skutečné ACL/search_path. Caddy 52MiB cap i stávající host monitor jsou nasazené. Skutečný čerstvý off-host backup prošel izolovanou PG17 obnovou; nejde o plné RTO/PITR nebo key-loss důkaz. Přesný stav, incident omezeného monitoring tokenu a zbývající C body vlastní aktuální sekce [serverového plánu](server-security-remediation-plan-2026-10-16.md) a [produkční receipt](../operations/security-remediation-20261016/production-result.json).

Abuse ochrana nebyla znovu implementovaná ani její migrace přepsaná. Dva historické nejasné emaily nebyly přehrané. Žádný nový web/Flutter release, navýšení RAM ani PITR aktivace se neprováděly. Níže zachované přednasazovací snapshoty jsou historické a nenahrazují produkční receipt.

## Ověřený stav

**Historický snapshot 2026-10-16 12:06 UTC (nahrazený aktuálním stavem výše):** nezávislý live readback potvrdil aplikovanou abuse migraci `20261016100000`, přítomnost abuse_policy_rules, aktivní native password hook a GOTRUE_RATE_LIMIT_HEADER. Live Caddy již má origin allowlist, přepis trusted headeru, read timeout a body capy 64KB/32MB. Sousední session oznámila dokončený web vstupenky.online `0.20.247+731`; webovou verzi tato session nezávisle znovu netestovala. Main zůstává `a95067e26d7b1d17009fa6100145708750833133`. Všechna tři nebezpečná RPC mají stále anon/authenticated EXECUTE a tři sync politiky zůstávají PUBLIC ALL. Follow-up tedy začíná na main konkrétními SQL opravami; nečeká na aktivaci abuse, nepřenáší původní diff a znovu neinstaluje Auth/proxy. Pro Storage přetrvává zjištěný obecný 32MB body cap.

Původní release session výslovně předala RPC/sync/provozní follow-up této práci a neimplementuje jej souběžně. Její zbývající abuse provozní evidence zahrnuje historické R2 bytes, fyzický push fan-out, vendor billing stropy a doladění alertů podle reálného provozu. Tyto body nejsou důvodem odkládat P0. Dva emaily s nejasným výsledkem doručení podle jejího předání zůstaly bez opětovného sendu; follow-up je nesmí rozeslat ani resetovat frontu.

Pro realizaci platí aktuální serverový plán a prompt. Následující podrobný průběh zachovává evidenci před merge/deployem; jeho tehdejší pending kroky nejsou nové úkoly. Abuse migrace je již aplikovaná: jen nové dopředné migrace a test aktuálního pořadí, nikoli přečíslování nebo simulace starého P0-before-abuse rollout scénáře.

Opakovaná kontrola 2026-10-16, poslední GitHub snapshot po 11:47:50 UTC. Sousední session `01a143b4-5d3d-7703-9cb7-0ae02eb9757a` převedla původní implementaci do release worktree `/private/tmp/festapp-abuse-release-20261016`, větev `feat/abuse-prevention-release-20261016`. Základní implementační commit je `5cf0af9b593ad6af860a91b285487a88ebdd7013`, následný CI fix `c8f9682fdf1022914d251371132bed340f764e64`. [PR #459](https://github.com/festappnet/festapp/pull/459) bylo v 11:47:50 UTC MERGED; merge commit i tehdejší GitHub main je `a95067e26d7b1d17009fa6100145708750833133`. Původní blocker review/selhaný delivery check je historický: `ticket-preview-and-delivery` již SUCCESS, další dva checks ještě při snapshotu běžely. CI fix změnil pouze dependency lock použitý ve workflow; hash abuse migrace se nezměnil. Stav před další akcí obnovit, nepovažovat historické REVIEW_REQUIRED z polí API za důkaz, že sloučené PR stále čeká na merge.

Autoritativní realizační podklad je nyní commitovaný release a jeho vlastní `docs/security/abuse-implementation-2026-10-16.md`, nikoli starší [přehled v původním stromu](../security/abuse-implementation-2026-10-16.md). Ten stále tvrdí, že neexistuje commit/push, a popisuje předchozí monitoring. Původní pracovní strom zůstává rozpracovaný; nepřepisovat jej obsahem release ani z něj znovu sestavovat stejný balík.

Release obsahuje generovanou `supabase/migrations/20261016100000_abuse_admission.sql` s nezávisle ověřeným SHA-256 `5ba74531a242669dd0a0b846af9648a6e63505a1b16494ec0b24b564d9a59f22`. Původní hash `973022da7b706d9e4d76d773a1ed0096325796337212b9345c80b36543097919` identifikuje starší pracovní variantu a nesmí být cílem deploye. Release inventory má 30 operation entries, 32 Edge Functions a 3 worker entries; počty nejsou důkazem úplného pokrytí.

Uživatel v sousední session již výslovně autorizoval nasazení sdíleného backendu s rozumnými výchozími odhady a následně požádal i o viditelné UI změny. Sousední session pokračuje backendem a webem `vstupenky.online`, včetně UI skrytých produktů, lokálním buildem a přímým deployem. Tato kontrolní session nic nenasazuje. Nedělat druhý souběžný deploy ani konkurenční release PR; existující oprávnění nevyžadovat znovu, ale nerozšiřovat ho na další tenantové větve. Serverový follow-up se automaticky nestává samostatným web releasem `prod/festapp`.

Produkční kontrola do 11:46 UTC přes ověřenou canonical aktivaci, target assertions a `BEGIN READ ONLY` potvrdila: migrace `20261016100000` není v ledgeru, `abuse_policy_rules` neexistuje, všechny tři auditované RPC stále mají EXECUTE pro anon i authenticated a tři sync politiky jsou PUBLIC ALL. Tento readback předchází merge #459. Sloučení není důkaz nasazení; před další implementací obnovit live stav a deployment evidence sousední session. Nebyl spuštěn zapisovací exploit ani měněna produkce.

Zdrojové specifikace ve starším abuse plánu místy stále mluví o budoucí implementaci. Aktuální stav kódu určuje implementační přehled a skutečné soubory, nikoli tato historická formulace.

## Co převzít a co zbývá

| Oblast | Skutečná lokální implementace | Další práce v serverovém plánu |
| --- | --- | --- |
| Centrální policy/usage/overrides | `database/functions/abuse/schema.sql`, `policy.sql`, `budgets.sql`, `seeds.sql` | Převzít současný mechanismus, nevytvářet druhý limiter; ověřit migraci a runtime stav |
| Create/duplicate/finalize, draft a Unit | Zapojení do existujících commandů; zdrojový seznam vlastní generátor | Zachovat, při rebasi ověřit parity a skutečné receipt/rollback testy |
| Email fair use, recipient/backlog a commitment rezervy | `abuse/email.sql`, stávající `emails/email_queue.sql` a producenti | Žádný nový sender ani přepsání provider gate; legacy MailerSend RPC stále vyřešit zvlášť |
| Password/Google/reset/QR, scan a rezervace | `abuse/auth.sql`, `qr.sql`, `scan.sql`, `orders.sql`, `reception.sql` a doménové zdroje | Převzít; doložit efektivní Auth config a aktivaci native password hooku |
| Šestimístné heslo | Výslovně zachované jako trvalé a opakovaně použitelné | Neměnit platnost, neinvalidovat hesla ani session; chránit pokusy a rozesílání |
| Image bytes, metadata, copy a private project access | `abuse/media.sql`, `storage.sql`, `image_projects.sql` a image worker | Převzít; dořešit legacy klienty a historii R2. Nevydávat cap nových alokací za změřenou historickou obsazenost |
| Dokumenty a externí fetch | `abuse/documents.sql`, bounded transport a existující handlery | Převzít včetně přesně připnutých dependencies/locku; neměnit na druhou implementaci |
| Push a participant privacy | Explicitní push dispatch, REST granty a `abuse/participants.sql` | Ověřit kompatibilitu starých writerů a count readerů; logical audience není fyzický fan-out provideru |
| Neomezený SQL HTTP importer | `sync_source_via_http.sql` a `setup_external_source.sql` vracejí service-only retired chybu před IO | Zachovat retirement; neopravovat jej zpět do aktivního importu |
| Proxy/IP a Auth hook | Pracovní Caddy/Compose změny, native password hook konfigurace | Kód již existuje, ale není aktivovaný. Opravit 32MiB obecný body cap pro Storage 50MiB, prokázat trust chain a live canaries |
| Aplikační monitoring/maintenance | Release rozšiřuje `get_festapp_monitoring_health_v1` a zachovává capability ve `festapp_monitoring_credentials`; maintenance installer zůstává | Nepřenášet starší `get_abuse_monitor_v1`/`abuse_monitor_key` ani druhý monitorovací worker. Ověřit existující credentials a stav po SQL |
| Tři nebezpečná RPC | V abuse zdrojích ani generované migraci nenalezena náprava `migrate_users_to_org`, `update_spot`, `apply_allocations_claim_only` | P0 containment a následná kontrakce zůstávají samostatnou prioritou |
| PUBLIC politiky tří sync tabulek | Retirement importeru neopravuje tabulkové ACL/RLS | Samostatná oprava stále nutná; neobnovovat importer kvůli pozitivnímu testu |
| Zbývající search_path/TRUNCATE/extension ACL | Není doložen úplný runtime katalog ani náprava auditované množiny | Dokončit cíleně serverovým plánem |
| Celková RAM/CPU/PID, restart a obnovitelnost/PITR | Není doložena realizace těchto provozních bodů | Serverový plán je nadále vlastníkem; širší billing/provider důkazy zůstávají v abuse přehledu |

## Jeden implementační základ a pořadí

1. **P0 samostatně:** uzavření tří nebezpečných RPC nesmí záviset na publikaci celé abuse implementace. Nová ACL migrace má vlastní test a žádný odkaz na abuse tabulky. Prověřit všechny vstupy do případných interních helperů.
2. **Navázat na existující release:** ověřit aktuální PR/head a stav sousední session. Je-li #459 sloučené, založit chybějící serverové opravy z aktuálního main obsahujícího release. Pokud sloučené není, P0 lze připravit zvlášť z aktuálního main; ostatní integraci odvodit z publikovaného release commitu v samostatném taskovém worktree. Nezasahovat do pracovního checkoutu sousední session a nekopírovat starší root diff přes novější zákaznické/monitorovací kontrakty. Manifest/generátor slouží ke kontrole úplnosti, nikoli k druhému sestavení již publikovaného PR.
3. **Doplnit rozdíl:** serverový plán vlastní chybějící RPC/RLS/ACL, config activation, resource budget a restore postup. U překryvu upravit stávající kanonický soubor, nevytvářet druhou autoritu. Po přesunu zkontrolovat `assemble-abuse-migration.py --check`.
4. **Doložit pořadí:** zachovat hash/verzi již aplikovaných migrací. Abuse migrace je již publikovaná v #459 a podle čerstvého live readbacku neaplikovaná; nepřečíslovávat ji nebo přepisovat paralelně k práci release session. Pořadí P0 a abuse aktivace musí vyhovět skutečnému release ledgeru, případné předpublikační rozhodnutí je nyní nutné řešit jako koordinovanou změnu existujícího PR. Neřešit to přepisem aplikované historie ani implicitním plošným db push. Izolovaně prokázat výsledná ACL po standardním pořadí i po případném dřívějším P0 containmentu, aby pozdější CREATE OR REPLACE/GRANT ochranu nevrátil.
5. **Aktivace abuse:** #459 již sloučené, selhaný delivery check opraven. Ověřit dokončení zbývajících gates a skutečný nasazovaný main SHA; dokončení deploye vlastní sousední session. SQL, kompatibilní adaptéry/workery, ingress, Auth hook a maintenance/existující monitoring ověřit podle release přehledu. Přímé legacy Storage/notification writery a participant UUID readers potřebují explicitní compat gate; web vydání samo neaktualizuje staré mobilní aplikace. V kontrolovaném release Caddy zůstává obecný 32MB strop, proto před označením ochrany uploadů za dokončenou vyřešit 50MiB Storage kontrakt.

P0 lze nasadit samostatně, ale obsah celého pracovního stromu se tím automaticky neschvaluje k releasu. Tato reconciliační práce mění dokumentaci, nikoli implementaci či produkci.

## Důkaz a meze ověření

Původní session deklarovala 42 SQL sad, 3 concurrency testy, skutečný GoTrue v2.189.0 a 311 Deno testů. Novější release přehled uvádí 355 Deno testů, 95 image-worker unit testů + typecheck, zachovaný monitoring a 13 CI policy/coverage/infrastructure testů. Jsou to výsledky jejího předání; tato session je celé nezávisle neopakovala. Při této revizi nezávisle prošly `assemble-abuse-migration.py --check` a `node --test automation/tests/abuse_policy_coverage.test.mjs` v release worktree na `c8f9682fdf1022914d251371132bed340f764e64`, jehož migrace má nový release hash. Passing lokální sady nejsou samy důkaz nasazení ani dokončení všech asynchronních CI kontrol.

Po integraci do aktuálního main stačí opakovat dotčené chování a povinné repository gates, nikoli automaticky všechny historické sady po každém dokumentačním editování. Přenesený kód není důkaz živého stavu. Fyzický push fan-out, globální provider billing cap, historické R2 bytes, aktuální control-plane pravidla a úplný runtime ACL/readback zůstávají výslovně otevřené.

Původní nesoulad transportního testu Edge Runtime je podle release přehledu vyřešen: bounded HTTPS GET a odmítnutí chybného TLS hostname jsou nyní doložené pro v1.74.0 i v1.74.2. Neopakovat tuto původní výhradu jako otevřený blocker bez nového rozporu. Zůstává nutný readback skutečně nasazeného bundle po aktivaci.
