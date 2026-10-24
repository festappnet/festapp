# Provedení: ochrana Festapp proti zneužití

Aktuální stav 2026-10-16 12:06 UTC: tento abuse balík už je nasazený; migrace, Auth hook i proxy byly nezávisle ověřené. Pro zbývající práci použij `docs/plans/server-security-remediation-EXECUTION-PROMPT-2026-10-16.md`. Starší instrukce o čekání na release nebo přenosu původní implementace neopakovat.

Aktualizace pro navazující session: implementace již lokálně existuje, nezačínej ji znovu. Nejdříve přečti `docs/security/abuse-implementation-2026-10-16.md` a `docs/plans/security-work-reconciliation-2026-10-16.md`. Pro sjednocenou nápravu auditu a provozu použij `docs/plans/server-security-remediation-EXECUTION-PROMPT-2026-10-16.md`. Následující původní pokyny určují aplikační kontrakt; již hotové části převezmi a ověř jen podle integračních změn. Aktuální implementace zachovává trvalé opakovaně použitelné šestimístné heslo a vyřazuje neaktivní neomezený SQL importer; nezaváděj jeho náhradu jen kvůli historickému bodu o importu.

Opakovaná kontrola: PR #459 je od 11:47:50 UTC sloučené, main `a95067e26d7b1d17009fa6100145708750833133`; delivery CI fix prošel. Použij aktuální main a release přehled, nikoli starší root variantu. Stav skutečného nasazení obnov podle reconciliačního dokumentu; poslední readback bez migrace předcházel merge. Sousední session dokončuje již autorizované nasazení backendu a webu vstupenky.online. Nevytvářej druhý release a nezasahuj do jejího checkoutu.

Pracuj v `/Users/miakh/source/festapp`. Přečti `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/abuse-prevention-plan-2026-10-16.md`

Ověření: `standard`. Původní zadání autorizovalo plán; implementaci zahaj až po navazujícím pokynu uživatele. Zachovej cizí rozpracované změny a zaznamenej aktuální source/main SHA. Výstupem je doložená ochrana všech vstupů podle plánu, ne tvrzení o absolutní bezpečnosti.

Postupuj podle části „Postup rychlé realizace“. Použij zásady skillu `focused-development`: jeden cílený průzkum chybějících faktů, souvislá implementace a relevantní validační dávka. Neopakuj obecnou architektonickou studii, nevytvářej další plán. Potvrzené kritické opravy nečekají na celý inventář. První řez je konfigurace a ochrana create/duplicate/finalize/draft a vzniku Unit; druhý e-maily a doložené Auth mezery; potom dokonči všechny zbývající cesty. Dílčí výsledek neoznačuj za hotový celý program.

Použij centrální `abuse_policy_rules`, omezené `abuse_policy_overrides` a oddělené `abuse_budget_usage`. Kód vlastní autorizaci/mapování/algoritmus, DB číselné limity. Pravidla mají přiměřenou rezervu, doložený růst a pevné capy; nové účty/session samy nezvyšují kvóty. Odděl krátké a denní čítače, všechny create cesty je sdílejí. Revize/override nevrací spotřebu a nemění identitu budgetu. Unit je pořadatel, Organization tenant; jejich limity nejsou zaměnitelné. Žádné volné vykonatelné formule, konkurenční konstanty nebo klientské změny capů.

Zapoj SQL admission po autorizaci/replay a před materializací, ne do obecného receipt helperu nebo rollbackového creatoru draftů. Použij existující receipts a zachovej lock graph. Nevyžaduj service-role JWT v helperu uživatelského SECURITY DEFINER commandu. Pokryj automatickou Unit registraci, aktivní import bez pruning po neúplném snapshotu a skutečné upload/Storage IO. Nepředpokládej existující media job ani idempotenci legacy facade s novým UUID. Rozlišuj commit pokusů, přijaté operace, occupancy a provider attempt.

Zachovej jedinou `public.email_messages` frontu, sender a provider fence. Běžný backlog cap nesmí blokovat platbu dříve přijaté objednávky; použij omezenou rezervu doložených závazků ve stejné frontě. Omez i limiter, polling, wake a metriky. Žádná nová centrální služba, framework, persistentní aplikační trigger, globální DB zámek nebo SQL závislost na cached public sync cestě. Admin UI není podmínkou funkčního řezu.

Testuj změněné veřejné kontrakty, ACL, souběh, rollback, retry a legitimní průchody na disposable lokálním backendu s explicitním lokálním připojením. Passing checks opakuj jen při změně pokrytých vstupů nebo novém důvodu. Povinné repository/release gates zůstávají. Žádné e-mailové kapacitní testy, syntetické dávky, reálné zprávy, faktury ani produkční zátěžové testy. Nepoužívej implicitní produkční `.env.local`.

Nové důkazy promítni do tohoto plánu; historické aplikované migrace nepřepisuj. Bez samostatné autority neprováděj produkční migrace, deploy, publikaci, změny provider nastavení ani další tenant rollout. Runtime přístup používá backend-access workflow a kontrolu canonical identity.

Dokončení vyžaduje pokrytý inventář a bezpečnostní matici, odstraněné nebo explicitně ohraničené bypassy z deletion ledgeru, konkrétní policy a cílené důkazy. Stručně předej skutečný výsledek, ověření a přesně zbývající provozní kroky. Rozlišuj lokální implementaci, merge, aplikovanou migraci a živou ochranu.
