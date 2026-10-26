# Časová agregace historie objednávek

Uživatelské upřesnění 26. 10. 2026 navazuje na schválený vzhled plochého feedu.
Změny objednávek mladší 24 hodin zůstávají jednotlivě. Starší se agregují
za akci a období, napříč vytvořením, náhradníky, storny a nabídkami. Posledních
sedm kalendářních dní má denní skupiny, starší období pondělní týdenní skupiny.
První neúplný týden ukazuje skutečný rozsah zbývajícího období. Jiná upozornění,
včetně otevření/uzavření formuláře, kapacity, bank a e-mailů zůstávají jednotlivě.

Skupina ukazuje počet všech viditelných akcí, ne míst ani unikátních objednávek
a ne pouze načtených položek. Rozbalení zpřístupní původní řádky a detail;
velké skupiny mají neztrátové stránkování. Pouze explicitní open potvrzuje stav.
Snímek zmrazí čas, kalendář a delivery sequence; nové doručení se nesmí skrytě
přidat k počtu. Odebraná práva odstraní počty i již rozbalené kontakty.

Počet 1 se zobrazuje u formulářů umožňujících více míst; u formulářů pouze
pro jedno místo se vynechá. Zachované historické údaje mají přednost. Pro staré
události bez těchto údajů se doplní autorizovaný aktuální kontext objednávky.

Ověření: 13 skutečně spuštěných SQL souborů, 6 testů skutečného souběhu,
19 cílených klientských testů včetně DST 23/25 hodin a identity/revocation fences.
Další integrační receipts a skutečný lokální Flutter/Supabase průchod jsou
v notification-order-history-evidence-2026-10-26/.

Kompletní klientské ověření finálních Dart vstupů: 2345 případů bez selhání.
Do společného vydání je připojen i pozdější main c77397611 (vstup do skeneru
a nápověda); dotčená webová sada má 754 PASS, 30 skips, 0 failures.
