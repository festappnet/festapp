# Plán: Přednášející jako core funkce + Poradny jako samostatná featura

**Stav: SCHVÁLENÝ NÁVRH (2026-07-10), nic není implementováno.** Jediný zdroj
pravdy pro tento refaktor. Navazuje na
`docs/archive/plans/2026-07-09_speakers_counseling_plan.md` (feature je hotová a živá
jako 0.19.48+298); tento plán mění **gating a UX**, ne datový model rezervací.

## 1. Zadání (uživatel, 2026-07-10)

- **Přednášející = základní funkce.** Ke *každé* eventě jde přiřadit
  přednášející, bez zapínání jakékoli featury; admin záložka „Přednášející“ je
  vidět vždy. Přiřazování v editaci eventu má vypadat slušně (ne holé chipy).
- **Poradny = samostatná nastavitelná featura** (`counseling`): zapnout/vypnout
  per occasion; teprve její zapnutí zpřístupní poradenské oblasti, generátor
  slotů, CounselingPage a rezervace.
- i18n **jen cs + en** (trvale, žádné další jazyky). Reálná data poradců zadává
  Julie v adminu — nejsou součástí tohoto plánu.

## 2. Závazná rozhodnutí

| # | Otázka | Rozhodnutí |
|---|---|---|
| R1 | Feature kódy | Nový kód **`counseling`** (`CounselingFeature`) s konfigurací `counseling_event_type` (default `counseling`), `registration_start_time`, `max_active_bookings` (default 1, 0 = bez limitu). Kód **`speakers` se ruší** — přednášející nejsou featura. Klíč `counseling_enabled` zaniká (nahrazuje ho `is_enabled` nové featury). |
| R2 | Migrace živých dat | SQL migrace přepíše `occasions.features` všech occasions: z elementu `speakers` vznikne element `counseling` (`is_enabled` = staré `is_enabled AND counseling_enabled`; přenést `counseling_event_type`, `registration_start_time`, `max_active_bookings`), element `speakers` se odstraní. Idempotentní (druhé spuštění nic nezmění). Live 643 má dnes `{speakers: enabled, counseling_enabled:true}` → stane se `{counseling: enabled}`. |
| R3 | SQL gaty | `get_is_speakers_enabled_on_occasion` → nová `get_is_counseling_enabled_on_occasion` (čte kód `counseling`); stará funkce se DROPne v migraci (klient se nasazuje současně, nic jiného ji nevolá). Číst kód `counseling` musí: `sign_user_to_event` (counseling větev — okno/108/109), `get_counseling_availability`, `create_counseling_slots` (`counseling_event_type`). **`search_occasion_content`: speaker větev se od-gatuje** (přednášející jsou vždy vyhledatelní; filtr `is_hidden` zůstává). `get_speakers`/`get_speakers_for_edit` zůstávají negatované (už jsou). |
| R4 | Flutter feature vrstva | `SpeakersFeature` → **`CounselingFeature`** (`counseling_feature.dart`); case v `Feature.fromJson`, `appSupportedFeatures` a `getDefaultFeatures` přechází na `counseling` (default `isEnabled:false`); `FeatureMetadata` titulek „Poradny“. `FeatureService.isCounselingEnabled()` = `isFeatureEnabled('counseling')`; `getSpeakersFeature()` → `getCounselingFeature()`. Konstanty: `FeatureConstants.counseling`, staré `speakers*` klíče smazat/přejmenovat. |
| R5 | Admin gating | Záložka „Přednášející“ (`SpeakersTab`) v `admin_page.dart` **vždy** (bez feature podmínky, vedle Places). Uvnitř tabu: sekce **Oblasti** (katalog témat) a v editoru přednášejícího sekce **Poradenské sloty** (generátor + mazání prázdných) se zobrazí **jen když je `counseling` zapnutý**; jinak se nerenderují (žádný disabled stav). Přepínač „Poradenský rozcestník“ v editaci eventu gatovat na `counseling`. |
| R6 | Event edit UX („slušně“) | Nový widget **`SpeakerPickerField`** (`lib/components/speakers/admin/speaker_picker_field.dart`), vždy viditelný (bez feature gate, bez podmínky `widget.id != null` — pozn. níže): pole ve stylu formuláře zobrazující vybrané přednášející jako **avatar-chipy** (SpeakerAvatar + jméno, × pro odebrání); tap otevře **výběrový dialog** s fulltext filtrem (jméno/role, diakritika-insensitive), checkbox-listem s avatary a tlačítkem „Přidat přednášejícího“ (otevře stávající `SpeakerEditorDialog`, po uložení se nový přednášející rovnou předvybere). Widget je čistý/stavový: data (seznam + výběr) dostává parametrem, žádné RPC uvnitř — RPC volá event_edit_page. **Ověřená fakta (2026-07-10):** (a) `EventEditPage` se v aplikaci otevírá vždy s id existujícího eventu (3 call-sites: event_page:1042, schedule_page:515, my_schedule_page:309; nové eventy vznikají v `AddNewEventDialog`) — přesto uložení nespoléhat na `widget.id`, nýbrž zachytit návrat `DbEvents.updateEvent` (vrací `EventModel` s id i po insertu, db_events.dart:413) a volat `set_event_speakers(updatedEvent.id!, ...)`; gate `widget.id != null` na load i save odstranit (load potřebuje jen occasion). (b) `SpeakerEditorDialog._save` dnes popuje `true` — změnit na pop uloženého `SpeakerModel` (`DbSpeakers.updateSpeaker` ho už vrací); zavírací tlačítko dál popuje `_changed` (bool); `SpeakersTab` (speakers_tab.dart:56) bere jako signál reloadu jakýkoli truthy výsledek (`true` i model). |
| R7 | Uživatelské UI gaty | Sekce „Přednášející“ na event_page: **vždy** (má-li event přiřazené přednášející). Tlačítko „Vybrat oblast a čas“ + `CounselingPage`: gate `isCounselingEnabled()`. Offline vyhledávání: speaker větev **bez gatu**; cache přednášejících v `SynchroService` **bez gatu** (vždy). Filtr slotů z timeline zůstává beze změny (řízený markerem `is_counseling_slot`, ne featurou). Mapping kódu 109 beze změny. |
| R8 | Verzování a deploy | Jeden verzovaný commit `<next-version>; speakers core + counseling feature split` na `prod/csmostrava2026` (styl `<verze>; <popis>`, bump přes `automation/configure_version.js` + `project.conf`). SQL migrace `supabase/migrations/20260710TBD_counseling_feature_split.sql` se aplikuje na live (lwfpdjxsdmkfyrzqbrlk) přes management API **před** pushem klienta. POZOR na necommitnutou rozdělanou práci v pracovním stromu — commitovat jen vlastní soubory podle cesty, nikdy `git add -A`. |

