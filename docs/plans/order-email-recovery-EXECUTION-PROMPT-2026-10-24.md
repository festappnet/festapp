# Implementace nápravy nedoručeného objednávkového e-mailu

Přečti `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán `docs/plans/order-email-recovery-plan-2026-10-24.md`. Ověřování standard kvůli oprávněním, změně osobních údajů, souběhu a odesílání e-mailů.

Realizuj vlny 1-3: přesný objednávkový cíl upozornění a zvýraznění řádku bez změny hromadného výběru; společný opravný detail; úzký autorizovaný a idempotentní příkaz pro změnu kontaktu a volitelné atomické zařazení opakovaného potvrzení do současné fronty. Vlnu 0 nejdříve porovnej s aktuálním mainem, protože odstranění souhrnu historie je už součástí PR #576.

Použij existující OrderCommands, command receipts, queue/renderery a storno. Nezakládej novou objednávku, platbu, provider queue ani implicitní změnu na zaplaceno; neobcházej suppression nebo neznámý výsledek odeslání. Zachovej původní doručovací důkazy a odděl zařazení, přijetí a doručení. Nezaměňuj kontakt objednávky za identitu uživatelského účtu.

Prokaž ACL, nezměněný inventář/platbu, replay a souběh, konflikt kontaktu, rollback enqueue, blokovanou adresu a čitelnost ve skutečném ThemeConfig z AppBar v obou režimech a na mobilu. Jeden Flutter proces, testy `--concurrency=1`, izolované lokální E2E bez skutečných zákaznických e-mailů. Při rozporu s aktuálním kódem aktualizuj fakta a dotčenou vlnu plánu. Nenechávej placeholdery nebo druhé kompatibilní implementace.

Tento prompt sám nepovoluje produkční migraci, nasazení ani odesílání zákazníkům. Vydání z vlny 4 vyžaduje samostatné zadání. Na konci rozliš implementované a ověřené chování od dosud neprovedených produkčních kroků.
