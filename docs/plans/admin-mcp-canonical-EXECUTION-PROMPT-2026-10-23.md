# Pokračování kanonické administrace a MCP

Aktuální pokračování: 2026-10-27. Načíst čerstvý origin/main, AGENTS.md,
CLAUDE.md a docs/architecture/ai_context.md. Ověřování standard, izolovaný
worktree; cizí dirty checkout neměnit.

Autoritativní plán: [admin-mcp-canonical-plan-2026-10-23.md](admin-mcp-canonical-plan-2026-10-23.md).
Poslední stav: [Stage 6 locally complete](admin-mcp-canonical-checkpoint-2026-10-23.md).
Etapy 0-5 mají doložené nasazení pro prod/festapptickets ve verzi
0.20.427+929. [Receipt](../operations/releases/festapptickets-2026-10-27.json)
obsahuje skutečné SQL/Edge/MCP/web revize. Etapa 6 je lokálně hotová a ověřená,
bez produkčního nasazení; větev feat/admin-mcp-stage6-20261027 z main a698f7403.
Před pokračováním ověřit stav jejího review/integrace. Main vyžaduje review;
staré admin výjimky se na další etapu či rollout nevztahují.

Další etapa je **7 - pokročilá editace plánků a vzhled vstupenek**. Přečíst
její konkrétní řezy v plánu. Provozní blokace/hold release/swap/order již existují;
neimplementovat je znovu. Navázat na kanonický layout/controller/save a současné
PDF/font/rendering vlastníky, zachovat draft, explicitní Save/Cancel, původní
verze, scope a oprávnění. Před kódem zapsat owner -> UI -> MCP a nejmenší
smysluplný testovací batch. Žádné vývojové subagenty bez autorizace.

Etapu 6 znovu neimplementovat. [Matice a kontrakt](admin-mcp-stage6-boundary-2026-10-27.md)
a [evidence](../reports/admin-people-evidence-2026-10-27.json) obsahují 19 nových
nástrojů, reálné PostgreSQL/SDK/Flutter kontroly a source hashe. Profily/skupiny
sdílejí původní command ownery; named profily a role mají rozdílný explicitní
záměr a OAuth scope. Organizer user grid používá nový společný verzovaný command
nad původní persistence funkcí, s jednou access-change invalidací. Neforkovat
žádnou ACL, receipt ani profile writer.

SQL měnit jako canonical source a novou forward migraci. Pro etapu 6 běží
python3 automation/assemble-people-migration.py --check a source/parity generátor.
Publikované migrace jsou neměnné. Změna occasion save owneru vyžaduje také
přegenerovat scoped runtime ticket-layout kontrakt a zahrnout jej do nové migrace.
Použít marker-verified disposable PostgreSQL, skutečné běžné identity a explicitní
souběhové testy pro zásadní kolize. Flutter pouze jeden proces, concurrency=1.

Hotovo 7/11 hlavních etap. Produkční release je oddělený, explicitně autorizovaný
krok. Vybraný tenant zůstává prod/festapptickets, jiné varianty ani Android do
výchozího scope nepatří. Backend přes canonical workflow, web lokálně přes
automation/deploy_direct.sh; rutinní autorizované nasazení delegovat dle AGENTS.
Souběžný ChatGPT veřejný pilot je samostatná práce, ne další doménová etapa.
