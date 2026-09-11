# Plán: Úklidová služba — navazující funkce (historie + blokování ohlašovatelů)

**Stav: NÁVRH PŘIPRAVENÝ K IMPLEMENTACI (revize 2026-07-11).** Navazuje na už
nasazenou featuru „Úklidová služba" (viz `docs/archive/plans/2026-07-10_uklidova_sluzba_plan.md`).
Nic z tohoto dokumentu ještě není implementováno. Rozhodnutí označená ✅ jsou
potvrzená uživatelem 2026-07-10; otázky v sekcích „Otevřené" se doladí za běhu.
*Revize 2026-07-11: všechna tvrzení o existujícím kódu ověřena proti repozitáři,
doplněna architektonická a UX doporučení (záložky historie, blokování v overflow
menu, `is_blocked` ve statusu, audit blokace) — cíl: co nejčistší architektura
i UX.*

## 0. Výchozí stav (co už funguje)

- Featura `cleaning` (SimpleFeature, default OFF), nasazená na prod jako
  **0.19.56+306**; na live occasion `csmostrava2026` (id 643) je **zapnutá**,
  1 místo označené jako WC, 1 člen čety, už padlo 1 hlášení.
- Toaleta = `places.type = 'toilet'`, nastavuje se **zaškrtávátkem „WC (úklid)"**
  ve správě Míst (feature-gated). *(Tato UX úprava + zjednodušení backendu je
  hotová lokálně a SQL funkce jsou nahrané na live, ale klient s tímto sloupcem
  ještě NENÍ nasazený na prod — čeká na společné nasazení s dalšími věcmi.)*
- Existující RPC (SECURITY DEFINER, envelope `{code,message,data}`):
  `report_cleaning_issue`, `get_cleaning_status`, `get_cleaning_reports(oc, p_include_resolved)`,
  `resolve_cleaning_place`, `get_is_cleaning_crew_on_occasion`.
- Anti-spam dnes: rate limit ~5 hlášení / 15 min / uživatel (kód 429).
- Klíčové soubory: `lib/components/cleaning/` (`cleaning_page.dart` — mřížka +
  crew view, `db_cleaning.dart`, `cleaning_report_flow.dart`, modely,
  `cleaning_strings.dart`), `database/functions/cleaning/`,
  `lib/components/users/` (occasion_user_model, user_columns, users_tab — vzor
  `is_cleaning_crew`), `lib/data_services/rights_service.dart`.

---

## 1. Funkce A — Historie hlášení

### Rozhodnutí
- ✅ **Formát stažení = prostý text `.txt`** (jeden řádek na hlášení).
- ✅ Viditelné **jen pro četu/admina** (`RightsService.isCleaningCrew()`).
- ✅ Zahrnuje **i vyřešená** hlášení (nejen otevřená).

### Datový základ
- Backend je hotový: `get_cleaning_reports(oc, p_include_resolved => true)` už
  vrací i vyřešená hlášení s poli `id, place, place_title, problem_type, note,
  data, created_at, created_by, created_by_name, resolved_at, resolved_by`.
  → **Není potřeba nová SQL funkce.**
- `DbCleaning.getReports(oc, includeResolved: true)` + model `CleaningReport`
  už existují (model má `resolvedAt` i `extraNotes`) — pro historii stačí beze změn.

### UI (návrh)
- Na stránce **Úklid** (`cleaning_page.dart`), crew-only sekce/obrazovka
  **„Historie hlášení"**. **Doporučení (UX):** záložky/`SegmentedButton`
  **„Aktuální / Historie"** nad seznamem hlášení v crew view — viditelné a
  objevitelné; ikona schovaná v AppBaru vedle „Obnovit" je snadno přehlédnutelná.
  Tlačítko „Stáhnout" pak patří jen do záložky Historie.
- Textový seznam řádků: `datum a čas · WC · typ problému · „poznámka" · nahlásil ·
  (uklizeno v HH:mm / otevřené)`. Řazení od nejnovějšího.
- Tlačítko **„Stáhnout"** → vygeneruje `.txt` a uloží přes `FileSaver`
  (vzor `DbEventFeedback.exportForEdit` + `FileSaver.instance.saveFile` v
  `user_page.dart`, jen místo CSV prostý text; `mimeType: MimeType.text`).
- Nové klíče do `CleaningStrings` (cs+en): titul „Historie hlášení", „Stáhnout",
  formát řádku (typ/čas), „otevřené"/„uklizeno".