## 3. Přesné dotčené body (zmapováno v kódu 2026-07-10)

**SQL** (`database/functions/`):
- `speakers/get_is_speakers_enabled_on_occasion.sql` → nahradit
  `speakers/get_is_counseling_enabled_on_occasion.sql` (kód `counseling`).
- `events/sign_user_to_event.sql` — counseling větev čte element `speakers` →
  `counseling`; sémantika 108/104/109 beze změny (108 = counseling featura
  chybí/vypnutá).
- `speakers/get_counseling_availability.sql` — gate na novou funkci.
- `speakers/create_counseling_slots.sql` — `counseling_event_type` z elementu
  `counseling`.
- `others/search_occasion_content.sql` — smazat `EXISTS (... code='speakers'
  ...)` podmínku ve speaker větvi (vyhledávání vždy).
- Nová migrace: transformace `occasions.features` (R2) + `DROP FUNCTION
  get_is_speakers_enabled_on_occasion` + `CREATE OR REPLACE` všech výše
  změněných funkcí (plné znění zkopírované ze souborů).

**Flutter** (gate-pointy nalezené grepem `FeatureConstants.speakers|isCounselingEnabled|getSpeakersFeature`):
- `lib/components/features/`: `speakers_feature.dart` → `counseling_feature.dart`
  (třída `CounselingFeature`, form bez přepínače counseling_enabled — featura
  sama je ten přepínač); `feature.dart` case; `feature_service.dart`
  (appSupportedFeatures, getDefaultFeatures, getCounselingFeature,
  isCounselingEnabled); `feature_constants.dart`; `feature_metadata.dart`.
