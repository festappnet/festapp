# Provedení: čistá akceptace MCP

V `/Users/miakh/source/festapp` přečtěte celý autoritativní plán
`docs/plans/mcp-clean-acceptance-plan-2026-11-05.md` a proveďte jeho vlny.
Uživatel výslovně zadal přípravu i provedení; ověření je standard.

Cíl: opakovatelná příprava skutečné lokální DB, plná MCP sada bez fail/skipped,
reálný Auth/Edge/OAuth/MCP/SQL pilot, vyhodnocení devíti rozdílů produkčních definic
a odpovídající generovaná dokumentace. Neoslabujte ACL, source parity, konflikty,
receipty ani testové assertiony. Používejte existující kanonické ownery.

Zachovejte nesouvisející rozpracovanou práci. Žádné produkční business operace,
migrace, deploy nebo publikace. Změní-li důkaz předpoklad, aktualizujte plán;
nedoplňujte tajné fallbacky ani falešné dokončení. Zaznamenejte skutečné výsledky,
hranice akceptace a konkrétní stav případného samostatného release kroku.
