# Code Review Checklist — Flutter/Backend — 2026-02-16

> Historical review snapshot. Checkboxes describe the February 2026 review,
> not current defects or deployment instructions. The obsolete remote SQL
> installer was removed on 2026-10-19. Use the [documentation map](../README.md)
> for active procedures.


Checklist vychází z `code_review_2026-02-16.md`. Zaškrtnout po opravě.

---

## 1. KRITICKÉ — all fixed

- [x] ~~**SQL Injection v `instance-install`**~~ — parametrizované dotazy (`$1`, `$2`)
- [x] ~~**TLS verifikace**~~ — `rejectUnauthorized: false` nahrazeno `tls: { enabled: true }`
- [x] ~~**HTML Injection**~~ — `unsafe()` nahrazeno `sanitizeHtml()` (DOMParser whitelist) + 14 testů

## 2. VYSOKÁ ZÁVAŽNOST

- [x] ~~**Chybějící RLS policies na eshop tabulkách**~~ — zdokumentováno v migraci (deny-all + RPC gateway pattern)
- [ ] **Overly permissive RLS** — `occasions`, `places` stále `USING (true)` pro public SELECT; `user_group_info`, `user_groups`, `exclusive_events` stále wide-open pro authenticated
- [x] ~~**Cirkulární závislosti**~~ — `SynchroService` injektován přes `configure()` v `main.dart`
- [x] ~~**Globální mutable state**~~ — `updateAppData()` serializován, `versionCheck()` deduplikován
- [ ] **CORS** — `instance-install/index.ts:4` stále `Access-Control-Allow-Origin: *`
- [x] ~~**Input validace edge functions**~~ — validace v `instance-install`

## 3. STŘEDNÍ ZÁVAŽNOST

- [ ] **God classes rozdělit:**
  - [ ] `activities_content.dart` (2 860 ř.)
  - [ ] `eshop_columns.dart` (1 409 ř.)
  - [x] ~~`bank_account_settings_screen.dart`~~ — rozdělen na 3 taby
  - [ ] `map_page.dart` (1 203 ř.)
  - [x] ~~`dialog_helper.dart`~~ — rozdělen na 3 soubory
  - [x] ~~`occasion_settings_tab.dart`~~ — rozdělen
  - [x] ~~`blueprint_editor_tab.dart`~~ — extrahován mobile scroll view
  - [x] ~~`scan_page.dart`~~ — extrahován field mappings, result display
  - [x] ~~`products_dialog.dart`~~ — extrahován info panel, changes preview
- [x] ~~**`debugPrint` → `AppLogger`**~~ — 74 výskytů nahrazeno
- [x] ~~**`print()` → `AppLogger`**~~ — 0 aktivních výskytů v `lib/`
- [ ] **Chybějící databázové indexy** — FK sloupce na eshop tabulkách
- [ ] **Audit log** — `orders_history` existuje pro objednávky; chybí pro platby, bankovní účty, transakce
- [ ] **CHECK constraints** — `products.price >= 0`, `payment_info.amount >= 0` atd.

## 4. NIŽŠÍ ZÁVAŽNOST / BACKLOG

Tyto položky jsou architektonické/long-term a neblokují release:

- [ ] Lint pravidlo pro zákaz `print`/`debugPrint`
- [ ] AppLogger rozšíření (severity, remote sink)
- [ ] Business logika oddělit od UI (god classes výše)
- [ ] State management sjednotit (638× `setState`)
- [ ] DI kontejner (GetIt apod.)
- [ ] Memory leak `map_page.dart:109` — chybí `removeListener` v `dispose()`
- [ ] Prázdné catch bloky (`form_design_settings.dart:194`)
- [ ] Unsafe type casty (`as?`)
- [ ] Mutable data modely (`EventModel` aj.)
- [ ] Session token v localStorage (standardní Supabase pattern, závisí na absenci XSS)
