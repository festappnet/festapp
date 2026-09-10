# Plán: Přednášející & Poradny (speakers + counseling)

**Stav: NÁVRH po grilování 2026-07-09 — schválená rozhodnutí zapracována,
nic není implementováno.** Jediný zdroj pravdy pro tuto feature; dřívější
samostatný SQL draft byl sloučen sem (sekce 9).

## 1. Zadání (z e-mailů Julie Adltové / P. Romana Kubína)

- V programu bude položka „Poradenství, přímluvná modlitba a svátost smíření“.
  Po rozkliku: úvodní text → volba **právě jedné** oblasti (~20 kategorií:
  „vztahy v rodině“, „úzkosti, deprese“, „duchovní rozhovor“, …) → nabídka
  odpovídajících poradců **a jejich volných časů** → přihlášení.
- Poradci si volí oblasti, ve kterých jsou kompetentní; podle toho se filtruje.
- Poradci mají fotku/avatar — v seznamu jako kolečko, v detailu „klasicky
  v textu“, ne jako úvodní banner (Juliin dotaz č. 1).
- Obecněji: možnost vytvořit **přednášející** a připojit je k programovým
  bodům (přednáška zobrazí přednášející s fotkou a medailonkem).

## 2. Rozhodnutí z grilování (2026-07-09, schváleno)

| # | Otázka | Rozhodnutí |
|---|---|---|
| R1 | Mechanismus rezervací | Slot = event, booking přes existující `sign_user_to_event`; do něj přibude **counseling větev** s vlastním registračním oknem ze speakers feature (workshops okno 104/108 se na sloty nepoužije). Kolize 107 s programem zůstávají — žádoucí. |
| R2 | Entita osoby | **Samostatná tabulka `speakers`**, bez FK na `user_info` — data zadává organizátor z tabulky (jako HK); poradce nepotřebuje účet. Vazba na účet jde případně dodat sloupcem později. |
| R3 | Soukromí tématu | Zvolená oblast se **nikam neukládá** — jen filtruje nabídku. V DB zbyde běžný `event_users` řádek. Poradce se téma dozví až osobně. |
| R4 | Limit rezervací | **Konfigurovatelný** `max_active_bookings` ve speakers feature (default 1, 0 = bez limitu) — počet *budoucích* counseling rezervací uživatele; překročení = nový kód **109** + lokalizovaná hláška. |
| R5 | Vstup + úvodní text | Přepínač „Poradenský rozcestník“ v edit stránce eventu (`data.counseling_entry=true`, vzor `feedback_enabled`). **Úvod = popis toho eventu** (stávající HTML editor); detail eventu pod popisem zobrazí tlačítko „Vybrat oblast a čas“ → CounselingPage. Žádné nové úložiště úvodu. |
| R6 | Viditelnost rezervace | **Obojí**: v „Můj program“ i na CounselingPage (sekce „Tvoje rezervace“ + zrušení). |
| R7 | Přihlášení | Rezervace **vyžaduje účet** (sign_user_to_event je user-based). Nepřihlášený vidí nabídku + výzvu k přihlášení. Osobní příchod na místo zůstává mimo appku. |
| R8 | Sloty NEJSOU skryté | **Slot = normální event** (`is_hidden=false`), typ = `counseling_event_type` ze speakers feature + marker `data.is_counseling_slot=true`. Z hlavní timeline a vyhledávání se **filtruje podle typu/markeru** (viz 2.1). „Můj program“ pak funguje bez SQL zásahu — rezervovaný slot se v něm objeví sám. |

### 2.1 Důsledky R8 (slot jako normální event)

Sloty nesmí zaplavit ostatní pohledy (20 poradců × 12 slotů × 5 dní ≈ stovky
mini-eventů). Filtrační místa:

1. **Hlavní timeline/rozvrh (Flutter)** — při sestavování programu z
   `get_events` přeskočit eventy s `type == counseling_event_type`
   (resp. `data.is_counseling_slot`). Jedno místo v klientu.
2. **GlobalSearch** — `search_occasion_content` (SQL) i offline index
   (`SearchService.rebuildOfflineIndex`) vynechají eventy s
   `data.is_counseling_slot = true`.
3. Ostatní (event page, feedback, admin datagrid, obsazenost) fungují beze
   změn — slot je běžný event; v admin gridu je vidět normálně (žádoucí).

