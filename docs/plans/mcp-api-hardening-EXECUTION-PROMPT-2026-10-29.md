# Implementuj opravy MCP a HTTP API

Pracuj v `/Users/miakh/source/festapp`. Nejprve přečti platné `AGENTS.md`,
`CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/mcp-api-hardening-plan-2026-10-29.md`

Verification: standard. Cíl: funkční kvóty s důvěryhodnou proxy identitou,
automatické zotavení process/session locků po pádu a SQL summary projekce bez
osobních údajů. Zachovej společnou doménovou logiku, veřejné full admin kontrakty,
OAuth scopes, granty a receipty. Dokončení znamená také odstranění nahrazených
cest podle deletion ledgeru, ne pouze přidání nové funkční varianty.

Proveď vlny v pořadí závislostí. Nenahrazuj kernel lock stale adresářem,
nezaváděj druhý objednávkový engine, obecný trust proxy ani fallback summary na
full RPC. Neodstraňuj lock SQLite soubory. Publikované migrace jsou neměnné;
SQL změny patří do nové forward migrace a současných source/security kontraktů.

Pokud aktuální kód nebo měření vyvrátí předpoklad plánu, oprav autoritativní
plán s konkrétním důkazem před změnou dané vlny. Nezanechávej placeholdery nebo
neplánované kompatibilní větve. Ověřuj jen cílené gate uvedené v plánu; DB testy
musí skutečně běžet v povolené disposable DB a runtime gate na připnutém Node 24.
Neprovedený nebo skipped gate výslovně uveď jako nedokončený.

Tento prompt se používá až po samostatném zadání implementace. Bez další
výslovné autority neprováděj commit/push, produkční SQL, deploy, proxy reload,
marketplace zápisy ani propagaci do dalších tenantů. Při předání uveď změněný
kontrakt, odstraněné cesty, výsledky ověření a přesné neprovedené provozní kroky.
