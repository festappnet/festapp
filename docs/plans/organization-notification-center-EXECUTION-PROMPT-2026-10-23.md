# Implementace organizačního zvonečku

Pracuj v `/Users/miakh/source/festapp`. Nejdříve přečti `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/organization-notification-center-plan-2026-10-23.md`

Realizuj jeho lokální implementační vlny v pořadí. Ověřování: standard kvůli oprávněním, migracím a souběhu. Výsledek je minimalistický osobní organizační zvoneček nad novými objednávkami, pořadníkem, kapacitou, bankou a všemi e-mailovými druhy v mezích serverových práv. Otevření označí dosud doručené položky jako přečtené napříč zařízeními, nová událost rozsvítí pouze tečku. Skupiny se rozbalují uvnitř panelu. Žádný backfill, další kanály, společný issue workflow ani účastnický inbox.

UI/UX přiděl samostatnému agentovi s medium reasoning; uživatel jej výslovně požaduje. Dej mu aktuální závazný kontrakt a úzký rozsah, použij existující UI vlastníky. Nepouštěj další nezávislý audit či paralelní engineering agenty bez zadání. Dodrž jedinou Flutter úlohu na workstation, testy `--concurrency=1` a izolovaný headless prohlížeč.

Nezakládej nový univerzální event bus, persistentní aplikační triggery, druhou e-mailovou frontu, bankovní import ani klientské emitování. Zachovej současné news/push notifikace. Proveď povinné read-cursor concurrency, ACL a dedupe testy; ověř skutečný nenulový test discovery. Pokud zdrojová evidence zneplatní fakt plánu, aktualizuj plán a dotčenou vlnu, ne uživatelský rozsah. Nenechávej placeholdery, falešná tvrzení o spamu nebo paralelní fallback úložiště.

Rozpracované nesouvisející změny patří uživateli, nepřepisuj je. Produkční migrace, nasazení, aktivace, commit a push vyžadují samostatné zadání; tento prompt je sám neautorizuje. Na konci uveď změněné kontrakty, skutečně provedené kontroly a přesné dosud neprovedené provozní kroky. Lokální dokončení a produkční aktivace jsou odlišné stavy.
