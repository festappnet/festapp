# Pokračování kanonické administrace a MCP

Aktuální pokračování: 2026-10-26. Načíst aktuální `origin/main`, AGENTS.md,
CLAUDE.md a `docs/architecture/ai_context.md`. Cizí dirty checkout neměnit.
Ověřování `standard`; práce patří do izolovaného worktree.

Autoritativní plán je [admin-mcp-canonical-plan-2026-10-23.md](admin-mcp-canonical-plan-2026-10-23.md).
Poslední aktuální sekce [checkpointu](admin-mcp-canonical-checkpoint-2026-10-23.md)
je **Stage 5 complete 2026-10-26**. Etapy 0-5 jsou implementované. Etapy 0-2B
jsou nasazené; etapy 3-5 jsou lokálně ověřené a čekají na review/rollout.
Jejich jediné review místo je [PR #617](https://github.com/festappnet/festapp/pull/617),
base main, branch `feat/admin-mcp-stage4-complete-20261026`. #613/#615/#616 jsou
uzavřené jako nahrazené. Neobnovovat review stack ani duplicitní implementace.
Při navázání znovu ověřit skutečný stav PR/headu a čerstvý main. Ochrana main
vyžaduje review; nevydávat bez samostatného oprávnění k danému rollout cíli.

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
