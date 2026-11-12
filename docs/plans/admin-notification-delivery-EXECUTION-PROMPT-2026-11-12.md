# Implementace administrátorských souhrnů

Implementuj celý autoritativní plán v `/Users/miakh/source/festapp`:

`docs/plans/admin-notification-delivery-plan-2026-11-12.md`

Přečti jej jednou celý a dodrž AGENTS.md, CLAUDE.md a `docs/architecture/ai_context.md`. Ověřování je standard kvůli oprávněním, migracím a společné frontě. Toto zadání autorizuje lokální implementaci a ověření; commit, push, produkční migrace, aktivace a deploy nejsou součástí.

Výsledek: jeden souhrn po 300 sekundách pro stejného uživatele napříč vybranými akcemi a organizacemi. Žádný daily režim, okamžité výjimky, admin push nebo další nastavení mimo rozsah plánu.

Priorita je reuse zpracování, nejen deduplikace zpráv. Nejdřív sjednoť facts/context/relevance přípravu podle tabulky v plánu a přepoj současné centrum/DTO callers. Používej captured count/formContext, existující recipient scopes, incident a payment owners. Odstraň nahrazené count/context/policy větve. Email pouze seskupí existující příspěvky do okna a zformátuje společný kontext. Žádný nový přepočet ticketů, finance, párování, role resolver, DTO kopie, prepared cache, N+1 RPC ani backfill UI kvůli mailu. Nezbytnou živou validaci před send permit zachovej.

Asynchronně čti existující deliveries přes per-scope sequence cursor. Collect a enqueue jsou dvě RPC/dva commity jednoho modulu; do feed projektoru nevkládej emailový hook. Deduplikuj source `(event_id,recipient)` i recipient item podle stabilní doménové identity, včetně bankovního incidentu napříč tenanty a různými okny. Členství a všechny queue/dispatch unikátní pojistky v plánu vynuť databází. Unknown nebo replay nesmí vytvořit náhradní zprávu.

Vše posílá jediná `email_messages` fronta. Implementuj úzký recipient scope pro admin digest, soukromý reporting a notification admission ve stávajícím abuse backendu. Žádný druhý sender, seznam příjemců ani autorizační bypass. Sjednoť bankovní producer/poller; legacy větve odstraň podle drain gate, audit zachovej.

Pracuj úsporně: použij mapu souborů a vlastníků z plánu, proveď jen cílený průzkum potřebný pro aktuální vlnu. Čti přes rg a malé výřezy; nezopakuj plošný audit ani průzkum celé architektury. Implementuj souvislou vlnu před kontrolami. Cílené testy připrav společně a spouštěj v jednom relevantním batchi; passing check opakuj jen po změně pokrytého kódu. Neomezuj povinné bezpečnostní, migrační a concurrency scénáře. Použij existující runners, žádné nové test/benchmark frameworky, nezávislé review nebo spekulativní abstrakce. Flutter pouze ve volném jediném slotu a testy s --concurrency=1. Browser případně podle AGENTS.md.

Dokonči vlny, reuse/deletion ledger a přejímací scénáře bez placeholderů či kompatibilních fallbacků. Cizí práci zachovej. Při skutečném rozporu oprav plán podle konkrétního důkazu. Závěr nejvýše pět bodů: sdílená příprava, odstraněné duplicity, funkční souhrn, ověření a přesné neprovedené provozní kroky. Plán není náhrada implementace a omezený počet tokenů není důvod prohlásit nehotovou práci za dokončenou.