Ověřeno v kódu při grilování:
- `sign_user_to_event.sql:55–76` aplikuje workshops okno globálně → nutná
  counseling větev (R1).
- `get_my_events_and_activities.sql` filtruje `is_hidden=FALSE` → s R8 už
  žádný zásah nepotřebuje (sloty nejsou skryté).

## 3. Architektura v kostce

- **`speakers`** — osoba (přednášející i poradce; poradce = speaker s tématy),
  avatar jako URL (image-worker, vzor `header_image`).
- **`speaker_topics`** + **`speaker_topic_links`** — katalog oblastí per
  occasion + kompetence M:N.
- **`event_speakers`** — M:N speakers ↔ events; přednáška zobrazí své
  přednášející, poradenský slot je navázán na právě jednoho poradce.
- **Slot** = běžný event (`type=counseling_event_type`,
  `data.is_counseling_slot=true`, `max_participants` default 1), generovaný
  hromadně; booking/odhlášení = stávající `sign_user_to_event` /
  `sign_user_out_of_event`; EventFeedback a admin přehled účastníků fungují
  automaticky.
- **Feature flag** `speakers` v `occasions.features` s konfigurací:
  `counseling_enabled`, `counseling_event_type` (default `counseling`),
  `registration_start_time` (vlastní okno poraden),
  `max_active_bookings` (default 1, 0 = bez limitu).

## 4. Datový model (4 nové tabulky)

| Tabulka | Klíčové sloupce |
|---|---|
| `speakers` | `occasion` FK CASCADE, `title` (jméno), `subtitle` (role/tituly), `description` (HTML bio), `image` (avatar URL), `order`, `is_hidden`, `data` jsonb, `created_at`/`updated_at` |
| `speaker_topics` | `occasion` FK CASCADE, `code` (volitelný, unique per occasion), `title`, `order`, `is_hidden` |
| `speaker_topic_links` | PK (`speaker`,`topic`), obě FK CASCADE |
| `event_speakers` | PK (`event`,`speaker`), obě FK CASCADE |

RLS: SELECT pro všechny; **žádné write policies** — zápisy jen přes SECURITY
DEFINER RPC (vzor `event_feedback`; obchází past s RLS na `unit_users`, viz
icons). `moddatetime` triggery na `updated_at`. Plné DDL v sekci 9.1.

## 5. SQL funkce

Všechny `public` schema, `SECURITY DEFINER`, `SET search_path = public,
extensions`, obálka `{code, data}`, guardy `get_is_editor_on_occasion`
(zápis) / `get_is_editor_view_on_occasion` (admin čtení).

| RPC | Kdo | Co |
|---|---|---|
| `get_speakers(p_occasion, p_include_description)` | veřejné | jeden payload jako `get_events`: viditelní speakers + topics + obě vazby. Cacheovatelné v `OfflineDataService`. |
| `get_speakers_for_edit(p_occasion)` | editor-view | vše vč. skrytých + per-speaker témata a napojené eventy s obsazeností |
| `update_speaker(p_occasion, p_speaker jsonb)` | editor | upsert; klíč `topics:[ids]` atomicky přepíše kompetence (témata cizí occasion se ignorují); update ověřuje `occasion` řádku |
| `delete_speaker(p_speaker_id)` | editor | smaže osobu, vazby CASCADE; slot-eventy zůstávají |
| `update_speaker_topic` / `delete_speaker_topic` | editor | CRUD katalogu oblastí |
| `set_event_speakers(p_event, p_speakers bigint[])` | editor | nahradí množinu přednášejících eventu; validace occasion |
| `create_counseling_slots(p_speaker, p_start, p_end, p_slot_minutes, p_place, p_capacity, p_title, p_break_minutes)` | editor | hromadný generátor slotů („út 14:00–18:00 po 20 min, pauza 5“); typ bere z feature configu, nastaví `data.is_counseling_slot` |
| `delete_empty_counseling_slots(p_speaker, p_from)` | editor | smaže **neobsazené** sloty poradce (regenerace mřížky), obsazené nechá |
| `get_counseling_availability(p_occasion, p_topic)` | veřejné (gate na feature) | **matcher**: poradci kompetentní ve zvoleném tématu + jejich budoucí sloty s `occupied`/`max_participants`/`isSignedIn` |
| `get_is_speakers_enabled_on_occasion(p_occasion)` | helper | čte feature flag |
| **úprava** `sign_user_to_event` | — | counseling větev (R1+R4), viz 5.1 |
| **úprava** `search_occasion_content` | — | vynechat `data.is_counseling_slot` eventy (2.1) |

