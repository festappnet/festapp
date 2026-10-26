# Pokračování kanonické administrace a MCP

Aktuální pokračování: 2026-10-26. Nejdřív načíst aktuální autoritativní
`origin/main`, AGENTS.md, CLAUDE.md a `docs/architecture/ai_context.md`.
Cizí dirty checkout nepřesouvat ani neměnit. Ověřování `standard`.

Autoritativní plán:
[admin-mcp-canonical-plan-2026-10-23.md](admin-mcp-canonical-plan-2026-10-23.md).
Aktuální stav a přesné důkazy:
[checkpoint](admin-mcp-canonical-checkpoint-2026-10-23.md), poslední sekce
„Stage 4B 2026-10-26“. Historické stop po 2B bylo novým pokynem uživatele
odvoláno. Transport/SDK ani hotové etapy znovu neimplementovat.

Etapy 0-2B jsou nasazené. Etapa 3 je lokálně ověřená v
[PR #613](https://github.com/festappnet/festapp/pull/613), head
`6bf8b5be03d2550e0e7206e4b17e2ed59cb5790b`, obsahuje main `3988bb7cb`.
Ověřit aktuální GitHub stav; produkční rollout etapy 3 neproběhl. Main vyžaduje
jedno schválení review, bez obcházení ochrany.

Řez 4A je lokálně ověřený v [PR #615](https://github.com/festappnet/festapp/pull/615),
head `7f4053be653fa3e745a5207dd7ac578f8d51c681`, stacked na #613. Řez 4B
rozšířených nastavení je dokončený na `feat/admin-mcp-form-settings-20261026`,
navazuje na #615 a zůstává nenasazený. Při navázání ověřit aktuální stav celé
review návaznosti a její heady; neslučovat ani nevydávat bez příslušné autorizace.
Další řez etapy 4 jsou veřejné odkazy a inline produktové změny MCP přes
existující vlastníky. Nabídky čekací listiny a obecné ruční objednávky zůstávají
otevřené. Neopakovat šest nástrojů 4A ani metadata/platební volby dokončené v 4B.
Před editací jednou určit owner, kontrakt, volající a nejmenší smysluplný ověřovací batch.
Navázat na existující SQL pravidla a receipts; UI i MCP vést jednou cestou.
Zvlášť zachovat draft/persisted rozdíl, původní verzi, null/default semantics,
práva, atomicitu a retry stejným command UUID. Nepřidávat univerzální CRUD
framework, kopie výpočtů/ACL nebo nový form engine.

Součástí řezu je odstranění všech nahrazených aktuálních volání, fallbacků a
lokálních zrcadel. Vydané veřejné klienty neodpojovat bez upgrade gate; zachovat
jen hranici na stejného doménového vlastníka a zapsat podmínku odstranění.
Provisioning/copy/delete celé akce ponechat v jejím vlastním atomickém lifecycle,
neobalovat jej sérií vnořených editorových receipts.

Řídit se [zásadami MCP](../architecture/mcp-design-practices.md) a aktuální
mapou administrace. U každého řezu ověřit data/SQL/síť: duplicity, skutečné FK,
limity před agregací, pořadí zámků, počet requestů a serializované bajty.
Výkonové tvrzení musí mít srovnatelnou evidenci; index ani cache bez konkrétního
důvodu nepřidávat. Opakovat jen zasažené kontroly po hotové koherentní změně.
Práva/replay/souběh ověřit na skutečné marked disposable PostgreSQL bez skipů.

Nejvýše jeden Flutter task na workstation, testy `--concurrency=1`; JavaScript
přes pnpm 11.24.0. Browser jen při změně skutečné UI interakce, izolovaně a
headless. Náhled e-mailu není pokyn k odeslání; nepoužívat skutečné zákazníky,
objednávky nebo platby jako testovací fixture.

Produkční změny jsou samostatným autorizovaným krokem; tento dokument oprávnění
neuděluje. Při již uděleném oprávnění se znovu neptat na totéž. Vybraný tenant
musí být doložen session scope; jiné varianty nevydávat. Pro případné pokračování
historického rollout scope šlo pouze o `festapptickets` / `vstupenky.online`, org3,
canonical backend `api.festapp.net`. Ověřit aktuální aktivaci/cíl, backup/recovery,
zdrojové digesty, SQL ledger/ACL, health a koherentní live verzi. Rutinní release
delegovat podle AGENTS levnějšímu agentovi s přesným frozen source a gates.
Web se sestavuje lokálně a vydává přes `automation/deploy_direct.sh`.

Po řezu aktualizovat checkpoint, mapu pokrytí, zdrojový JSON katalogu a HTML přes
`node automation/reports/generate_admin_capabilities.mjs`. Stručně odlišit
lokálně hotovo, publikováno a nasazeno. Pokud další krok blokuje review nebo
vnější stav, zapsat konkrétní podmínku; nevydávat cizí rozpracované změny.
