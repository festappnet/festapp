# Bankovní autorizace - dvě nezávislé role

Uživatelské upřesnění 2026-10-21: správa bankovního účtu vyžaduje současně
správce organizace/pořadatele (`unit_users.is_manager`) a správce konkrétního
účtu (`eshop.bank_account_users.is_admin`). Tenantový
`organization_users.is_admin` je jiné oprávnění a bankovní role nenahrazuje.

Účet je fyzický resource sdílený mezi více pořadateli přes
`eshop.unit_bank_accounts`. Manager libovolného jiného pořadatele nestačí.
U existujícího účtu musí být spravovaný pořadatel skutečně připojený.

| Operace | Požadavek a serverový vstup |
|---|---|
| Přehled účtů pořadatele | Unit Manager; stávající omezené demo čtení se zachovává. `get_bank_accounts_for_unit_management`. |
| Vytvoření | Povinný cílový pořadatel a jeho Unit Manager; stejná transakce vytvoří účet, bank admin členství a link. `update_bank_account`. |
| Nové připojení existujícího účtu | Unit Manager cílového pořadatele **a** Bank Account Admin; předchozí link se nevyžaduje. `link_bank_account_to_unit`. |
| Změna pořadí / odpojení | Unit Manager konkrétního linku; účet ani jeho přístupová práva se nemění. Dependency check při odpojení zůstává. |
| Údaje účtu a přístupová práva | Obě role, skutečný link, zákaz demo zápisů. `can_manage_bank_account` vlastní policy. |
| BankSync stav, credentials, pause/resume, operace a observations | Stejný `can_manage_bank_account` přes `check_is_admin_for_bank_account`; Edge předává ověřený uživatelský JWT do tohoto SQL vstupu. |
| Ruční přiřazení/odebrání transakce a dostupné transakce objednávky | Stejný bankovní guard; existující order/resource invarianty zůstávají. |
| Přímý connection route | Vyžaduje `bank_sync.manage` z SQL projekce; pouhý seznam vlastních bank admin členství není oprávnění k otevření. |
| Výběr vlastního účtu k novému připojení | Bank admin seznam zůstává použitelný i před vytvořením linku; connection metadata se vrací pouze při splněné správě účtu. |
| Seznam uživatelů účtu | Stávající read-only bank admin/support nebo manager konkrétního linku; neuděluje právo role měnit. |
| Service ingest/reconcile/claim | Oddělená `require_service_role` hranice a resource/operation fence; tato systémová práce nevytváří uživatelské bankovní oprávnění. |

Dřívější dokumentace `lib/components/bank_accounts/README.md` popsala role jako
oddělené kontexty. Existující update a BankSync skutečně kontrolovaly jen bank
admina; přímý connection route výslovně nevyžadoval správu pořadatele. To bylo
v rozporu s aktuálním uživatelským upřesněním a nyní se zpřísňuje explicitně,
nikoli pod tvrzením o nezměněné paritě.

Projekce přidává setový JOIN spravovaných připojených účtů do stávajícího context
RPC. Používá stejný immutable `bank_account_write_rule` jako serverový predikát;
nevzniká další RPC ani dotaz na každou kartu. Odebrání bank role, unit role nebo
linku se ověřuje živě serverem, včetně návratu existující BankSync operace.

Při ověřování pozitivního JWT zápisu se navíc zjistilo, že demo migrace znovu
vytvořila details RPC bez obnovení authenticated EXECUTE. Forward migrace grant
obnovuje explicitně; anon/PUBLIC oprávnění k writerům se neposkytuje.

Ověření na task-owned PostgreSQL 15.8, port 61022, email a cron vypnuté:

- Dva skutečné SQL integration testy: čtyři kombinace rolí, details/users/BankSync,
  revokace před replay, nepřipojený účet, nové připojení, odpojení a povinný unit.
- Devět cílených SQL kontraktů prošlo: creator, unlink, unit management,
  details atomicity, BankSync permissions/recovery, demo čtení, interní hranice a source parity.
- Celý SQL/MCP balík: 66 prošlo, žádný test se nepřeskočil.
- Bankovní lifecycle/Rights/widget průchod: 41 prošlo. Analyzér změněných
  souborů neměl chyby ani warnings; hlásil 3 stávající style infos.
- Konečné Flutter bank cases: 46 prošlo. Zastaralé fixture očekávání pro banku
  0800 se opravilo na podporovaný režim; nepodporovaná banka má vlastní case.
  Poslední Rights/crew/reception průchod má 23 pass.


Po vytvoření účtu, vytvoření/odstranění linku a změně vlastních bankovních rolí
UI vyprázdní starou projekci a jednou načte normální context RPC. Díky tomu lze
nový účet rovnou napojit, aniž by UI vymýšlelo bank admin roli z úspěšného ID
nebo ji drželo z předchozího stavu. Otevřené nastavení sleduje změny projekce.
Běžné uložení údajů ani změna pořadí další permission request nepřidávají.
SQL `42501` a Edge HTTP `403` zahodí projekci a načtou context jednou;
stejný exception objekt se při dalším UI zpracování neduplikuje. Odmítnutý
zápis se neopakuje. Poslední klientský batch měl 56 pass/4 fixture fail;
po opravě těchto fixtures oba dotčené soubory prošly všemi 14 testy.

Starý Edge `fetch-transactions` nyní používá actor-bound
`get_bank_sync_connections_for_occasion`. Manager bez bank admin role nedostane
connection, bank admin bez manager role nedostane přístup. SQL ověřuje skutečný
link a demo ochranu, Edge synchronizuje pouze vrácené účty. Starý
`get_bank_sync_connections_for_unit` je odstraněný guarded DROP RESTRICT.
Skutečný SQL průchod ověřuje čtyři kombinace rolí a odebrání linku; tři Edge
testy ověřují, že po odmítnutí remote synchronizace vůbec neběží.

Opakované konečné měření contextu se 4/50 bankovními členstvími splnilo
p95/throughput limit 5 % sériově i se čtyřmi klienty, včetně prvního požadavku
na novém DB spojení. Přesná čísla, raw vstupy a rozdíly SQL snapshotů jsou
v `evidence/canonical-authorization-20261020/performance-summary.json`.
Lokální inventory/deletion a výkonové podmínky vln 0-4 jsou uzavřené;
produkční aplikace zůstává neprovedená.