### 5.1 Counseling větev v `sign_user_to_event`

Za detekci `(e.data->>'is_counseling_slot')::boolean IS TRUE`:

1. **Okno**: přeskočit workshops gate (104/108); místo něj číst feature
   `speakers` → `registration_start_time` (není-li, sloty jsou otevřené) a
   `is_enabled` (jinak 108-ekvivalent).
2. **Limit**: `max_active_bookings` > 0 a uživatel má už ≥ limit budoucích
   (`end_time > now`) counseling rezervací na occasion → **kód 109**.
3. Zbytek beze změny: kapacita 101, kolize 107, duplicita 103, členství.

Chybové kódy: 200/400/403/404 v obálce nových RPC; booking vrací stávající
kódy 100–108 + nový 109 (lokalizovaná hláška v Dartu).

## 6. Flutter klient

### 6.1 Feature registrace
`FeatureConstants.speakers = 'speakers'`; `SpeakersFeature extends Feature`
(konfigurace dle sekce 3); case v `Feature.fromJson`; registrace
v `FeatureService.appSupportedFeatures`; `buildFormField` pro nastavení
occasion (vzor `WorkshopsFeature` pro okno, `ScheduleFeature.eventTypes`
pro editor kategorií).

### 6.2 Modely a data (`lib/components/speakers/`)
`SpeakerModel`, `SpeakerTopicModel` (vzor `PlaceModel`; `fromJson`/`toJson`),
`DbSpeakers` (vzor `DbEventFeedback` vč. `_ensureOk` + typované výjimky),
cache payloadu `get_speakers` v `OfflineDataService`.

### 6.3 UI — účastník
- **Detail přednášky** (`event_page.dart`): sekce „Přednášející“ — avatar
  kolečko + jméno + subtitle; rozklik na medailonek s fotkou **v textu**
  (Juliin dotaz č. 1).
- **Hlavní timeline**: filtr slotů dle 2.1.
- **CounselingPage** (nová route): 1) „Tvoje rezervace“ (je-li) + zrušení,
  2) výběr **jedné** oblasti (radio list), 3) karty poradců + chips časů
  (obsazené šedě, `occupied/max`), 4) tap → `DbEvents.signInToEvent`
  (stávající mapping kódů + nový 109). Nepřihlášený: nabídka viditelná,
  místo bookingu výzva k přihlášení (R7).
- **Vstup**: event s `data.counseling_entry=true` zobrazí pod popisem
  tlačítko „Vybrat oblast a čas“ (R5). Rezervovaný slot se objeví v „Můj
  program“ automaticky (R8); titulek slotu = „Poradenství – Jméno“.

### 6.4 UI — admin
- **Správa přednášejících** v occasion settings (vzor `IconsManagementWidget`):
  seznam; dialog s `ImageArea` (komprese `ImageCompressionHelper` ~400 px,
  upload `DbImages.uploadImage` + `add_image_record`), HTML bio, multi-select
  témat, order, skrýt.
- **Katalog oblastí**: add/edit/remove editor (vzor `EventType` formulář).
- **Generátor slotů** v detailu poradce: od–do, délka, pauza, kapacita,
  místo → `create_counseling_slots`; tlačítko „Smazat prázdné sloty“.
- **Event edit page**: přepínač „Poradenský rozcestník“ (R5) + multi-select
  přednášejících → `set_event_speakers`.

### 6.5 i18n
`speakers_strings.dart` (namespaced Strings-class vzor) + klíče do
`assets/translations/{cs,en}.json`; de/pl/sk/uk záměrně částečné.
Seed 20 oblastí z Juliina e-mailu pro csmostrava = data (SQL seed /
admin import), ne překlady.

## 7. Testy

- **DB** (`database/tests/speakers_test.sql`, auto-rollback): editor guardy
  (403), upsert s tématy, cross-occasion ochrana (404/400), generátor
  (počty/pauzy/hranice), `delete_empty_counseling_slots` nechává obsazené,
  matcher (jen budoucí sloty, jen viditelní poradci, `isSignedIn`),
  counseling větev sign-upu: vlastní okno (workshops gate se nepoužije),
  limit 109, kolize 107 slot×slot i slot×přednáška.
- **Flutter**: widget testy topic-pickeru (single-select) a slot chips
  (volný/obsazený/můj); `DbSpeakers` mapování payloadu; filtr timeline.

