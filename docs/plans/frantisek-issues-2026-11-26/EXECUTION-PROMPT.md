# Execution prompt - Františkova issue ve Festappu

Dokonči opravy [#1067](https://github.com/festappnet/festapp/issues/1067),
[#1068](https://github.com/festappnet/festapp/issues/1068) a
[#1069](https://github.com/festappnet/festapp/issues/1069), prověř a doplň
zdokumentované zbytky #958/#959 a doruč jeden společný PR na `main`.
Přečti celý [audit](README.md), [plán #1068](1068-bank-account-priority.md),
[plán #1067](1067-bank-email-queue.md), [plán #1069](1069-consent-in-app.md)
a [MCP postup](mcp-follow-up.md). Tyto soubory jsou autoritativní rozsah práce.
Přečti `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a
`CONTRIBUTING.md`. Výchozí GitHub základ auditu je
`50bd830f163e697eef51ad35bd580d8d9e4cb867`.

1. Načti aktuální upstream `main`. Proveď čistý worktree a zkontroluj stav
   všech tří issue i relevantní nové commity. Pokud nový kód mění faktický
   předpoklad, oprav plán současně s implementací. Nepřebírej rozpracované
   změny z karanténního checkoutu. Pokud plány nejsou ve tvém worktree,
   přenes složku artefaktů z `~/Developer/festapp-frantisek-issue-audit`.
   U souhlasu prověř předchozí lokální
   implementaci `fix/consent-link-in-app`. Je možné ji použít jako zdroj
   selektivního diffu po nové kontrole.
2. Implementuj #1068 jako dopřednou změnu čtecího RPC a příslušnou úpravu UI.
   Ověř pořadí po novém načtení, měnové výchozí hodnoty i podmíněný zápis
   při souběhu. #1067 oprav použitím existujícího navigátoru účtu, dialogů
   a přístupných responzivních karet. #1069 řeš přepnutím výslovně zvoleného
   odkazu na existující embed. V MCP doplň vysvětlení oprávnění a ověř
   readback ve vymezeném rozsahu. Uzavřené části auditu slouží jako
   regresní očekávání a evidence pro popis PR.
3. Použij standardní ověření kvůli SQL migraci, finančnímu toku, souhlasu a
   veřejnému kontraktu. Spusť cílené akceptační testy plánů, DB upgrade na
   jednorázové databázi, příslušné CI mirror lanes z `automation/test_ci.sh`
   před publikací a UI kontroly přes podporované vstupy. Flutter úlohy s
   `--concurrency=1` po kontrole volného slotu. Prohlížečová ověření deleguj
   dle osobních pravidel. U kódu udělej závěrečný review rozsahu, UX, vlastnictví
   domén, oprávnění, migračního kontraktu, retry a regresí. Odstraň dočasné
   fixture a experimenty mimo dohodnuté testy.
4. Připrav samostatné commity podle změn. Těsně před prvním pushem nebo
   založením PR znovu fetchni autoritativní `main` a porovnej SHA.
   Pokud se posunul, zapracuj relevantní změny a ověř dotčené části.
   Publikuj z běžného autorizovaného checkoutu s write přístupem.
   Karanténní `PUSH-DISABLED` je hranice, kterou neobcházej. Založ jeden PR
   s popisem pro každé issue a výsledky ověření. Použij `Closes #1067` a
   `Closes #1068` po splnění jejich akceptace. U #1069 dodrž pravidlo
   o přímé kontrole Messengeru z jeho plánu. U uzavřených issue odkaž na
   regresní evidenci.
5. Počkej na požadované kontroly a schválení na finálním headu, vyřeš
   případné opravitelné blokery a zamerguj schváleným způsobem. Zkontroluj
   merge a příslušný commit na `main`. Vrať odkaz na PR, výsledky testů,
   stav jednotlivých issue a otevřené ověření s konkrétní příčinou.
   Produkční nasazení, aplikace migrace na živou DB, nový přístup a
   reálné finanční operace vyžadují samostatný výslovný rozsah.