- `lib/components/occasion/admin_page.dart` — SpeakersTab bez podmínky.
- `lib/components/speakers/admin/speakers_tab.dart` — sekce Oblastí gated na
  counseling; `speaker_editor_dialog.dart` — sloty gated na counseling.
- `lib/components/schedule/event_edit_page.dart` — 3 gaty: speaker picker
  (odstranit gate i podmínku `widget.id != null`, nahradit widgetem z R6),
  rozcestník-toggle (gate → counseling; týž gate i na zápis
  `counselingEntry` do `event.data` při save), `setEventSpeakers` volání
  (odstranit gate; volat s id z návratu `DbEvents.updateEvent`, ne
  `widget.id!`).
- `lib/components/speakers/admin/speaker_editor_dialog.dart` — `_save`
  popuje uložený `SpeakerModel` místo `true` (R6b);
  `speakers_tab.dart:56` — reload na truthy výsledek.
- `lib/components/schedule/event_page.dart` — sekce přednášejících bez gatu;
  tlačítko poraden gate `isCounselingEnabled()` (dnes už používá — jen ověřit,
  že čte novou featuru).
- `lib/components/search/db_search.dart` — speaker větev offline indexu bez gatu.
- `lib/data_services/synchro_service.dart` — cache přednášejících bez gatu.
- i18n: nové/změněné klíče jen do `assets/translations/{cs,en}.json` + kopie do
  `web_client/public/assets/translations/` (byte-identické). Namespace
  `FeatureCounseling` pro metadata featury („Poradny“); `FeatureSpeakers.*`
  klíče, které se týkaly featury, odstranit/přesunout; UI klíče `Speakers.*`
  a `Counseling.*` zůstávají. Pro SpeakerPickerField nové `Speakers.*` klíče
  (placeholder pole, titulek dialogu, hint fulltextu, „Přidat přednášejícího“,
  prázdný stav) — přes `SpeakersStrings`, žádné `.tr()` literály v UI.

## 4. Testy (kompletní, součást stejného commitu)

**DB — `database/tests/speakers_test.sql`** (rozšířit/upravit stávajících 8 bloků):
1. Fixtura: occasion s `[{"code":"counseling","is_enabled":true,...}]`
   (už žádný `speakers` element).
2. Stávající bloky 1–5 (guardy, upsert, cross-occasion, generátor, mazání
   prázdných) — beze změn sémantiky, jen fixtura.
3. Blok 6 (matcher) + blok 7 (sign_user 108/104/109): gate scénáře přepsat na
   `counseling` element — (a) element chybí → 108; (b) `is_enabled:false` →
   108; (c) `registration_start_time` v budoucnu → 104; (d) limit → 109;
   (e) starý `speakers` element (enabled) BEZ `counseling` elementu → 108
   (ověření, že starý kód už negatuje).
4. Blok 8 (vyhledávání): přednášející vyhledatelný **i bez jakékoli featury**
   (odstraněný gate); skrytý přednášející nevyhledatelný; sloty nadále mimo
   výsledky.
5. **Nový blok 9 (migrace features)**: vlož occasion s
   `{"code":"speakers","is_enabled":true,"counseling_enabled":false,...}`,
   zavolej transformační logiku migrace (extrahovanou jako idempotentní SQL v
   migraci — v testu spustit tentýž UPDATE), ověř: vznikl `counseling` s
   `is_enabled:false`, `speakers` element zmizel, ostatní featury nedotčené;
   druhé spuštění nic nezmění. Varianty: `counseling_enabled:true` →
   `is_enabled:true`; occasion bez `speakers` elementu → beze změny.
6. Spouštět: `DATABASE_URL='postgresql://postgres@localhost:55432/festapp_test'
   node web_client/scripts/run_db_tests.js database/tests/speakers_test.sql`
   (lokální PG17; když neběží, `scratchpad/pgtest/bootstrap.sh` — pozn.:
   bootstrap musí nově aplikovat i recovery soubor a obě speakers migrace).
   Celá DB sada musí zůstat na baseline (aktuálně 51/0 lokálně).

