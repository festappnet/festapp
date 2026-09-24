# Execution prompt: Úklidová služba — navazující funkce (A + B)

Implementuj plán `docs/archive/plans/2026-07-10_uklidova_sluzba_navazujici_plan.md` — navazující
funkce úklidové služby: **A) Historie hlášení s exportem .txt**, **B) Blokování
ohlašovatelů**. Funkce C (recenze WC) **NEDĚLEJ**, je to samostatný task.

Nejdřív si přečti: `docs/architecture/ai_context.md`, celý plán, a předchozí plán
`docs/archive/plans/2026-07-10_uklidova_sluzba_plan.md` (kontext hotové featury).

Postupuj přesně po fázích ze sekce 4 plánu (DB → Flutter data → UI historie →
UI blokování → i18n → nasazení). Drž se rozhodnutí ✅ a doporučení v plánu, zejména:

- **Historie:** záložky „Aktuální / Historie" (SegmentedButton) v crew view, export
  prostý `.txt` přes FileSaver (vzor `lib/components/users/views/user_page.dart`).
- **Blokování:** sloupec `occasion_users.is_cleaning_blocked` (vzor `is_cleaning_crew`),
  RPC `set_cleaning_reporter_blocked` s auditem do `occasion_users.data`
  (`cleaning_blocked_by`/`cleaning_blocked_at`), 403 kontrola v `report_cleaning_issue`,
  `get_cleaning_status` nově vrací `is_blocked` pro volajícího.
- Model `CleaningReport` dnes **NEparsuje `created_by` (uuid)** — doplnit `createdBy`.
- **UI blokování:** overflow menu (⋮) na kartě hlášení + potvrzovací dialog se jménem;
  blokovaný účastník stránku vidí, jen má zašedlé „Nahlásit problém" s hláškou.

U otevřených otázek použij tyto defaulty (neptej se): historie bez filtru (vše),
hlavička `.txt` = název akce + datum exportu, `extra_notes` zahrnout (odsazené pod
řádkem); blokace per-occasion stačí; blokovat smí četa, **OD**blokovat jen editor/admin
(RPC pro `p_blocked = false` vyžaduje editor právo; odblokování jde i přes grid
Uživatelé).

Závazná pravidla (sekce 5 plánu): zápisy z klienta jen přes RPC; SECURITY DEFINER
vždy se `SET search_path = public, extensions` + explicitním permission checkem;
chyby přes `ExceptionHandler.guard`; gate přes `RightsService`; lokalizace jen přes
`CleaningStrings`/`UserStrings` (cs+en, byte-identická kopie do
`web_client/public/assets/translations/`); žádné `'literál'.tr()`.

Testy: nové DB testy do `database/tests/cleaning/` (blokovaný → 403, blok/odblok
přes RPC, non-crew nesmí blokovat, `is_blocked` ve statusu); lokální DB
`postgresql://postgres:postgres@localhost:55432/postgres`, spouštění
`node web_client/scripts/run_db_tests.js database/tests/cleaning/cleaning_test.sql`;
na závěr `./automation/test_all.sh` (2 pre-existing DB failures jsou baseline).

Nasazení (standard csmostrava): SQL na live **PŘED** klientem přes Management API
(ref `lwfpdjxsdmkfyrzqbrlk`, browser User-Agent), pak manuální bump verze,
commit jen vlastních souborů, `./automation/deploy_direct.sh` — **NIKDY git push**.
Nasadit společně s už hotovým (necommitnutým) zaškrtávátkem „WC (úklid)" ve
správě Míst, které na klienta na prod zatím nešlo.
