# Implementace doručení vstupenek v e-mailu

Archivováno po lokální implementaci 2026-10-23; výsledky a otevřené provozní brány jsou v autoritativním plánu.

Pracuj v repozitáři Festapp. Nejdříve přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý autoritativní plán:

`docs/archive/plans/ticket-email-delivery-plan-2026-10-23.md`

Implementuj plán v pořadí jeho čtyř kroků. Výsledek: jedna volba pro celou akci mezi `pdf_attachment`, `inline_qr` a `both`; výchozí pro nové i existující akce je vždy PDF v příloze. Jedna vstupenka má jeden stávající symbol a sdílený stav kontroly vstupu bez ohledu na způsob doručení. V těle e-mailu zobrazuj pouze jednoduchý QR pro každou vstupenku, bez grafické karty a bez automaticky přidaných údajů akce, produktu nebo sedadla. Ostatní informace zůstávají v běžném textu šablony. Pořadateli stručně vysvětli, že tato varianta neobsahuje grafickou vstupenku ani PDF. Inline režim nesmí vyžadovat PDF layout, fonty ani pozadí.

Ověřování: standard, cílené SQL/Deno/Flutter testy a náhledy podle plánu. Neprováděj širokou release validaci bez požadavku na vydání. Dodrž jediný Flutter úkol na stanici a testy s `--concurrency=1`. JavaScript příkazy pouze přes pnpm 11.24.0. UI/UX práci a její posouzení deleguj subagentovi `gpt-6-astra` s reasoning `medium`, podle výslovného přání uživatele.

Zachovej globální e-mailovou frontu, oprávnění, atomické snapshoty, deduplikaci, send fencing, staré PDF snapshoty, stávající PDF tisk/download a neodesílej znovu při pouhé změně nastavení. Nezaváděj nový druh vstupenky, novou frontu ani alternativní veřejnou cestu k QR. Uprav potvrzovací náhled pouze přidáním explicitního typu zprávy, nikoli jeho nahrazením.

Pokud současné zdroje zneplatní faktický předpoklad plánu, oprav plán s konkrétním důkazem a přizpůsob příslušný krok. Nenechávej placeholdery ani duplicitní renderery. Zachovej cizí rozpracované změny a dodrž canonical main/tenant pravidla; nezačínej resetem nebo přepnutím obsazené větve.

Tento prompt je připravený podklad, nikoli současné pověření k implementaci. Po jeho výslovném zadání implementuj lokálně; produkční SQL, commit/push, deployment, skutečné platby nebo odesílání do reálných schránek vyžadují zvláštní rozsah oprávnění. Bez něj uveď neprovedené provozní brány přesně a neoznačuj práci za živě nasazenou.

Při předání stručně uveď změněné chování, provedené cílené testy, výsledek UI/UX posouzení a případné neověřené poštovní klienty či nenasazené kroky. Po dokončení aktualizuj stav plánu a přesuň dokončené plánovací artefakty podle repo dokumentačního lifecycle.