## 8. Postup nasazení (po schválení plánu)

1. SQL: DDL do `database/tables/tables.sql`, funkce po jedné do
   `database/functions/speakers/*.sql` (+ úprava `events/sign_user_to_event.sql`,
   `search_occasion_content`), migrace v `supabase/migrations/`; DB testy;
   aplikace na live přes management API.
2. Flutter modely + `DbSpeakers` + feature registrace.
3. Admin UI (osoby, témata, sloty; event edit).
4. Uživatelské UI (event page sekce, CounselingPage, timeline filtr).
5. i18n + seed oblastí; `fvm dart analyze`; `./automation/test_all.sh`; bump verze.

## 9. Příloha: návrh SQL (referenční znění)

Rozhodnutí R1/R4/R8 zapracována (sloty nescryté, vlastní okno, limit 109).
Při implementaci se rozpadne do repo konvence (soubor na funkci).

### 9.1 DDL + RLS

```sql
CREATE TABLE IF NOT EXISTS public.speakers (
  id          bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  occasion    bigint NOT NULL REFERENCES public.occasions(id) ON DELETE CASCADE,
  title       text NOT NULL,          -- jméno
  subtitle    text,                   -- role/tituly ("psycholog", "P. Mgr. ...")
  description text,                   -- HTML bio
  image       text,                   -- avatar URL (img.festapp.net)
  "order"     bigint NOT NULL DEFAULT 0,
  is_hidden   boolean NOT NULL DEFAULT false,
  data        jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT speakers_title_length_check CHECK (char_length(title) <= 200)
);
CREATE INDEX IF NOT EXISTS speakers_occasion_idx ON public.speakers (occasion);

CREATE TABLE IF NOT EXISTS public.speaker_topics (
  id          bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  occasion    bigint NOT NULL REFERENCES public.occasions(id) ON DELETE CASCADE,
  code        text,
  title       text NOT NULL,
  "order"     bigint NOT NULL DEFAULT 0,
  is_hidden   boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS speaker_topics_occasion_idx ON public.speaker_topics (occasion);
CREATE UNIQUE INDEX IF NOT EXISTS speaker_topics_occasion_code_uidx
  ON public.speaker_topics (occasion, code) WHERE (code IS NOT NULL);

CREATE TABLE IF NOT EXISTS public.speaker_topic_links (
  speaker bigint NOT NULL REFERENCES public.speakers(id) ON DELETE CASCADE,
  topic   bigint NOT NULL REFERENCES public.speaker_topics(id) ON DELETE CASCADE,
  CONSTRAINT speaker_topic_links_pkey PRIMARY KEY (speaker, topic)
);
CREATE INDEX IF NOT EXISTS speaker_topic_links_topic_idx ON public.speaker_topic_links (topic);

CREATE TABLE IF NOT EXISTS public.event_speakers (
  event   bigint NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  speaker bigint NOT NULL REFERENCES public.speakers(id) ON DELETE CASCADE,
  CONSTRAINT event_speakers_pkey PRIMARY KEY (event, speaker)
);
CREATE INDEX IF NOT EXISTS event_speakers_speaker_idx ON public.event_speakers (speaker);

-- moddatetime triggery na speakers + speaker_topics (DO $$ ... duplicate_object)
-- RLS: ENABLE na všech 4; policy "Enable select for all" USING (true);
-- žádné write policies (zápis jen přes SECURITY DEFINER RPC).
```

### 9.2 Feature gate helper

```sql
CREATE OR REPLACE FUNCTION public.get_is_speakers_enabled_on_occasion(p_occasion bigint)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.occasions o, jsonb_array_elements(o.features) elem
    WHERE o.id = p_occasion AND elem->>'code' = 'speakers'
      AND (elem->>'is_enabled')::boolean IS TRUE);
$$;
```

### 9.3 Counseling větev v `sign_user_to_event` (náčrt diffu)

