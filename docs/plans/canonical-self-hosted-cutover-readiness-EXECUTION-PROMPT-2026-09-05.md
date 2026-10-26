# Execute: dokončení canonical self-hosted Supabase cutoveru

Pracuj v `<repo-root>` v release verification režimu a dodrž
`AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a produkční runbook.

Autoritativní plán je:

`docs/plans/canonical-self-hosted-cutover-readiness-plan-2026-09-05.md`

Přečti jej celý před změnami. Výsledkem musí být jediná write/Auth/Storage
autorita `https://api.festapp.net`, všechny cloudy read-only a každý klientský i
serverový writer uzavřený čerstvým důkazem. Dokončení znamená nejen funkční
canonical cestu, ale také odstranění nebo přesně omezené retenční zachování
každé legacy cesty z deletion ledgeru.

Proveď vlny v pořadí. Nezaváděj journal-hybrid, dual-write, reverse sync,
neplánovaný fallback, dynamický endpoint ani persistentní aplikační trigger.
Necommitnutý `workers/supabase-legacy-keepalive/` buď canonicalizuj jako
read-only retenční boundary, nebo jej nenasazuj; nesmí zůstat mimo inventory.
Pokud aktuální evidence vyvrátí fakt v plánu, aktualizuj autoritativní plán a
dotčenou vlnu, nikoli cílový výsledek.

Android build/upload/release, produkční freeze, export/import, runtime promotion,
otevření zápisů, aktivace klientů, rotace credentials a smazání legacy zdrojů
vyžadují každé svou samostatnou explicitní autoritu. Cloudy nikdy nemaž bez
výslovného destruktivního souhlasu. Při handoffu uveď canonical kontrakt,
migrované callers/data, odstraněné legacy artefakty, přesné validační výsledky a
každý dosud neprovedený provozní krok nebo blocker.