**Flutter unit — `test/components/speakers/speakers_mapping_test.dart`**:
- `SpeakersFeature` skupinu nahradit `CounselingFeature`: defaulty
  (`isEnabled:false`, type `counseling`, limit 1), `Feature.fromJson` s kódem
  `counseling` vrací `CounselingFeature`, toJson roundtrip, limit 0.
- Nový test: `Feature.fromJson` s legacy kódem `speakers` vrací `SimpleFeature`
  (tj. neexistuje speciální třída — ochrana proti regresi).

**Flutter unit — nový `test/components/features/counseling_gating_test.dart`**:
- `FeatureService.isCounselingEnabled(features: [...])` přes injektované
  seznamy: counseling enabled/disabled/chybí; legacy `speakers` element sám o
  sobě counseling NEzapíná.

**Flutter widget — `test/components/speakers/`**:
- stávající `counseling_widgets_test.dart` (TopicPicker, SlotChip) beze změny —
  ověřit, že projde.
- **nový `speaker_picker_field_test.dart`**: (a) render vybraných jako
  avatar-chipy se jmény; (b) odebrání chipu zavolá onChanged bez id;
  (c) dialog: fulltext filtr zúží seznam (diakritika-insensitive na jméno i
  roli); (d) potvrzení dialogu vrátí vybraná id; (e) prázdný stav ukazuje
  placeholder text; (f) „Přidat přednášejícího“ zavolá injektovaný
  `onCreateSpeaker` callback a vrácený nový přednášející se objeví v seznamu
  předvybraný (callback injektovaný — otevření SpeakerEditorDialog dělá až
  event_edit_page). Widget navrhnout testovatelně (čistý stavový widget,
  data injektovaná parametrem, žádné RPC uvnitř — RPC volá event_edit_page).
- Ruční ověření (není widget-testovatelné bez supabase mocku): uložení eventu
  volá `set_event_speakers` s id z návratu `updateEvent`; po znovuotevření
  editace jsou přednášející předvybraní.

**Statika + celek**: `fvm dart analyze` = 0 errorů v celém projektu;
`fvm flutter test` celá sada zelená; `./automation/test_all.sh` s lokální DB
prochází (známé environmentální výjimky: chybějící FIO creds; lokální PG nemá
pg_cron/http).

**Ověření na live po deployi** (read-only přes management API + curl):
- `occasions.features` id 643: obsahuje `counseling`, neobsahuje `speakers`.
- `get_counseling_availability` gate: vypnout/zapnout test nedělat na live —
  ověřit jen přes `get_is_counseling_enabled_on_occasion(643)`.
- `search_occasion_content(643, '<jméno testovacího speakera>')` — pokud Julie
  už zadala data; jinak jen `festapp-version.json` == nová verze a smoke
  `get_speakers(643)` == 200.

## 5. Postup (fáze = pořadí prací, jeden výsledný commit)

1. **SQL**: úprava funkcí (R3) + migrace (R2) + testy (§4 DB) → lokálně zelené.
2. **Flutter feature vrstva** (R4) + gaty (R5, R7) + unit testy.
3. **SpeakerPickerField** (R6) + integrace do event_edit_page + widget testy.
4. **i18n** cs+en + sync web_client kopií; analyze + celá Flutter sada;
   test_all.
5. **Nasazení**: aplikovat migraci na live (management API, curl; ověřit
   transformaci features), pak version bump + verzovaný commit + push
   `prod/csmostrava2026` (fast-forward; force jen s `--force-with-lease` a jen
   pokud nezbytné) → CI deploy → ověření manifestu a smoke testy (§4).

## 6. Mimo rozsah

- Speaker picker v `AddNewEventDialog` (hromadné zakládání eventů) —
  přednášející se přiřazují až v editaci eventu.
- Per-event pořadí přednášejících (`event_speakers` nemá sloupec `order`;
  pořadí řídí globální `speakers."order"` — vědomá limitace, případná
  aditivní změna později).
- Reálná data poradců/oblastí (zadává Julie v adminu).
- Překlady mimo cs/en (trvale se nedělají).
- Jakékoli změny rezervační logiky slotů (kódy 100–109 beze změny).