```sql
-- po načtení eventu:
SELECT (data->>'is_counseling_slot')::boolean IS TRUE
  INTO v_is_counseling FROM events WHERE id = ev;

IF v_is_counseling THEN
  -- (a) vlastní okno místo workshops gate
  SELECT elem INTO speakers_feature FROM occasions,
       jsonb_array_elements(features) elem
   WHERE id = v_occasion AND elem->>'code' = 'speakers' LIMIT 1;
  IF speakers_feature IS NULL
     OR (speakers_feature->>'is_enabled')::boolean IS NOT TRUE THEN
    RETURN json_build_object('code', 108);
  END IF;
  registration_start := (speakers_feature->>'registration_start_time')::timestamp;
  IF registration_start IS NOT NULL
     AND CURRENT_TIMESTAMP AT TIME ZONE 'UTC' < registration_start THEN
    RETURN json_build_object('code', 104,
      'events_registration_start', registration_start AT TIME ZONE 'UTC');
  END IF;
  -- (b) limit budoucích rezervací (0 = bez limitu)
  v_limit := COALESCE((speakers_feature->>'max_active_bookings')::int, 1);
  IF v_limit > 0 THEN
    SELECT count(*) INTO v_active
      FROM event_users eu JOIN events e2 ON e2.id = eu.event
     WHERE eu."user" = usr AND e2.occasion = v_occasion
       AND (e2.data->>'is_counseling_slot')::boolean IS TRUE
       AND e2.end_time > CURRENT_TIMESTAMP AT TIME ZONE 'UTC';
    IF v_active >= v_limit THEN
      RETURN json_build_object('code', 109);   -- nový kód: limit rezervací
    END IF;
  END IF;
ELSE
  -- stávající workshops gate beze změny
END IF;
-- dál beze změny: 100/103/102/105/106/107/101
```

### 9.4 Matcher `get_counseling_availability(p_occasion, p_topic)` (náčrt)

```sql
-- gate: get_is_speakers_enabled_on_occasion → jinak 404
-- topic musí patřit occasion a nebýt skrytý → jinak 404
SELECT jsonb_agg(... jsonb_build_object(
  'id', s.id, 'title', s.title, 'subtitle', s.subtitle, 'image', s.image,
  'slots', COALESCE((
     SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'start_time', e.start_time, 'end_time', e.end_time,
        'place', e.place, 'max_participants', e.max_participants,
        'occupied', (SELECT count(*) FROM event_users eu WHERE eu.event = e.id),
        'isSignedIn', ...auth.uid()...) ORDER BY e.start_time)
       FROM event_speakers es JOIN events e ON e.id = es.event
      WHERE es.speaker = s.id AND e.occasion = p_occasion
        AND (e.data->>'is_counseling_slot')::boolean IS TRUE
        AND e.end_time > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')), '[]'))
  FROM speakers s
  JOIN speaker_topic_links stl ON stl.speaker = s.id AND stl.topic = p_topic
 WHERE s.occasion = p_occasion AND s.is_hidden = FALSE
 ORDER BY s."order", s.title;
```

### 9.5 Generátor a úklid slotů (náčrt)

```sql
-- create_counseling_slots(p_speaker, p_start, p_end, p_slot_minutes,
--   p_place DEFAULT NULL, p_capacity DEFAULT 1, p_title DEFAULT NULL,
--   p_break_minutes DEFAULT 0)
-- guard editor; validace parametrů (délka ≥5, start<end, kapacita ≥1,
-- place patří occasion); typ = counseling_event_type z feature configu;
-- LOOP: INSERT INTO events (occasion, title=COALESCE(p_title, jméno),
--   start/end, max_participants=p_capacity, place, type, is_hidden=FALSE,
--   data={'is_counseling_slot':true}) + INSERT event_speakers;
-- vrací {created, event_ids}.

-- delete_empty_counseling_slots(p_speaker, p_from DEFAULT NULL)
-- guard editor; smaže speakerovy is_counseling_slot eventy bez event_users
-- (od p_from), vč. event_users_saved; vrací {deleted}.
```

### 9.6 CRUD (podpis + chování — plné znění vznikne při implementaci)

`update_speaker` / `update_speaker_topic`: upsert dle přítomnosti `id`
v jsonb; UPDATE vždy s `AND occasion = p_occasion` (cross-occasion → 404);
`topics:[ids]` = atomický replace linků omezený na témata téže occasion.
`delete_speaker` / `delete_speaker_topic`: guard přes occasion řádku, CASCADE.
`set_event_speakers`: guard přes occasion eventu; validace, že všichni
speakers patří k occasion (jinak 400); delete-missing + insert-new.
`get_speakers` / `get_speakers_for_edit`: viz tabulka v sekci 5;
veřejná varianta stripuje skryté a `description` vydává jen na vyžádání
(vzor `get_events(p_include_description)`).
