# Stav kanonické administrace a MCP po dokončení etap

Aktualizace 2026-10-27: **etapy 0-10 jsou lokálně dokončené a ověřené**.
Další implementační etapa není otevřená. Neopakovat již dokončené doménové řezy
ani nevytvářet náhradní ACL, účetní výpočty, receipt ledger nebo storage autoritu.

[Autoritativní plán](admin-mcp-canonical-plan-2026-10-23.md),
[závěrečný checkpoint](admin-mcp-canonical-checkpoint-2026-10-23.md#stage-7-10-final-local-closure),
[matice vlastníků](admin-mcp-final-stages-boundary-2026-10-27.md),
[evidence](../reports/admin-authoring-final-evidence-2026-10-27.json)
a [katalog 193 nástrojů](../reports/admin-capabilities-2026-10-23.html).

Aktuální kandidát je větev `feat/admin-mcp-stage6-20261027` v izolovaném worktree
`/private/tmp/festapp-admin-mcp-stage6-20261027`, nad main `a698f7403`.
[PR #641](https://github.com/festappnet/festapp/pull/641) obsahuje etapy 6-10.
Před další publikací načíst čerstvý origin/main a ověřit aktuální review/integraci.
Main vyžaduje běžné review; staré admin výjimky ani stará release oprávnění se
na tento kandidát nepřenášejí.

Etapy 0-5 mají doložené nasazení pro `prod/festapptickets` ve verzi 0.20.427+929.
[Původní release receipt](../operations/releases/festapptickets-2026-10-27.json)
se nemění. Etapy6-10 zatím v produkci nejsou. Další rollout vyžaduje samostatné
výslovné zadání. Výchozí scope neobsahuje další tenanty ani Android. Při později
autorizovaném web release zachovat kanonickou main/tenant ancestry, backendové
brány, lokální build a `automation/deploy_direct.sh`; rutinní release běh delegovat
dle AGENTS.md. Veřejný ChatGPT pilot zůstává samostatnou prací.

Pro opravy kandidáta používat canonical SQL a nové dosud nepublikované forward
migrace. Jejich source freeze ověří
`python3 automation/assemble-admin-authoring-migration.py <7|8|9|10> --check`,
source/parity generátor a runtime ticket-layout kontrakt. Historické publikované
migrace neměnit. Backendové testy jen v marker-verified disposable databázi se
zastaveným cronem a doručováním. Flutter pouze jeden proces, concurrency=1.
Cizí dirty checkout neměnit. Bez autorizace nepoužívat vývojové subagenty.
