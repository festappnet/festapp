# #1068 Uložené pořadí bankovních účtů

## Příčina a autorita

`UnitBankAccountsScreen._onReorder` posílá předchozí a nové pořadí.
`manage_bank_authoring` v `database/functions/authoring/finance.sql` porovná
`expectedOrder` pod zámkem s celým seznamem účtů bez CASH, seřazeným podle
`coalesce(priority,0), bank_account`. Změna při souběhu končí
`BANK_ACCOUNT_ORDER_CHANGED`. Nové priority jsou indexy od nuly.
`get_bank_accounts_for_unit_management.sql` prioritu neprojektuje a návrat
neřadí. Flutter v `SupabaseBankAccounts.getBankAccountsForUnit` řadí podle
`BankAccountModel.priority` a ID. Při chybějící hodnotě model dosadí 0, proto
může špatně ukázat i štítek výchozího účtu podle měny nebo odeslat zastaralé
`expectedOrder`. Schéma `database/tables/tables.sql` deklaruje prioritu
vazby jako `INT NOT NULL DEFAULT 0`.

## Implementace

1. Doplň `priority int` na konec výsledku management RPC, projektuj
   `uba.priority` a použij stabilní pořadí priority a ID shodné s příkazem.
   Zachovej filtrování CASH, recovery, ochranu demo účtů, projekci BankSync
   a granty. Vytvoř novou dopřednou migraci pro tento jediný zdroj v
   `automation/migration-forward-owners.json`. Výměna `RETURNS TABLE` používá
   transakční DROP/CREATE již obsažený v kanonické funkci, s obnovou stejných
   grantů. Zkontroluj závislosti před výměnou, použití CASCADE sem nepatří.
   `20261122180000_bank_email_confirmation.sql` je v registru stále aktivní
   generovaný vlastník. Před změnou zdroje ji v registru převeď na ověření
   existujícího SHA-256 a zachovej původní výběr zdrojů. Nový záznam se
   stane pozdějším vlastníkem RPC. Obsah staré migrace zůstane byte-for-byte.
   Změna nepotřebuje přepis priorit.
2. Výpis a pořadí štítků čti z jednoho výsledku. Odstraň redundantní Flutter
   sort, pokud kontrakt použitých RPC klientů garantuje převzetí tohoto
   pořadí. Modelový default ponech pro ostatní projekce, které pořadí
   nevyjadřují. Ověř refresh přes `BankAccountsLoadScope` i běžné opuštění
   obrazovky. Při konfliktu načti vítězné pořadí a ukaž lokalizovaný
   srozumitelný stav. Při neúspěšném načtení odliš neověřený výsledek od
   potvrzeného uložení. Během zápisu zablokuj souběžnou manipulaci i tlačítka
   posunu. Pokud je aktivní pouze recovery a výpis je záměrně neúplný,
   zachovej jeho read-only semantiku. V UI ani RPC se kvůli shodě množin
   nesmí rozšířit oprávnění. Klientský transport při potvrzeném
   `40001 / BANK_ACCOUNT_ORDER_CHANGED` uvolní rezervaci pouze pro odpovídající
   příkaz. Nový pokus po načtení dostane nové ID. Nejednoznačná chyba přenosu
   zachová identitu původního příkazu pro replay. Nový pokus může ověřit
   dřívější neuzavřenou změnu pod jejím původním ID. Po obnově jiné změny
   uživatel nejprve dostane aktuální pořadí.
3. `form_payment_options.sql` vlastní nabídku formuláře.
   `ensure_order_payment_instructions_internal` vlastní výběr pro nový
   převod podle měny a explicitního účtu formuláře. Ve výchozím pořadí používají
   prioritu a ID, takže změna opravuje projekci, bez změny resolveru nebo
   vydaných platebních instrukcí. Samostatný authoring výpis účtů v
   `finance.sql` stránkuje podle ID a již vrací prioritu. Cursor zůstává
   podle ID.

## Akceptace a kontrola

- Rozšiř existující `database/tests/units/get_bank_accounts_for_unit_management_test.sql`
  nebo odpovídající test příkazu. Použij alespoň dva běžné účty s opačným
  pořadím než ID, shodu priorit jako tie-break, překryv měn, skutečný reorder
  a následný readback s ordinalitou. Souběžný/stale `expectedOrder` je
  odmítnut a uložené pořadí se nepřepíše. Dolož CASH/recovery/demo a ACL.
- Flutter `unit_bank_accounts_load_test.dart`, `bank_account_card_test.dart`,
  `form_bank_account_picker_test.dart`. Ověř přetažení, ovládání tlačítky,
  správný štítek pro každou měnu po návratu a zachování explicitního účtu
  formuláře. Použij lokalizovaná hlášení bez surového kódu výjimky.
- Ověř generovanou migraci přes `--check` tenkého assembleru používajícího
  `migration_cli` a kontrolu registru `verify_forward` podle vzoru CI, upgrade čisté jednorázové DB a relevantní DB/Flutter lane z registru CI.
  Ukonči při shodě skutečného výpisu, podkladů pro `expectedOrder` a výběru
  výchozího účtu v obou směrech změny pořadí.
