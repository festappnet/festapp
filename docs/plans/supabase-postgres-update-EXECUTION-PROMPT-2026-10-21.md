# Příprava bezpečné aktualizace PostgreSQL a Supabase

Pracuj v repozitáři Festapp, z čistého izolovaného checkoutu aktuálního autoritativního main. Rozpracovanou kopii /Users/miakh/source/festapp nerevertuj ani nepřepisuj.

Autoritativní plán přečti celý:

`docs/plans/supabase-postgres-update-plan-2026-10-21.md`

Přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a projektový festapp-backend-access skill. Ověřování standard, plus povinné release gates. Cílem je předem připravený a nacvičený upgrade PostgreSQL 17.6 -> 17.11 a kompatibilní Supabase sada s minimálním řízeným výpadkem; ne nulový výpadek slíbený bez HA.

Výchozí rozsah při zadání přípravy: vlny 1-4. Dodej přesné piny/digesty, pgBackRest derivát, úzký testovaný updater, izolovaný restore/upgrade/rollback důkaz a finální runbook s konkrétními příkazy a naměřeným oknem. Nepoužívej historické promotion/restore skripty bez kontroly kontraktu. Nový pgBackRest installer neaktivuj znovu a nepřidávej vypnutý Storage. PG17.11 artefakt, migrace a downgrade musí být doložené; pokud vhodný image není, uveď blokaci a odděl hotovou Supabase část od nedokončené PG části.

Zachovej jedinou DB autoritu, potvrzené zápisy, session/keys, WAL/backup/recovery, originální pause/jobs stav a externí idempotenci. Přípravná kopie nesmí provádět produkční integrace. Pokud současné důkazy zneplatní předpoklad plánu, uprav plán s důkazem a dotčenou vlnu znovu ověř.

Samotný tento dokument ani předchozí žádost o plán neopravňuje produkční změny, restart, obnovu, publikaci/commit/push nebo placený testovací host. Provedení vln 5-6 vyžaduje samostatné pověření a schválený rozsah dopadu sdíleného backendu. Rutinní autorizované provedení a monitoring deleguj podle AGENTS.md levnějšímu subagentovi s přesným source SHA a runbookem; nečekané technické chyby eskaluj.

Handoff stručně: co je připravené a otestované, naměřený výpadek/návrat, přesné otevřené blokace a dosud neprovedené produkční kroky. Nic neoznač za nasazené pouze podle pinů nebo běžících kontejnerů.

Tempo: jeden souvislý přípravný balík, jedna cílená kontrola změn, jeden společný izolovaný nácvik upgradu a návratu a jedna dávka cílené validace. Neopakuj celý audit ani nebuduj deployment framework. Realtime ověřuj souběžně s ostatními kontrolami; následný 24h monitoring neblokuje obnovení API ani předání výsledku. Zachovej všechny blokující datové a recovery gates a existující autorizační hranici.
