# Dokončit provozní spolehlivost BankSync

Autoritativní rozsah je celý `banksync-operations-plan-2026-10-08.md` vedle tohoto souboru. SDK vlastní `/Users/miakh/source/banksync`, kompozici `/Users/miakh/source/roman_seznamka/services/banksync`. Načti pravidla všech dotčených repozitářů. Verification: standard; publikace musí splnit chráněné release gates. Nespouštěj subagenty bez výslovné autorizace.

## Aktuální skutečný stav

Celý kandidát je na SDK main `9d1e70ecd6407a6518e9906200a897f75a770ea0`, package stále 0.2.8. Produkce má 100 % Worker version `e4fb42cd-236e-4846-b48e-8c5ac4a2a41c`; health 200 a deployment byly znovu ověřené po runtime exit. Immutable nevydaný tarball SHA-256 je `224157a439bf956296b04fabfec57e15e358b5272d771976b7eabfc432b91c6e`. D1 zůstává původní `84e10787-c4bf-4f0c-9f6d-8c7dcd21fdd8`, migrovaná v místě na schema 13. Maintenance je off. Neopakuj migraci, cutover ani hotové backup deletion.

Běžný Fio polling používá durable `/last`, potvrzené textové movement ID, credential generation, shared-token fencing a obnovu přes `/set-last-id`. `/periods` zůstává bootstrap/rekonciliace a neposouvá delta cursor. Všech 8 původních účtů má inicializované kurzory a je fresh. Proxy podporuje set-last-id, prošla třemi testy, typecheckem i nasazeným auth/API probe bez bankovních requestů; její aktuální zdroj odpovídá nasazeným SHA.

Open-batch query používá partial index; původní empty-open dotaz přešel z 31 507 rows read na 0. Completed recovery cipher je 0, žádná completed metadata starší 7 dnů. Cleanup má limit 500 na kategorii každých 5 minut a navíc daily běh. Pending a quarantine důkazy zůstávají obnovitelné; karanténa pinne původní completed message digest.

Přesný závěrečný audit přiřadil všech 402 původních R2 klíčů ke quarantine, max attempts 0, cipher/key zachované, 0 neklasifikovaných. Osm původních emailových záznamů během všech vzorků zachovalo attempts/state/body digest/last_error. Transient backoff a stale-claim fencing pokrývají prošlé integrační testy. Neprováděj automatický finanční replay, neslučuj různá MIME SHA a nezaměňuj sanitizovaný diagnostický text za původní obsah.

Finanční SHA všech 538 transactions, 748 delivery jobs a 21 subscriptions jsou při exit přesně shodná s ověřeným backupem. Jobs mají 320 delivered a 428 historických terminal; nerealertovat ani replayovat všechny historické jobs. Stávající 90denní transaction retence se neměnila a daily preflight měl 0 eligible rows. Nové recovery cleanup transactions neoslovuje.

Skutečný daily cron úspěšně zapsal last_maintenance_at=2026-10-08 03:16:14. D1 storage sample má 80 789 504 bajtů; krátké přepočty growth nejsou ustálená měsíční predikce. Successful backup marker je 2026-10-08T01:05:40.907902+00:00. Skutečný encrypted backup a D1 restore všech 21 tabulek i AUTOINCREMENT sekvencí prošly přesnými SHA a FK 0; owned dočasné D1 i Workers byly odstraněny a 404 ověřené, plaintext odstraněný, nezávislý obnovovací klíč zůstává chráněně mimo Cloudflare. Streaming backup opravuje skutečně reprodukovaný memory-limit pád. Celkem 637 testů/39 souborů, build/typecheck/package exports, dependency audit a fresh/v9 migration flows prošly.

Festapp retence 14 dní denních záloh + 4 dokončené týdenní kopie je nasazená. Autorizovaně odstraněno 16 sad/80 objektů/23 013 748 697 bajtů, deletion ověřená. Nový skutečný scheduled backup 20261008T023344Z úspěšně dokončil upload i retenci v 02:34:52 UTC, off_host_verified=true, 17 zachovaných sad, žádné další mazání. Nezkracuj tuto uživatelskou politiku a nemaž jiné buckety ani migrační důkazy.

README je ověřeně stručné a popisuje skutečný účel SDK i deployment kompozice. Byl vyhledán a použit GitHub skill `softaworks/agent-toolkit/skills/crafting-effective-readmes`; nebyl instalován jako nový globální skill. SDK nepřebírá payment matching consumerů.

## Živé handly a zbývající práce

Runtime observer exec84237/PID43380 úspěšně skončil 03:35:03 UTC. Je terminální: 17 vzorků, 0 collection errors, vždy 8/8 fresh, 0 API errors, schema 13, maintenance off a completed cipher 0. Neznovuspouštěj ho. Uživatelské maximum je 7 hodin, ideálně méně; staré 24h období bylo výslovně zrušeno. Pozorovaný začátek zůstal 01:08:38.920429 UTC, konec 03:35 UTC.

