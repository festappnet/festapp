# Implementace ochrany proti zneužití - 2026-10-16

Stav: Původní lokální implementační záznam. Pozdější [release a live readback](../plans/security-work-reconciliation-2026-10-16.md) nahrazují zdejší tvrzení o neprovedeném nasazení a původní monitorovací návrh. Aktuální zdroje a release používají existující `get_festapp_monitoring_health_v1` / `festapp_monitoring_credentials`; níže uvedené `get_abuse_monitor_v1` / `abuse_monitor_key` nejsou pokyny k provisioningu.


Stav: lokální implementace a ověření. Žádný commit, push, deploy, změna produkčního hesla ani spuštění starého image migrátoru. Rozpracované cizí změny zůstávají ve stromu. Výchozí HEAD `eb23047248d59bf86345b9e0b79db4a988275231`, zaznamenaný main `9638008fe4bbf735bfb7b417fd1113582ec8a581`. Lokální ochrana není důkaz nasazení.

## Výsledný kontrakt a transakce

Uživatel výslovně potvrdil trvalé opakovaně použitelné šestimístné heslo. Registrace i starší `invitation_code` vstup vytvářejí totéž heslo; starší `enqueue_sign_in_code_v1` pouze deleguje na `reset_password_and_enqueue_email`. Deadline zprávy neomezuje platnost hesla. Existující hesla se nemigrují, nerotují ani nemažou. Pokusy mají centrální account UUID budget 10/60 s a 30/900 s; změna hesla jej neobnovuje. Native GoTrue PostgreSQL function hook commitne pokus ve vlastní transakci před vydáním session. Nejde o databázový trigger ani novou Edge route. Zamítnutí neodhlašuje aktivní relace. Manuální i e-mailem vyvolaná změna hesla sdílí oprávnění a centrální admission před bcrypt.

Create/duplicate/finalize zachovávají existující permission, mutation receipt, row lock a doménový command. Replay předchází čerpání. Kopie a finalizace mají jeden snapshot pravidel; ověřují bounded source/result cost. Draft má vlastní birth/work/occupancy/byte limity a UUID lock. Bootstrap rollback není skutečné vytvoření akce. Unit je pořadatel, Organization tenant; jejich čítače se nezaměňují. Usage nemá FK na mazatelnou doménu a klíč nezahrnuje command UUID ani policy revision. Overrides mění jen čísla v omezeném scope, mají audit, revizi a nejvýše 90 dnů platnosti.

E-mail zůstává v jediné frontě s původním provider gate. Dedupe předchází admission. Actor/Unit/Organization/recipient a skutečné backlog bytes jsou samostatné centrální budgety. Ověřené automatické paid/sent a storno závazky drží vlastní třídu i po migraci čekajících zpráv, bez opětovného čerpání. Prioritu nelze podvrhnout. Skutečný send recipient gate běží po provider defer kontrolách a před provider permit; odklad zachová stejný intent, nezvýší send attempt a používá vypočtené uvolnění okna. Fair výběr zohledňuje Organization, Unit a stáří. Růst dovolují pouze plně bankou pokryté kladné objednávky, s capem a freshness fallbackem.

Auth/reset/Google/QR a invalid scan pokusy se vracejí jako boolean/JSON odmítnutí, takže pozdější doménové selhání nevrátí již commitnutou spotřebu. Staré aktivní reset/Google/recepční čítače jsou převzaté. Forwarded identity přijímá jen připravená serverová proxy hranice. Scan/read/mark/unmark/export/reset, storno/delete receipts a cleaning sdílejí konkrétní doménové ochrany. Cleaning append nemůže resetovat budget smazáním reportu.

Push dispatch explicitně volají existující RPC přes pg_net. Původní business trigger a jeho funkce jsou odstraněné; setup registruje jen updated_at. Direct notification REST INSERT je zavřený. Canonical stored intent, logical target budget, durable dispatch gate a provider UUID idempotency zůstávají. Počet členů není počet fyzických subscriptions.

## Obrázky, dokumenty a čtení

Nové image copy používají download a stávající upload Worker, včetně starých Storage URL. Restrictive Storage policy zavírá staré INSERT/UPDATE/copy a metadata listing/delete ověřuje přesný uložený link a vlastníky. Nové image metadata mají vlastní centrální budget a přímý REST INSERT/UPDATE je zavřený. Worker po selhání metadata zápisu kompenzuje nový R2 objekt.

Před R2 put se navíc započítají skutečné transformované bytes do trvalého allocation budgetu: Unit 2 GiB, Organization 20 GiB, global 100 GiB, s pevnými vyššími hard caps v centrální policy. Usage má epoch bucket a neexpiruje. Retry, overwrite, smazání ani rollback klienta ji nevrátí. Jde o konzervativní cap nových alokací od aktivace; historické R2 bytes nejsou vydávány za změřené a automatický reclaim není implementovaný.

Privátní read/presign/delete i scoped upload používají jediný `get_image_project_access_v1`. Imported Organization provenance z `festapp_merge` zachovává projekty `a` a `slunovrat`; nové/native organizace patří do `default`. Historické sdílení mezi editory stejného projektu zůstává, konsolidovaný backend nesmí povolit cizí projekt. Filename neprokazuje vlastníka. Disabled private-public fallback je odstraněný. AKH má vlastní existující auth kontrakt.

