# Pokračování kanonické administrace a MCP

Aktuální pokračování: 2026-10-27. Načíst aktuální `origin/main`, AGENTS.md,
CLAUDE.md a `docs/architecture/ai_context.md`. Cizí dirty checkout neměnit.
Ověřování `standard`; práce patří do izolovaného worktree.

Autoritativní plán je [admin-mcp-canonical-plan-2026-10-23.md](admin-mcp-canonical-plan-2026-10-23.md).
Poslední aktuální sekce [checkpointu](admin-mcp-canonical-checkpoint-2026-10-23.md)
je **Production rollout 2026-10-27**. Etapy 0-5 jsou implementované a pro
`prod/festapptickets` nasazené ve verzi **0.20.427+929**. Kód release main
`00c1da5cef9bb1e949bf230f270f221b1b9f69d8`, tenant
`bfbc1c3c1740efe34949b688a914808f61bb9252`.
[Release receipt](../operations/releases/festapptickets-2026-10-27.json)
obsahuje ověřené SQL/Edge/MCP/web komponenty a limity. #617/#618/#619 jsou
sloučené; #613/#615/#616 byly nahrazené. Neobnovovat starý review stack.
Při navázání ověřit čerstvý main a skutečný stav služby. Admin výjimky byly
výslovně omezené na dokončený rollout; další etapa a nasazení se řídí běžnými
pravidly a případným novým oprávněním uživatele. Souběžný ChatGPT pilot je
samostatná práce, nikoli další dokončená doménová etapa.

Další doménová etapa je **6 - lidé, role, skupiny a dobrovolníci**. Nejprve
najít konkrétní UI handlery a existující group/profile/unit command vlastníky,
vypsat typed predicate -> SQL owner -> UI -> nástroj. Postupovat scoped čtením,
pak běžnými údaji a členstvím; role jako samostatný explicitní příkaz. Před
kódem potvrdit úzký kontrakt a nejmenší smysluplný ověřovací batch.

Etapu 5 znovu neimplementovat: osm nástrojů sdílí původní occasion/unit/game
receipt vlastníky. Kontrakt `packages/festapp_contracts/configuration-settings.json`
generuje SQL a MCP strict schemas. Současný UI producer posílá named metadata;
sloučení až po původním hashi/version locku. Game UI/MCP vyžaduje původní verzi,
organizer settings vlastní manager oprávnění a explicitní whole-unit souhlas.
Současný přesun mimo scope je otestovaný přes skutečný row-lock wait; nesmí
přežít ani vrátit čtení nebo commit. Důkazy:
[admin-configuration-evidence-2026-10-26.json](../reports/admin-configuration-evidence-2026-10-26.json).

Publikované migrace neměnit. Aktuální konfiguraci sestavuje
`automation/assemble-configuration-migration.py`, pak generátory canonical source
contract a katalogu. Změna occasion save owneru vyžaduje též přegenerovat runtime
ticket-layout kontrakt a zahrnout jej do nové migrace; samotné změnění source
souboru nestačí. Striktní vstupy ani nové scopes nesmí rozšířit starší souhlasy.
Draft finalizace, provider setup a ticket artwork si ponechávají své vlastníky.

Celkem 6/11 hlavních etap, orientačně 45 % podle velikosti (40-50 %). Nejde o
odpracované hodiny. Další výrazné bloky jsou 6, 7, 8 a 10. Efektivita: nevytvářet
novou ACL, writer, receipt, univerzální JSON CRUD ani paralelní cestu k existující
operaci. Testovat skutečné běžné identity a cílené inputy; passing check neopakovat,
pokud jeho vstupy zůstaly stejné. Flutter pouze jeden proces a concurrency=1.