GraphQL collector exec70807/PID45456 skončil terminal exit 0 v 03:50:03 UTC. Celé uzavřené okno 01:08:38-03:35 UTC: 362 requests, 1004 subrequests, 0 runtime errors, CPU P50 5,236 ms/P99 251,891 ms. Jednotky mikrosekund ověřeny autentizovaným GraphQL schématem. Poslední ops checkbox je splněn. Oba collectory zůstávají ukončené, nespouštěj další observaci. Invocation success není důkaz HTTP 200 každého endpointu.

Dokončení stále zahrnuje jediné závěrečné protected registry vydání a přesný pin kompozice na tentýž ověřený artefakt po všech gates. Nepublikuj další verzi ani tag před úplnou připraveností. Současný registry pin 0.2.8 je mezikrok, ne trvalý local override; starý registry 0.2.8 není kompatibilní rollback pro schema 13. Před první publikací fetch authoritative main, vyhodnoť aktuální base/head, respektuj chráněné workflow, provenance/SBOM a release gates. Neprováděj rollout jiných tenantů.

Mendelio stále vyžaduje v AGENTS.md:104: „Nikdy necommituj, dokud uživatel nepotvrdí funkčnost v prohlížeči.“ Otázka na výjimku pro ověřené backendové změny je již položená a neodpovězená; neptej se opakovaně, nevykládej čekání jako souhlas a necommituj bez odpovědi/potvrzení. Je připravený ověřeně aplikovatelný source-review patch osmi souborů, který zahrnuje jen provozní logging z wrangler změn a vylučuje cizí domain/allowlist změny. Festapp checkout je na cizí feature větvi; backup patch šesti souborů je oddělený a prošel aplikací proti main. Zachovej ostatní dirty práci.

Historická příčina předchozích runtime výjimek není doložená: původní Workers Logs nebyly zapnuté a telemetry REST read má scope 403. GraphQL metriky jsou dostupné. Platný HTTP admin secret nebyl v této session načtený; pozitivní authenticated `/status` probe netvrď za provedený. Neplatný credential má ověřený HTTP 401; skutečná getOperationsStatus cesta nad produkční D1 a role guard testy prošly. Nevymýšlej incidentní kauzalitu ani nerotuj klíče kvůli získání tohoto probe.

## Autoritativní důkazy

Chráněný root: `/Users/miakh/.codex/protected/banksync/schema13-20261008`.

- `runtime-exit-summary.json`, `final-exit-evidence.json`, `r2-inventory/classification-final.json`.
- `worker-metrics-observation.jsonl`, `worker-metrics-state.json`, `worker-metrics-units.json`.
- `after-daily-evidence.json`, `final-runtime-deployment-health.json`, `final-migration-gates.json`.
- `operator/backup-evidence.json`, `operator/d1-restore-evidence.json`, původní migration/backup/bookmark evidence.
- `festapp-scheduled-retention-evidence.json`, `festapp-backup-retention-source.patch` a jeho JSON evidence.
- `mendelio-banksync-source-review.patch` a jeho JSON evidence; registry pin se musí ještě aktualizovat při závěrečném vydání.

Aktualizuj plán podle final metrik a reálného source/publication stavu. Goal neoznačuj complete před celým completion auditem; při skutečném impasse dodrž tři po sobě jdoucí blocked goal turns. Běžící collector a jeho časový sběr nejsou blocked.

Festapp zdrojová retence je aplikovaná v izolovaném worktree /tmp/festapp-banksync-backup-retention-20261008, branch fix/banksync-backup-retention-20261008 z origin/main 0799f8e991ea1782ad59b7441c03d966efbe589c. Původní feature checkout neměnit. Před commitem CONTRIBUTING vyžaduje apply_config.sh a test_all.sh; main vyžaduje 1 review, proto publikace přes PR.

Zdrojová retence publikována v https://github.com/festappnet/festapp/pull/346, head 2ed33fe78715c6499110ef184c350da45381b04e na aktuálním main 0799f8e991ea1782ad59b7441c03d966efbe589c (0 behind). apply_config prošel; full test_all na vlastní aktuální lokální DB: SQL 139, Flutter 1170, Deno 271 a automatizace PASS. Chybějící worker dependencies doplněny a integrační entrypoint zopakován: 27 remote tests dokumentovaně skipped pro local DB. Node backup 4/Python 5 PASS. Testovací DB zastavena, worktree clean, původní feature checkout zachován. PR vyžaduje review. Mendelio commit stále čeká na odpověď na již položenou výjimku z AGENTS.md:104; nic nereleaseovat před tímto gate a finálním registry/pin dokončením.