### Otevřené otázky (A)
- Filtrování podle dne / jen dnešní vs. celé? (zatím: vše, bez filtru)
- Přesná skladba řádku a hlavičky `.txt` (doporučení: první řádek = název akce +
  datum exportu, pak jeden řádek na hlášení; `extra_notes` odsazené pod řádkem).
- Zobrazit i „extra_notes" (poznámky z duplicitních hlášení)? (pravděpodobně ano)

---

## 2. Funkce B — Blokování ohlašovatelů (anti-spam, tvrdý zákaz)

### Rozhodnutí
- ✅ **Obojí**: tlačítko **„Zablokovat"** přímo u hlášení v crew view **i**
  zaškrtávátko v admin záložce **Uživatelé** (pro přehled a odblokování).
- Doplňuje stávající rate limit — je to trvalý zákaz pro konkrétního opakovaného
  potížistu, ne časové omezení.

### Datový model (návrh)
- ⚠️ **Zjištěno kontrolou kódu (2026-07-11):** Flutter model `CleaningReport`
  dnes **neparsuje `created_by` (uuid)** — bere jen `created_by_name`. SQL ho
  vrací, ale do UI se nedostane; pro tlačítko „Zablokovat" u hlášení je nutné
  do modelu doplnit pole `createdBy`.
- Nový sloupec **`occasion_users.is_cleaning_blocked boolean not null default false`**
  (přesný vzor `is_cleaning_crew`: `tables.sql` + `ALTER TABLE … ADD COLUMN IF
  NOT EXISTS` na live; do modelu `OccasionUserModel`, `UserColumns`, `users_tab`,
  `to_jsonb(ou)` ho protáhne do gridu automaticky).
- **`report_cleaning_issue`**: hned po ověření přihlášení zkontrolovat, zda má
  volající na dané occasion `is_cleaning_blocked = true` → vrátit **403**
  („Hlášení máš dočasně zakázané"). Kontrola přes malý helper nebo inline select.
- Nová RPC **`set_cleaning_reporter_blocked(p_occasion bigint, p_user uuid, p_blocked boolean)`**
  — SECURITY DEFINER, gate `get_is_cleaning_crew_on_occasion(p_occasion)` (blokovat
  smí četa i editor), nastaví flag na `occasion_users`. Envelope `{code,message,data}`.
  *(Blokování z gridu Uživatelé jde i stávající cestou `updateOccasionUser`, ale
  ta je editor-only; RPC umožní blokovat i řadovému členu čety přímo od hlášení.)*
  Pozor na symetrii práv: takto navržená RPC dovolí členu čety i **od**blokovat.
  Pokud má odblokování zůstat editor-only, musí funkce pro `p_blocked = false`
  vyžadovat vyšší právo — rozhodnout v otevřených otázkách níže.
- **Audit v témže RPC**: při zablokování zapsat do `occasion_users.data` klíče
  `cleaning_blocked_by` (uuid) a `cleaning_blocked_at` (timestamp), při odblokování
  je smazat. Levné, bez nové tabulky, řeší otázku „kdo a kdy".
- **Čistší informování účastníka (architektura):** místo nové RPC / helperu
  navíc vrátí **`get_cleaning_status`** v odpovědi i flag **`is_blocked`** pro
  volajícího. Stránka Úklid ho už stejně volá — UI zašedne tlačítko „Nahlásit
  problém" + zobrazí hlášku bez dalšího round-tripu. Kontrola v
  `report_cleaning_issue` (403) zůstává jako zdroj pravdy; flag je jen pro UX.

### UI (návrh)
- **Crew view** (`cleaning_page.dart`, `_CrewReportCard`): akce **„Zablokovat
  ohlašovatele"** u hlášení. **Doporučení (UX):** destruktivní/výjimečná akce
  nepatří jako primární tlačítko na kartu — dát do **overflow menu (⋮)** karty,
  vždy s potvrzovacím dialogem (se jménem ohlašovatele), pak volá
  `set_cleaning_reporter_blocked(..., true)` s `report.createdBy` → reload.
  (SQL `created_by` vrací; do modelu `CleaningReport` nutno doplnit — viz ⚠️ výše.)
  U hlášení od už zablokovaného uživatele zobrazit místo akce štítek „zablokován".
- **Uživatelé** (`users_tab` + `user_columns` + `occasion_user_model`):
  zaškrtávátko-sloupec **„Zákaz hlášení úklidu"** (feature-gated `cleaning`),
  vzor sloupce „Úklidová služba". Slouží k přehledu a **odblokování**.
- **Účastník:** stránku Úklid vidí dál (barvy stavů), jen tlačítko „Nahlásit
  problém" je zašedlé se slušnou hláškou — řízeno flagem `is_blocked` z
  `get_cleaning_status` (viz výše), žádný nový helper v `RightsService` není
  potřeba. Tichá 403 zůstává jen jako pojistka.

### Otevřené otázky (B)
- Blokace je **per-occasion** (přes `occasion_users`) — potvrdit, že to stačí
  (spammer bývá vázaný na akci).
- Smí odblokovat i člen čety, nebo jen editor/admin? (návrh: blokovat četa,
  odblokovat editor/admin přes grid; RPC pak musí pro `p_blocked = false`
  vyžadovat editor právo — viz poznámka o symetrii výše)

*(Dřívější otázky „vidí blokovaný stránku?" a „logovat kdo/kdy?" jsou vyřešené
v návrhu výše: vidí, jen nemůže odeslat; audit do `occasion_users.data`.)*

---

## 3. Funkce C — Recenze / hodnocení toalety (samostatný nezávislý task)

Přání (relayed 2026-07-11): **po kliknutí na WC** (v mapovém popupu i na dlaždici /
v dialogu hlášení) nabídnout navíc možnost **přidat recenzi/hodnocení** toalety —
vedle „Nahlásit problém". Řešit jako samostatný task, ne v rámci A/B.

Otevřené otázky (nutno upřesnit před návrhem):
- Co „recenze" znamená: smajlíkové/hvězdičkové **hodnocení** (vzor
  `event_feedback` — happy/neutral/sad), textový **komentář**, nebo obojí?
