# Exekuční prompt: zbývající bezpečnostní opravy Festapp

Realizuj zbývající opravy v `/Users/miakh/source/festapp`. Začni implementací, neopakuj obecný audit ani plánování. Použij standard ověření pro bezpečnost a migrace.

Přečti příslušné AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý autoritativní plán:
`docs/plans/server-security-remediation-plan-2026-10-16.md`.

Aktuální rozdělení práce je v `docs/plans/security-work-reconciliation-2026-10-16.md`; audit v `docs/operations/security-audit-2026-10-16.md` použij pouze pro konkrétní opravované nálezy. Není třeba znovu pročítat všechny historické plány a session logy.

## Již hotovo - neopakovat

PR #459 je sloučené a abuse ochrana nasazená. Main při kontrole je `a95067e26d7b1d17009fa6100145708750833133`. Nezávislá kontrola 2026-10-16 12:06 UTC potvrdila aplikovanou migraci `20261016100000`, centrální policy tabulky, aktivní Auth password hook a trusted IP hlavičku. Live proxy již má origin allowlist, timeouty a body capy. Předchozí session dokončila backend i web vstupenky.online a zbývající RPC/sync opravy předala tomuto follow-upu. Nečekej na starý release, nekopíruj starší root abuse diff a nevytvářej druhý limiter, sender, monitoring nebo obecný framework. Nenasazuj znovu web jen kvůli SQL změně.

## Pracovní postup

1. Jednou fetchni aktuální main a založ vlastní čistý taskový worktree. Zachovej cizí rozpracované změny a checkout předchozí session. Tento plán/prompt/audit mohou být pouze untracked v původním stromu; přečti a přenes pouze tyto potřebné dokumenty. Projektový backend-access skill používej bez kopírování tajemství.
2. Jednou ověř cílový backend a aktuální opravované ACL přes `.agents/skills/festapp-backend-access/SKILL.md`, SSH `festapp-backend-agent` a explicitní READ ONLY transakci. Canonical aktivace festapp, organizace 1, hostname a aktivní DB musí souhlasit. Nepoužívej legacy SUPABASE_URL. Při nedostupném readbacku připrav lokální opravu a označ chybějící důkaz.
3. **Balík A jako první:** zabezpeč `migrate_users_to_org(bigint)`, `update_spot(jsonb)` a `apply_allocations_claim_only(bigint)`. Při poslední kontrole všechny stále měly EXECUTE pro anon i authenticated. Prověř skutečné signatury, PUBLIC dědičnost a přímé/vnitřní callery. Připrav malou samostatně použitelnou P0 migraci; mrtvé funkce po kontrole závislostí odstraň bez CASCADE, používaným zachovej pouze autorizovaný kontrakt. Nezaměňuj claim-only chování za apply_allocations. Oprav kontrolu všech objektů batch inventáře, NULL musí zamítnout. Uzavři klientský přístup tří interních tabulek external_sync_sources, external_sync_maps a external_occasions_cache; jejich PUBLIC ALL politiky stále trvají. Retirement neomezeného SQL importeru zachovej. Kanonické SQL zdroje a nová dopředná migrace musí souhlasit; již aplikovanou abuse migraci ani baseline nepřepisuj.
4. **Jedna cílená validační dávka po balíku:** izolovaný PG17, skutečné role anon/authenticated/service a dvě tenantové fixture. Ověř odmítnuté i povolené operace, žádné vedlejší zápisy při odmítnutí, smíšený batch rollback a dotčené objednávkové/inventory regrese. Použij existující testovací infrastrukturu a aktuální migrační pořadí včetně již nasazeného abuse. Testy po každém souboru, všechny historické Deno/worker sady a Flutter build bez změny klienta nejsou potřebné. Povinné repository/CI gates zachovej.
5. **Balík B:** doplň pouze chybějící runtime/hygienu z plánu: zejména sladění obecného 32MB proxy capu s podporovaným 50MiB Storage uploadem, zbývající search_path, zbytečné TRUNCATE/extension granty, legacy MailerSend sender a čtecí detekci driftu. Aktivní Auth/proxy/monitoring zachovej a uprav jen konkrétní nedostatek. Používej get_festapp_monitoring_health_v1/festapp_monitoring_credentials; starší paralelní get_abuse_monitor_v1 nevracej.
6. **Balík C:** připrav skutečně chybějící resource budget, údržbu a bezpečnou izolovanou obnovu podle plánu. Metriky, servisní okno, provider billing evidence nebo rozhodnutí o PITR neblokují hotový balík A. Neodhaduj náhodné nízké hard capy a nezakládej další plán. Blokovaný provozní bod pojmenuj a pokračuj nezávislou prací.

## Invarianty a hranice práce

Zachovej přihlášení, nákup, placené závazky, zákaznické capabilities, scan s platným tajným kódem, jedinou emailovou frontu a její provider gate. Šestimístné heslo je výslovně trvalé a opakovaně použitelné: nemigrovat na jednorázový token, neměnit platnost, neinvalidovat hesla ani session. Neresetuj usage, identity key, receipts ani frontu; neopakuj send zpráv s nejasným výsledkem. Žádné persistentní aplikační triggery, CASCADE, spekulativní fallbacky nebo nové služby.

Produkční exploity, fixtures, zátěžové testy a obnova přes živou DB jsou zakázané. Testy běží ve vlastním izolovaném prostředí. Passing kontrolu opakuj pouze při změně pokrytého kódu/runtime nebo konkrétním novém důvodu. Aktuální main a live stav ověř znovu před publikací/nasazením, nikoli po každé editaci. Bez výslovné žádosti nespouštěj subagenty nebo další nezávislý audit. Nový rozpor zapracuj do existujícího plánu.

Toto zadání autorizuje lokální implementaci, cílené testy a bezpečnou read-only diagnostiku. Commit/push/merge, produkční SQL, deploy/restart, control-plane změny a placenou kapacitu prováděj pouze podle skutečného navazujícího pověření; již udělené oprávnění nevyžaduj znovu. Před chybějícím provozním schválením dokonči konkrétní ověřený balík, přesné migrace/konfiguraci, rollback a readback. Odebrané veřejné destruktivní granty nejsou přijatelný rollback.

Výstup: hotový kód, cíleně ověřené migrace a konfigurace, aktualizovaný stav plánu a nejvýše pět bodů s výsledkem testů, worktree/main SHA a přesnými zbývajícími provozními kroky. Neoznačuj produkci za opravenou bez důkazu aplikace a skutečných ACL. Nezůstávej u dalšího návrhu a nepřipravuj znovu již nasazenou abuse ochranu.
