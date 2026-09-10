# Plán: Místa + úklid — architektonický úklid (oprava přesunu místa, konsolidace)

**Stav: NÁVRH PŘIPRAVENÝ K IMPLEMENTACI (2026-07-11).** Vychází z hloubkové
architektonické revize vrstvy míst (`lib/components/map/`) a úklidové služby
(`lib/components/cleaning/`). Všechna tvrzení o kódu (soubory, řádky, RLS) byla
2026-07-11 ověřena proti repozitáři na větvi `prod/csmostrava2026`. Rozhodnutí
označená ✅ jsou závazná — **neptej se na ně, drž se jich**.

> **Prerekvizita:** Na větvi je rozpracovaná funkce „ztlumení notifikací úklidu"
> (necommitnuté změny vč. `set_cleaning_notifications_muted.sql`). Tento plán se
> implementuje **až po jejím dokončení a commitu** — nemíchej ji do svých změn.
> Před začátkem ověř `git status`; cizí rozpracované soubory necommituj.

## 0. Výchozí stav (zjištění revize)

- **Bug (hlavní důvod tohoto plánu):** `DbPlaces.saveLocation`
  (`lib/components/map/db_places.dart:94-105`) a mapový popup
  (`lib/components/map/map_description_popup.dart:62-65`) dovolují
  **group-adminovi** přesunout místo vlastní skupiny, ale RLS UPDATE politika na
  `public.places` (`database/policies/02_policies.sql:522-527`) pouští **jen
  editory** (`get_is_editor_on_occasion`). Přímý UPDATE od group-admina, který
  není editor, tiše zasáhne **0 řádků** a vrátí 200 — uživatel si myslí, že
  místo přesunul, ale nepřesunul. (Stejná třída chyby jako oprava „create
  ubytování" z 2026-07-10.)
- Všechny ostatní zápisy míst jdou přímým PostgREST přes RLS (editor-only) —
  to je v pořádku a **neměníme to**; opravujeme jen `saveLocation`, kde je
  potřeba složitější permission check (editor NEBO group-admin vlastního místa).
- DDL tabulky `place_types` žije **jen** v recovery skriptu
  (`database/recovery/2026-06_csmostrava_lost_backend.sql:84-107`), ne ve
  zdrojích `database/tables/tables.sql` + `database/policies/` — fragmentovaný
  zdroj pravdy.
- `PlaceModel` (`lib/components/map/place_model.dart`): `latLng` je `dynamic`,
  `getLat()/getLng()` (řádky 26-27) spadnou na null; `MapPlaceModel.fromPlaceModel`
  (`map_place_model.dart:25`) force-unwrapuje `title!` a volá `getLat()` — místo
  bez souřadnic/titulku shodí mapu.
- `cleaning_page.dart` má **943 řádků** a obsahuje 8 privátních widget tříd
  (`_SummaryBanner`, `_Legend`, `_CleaningTile`, `_CrewReportCard`,
  `_ReportHint`, `_BlockedBanner`, `_HistoryRow`, `_CleaningData`), zatímco
  dialog už je ve `widgets/` — nekonzistentní.
- `report_cleaning_issue.sql`: notifikace používá `COALESCE(v_organization, 1)`
  (řádek ~143) — magická konstanta; organizace je dostupná z `occasions`.
- Stránka Úklid není gatovaná feature flagem — deep-link `/:link/cleaning`
  funguje i s vypnutou featurou (SQL statusu flag nekontroluje). Neškodné, ale
  nekonzistentní UX.
- Seznam typů problémů (`paper|hygiene|contamination`) je na 4 místech
  (CHECK constraint v `tables.sql`, `report_cleaning_issue.sql`,
  `cleaning_status.dart`, `cleaning_report_dialog.dart`) a mapa závažnosti na
  2 místech (`get_cleaning_status.sql:36-47`, pořadí enumu v
  `cleaning_status.dart:5`) — bez křížových komentářů „keep in sync".

Group-admin je v DB modelován takto (ověřeno): `public.user_groups`
(`tables.sql:794`) je junction `("user" uuid, "group" bigint, is_admin bool)`
→ `public.user_group_info` (`tables.sql:604`) má FK `place` na `places.id`.
Tzn. „group-admin místa X" = `EXISTS (SELECT 1 FROM user_groups ug JOIN
user_group_info ugi ON ugi.id = ug."group" WHERE ug."user" = auth.uid() AND
ug.is_admin AND ugi.place = X)`.

---

## Fáze 1 — Oprava přesunu místa: RPC `save_place_location` (DB)

### Rozhodnutí
- ✅ Řešit **SECURITY DEFINER RPC**, ne rozšířením RLS politiky (přesný vzor
  úklidových funkcí; drží se dokumentovaného pravidla „složité zápisy přes SQL
  funkce", viz `docs/architecture/ai_context.md`).
- ✅ Práva: **editor na occasion místa NEBO group-admin skupiny, jejíž
  `user_group_info.place` je právě toto místo.** Nic víc.

### Kroky
1. Nový soubor **`database/functions/places/save_place_location.sql`**
   (nový adresář `places/`). Vzor struktury souboru = kterákoli funkce
   z `database/functions/cleaning/` (hlavička, `SECURITY DEFINER`,
   `SET search_path = public, extensions`, envelope, GRANT na konci —
   zkopíruj konvence 1:1 včetně stylu komentářů).
2. Signatura: `save_place_location(p_place_id bigint, p_lat double precision,
   p_lng double precision) RETURNS jsonb`, `VOLATILE`.
3. Logika (v tomto pořadí):
   - `auth.uid() IS NULL` → `{code:401}`.
   - Načti `occasion` místa; místo neexistuje → `{code:404}`.
   - Permission check: `get_is_editor_on_occasion(v_occasion)` **NEBO**
     group-admin EXISTS dotaz ze sekce 0 → jinak `{code:403}`.
   - `UPDATE public.places SET coordinates = jsonb_build_object('latLng',
     jsonb_build_object('lat', p_lat, 'lng', p_lng)) WHERE id = p_place_id;`
   - Vrať `{code:200, data: {id: p_place_id}}`.
4. Klient: `DbPlaces.saveLocation` (`db_places.dart:94`) přepsat na
   `_supabase.rpc('save_place_location', params: {...})` + kontrolu envelope
   (vzor `DbCleaning._ensureOk` v `lib/components/cleaning/db_cleaning.dart:106` —
   ale nezaváděj závislost map→cleaning; udělej malý lokální check nebo vyhoď
   `Exception(message)` při `code != 200`). **Stávající klientský rights-check
   (řádky 95-99) ponech** — je to rychlá UX pojistka; zdroj pravdy je RPC.
5. Volající `saveLocation` nech beze změn (chyby už procházejí přes
   `ExceptionHandler.guard` na call-site v mapě — ověř grepem
   `saveLocation` a případně guard doplň).
6. **DB test**: nový `database/tests/places/save_place_location_test.sql`
   (vzor fixture + impersonace přes `request.jwt.claim.sub` =
   `database/tests/cleaning/cleaning_test.sql`). Scénáře:
   a) editor přesune libovolné místo occasion → 200 + souřadnice se změnily;
   b) group-admin přesune místo **své** skupiny → 200 + souřadnice se změnily;
   c) group-admin zkusí **cizí** místo (jiné skupiny / bez skupiny) → 403 a
      souřadnice beze změny;
   d) řadový přihlášený uživatel → 403;
   e) nepřihlášený → 401; neexistující místo → 404.
7. Nasazení SQL na live **před** nasazením klienta (viz Fáze 7).

---

## Fáze 2 — `place_types`: DDL do zdrojů (jen git, bez zásahu do live)

- ✅ Live DB se **nemění** (tabulka tam existuje) — jde o srovnání zdroje pravdy.
1. Z `database/recovery/2026-06_csmostrava_lost_backend.sql:84-107` přenes:
   - `CREATE TABLE public.place_types` (+ unique constraint `(occasion, code)`
     a partial unique index `place_types_one_default_per_occasion`) do
     `database/tables/tables.sql` — styl `create table if not exists`, zařaď
     abecedně/logicky k okolním tabulkám (poblíž `places`).
   - `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` do
     `database/policies/01_enable_security.sql` (vzor okolních řádků).
   - Politiky (public SELECT, editor INSERT/UPDATE/DELETE) do
     `database/policies/02_policies.sql` — přesně ve stylu bloku
     `public.places` (řádky 519-551) vč. `DROP POLICY IF EXISTS`.
2. Obsah musí být **významově identický** s recovery skriptem (názvy politik,
   podmínky) — nic nevylepšuj.
3. Ověření: `./automation/test_all.sh` musí projít (testovací DB se staví ze
   zdrojů; pokud runner tabulku už vytvářel jinou cestou, oprav kolizi ve
   prospěch `tables.sql`).

---

## Fáze 3 — Bezpečné souřadnice v `PlaceModel` (defenzivní minimum)

- ✅ **Nepřepisujeme serializaci ani nerušíme `MapPlaceModel`** (viz Mimo
  rozsah) — jen odstraňujeme pády na null.
1. `place_model.dart`: přidej getter
   `bool get hasCoordinates => latLng != null && latLng?["lat"] != null && latLng?["lng"] != null;`
   a nad pole `latLng` doc-komentář vysvětlující dvě podoby dat:
   `fromJson` čte `coordinates["latLng"]`, `fromPlutoJson` čte hodnotu buňky
   napřímo, `toJson` obaluje zpět do `{"latLng": ...}` — **záměrně neměnit bez
   úpravy obou stran**.
2. `map_place_model.dart` (`fromPlaceModel`): nahoře `assert`/guard není
   potřeba — místo toho **filtruj na vstupu**: najdi všechna volání
   `MapPlaceModel.fromPlaceModel` (grep) a před nimi přidej filtr
   `.where((p) => p.hasCoordinates && p.title != null)`. Hlavní místo je
   `map_page.dart` (`loadData`, offline i online větev). Tichý skip je žádoucí
   (místo bez souřadnic na mapu nepatří).
3. Ověření: `fvm flutter analyze` bez nových warningů; mapa na localhostu
   zobrazí stejná místa jako předtím.

---

## Fáze 4 — Rozdělení `cleaning_page.dart` (mechanický refactor)

- ✅ **Čistý přesun kódu, nula změn chování.** Žádné přejmenování parametrů,
  žádné „vylepšení" logiky.
1. Privátní třídy přesuň do vlastních souborů a zveřejni (prefix `Cleaning`
  kde chybí):

  | Třída dnes | Nový soubor | Nové jméno |
  |---|---|---|
  | `_SummaryBanner` | `widgets/cleaning_summary_banner.dart` | `CleaningSummaryBanner` |
  | `_Legend` | `widgets/cleaning_legend.dart` | `CleaningLegend` |
  | `_CleaningTile` | `widgets/cleaning_tile.dart` | `CleaningTile` |
  | `_CrewReportCard` | `widgets/cleaning_crew_report_card.dart` | `CleaningCrewReportCard` |
  | `_ReportHint` | `widgets/cleaning_report_hint.dart` | `CleaningReportHint` |
  | `_BlockedBanner` | `widgets/cleaning_blocked_banner.dart` | `CleaningBlockedBanner` |
  | `_HistoryRow` | `widgets/cleaning_history_row.dart` | `CleaningHistoryRow` |
  | `_CleaningData` | `models/cleaning_data.dart` | `CleaningData` |

2. Callbacky a data předávej konstruktorem tak, jak už dnes privátní třídy
   dostávají — jen se změní viditelnost. Importy dořeš; `cleaning_page.dart`
   by měl klesnout zhruba na 400-500 řádků čisté page logiky.
3. Ověření: `fvm flutter analyze` + ruční projití stránky Úklid na localhostu
   (účastník i četa: dlaždice, hlášení, historie, export, blokování, mute).

---

## Fáze 5 — Drobnosti v SQL úklidu + gate stránky

1. **`report_cleaning_issue.sql`**: nahraď `COALESCE(v_organization, 1)` čtením
   `organization` z řádku `occasions` (select už tam occasion načítá — přidej
   sloupec do stejného SELECTu). Fallback na `1` smaž. České labely typů
   problémů (řádky ~94-98) **ponech** (akce je česká; lokalizace push zpráv je
   mimo rozsah) — jen k nim přidej komentář, že jsou vědomě cs-only.
2. **Feature gate v UI**: v `cleaning_page.dart` na začátku `build` (nebo
   `initState`) zkontroluj `FeatureService.isFeatureEnabled(FeatureConstants.cleaning)`;
   když je featura vypnutá, vykresli prázdný stav s hláškou (nový klíč
   `CleaningStrings`, viz Fáze 6) místo obsahu. SQL funkce se **nemění**;
   do hlavičkových komentářů `get_cleaning_status.sql`,
   `get_cleaning_reports.sql` a `resolve_cleaning_place.sql` doplň větu, že
   feature flag vědomě nekontrolují (čtení stavů a dořešení úklidu má fungovat
   i po vypnutí featury; nová hlášení blokuje check v `report_cleaning_issue`).
3. **„Keep in sync" komentáře**: ke každému výskytu seznamu typů problémů
   (CHECK v `tables.sql` u `cleaning_reports`, `report_cleaning_issue.sql`,
   `cleaning_status.dart`, `cleaning_report_dialog.dart`) a mapy závažnosti
   (`get_cleaning_status.sql`, `cleaning_status.dart`) přidej jednořádkový
   komentář odkazující na ostatní místa. Žádná změna logiky.
4. Pozn.: změna z bodu 1 vyžaduje nahrání `report_cleaning_issue.sql` na live
   (Fáze 7). DB testy úklidu musí dál procházet beze změn
   (`node web_client/scripts/run_db_tests.js database/tests/cleaning/cleaning_test.sql`).

---

## Fáze 6 — i18n

- Nový klíč do `CleaningStrings` (cs+en): hláška „Úklidová služba není na této
  akci zapnutá." / „Cleaning service is not enabled for this event." (přesné
  znění dle stylu okolních klíčů).
- Případná chybová hláška pro selhání přesunu místa: **nejdřív** zkontroluj
  `MapStrings` / existující generické chybové klíče a použij existující; nový
  klíč zaváděj jen pokud žádný nesedí.
- Pravidla: klíče jen přes `*Strings` třídy (žádné `'literál'.tr()`), doplnit
  do `assets/translations/cs.json` + `en.json` a **byte-identickou kopii** do
  `web_client/public/assets/translations/`. Ostatní jazyky (de/pl/sk/uk)
  nedoplňuj — jsou záměrně částečné.

---

## Fáze 7 — Testy, revize, nasazení

1. `./automation/test_all.sh` — vše zelené (pozor: 2 dlouhodobě failující DB
   testy jsou známý baseline mimo úklid/místa; nové failury nesmí přibýt).
2. Lokální revize: `fvm flutter run -d web-server --web-port 8080` (nikdy
   `-d chrome`), uživatel si projde mapu (přesun místa jako editor), stránku
   Úklid a grid Míst na `localhost:8080`. **Počkej na odsouhlasení, pak teprve
   nasazuj.**
3. Nasazení (standard csmostrava):
   - SQL na live **před** klientem přes Management API (ref
     `lwfpdjxsdmkfyrzqbrlk`): `save_place_location.sql` (nová) +
     `report_cleaning_issue.sql` (změněná). Nic jiného se na live nemění.
   - Bump `VERSION` (nikdy dolů), commit **jen vlastních souborů** s anglickou
     zprávou, `deploy_direct.sh`, **žádný `git push`**.

## Závazná pravidla (připomínka)

- Zápisy s netriviálním permission checkem z klienta **jen přes RPC**; každá
  SECURITY DEFINER funkce má `SET search_path = public, extensions` +
  explicitní kontrolu práv + envelope `{code,message,data}` + GRANT dle vzoru.
- UI chyby přes `ExceptionHandler.guard`; gate přes `RightsService` /
  `FeatureService`; lokalizace jen přes `*Strings` (cs+en).
- Vždy `fvm` prefix; localhost-first; stavět jen to, co říká plán — žádná
  vylepšení navíc.

## Mimo rozsah (vědomě NEDĚLAT)

- Sjednocení tří place modelů (`PlaceModel`/`MapPlaceModel`/`ActivityPlaceModel`)
  a typovaný `LatLng` v `PlaceModel` — velký zásah, samostatný task.
- Refactor `map_page.dart` (1739 řádků) a rozdělení `DbPlaces` (místa+trasy+ikony).
- Lokalizace push notifikací (české labely v SQL zůstávají).
- Atribuce duplicitních hlášení (`data.extra_notes` bez `created_by`).
- Per-occasion rate limit hlášení; kontrola členství na occasion v
  `report_cleaning_issue`.
- Převod ostatních zápisů míst (grid CRUD) na RPC — RLS editor-only stačí.