Uživatel po rychlé kontrole výslovně schválil finální vydání a backendový commit. Kontrola: health 200, 8/8 fresh účtů, 0 API errors a 0 otevřených recovery; 8/8 Fio cursors initialized, posledních 30 minut 214 poll_kind=last batches. SDK PR #61 byl sloučen do main 1216e2fbc16922825a949a5db445f6d93fac0cf7 a tag v0.2.9 byl vydán přes chráněný npm workflow 37747697046: všechny gates SUCCESS včetně audit, fresh/v9 migration, dry-run, attestations a trusted publish. GitHub release https://github.com/festappnet/banksync/releases/tag/v0.2.9 má SHA-256 f27e3567c404c4ada354a5ac3ce8b0a9cec2268d59294eb0a958d6e0015b9687. npm přijal publish v 08:08:40 UTC, ale veřejné metadata/tarball zatím vracejí 404; neoznačovat dostupnost v registru ani finální registry deploy za doložené. Jeden poller /tmp/banksync-wait-registry-029.py, handle 5173, běží max 20 minut a ověří přesnou integritu + SHA. Při timeoutu nespouštět republish stejné verze.

Mendelio source pin 0.2.9 připraven jako commit 6132a29ee8691d415a37ea08c2afdb500a724cc2 v persistentním slot-5, branch fix/banksync-release-0.2.9 na aktuálním origin/main 317082ae8dccd2f4e61cfd18d20e22d68e1fd741. Zachovává InvoiceSync konfiguraci z upstreamu a nesmí publikovat dalších 7 lokálních main commits. Před publikací dokončit standard owning typecheck/quick/verify v slotu; registry 404 dosud blokuje frozen install. Main checkout má připravený owned staged scope 9 souborů a cizí dirty změny zachované. Deploy pouze z main checkoutu po kanonickém installu. Festapp PR #346 zůstává REVIEW_REQUIRED; auto-merge není v repu povolený, neobcházet review.

Finální registry deployment je hotový: @festapp/banksync@0.2.9, Worker e4c6408e-ead9-4bd7-947b-d087bc8db952, registry tarball přesně shodný s GitHub release. npm poller 5173 skončil exit 0 v 08:26:10 UTC; nikdy ho znovu nespouštět. Skutečný post-deploy proof: health 200, 8/8 fresh accounts, 0 API errors, žádné recent events, bindings unchanged. Důkazy release-029-registry-proof.json a release-029-production-proof.json. Zbývá canonical composition source publication po dokončení standard kontroly (handle 81826) a mandatory Festapp PR #346 review. První full gate narazil na nesouvisející test s pevným zářijovým datem po expiraci 28denní retence; test-clock fix je izolovaný commit 6884fe98a, produktové chování nezměněno.


## Aktuální stav po publikaci zdrojů (nahrazuje staré pending údaje)

Mendelio canonical origin/main je f8317411e3db51b7f51097c8df97e004e62e3e3d. Pin SDK 0.2.9, wrapper konfigurace a Fio proxy jsou publikované. Standard gate dokončen ve dvou dávkách: unit a Voice (4709 Python passed) v první; podcast, services, standalone Python, simulated a privacy ve druhé (exit 0). Owning typecheck a composition test prošly. Staré testovací handly jsou terminální; nic neopakovat bez nové změny. Sdílený main byl bezpečně sloučen s upstreamem, owned source soubory jsou čisté a cizí dirty práce i 7 nepublikovaných commits zachované. Slot-5 uvolněn. Důkaz: release-029-source-publication-proof.json.

Produkce již běží na skutečném registry 0.2.9, Worker e4c6408e-ead9-4bd7-947b-d087bc8db952; všech 8 Fio účtů doloženě synchronizovalo po nasazení. Neprovádět další release kvůli dokumentaci. Na žádost uživatele je zestručněný integration guide připraven v BankSync PR #62; čeká pouze chráněné CI/sloučení. Festapp PR #346 stále OPEN/REVIEW_REQUIRED, bez obcházení povinného review.

Dokumentace publikována: BankSync PR #62 MERGED v 09:00:33 UTC, main 437c38bfe88faa975b270267d3e72d524eeef19e. Guide 330 -> 134 řádků, funkční webhook verification/process/receipt příklad, reference operations a optional payment references. Všechny protected CI checks PASS; bez další verze/deploye. Důkaz guide-readability-publication-proof.json. Jediný nedokončený publication gate původního cíle je mandatory review Festapp PR #346.

Na rozšířený požadavek uživatele upraven celý dokumentační celek BankSyncu: README, SECURITY, operations, payment references a security rollout. Staré plány označeny jako historické při zachování důkazů. PR #63 MERGED v 09:07:53 UTC, main ad7f5d1c0f2c7a64493e580333384f6aabc0c6d5; všechny protected CI checks PASS, bez další verze/deploye. Důkaz documentation-suite-publication-proof.json.
