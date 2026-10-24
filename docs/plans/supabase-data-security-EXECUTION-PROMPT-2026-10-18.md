# Implementace Supabase datové bezpečnosti

Pracuj v repozitáři `/Users/miakh/source/festapp`, na aktuálním čistém main v izolovaném worktree. Zachovej rozsáhlé existující změny původního checkoutu. Přečti příslušné agentní instrukce, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/supabase-data-security-plan-2026-10-18.md`

Použij `verification: standard`. Implementuj všechny jeho lokální vlny v pořadí závislostí: uzavři historické Auth bypassy, zachovej dokončenou skupinovou migraci na main, dokonči skutečné zbývající čtenáře novinek a akcí, oprav scoped ACL/RLS a nadbytečné peer/profile/location výstupy a zabezpeč výchozí granty. Respektuj protokol a capability client-sync, canonical-mutation gate, emailovou frontu a současné doménové vlastníky. Pouhé převedení klienta na RPC bez uzavření tabulkového bypassu nestačí.

Dokončení vyžaduje DB01-DB08 z plánu, pozitivní i negativní testy, fresh/upgrade shodu, efektivní granty, skutečný read/write call graph a splněný deletion ledger. Podporované starší klienty inventarizuj; případné bezpečné kompatibilní hranice výslovně eviduj s konkrétní podmínkou odstranění. Žádné neplánované fallbacky, duplicitní business implementace nebo přepisování aplikované historie. Není to zadání k odstranění celé legacy capability ani k migraci všech tabulek aplikace na RPC.

Pokud aktuální main/runtime vyvrací předpoklad plánu, aktualizuj autoritativní plán s důkazem a uprav příslušnou vlnu. Nepřebírej zpět starší implementaci z pracovního diffu. Neoznačuj citlivá pole za legitimně veřejná bez doloženého konzumenta.

Zapisovací testy spouštěj výhradně na ověřené izolované lokální DB s explicitním `DATABASE_URL`, nikoli na produkci ani jako rollback fixtures. Dodrž targeted checks a ověř, že runner skutečně provedl požadované testy. Nezadávej nezávislý subagent audit bez výslovného požadavku.

Připrav konkrétní reviewable SQL fáze, digesty, kompatibilitní preflight a release postup. Produkční migrace, nasazení, vydání mobilních aplikací, commit ani push nejsou tímto promptem autorizovány. Při později autorizovaném releasu použij ověřený self-hosted target, pouze vybraný tenant `festapp`/`prod/festapp`, lokální build a `automation/deploy_direct.sh`; rutinní release práci deleguj podle standing instrukcí. Sdílený dopad DB musí být součástí konkrétního schváleného kroku.

Při předání stručně uveď změněné kontrakty, převedené čtenáře, odstraněné bypassy, skutečné test evidence, ponechané bezpečné hranice a přesné produkční kroky, které zůstávají pending. Lokální opravu nevydávej za uzavřený živý nález.
