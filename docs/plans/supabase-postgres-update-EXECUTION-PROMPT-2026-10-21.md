# Proveď úplnou aktualizaci Supabase a PostgreSQL včetně produkce

Aktualizováno 2026-11-15. verification: standard.

V repozitáři /Users/miakh/source/festapp přečti celý autoritativní plán:
`docs/plans/supabase-postgres-update-plan-2026-10-21.md`.
Dodrž AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a projektový
festapp-backend-access skill. Zkontroluj cíleně změny od průzkumu;
neopakuj celý audit ani nevytvářej další plán.

Proveď všechny vlny 1-6 jako jeden souvislý úkol až k ověřenému produkčnímu výsledku. Uživatel 2026-11-15 výslovně zahrnul nasazení na produkci; po splnění gates nevyžaduj další potvrzení. Cíl: Supabase
self-hosted/v0.8.4 (commit 189adda99d1b56da55fc5a6ee3f849354aaea92a)
a PostgreSQL 17.12, oficiální supabase/postgres:17.12.0.000 pro linux/arm64,
pin sha256:6c056e9a0f81d423c1a81fdf4e6587c16efd3f63960897371dab8ae2694a4714.
PG18 není součástí. Dostupnost a platforma PG17.12 image jsou ověřeny;
kompatibilita našich dat a pgBackRest derivátu dosud není nacvičena.

Začni čistým izolovaným checkoutem aktuálního autoritativního main.
Protože plán a tento prompt zatím nejsou commitnuté, přenes do checkoutu
oba tyto dokumenty z této pracovní kopie; nepřenášej jiné rozpracované změny.

Dodej přesné piny a pgBackRest derivát, úzký otestovaný updater a jeden
společný izolovaný restore/upgrade/rollback nácvik. Ověř všechny databáze,
C extensions a jejich update cesty, libc/collation a potřebný REINDEX,
WAL/PITR, session, RPC, Realtime, CORS a chybové odpovědi Functions,
paměťové limity, main worker i odchozí TLS. Vysvětli zaznamenané archive
selhání z 2026-11-12. Nepoužívej cizí Alpine balíčky ani nevypínej bezpečnostní
kontroly jako náhradu kompatibility. Prokazuj skutečné chování, ne jen piny.

Zachovej jediného writera, potvrzené zápisy, session/keys, stávající zálohy,
kompletní instalovaný Compose včetně email a pgBackRest a původní pause/jobs
stav. Zahrň MCP klienty a ostatní writery. Izolovaná kopie nesmí posílat
emaily, platby, webhooky ani jiné produkční side effects. Storage zůstává
vypnuté. Zachovej současné release gates. Nevytvářej deployment framework.

Příprava je hotová až s ověřenými artefakty, jedním úspěšným společným
nácvikem a konkrétním runbookem s naměřeným výpadkem, návratem a stop body.
Pokud důkazy vyvrátí předpoklad, oprav autoritativní plán a dotčenou část.
Nezanechávej placeholdery. Neprovedený nácvik nebo nekompatibilní rozšíření
uveď jako přesnou blokaci, nikoli jako hotovou přípravu.

Po úspěšné přípravě a nácviku publikuj validované zdroje do autoritativního
main podle pravidel repozitáře, splň povinné CI/release gates pro přesný SHA
a proveď nacvičený upgrade sdíleného produkčního backendu api.festapp.net.
Vyber nejbližší vhodné okno s nízkým provozem bez aktivního skenování a špičky.
Zůstaň v rozpočtu 15 minut včetně nacvičeného návratu; pokud nácvik tento
rozpočet nepotvrdí, produkční okno neotvírej a dolož přesný problém.
Nezastavuj se po commitu, uploadu nebo instalaci. Ověř skutečné běžící image,
SQL verzi 17.12, dostupnost API/Auth/REST/Functions/Realtime, obnovený email
worker a původní joby, zdravou WAL archivaci a obnovu nové zálohy. Dohled
24 hodin zajisti existujícím monitoringem; otevřené následné kontroly eviduj
a neoznač je za provedené předem.

Rutinní produkční provedení a monitoring deleguj podle AGENTS.md na
levnějšího subagenta s přesným SHA, příkazy a gates. Technické chyby řeší
hlavní agent. Neobcházej neúspěšný nácvik, CI nebo přístupové brány.
Toto zadání zahrnuje nezbytné produkční restarty a migrace vybrané sady,
povinné zálohy a nacvičený návrat. Nezahrnuje frontend/Android releasy,
jiné tenant větve, placený provisioning, zprávy uživatelům ani improvizovanou
destruktivní obnovu nebo ztrátu potvrzených zápisů.

Na konci stručně předej skutečné produkční image/source SHA, výsledky nácviku
a live kontrol, naměřený výpadek, backup/recovery důkazy a případné dosud
čekající následné kontroly. Při blokaci uveď konkrétní gate a skutečný stav
produkce. Připravený balík sám není dokončený upgrade.