- Viditelnost: vidí ji jen četa, nebo veřejně (agregovaný průměr)? Anonymní?
- Úložiště: nová tabulka `cleaning_reviews`, nebo rozšíření `cleaning_reports`
  o typ „review"? Zápis přes SECURITY DEFINER RPC (vzor `submit_event_feedback`).
- Vstupní body: mapový popup u WC + dialog na dlaždici na stránce Úklid.
- Limit: 1 recenze na uživatele a WC? Rate limit?

Stav: **zaznamenáno jako samostatný task**; detailní návrh až po upřesnění výše.

## 4. Fáze implementace (návrh pořadí)

1. **DB**: sloupec `is_cleaning_blocked` (tables.sql + live ALTER), kontrola v
   `report_cleaning_issue` (403), `get_cleaning_status` vrací `is_blocked`,
   nová funkce `set_cleaning_reporter_blocked` (+ audit do `occasion_users.data`),
   DB testy (blokovaný → 403; blok/odblok přes RPC; non-crew nesmí blokovat;
   `is_blocked` ve statusu). Historie A žádné nové DB objekty nepotřebuje.
2. **Flutter data**: `DbCleaning.setReporterBlocked(...)`, `createdBy` (uuid)
   do modelu `CleaningReport`, `isCleaningBlocked` v `OccasionUserModel`,
   `isBlocked` v modelu cleaning statusu.
3. **UI historie (A)**: záložky „Aktuální / Historie" v crew view + export `.txt`.
4. **UI blokování (B)**: akce v overflow menu karty hlášení + sloupec v
   Uživatelé + zašedlé tlačítko s hláškou u blokovaného účastníka.
5. **i18n**: nové klíče do `CleaningStrings` / `UserStrings`, cs+en, byte-identická
   kopie do `web_client/public/assets/translations/`.
6. **Nasazení** (dle standardu csmostrava — viz níže): SQL na live **před**
   klientem, bump verze, verzovaný commit jen vlastních souborů, `deploy_direct.sh`,
   žádný git push. Nasadit **společně** i s už hotovým sloupcem „WC (úklid)".

## 5. Závazná pravidla (připomínka)

- Zápisy do `cleaning_reports` / `occasion_users` z klienta **jen přes RPC**.
- Každá SECURITY DEFINER funkce: `SET search_path = public, extensions` + explicitní
  permission check, žádný `EXECUTE` s raw stringy.
- UI chyby přes `ExceptionHandler.guard`, crew/admin prvky gatovat přes
  `RightsService`, lokalizace jen přes `*Strings` (žádné `'literál'.tr()`).
- Verze nikdy nejde dolů; lokální DB test PG17 na `festapp_test` (:55432),
  live SQL přes Management API (ref `lwfpdjxsdmkfyrzqbrlk`, browser User-Agent).

## 6. Mimo rozsah (zatím)
- Automatická expirace/self-service odblokování po čase.
- Statistiky úklidu, SLA, více jednotek čety.
- CSV/Excel export historie (rozhodnut prostý `.txt`).