Dokumenty i preview dostávají centralizované byte/page limity ze SQL. Kontrolují vstup a výstup před base64. Agreement assety používají bounded HTTPS transport s veřejnou DNS validací, pinningem adresy a ověřením TLS hostname. Stejný transport chrání externí obrázky a ticket resource čtení. Na skutečném Edge Runtime v1.74.2 prošel public HTTPS GET s připnutou adresou i odmítnutí chybného TLS hostname. Použitý `undici@6.29.1` je přesně připnutý, integrity je v `supabase/functions/deno.lock`; testy používají frozen lock. Neúspěšné starší transportní prototypy nejsou součástí řešení.

Public sync/image cache hit zůstává bez SQL. Native miss limiter je per-location best effort, nikoli globální billing cap. Neaktivní SQL HTTP importer a jeho setup jsou explicitně vyřazené před IO: runtime inventory doložila 0 sources/maps/import cronů; extension neměla bezpečný stream byte cap. Nevzniká náhradní importer.

Participant UUID přestávají být veřejné přes `event_users`; vlastní řádky a autorizovaní editoři zůstávají dostupní. Agregační RPC zachovává counts bez UUID i po privacy cutoveru.

## Provozní evidence a aktivace

Read-only kontrola ověřila canonical host a DB `festapp_rehearsal_20260909220601`, produkční GoTrue v2.189.0, provider allocation/gate, nepřístupné interní porty a poslední dostupné restore receipts. Připravený Caddy prošel adapt na produkční binary bez reloadu. Proxy config přepisuje trusted source header a omezuje origin, hlavičky, body a časy čtení. Nejde o změnu živé konfigurace.

Aktivace musí aplikovat dopřednou migraci z ověřeného main, pak dotčené existující adaptéry/workery a Auth config. Native password hook vyžaduje nejdřív SQL funkci a grant pouze `supabase_auth_admin`. Starší klientské Storage-copy a notification REST writery je třeba koordinovat s vydáním; zůstávají záměrně zavřené. Žádný tenant release se tím automaticky neprovádí.

Pozdější release používá existující monitoring `get_festapp_monitoring_health_v1`
a capability v `festapp_monitoring_credentials`. Původní návrh samostatného
`get_abuse_monitor_v1` / `abuse_monitor_key` byl nahrazen; neprovisionovat ho.
Stav maintenance installeru, monitoru a zbývajících provozních důkazů se řídí
[release reconciliací](../plans/security-work-reconciliation-2026-10-16.md),
nikoli přednasazovacím stavem tohoto lokálního záznamu.

Při incidentu nemazat usage, nerotovat identity key a nepřepínat zpět na staré granty. Navýšení probíhá auditovaným `set_abuse_policy_v1` do hard capu. Global provider pause zastavuje i závazky; zachovat frontu, receipts a finanční evidenci.

## Ověření a hranice výsledku

`bash database/tests/abuse/run-local.sh` používá výhradně vlastní disposable Supabase projekt a explicitní localhost DB URL, aplikuje celou baseline a skutečné role. Zahrnuje SQL scénáře, tři testy souběhu a skutečný připnutý GoTrue v2.189.0. Kontroluje opakované použití pět let starého hesla, společný account budget a přetrvání odmítnutých HTTP pokusů. Provider testy jsou mockované; pg_net push test rollbackne queue a neodesílá živé zprávy. Image remote integration suite se nespouští.

Finální čistá baseline: 42 SQL sad, 3 testy souběhu a skutečný native Auth test PASS. Dále: 311 Deno testů v 53 souborech, image-worker 95 unit + typecheck, monitor 5 testů. Společná CI policy/Edge coverage/infrastructure/monitor sada: 19 testů PASS. Předchozí nezměněné vstupy: sync-worker 9 + typecheck, Dart image adapter 10, JS překlady/mapping 9. Historickou parity kontrolu prováděl dnes vyřazený `assemble-abuse-migration.py`. Aktuální definition-only forward assembly vlastní `automation/assemble-operations-foundation-migration.py --check`; historickou adopci rozpočtů znovu nespouští.

Konkrétní neuzavřené provozní hranice: skutečná historická R2 obsazenost, fyzický OneSignal subscription fan-out a globální vendor billing caps, úplný runtime ACL katalog a aktuální monitoring/restore/IAM readback po aktivaci. Stávající project sharing a externí iframe embed jsou podporované kontrakty; jejich užší izolace/strict script CSP vyžaduje samostatný kompatibilní produktový přechod. Tyto body nejsou vydávané za dokončený bezpečnostní audit ani za aktivní ochranu produkce. [OneSignal targeting](https://documentation.onesignal.com/reference/push-notification) omezuje API targety; alias/tag audience není důkaz skutečného počtu zařízení.

Taskové testovací kontejnery po ověření odstraněné, cizí lokální projekty ponechané.

SHA-256 dopředné migrace: `973022da7b706d9e4d76d773a1ed0096325796337212b9345c80b36543097919`.
