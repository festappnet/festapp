# Implementuj úspornější CI

Autoritativní plán: `docs/plans/ci-efficiency-plan-2026-11-16.md`. Přečti jej celý spolu s aktuálními AGENTS.md, CLAUDE.md, ai_context.md a CONTRIBUTING.md.

Pracuj v čistém worktree od aktuálního main. Checkout, ve kterém plán vznikl, obsahuje starší CI a rozsáhlé cizí změny; ty nepřenášej. Ověřování implementace je standard. Nezakládej další plánovací či měřicí framework a neopakuj dokončenou práci ze starších plánů.

Cíl: zkrátit čas k výsledku a snížit runner minuty pomocí levnějšího selectoru, rozdělení Wix/SQL bloků a ověřeného výběru jednotek. Zachovej osm povinných jobs, úplný testovací inventář, původ přímé exekuční evidence, přesný release SHA, cold upgrade a reálnou CMS matici. Nejdřív rozdělení s plným pokrytím, potom jemný výběr a jednotkový reuse. Lokální explicitní lane stále běží celý. Neznámé vstupy znamenají plný rozsah.

Postupuj ve vlnách plánu. Žádné plošné rušení main/release běhů, zvyšování Flutter souběhu, trvalé kompatibilní fallbacky nebo přesouvání testů mimo required gate. Pokud aktuální důkazy vyvrátí premisu, oprav plán i dotčenou vlnu. Nevydávej očekávanou úsporu za naměřenou.

Ověř cílené kontraktové/negativní testy a dotčené canonical mirror lanes. Při případné publikaci dodrž upstream gate a všechna pravidla repozitáře. Toto zadání samo neopravňuje push, produkční deploy, placené runnery ani změnu branch protection; potřebují samostatné zadání. Bez publikace označ hosted vyhodnocení jako čekající.

Dokončení vyžaduje odstranění nahrazených aktivních kroků a duplicitních map, bezpečný aggregate receipt a výsledkový dokument podle plánu. Handoff stručně uvede změny, validaci, naměřený čas a runner minuty, zbylé limity a případný neprovedený publikační krok. Nezahajuj samostatný subagent audit.
