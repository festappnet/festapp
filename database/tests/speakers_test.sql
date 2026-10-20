BEGIN;

-- Regression tests for the speakers + counseling feature (plan section 7).
--
-- Covers: editor guards (403), upsert with atomic topic replace, cross-occasion
-- protection (404/400), the slot generator (counts / breaks / boundaries),
-- delete_empty_counseling_slots (occupied slots survive), the counseling
-- availability matcher (future-only, visible-only, isSignedIn/occupied), the
-- counseling branch of sign_user_to_event (own window skips the workshops gate,
-- missing/legacy gate → 108, limit code 109, collisions 107), speaker search
-- (ungated — speakers are core), and the features migration transform (block 9).
--
-- Speakers are core; the "counseling" feature gates the counseling flow only.
--
-- Style follows database/tests/rpc/create_service_item_test.sql: fixtures built
-- inline, callers impersonated via request.jwt.claim.sub, auto-rollback.

-- ---------------------------------------------------------------------------
-- Shared fixture builder: one occasion with the speakers feature enabled, an
-- editor, two attendees, a place. Returns ids via a temp table.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc       bigint;
    v_place    bigint;
    v_editor   uuid;
    v_att1     uuid;
    v_att2     uuid;
BEGIN
    PERFORM create_user_for_test('spk_editor', 'spk_editor@test.local');
    PERFORM create_user_for_test('spk_att1',   'spk_att1@test.local');
    PERFORM create_user_for_test('spk_att2',   'spk_att2@test.local');
    v_editor := get_user_id('spk_editor');
    v_att1   := get_user_id('spk_att1');
    v_att2   := get_user_id('spk_att2');

    INSERT INTO public.occasions (title, link, start_time, end_time, is_open, features)
    VALUES ('Speakers Test Occasion',
            'spk-' || gen_random_uuid(),
            now(), now() + interval '30 days',
            true,
            '[{"code":"counseling","is_enabled":true,"counseling_event_type":"counseling","max_active_bookings":1}]'::jsonb)
    RETURNING id INTO v_oc;

    INSERT INTO public.occasion_users (occasion, "user", is_editor, is_editor_view, is_approved)
    VALUES (v_oc, v_editor, true, true, true);
    INSERT INTO public.occasion_users (occasion, "user", is_approved) VALUES (v_oc, v_att1, true);
    INSERT INTO public.occasion_users (occasion, "user", is_approved) VALUES (v_oc, v_att2, true);

    INSERT INTO public.places (title, occasion, coordinates)
    VALUES ('Room A', v_oc, '{"latLng":{"lat":0,"lng":0}}'::jsonb)
    RETURNING id INTO v_place;

    CREATE TEMP TABLE IF NOT EXISTS _spk (k text PRIMARY KEY, v bigint);
    INSERT INTO _spk VALUES ('occasion', v_oc), ('place', v_place);

    RAISE NOTICE 'fixture built: occasion=%, place=%', v_oc, v_place;
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 1. Editor guards: non-editor writes are rejected with 403.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc  bigint := (SELECT v FROM _spk WHERE k = 'occasion');
    v_res jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spk_att1')::text, true);

    v_res := public.update_speaker(v_oc, '{"title":"Nope"}'::jsonb);
    PERFORM assert_eq(v_res->>'code', '403', 'update_speaker as non-editor → 403');

    v_res := public.update_speaker_topic(v_oc, '{"title":"Nope"}'::jsonb);
    PERFORM assert_eq(v_res->>'code', '403', 'update_speaker_topic as non-editor → 403');

    v_res := public.create_counseling_slots(1, now(), now() + interval '1 hour', 20);
    -- speaker 1 does not belong here / caller not editor → 404 or 403 (never 200)
    PERFORM assert_true(v_res->>'code' <> '200', 'create_counseling_slots as non-editor never succeeds');

    RAISE NOTICE 'test 1 (editor guards) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 2. Topic catalog + speaker upsert with atomic topic replace; foreign topic
--    ids in the array are ignored.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc     bigint := (SELECT v FROM _spk WHERE k = 'occasion');
    v_res    jsonb;
    v_t1     bigint;
    v_t2     bigint;
    v_t3     bigint;
    v_sp     bigint;
    v_foreign_topic bigint;
    v_foreign_oc bigint;
    v_topics jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spk_editor')::text, true);

    -- three topics
    v_res := public.update_speaker_topic(v_oc, '{"title":"Rodina","order":1}'::jsonb);
    PERFORM assert_eq(v_res->>'code', '200', 'topic insert → 200');
    v_t1 := (v_res->'data'->>'id')::bigint;
    v_res := public.update_speaker_topic(v_oc, '{"title":"Uzkosti","order":2}'::jsonb);
    v_t2 := (v_res->'data'->>'id')::bigint;
    v_res := public.update_speaker_topic(v_oc, '{"title":"Duchovni rozhovor","order":3}'::jsonb);
    v_t3 := (v_res->'data'->>'id')::bigint;

    -- a foreign occasion + its own topic, to prove cross-occasion ids are ignored
    INSERT INTO public.occasions (title, link, start_time, end_time)
    VALUES ('Foreign', 'spk-foreign-' || gen_random_uuid(), now(), now() + interval '1 day')
    RETURNING id INTO v_foreign_oc;
    INSERT INTO public.speaker_topics (occasion, title) VALUES (v_foreign_oc, 'Foreign topic')
    RETURNING id INTO v_foreign_topic;

    -- insert speaker with topics [t1, t2]
    v_res := public.update_speaker(v_oc, jsonb_build_object(
        'title', 'P. Novak', 'subtitle', 'knez',
        'topics', jsonb_build_array(v_t1, v_t2)));
    PERFORM assert_eq(v_res->>'code', '200', 'speaker insert → 200');
    v_sp := (v_res->'data'->>'id')::bigint;
    PERFORM assert_eq(jsonb_array_length(v_res->'data'->'topics'), 2, 'speaker has 2 topics after insert');

    -- update same speaker: replace topics with [t2, t3, foreign] → foreign ignored
    v_res := public.update_speaker(v_oc, jsonb_build_object(
        'id', v_sp,
        'topics', jsonb_build_array(v_t2, v_t3, v_foreign_topic)));
    PERFORM assert_eq(v_res->>'code', '200', 'speaker topic replace → 200');
    PERFORM assert_eq(jsonb_array_length(v_res->'data'->'topics'), 2,
        'foreign topic ignored → still 2 topics');

    SELECT count(*) INTO v_t1 FROM public.speaker_topic_links WHERE speaker = v_sp AND topic IN (v_t2, v_t3);
    PERFORM assert_eq(v_t1::int, 2, 'links replaced atomically to {t2,t3}');
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.speaker_topic_links WHERE speaker = v_sp AND topic = v_foreign_topic),
        'no link to foreign topic');

    INSERT INTO _spk VALUES ('speaker', v_sp), ('topic1', (SELECT v FROM _spk WHERE k='occasion')) ON CONFLICT DO NOTHING;
    -- store the concrete topic id for later matcher tests
    UPDATE _spk SET v = (SELECT topic FROM public.speaker_topic_links WHERE speaker = v_sp AND topic = v_t2 LIMIT 1) WHERE k='topic1';
    INSERT INTO _spk VALUES ('foreign_oc', v_foreign_oc), ('foreign_topic', v_foreign_topic) ON CONFLICT DO NOTHING;

    RAISE NOTICE 'test 2 (topics + upsert atomic replace) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 2b. The canonical v1 command accepts a non-empty topic array. This guards
--     against ambiguous aliases in both validation and link replacement.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc      bigint := (SELECT v FROM _spk WHERE k = 'occasion');
    v_sp      bigint := (SELECT v FROM _spk WHERE k = 'speaker');
    v_payload jsonb;
    v_res     jsonb;
    v_version bigint;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spk_editor')::text, true);
    SELECT jsonb_build_object(
        'id', s.id, 'title', s.title, 'subtitle', 'v1 command',
        'description', s.description, 'image', s.image, 'order', s."order",
        'is_hidden', s.is_hidden, 'data', s.data,
        'topics', COALESCE((SELECT jsonb_agg(l.topic ORDER BY l.topic)
            FROM public.speaker_topic_links l WHERE l.speaker=s.id), '[]'::jsonb))
      INTO v_payload
      FROM public.speakers s WHERE s.id=v_sp;

    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='speaker' AND scope_type='occasion'
      AND scope_id=v_oc AND aggregate_id=v_sp::text;
    v_res := public.save_speaker_client_sync_v1(
        v_oc, gen_random_uuid(), v_version, v_payload);
    PERFORM assert_eq(v_res->>'status', 'applied',
        'v1 speaker save with non-empty topics is applied');
    PERFORM assert_eq((v_res->'data'->>'version')::int, (v_version+1)::int,
        'v1 speaker save advances the aggregate version');
    PERFORM assert_eq((SELECT count(*)::int
        FROM public.speaker_topic_links WHERE speaker=v_sp), 2,
        'v1 speaker save preserves both topic links');
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 2c. The canonical event-speaker command accepts an empty array and a
--     non-empty array. This guards both unnest paths against ambiguous `id`
--     aliases used by the event editor save flow.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc      bigint := (SELECT v FROM _spk WHERE k = 'occasion');
    v_sp      bigint := (SELECT v FROM _spk WHERE k = 'speaker');
    v_event   bigint;
    v_res     jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spk_editor')::text, true);
    INSERT INTO public.events (occasion, title, start_time, end_time)
    VALUES (v_oc, 'Event speaker command', now() + interval '6 days',
      now() + interval '6 days 1 hour')
    RETURNING id INTO v_event;
    INSERT INTO public.event_speakers (event, speaker) VALUES (v_event, v_sp);

    v_res := public.save_event_speakers_client_sync_v1(
      v_oc, v_event, gen_random_uuid(), 0, '{}'::bigint[]);
    PERFORM assert_eq(v_res->>'status', 'applied',
        'v1 event speaker save accepts an empty array');
    PERFORM assert_eq((v_res->'data'->>'version')::int, 1,
        'empty event speaker save advances the aggregate version');
    PERFORM assert_true(NOT EXISTS (
        SELECT 1 FROM public.event_speakers WHERE event=v_event),
        'empty event speaker save removes existing links');

    v_res := public.save_event_speakers_client_sync_v1(
      v_oc, v_event, gen_random_uuid(), 1, ARRAY[v_sp]);
    PERFORM assert_eq(v_res->>'status', 'applied',
        'v1 event speaker save accepts a non-empty array');
    PERFORM assert_eq((v_res->'data'->>'version')::int, 2,
        'non-empty event speaker save advances the aggregate version');
    PERFORM assert_true(EXISTS (
        SELECT 1 FROM public.event_speakers
        WHERE event=v_event AND speaker=v_sp),
        'non-empty event speaker save creates the requested link');
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 3. Cross-occasion protection: updating a speaker under the wrong occasion →
--    404; set_event_speakers with a foreign speaker → 400.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc         bigint := (SELECT v FROM _spk WHERE k = 'occasion');
    v_foreign_oc bigint := (SELECT v FROM _spk WHERE k = 'foreign_oc');
    v_sp         bigint := (SELECT v FROM _spk WHERE k = 'speaker');
    v_res        jsonb;
    v_ev         bigint;
    v_foreign_sp bigint;
BEGIN
    -- editor of foreign occasion tries to edit our speaker (belongs to v_oc)
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spk_editor')::text, true);
    -- our editor is NOT editor on foreign occasion; make them editor there to
    -- isolate the cross-occasion (404) path rather than the 403 path.
    INSERT INTO public.occasion_users (occasion, "user", is_editor, is_editor_view, is_approved)
    VALUES (v_foreign_oc, get_user_id('spk_editor'), true, true, true);

    v_res := public.update_speaker(v_foreign_oc, jsonb_build_object('id', v_sp, 'title', 'Hijack'));
    PERFORM assert_eq(v_res->>'code', '404', 'update_speaker across occasion → 404');

    -- set_event_speakers: build a normal event in our occasion, then pass a
    -- foreign speaker id → 400.
    INSERT INTO public.speakers (occasion, title) VALUES (v_foreign_oc, 'Foreign speaker')
    RETURNING id INTO v_foreign_sp;
    INSERT INTO public.events (occasion, title, start_time, end_time)
    VALUES (v_oc, 'Lecture', now() + interval '5 days', now() + interval '5 days' + interval '1 hour')
    RETURNING id INTO v_ev;

    v_res := public.set_event_speakers(v_ev, ARRAY[v_foreign_sp]);
    PERFORM assert_eq(v_res->>'code', '400', 'set_event_speakers with foreign speaker → 400');

    -- valid speaker succeeds
    v_res := public.set_event_speakers(v_ev, ARRAY[v_sp]);
    PERFORM assert_eq(v_res->>'code', '200', 'set_event_speakers with valid speaker → 200');

    RAISE NOTICE 'test 3 (cross-occasion protection) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 4. Slot generator: 14:00–18:00, 20-min slots, 5-min break → 9 slots; type,
--    markers, capacity, event_speakers link. Invalid params → 400.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc    bigint := (SELECT v FROM _spk WHERE k = 'occasion');
    v_place bigint := (SELECT v FROM _spk WHERE k = 'place');
    v_sp    bigint := (SELECT v FROM _spk WHERE k = 'speaker');
    v_res   jsonb;
    v_start timestamptz := date_trunc('day', now()) + interval '10 days' + interval '14 hours';
    v_end   timestamptz := date_trunc('day', now()) + interval '10 days' + interval '18 hours';
    v_first bigint;
    v_all   int;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spk_editor')::text, true);

    v_res := public.create_counseling_slots(v_sp, v_start, v_end, 20, v_place, 2, NULL, 5);
    PERFORM assert_eq(v_res->>'code', '200', 'create_counseling_slots → 200');
    PERFORM assert_eq((v_res->'data'->>'created')::int, 9,
        '14:00–18:00 by 20+5 → 9 slots (last 17:20–17:40)');

    -- markers/type/capacity/is_hidden on all generated events
    SELECT count(*) INTO v_all FROM public.events e
    JOIN public.event_speakers es ON es.event = e.id
    WHERE es.speaker = v_sp
      AND (e.data->>'is_counseling_slot')::boolean IS TRUE
      AND e.type = 'counseling'
      AND e.is_hidden = false
      AND e.max_participants = 2
      AND e.place = v_place;
    PERFORM assert_eq(v_all, 9, 'all 9 slots have marker/type/capacity/place/visible');

    SELECT min(e.start_time) INTO v_start FROM public.events e
    JOIN public.event_speakers es ON es.event = e.id WHERE es.speaker = v_sp
      AND (e.data->>'is_counseling_slot')::boolean IS TRUE;
    PERFORM assert_eq(v_start, date_trunc('day', now()) + interval '10 days' + interval '14 hours',
        'first slot starts at p_start');

    -- invalid params
    v_res := public.create_counseling_slots(v_sp, now(), now() + interval '1 hour', 4);
    PERFORM assert_eq(v_res->>'code', '400', 'slot_minutes < 5 → 400');
    v_res := public.create_counseling_slots(v_sp, now() + interval '1 hour', now(), 20);
    PERFORM assert_eq(v_res->>'code', '400', 'start >= end → 400');

    RAISE NOTICE 'test 4 (slot generator) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 5. delete_empty_counseling_slots keeps occupied slots, removes empty ones.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_sp      bigint := (SELECT v FROM _spk WHERE k = 'speaker');
    v_res     jsonb;
    v_occupied bigint;
    v_before  int;
    v_after   int;
    v_deleted int;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spk_editor')::text, true);

    SELECT count(*) INTO v_before FROM public.events e
    JOIN public.event_speakers es ON es.event = e.id
    WHERE es.speaker = v_sp AND (e.data->>'is_counseling_slot')::boolean IS TRUE;

    -- occupy the first slot with a direct fixture insert
    SELECT e.id INTO v_occupied FROM public.events e
    JOIN public.event_speakers es ON es.event = e.id
    WHERE es.speaker = v_sp AND (e.data->>'is_counseling_slot')::boolean IS TRUE
    ORDER BY e.start_time LIMIT 1;
    INSERT INTO public.event_users (event, "user") VALUES (v_occupied, get_user_id('spk_att1'));

    v_res := public.delete_empty_counseling_slots(v_sp);
    PERFORM assert_eq(v_res->>'code', '200', 'delete_empty_counseling_slots → 200');
    v_deleted := (v_res->'data'->>'deleted')::int;
    PERFORM assert_eq(v_deleted, v_before - 1, 'deleted all but the occupied slot');

    SELECT count(*) INTO v_after FROM public.events e
    JOIN public.event_speakers es ON es.event = e.id
    WHERE es.speaker = v_sp AND (e.data->>'is_counseling_slot')::boolean IS TRUE;
    PERFORM assert_eq(v_after, 1, 'exactly the occupied slot survives');
    PERFORM assert_true(EXISTS(SELECT 1 FROM public.events WHERE id = v_occupied),
        'occupied slot still exists');

    -- clean up so later tests start from a known state
    DELETE FROM public.event_users WHERE event = v_occupied;
    DELETE FROM public.event_speakers WHERE event = v_occupied;
    DELETE FROM public.events WHERE id = v_occupied;

    RAISE NOTICE 'test 5 (delete_empty_counseling_slots) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 6. Availability matcher: future-only slots, visible-only counselors,
--    occupied/isSignedIn; disabled feature and foreign/hidden topic → 404.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc     bigint := (SELECT v FROM _spk WHERE k = 'occasion');
    v_sp     bigint := (SELECT v FROM _spk WHERE k = 'speaker');
    v_topic  bigint := (SELECT v FROM _spk WHERE k = 'topic1');
    v_foreign_topic bigint := (SELECT v FROM _spk WHERE k = 'foreign_topic');
    v_res    jsonb;
    v_future bigint;
    v_past   bigint;
    v_hidden_sp bigint;
    v_counselors jsonb;
    v_slots  jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spk_att1')::text, true);

    -- one future slot + one past slot for our speaker (linked to the topic)
    INSERT INTO public.events (occasion, title, start_time, end_time, max_participants, type, data)
    VALUES (v_oc, 'Future slot', now() + interval '2 days', now() + interval '2 days' + interval '20 minutes',
            1, 'counseling', '{"is_counseling_slot":true}'::jsonb)
    RETURNING id INTO v_future;
    INSERT INTO public.event_speakers (event, speaker) VALUES (v_future, v_sp);

    INSERT INTO public.events (occasion, title, start_time, end_time, max_participants, type, data)
    VALUES (v_oc, 'Past slot', now() - interval '2 days', now() - interval '2 days' + interval '20 minutes',
            1, 'counseling', '{"is_counseling_slot":true}'::jsonb)
    RETURNING id INTO v_past;
    INSERT INTO public.event_speakers (event, speaker) VALUES (v_past, v_sp);

    -- a hidden speaker linked to the same topic must be excluded
    INSERT INTO public.speakers (occasion, title, is_hidden) VALUES (v_oc, 'Hidden', true)
    RETURNING id INTO v_hidden_sp;
    INSERT INTO public.speaker_topic_links (speaker, topic) VALUES (v_hidden_sp, v_topic);

    v_res := public.get_counseling_availability(v_oc, v_topic);
    PERFORM assert_eq(v_res->>'code', '200', 'availability → 200');
    v_counselors := v_res->'data'->'counselors';
    PERFORM assert_eq(jsonb_array_length(v_counselors), 1, 'only the visible counselor is returned');
    v_slots := v_counselors->0->'slots';
    PERFORM assert_eq(jsonb_array_length(v_slots), 1, 'only the future slot is returned');
    PERFORM assert_eq((v_slots->0->>'id')::bigint, v_future, 'future slot id matches');
    PERFORM assert_eq((v_slots->0->>'occupied')::int, 0, 'future slot occupied=0 before sign-in');
    PERFORM assert_eq((v_slots->0->>'isSignedIn')::boolean, false, 'not signed in yet');

    -- sign the attendee into the future slot, re-query → occupied=1, isSignedIn=true
    INSERT INTO public.event_users (event, "user") VALUES (v_future, get_user_id('spk_att1'));
    v_res := public.get_counseling_availability(v_oc, v_topic);
    v_slots := v_res->'data'->'counselors'->0->'slots';
    PERFORM assert_eq((v_slots->0->>'occupied')::int, 1, 'occupied=1 after sign-in');
    PERFORM assert_eq((v_slots->0->>'isSignedIn')::boolean, true, 'isSignedIn=true for the caller');

    -- disabled feature → 404
    UPDATE public.occasions SET features = '[{"code":"counseling","is_enabled":false}]'::jsonb WHERE id = v_oc;
    v_res := public.get_counseling_availability(v_oc, v_topic);
    PERFORM assert_eq(v_res->>'code', '404', 'disabled counseling feature → 404');
    -- restore
    UPDATE public.occasions SET features = '[{"code":"counseling","is_enabled":true,"counseling_event_type":"counseling","max_active_bookings":1}]'::jsonb WHERE id = v_oc;

    -- foreign topic → 404
    v_res := public.get_counseling_availability(v_oc, v_foreign_topic);
    PERFORM assert_eq(v_res->>'code', '404', 'foreign topic → 404');

    -- cleanup the extra slots so the sign-in tests are isolated
    DELETE FROM public.event_users WHERE event IN (v_future, v_past);
    DELETE FROM public.event_speakers WHERE event IN (v_future, v_past);
    DELETE FROM public.events WHERE id IN (v_future, v_past);
    DELETE FROM public.speaker_topic_links WHERE speaker = v_hidden_sp;
    DELETE FROM public.speakers WHERE id = v_hidden_sp;

    RAISE NOTICE 'test 6 (availability matcher) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 7. Counseling branch of sign_user_to_event.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc     bigint := (SELECT v FROM _spk WHERE k = 'occasion');
    v_sp     bigint := (SELECT v FROM _spk WHERE k = 'speaker');
    v_att1   uuid := get_user_id('spk_att1');
    v_att2   uuid := get_user_id('spk_att2');
    v_res    jsonb;
    v_slotA  bigint;
    v_slotB  bigint;
    v_slotC  bigint;
    v_lecture bigint;
BEGIN
    -- (a) workshops gate is skipped for counseling slots: enable a workshops
    -- feature whose start_time is far in the future alongside counseling.
    UPDATE public.occasions SET features =
      '[{"code":"counseling","is_enabled":true,"counseling_event_type":"counseling","max_active_bookings":0},
        {"code":"workshops","is_enabled":true,"start_time":"2099-01-01T00:00:00"}]'::jsonb
    WHERE id = v_oc;

    INSERT INTO public.events (occasion, title, start_time, end_time, max_participants, type, data)
    VALUES (v_oc, 'Slot A', now() + interval '3 days', now() + interval '3 days' + interval '20 minutes',
            1, 'counseling', '{"is_counseling_slot":true}'::jsonb)
    RETURNING id INTO v_slotA;
    INSERT INTO public.event_speakers (event, speaker) VALUES (v_slotA, v_sp);

    PERFORM set_config('request.jwt.claim.sub', v_att1::text, true);
    v_res := public.sign_user_to_event(v_slotA, v_att1);
    PERFORM assert_eq(v_res->>'code', '200',
        'counseling sign-in ignores the far-future workshops gate → 200');

    -- (b) counseling registration_start_time in the future → 104
    UPDATE public.occasions SET features =
      '[{"code":"counseling","is_enabled":true,"registration_start_time":"2099-01-01T00:00:00","max_active_bookings":0}]'::jsonb
    WHERE id = v_oc;
    INSERT INTO public.events (occasion, title, start_time, end_time, max_participants, type, data)
    VALUES (v_oc, 'Slot B', now() + interval '4 days', now() + interval '4 days' + interval '20 minutes',
            1, 'counseling', '{"is_counseling_slot":true}'::jsonb)
    RETURNING id INTO v_slotB;
    INSERT INTO public.event_speakers (event, speaker) VALUES (v_slotB, v_sp);
    PERFORM set_config('request.jwt.claim.sub', v_att2::text, true);
    v_res := public.sign_user_to_event(v_slotB, v_att2);
    PERFORM assert_eq(v_res->>'code', '104', 'registration window not open → 104');

    -- (c) counseling feature disabled → 108
    UPDATE public.occasions SET features = '[{"code":"counseling","is_enabled":false}]'::jsonb WHERE id = v_oc;
    v_res := public.sign_user_to_event(v_slotB, v_att2);
    PERFORM assert_eq(v_res->>'code', '108', 'counseling feature disabled → 108');

    -- (c2) counseling element missing entirely → 108.
    UPDATE public.occasions SET features = '[]'::jsonb WHERE id = v_oc;
    v_res := public.sign_user_to_event(v_slotB, v_att2);
    PERFORM assert_eq(v_res->>'code', '108', 'counseling feature absent → 108');

    -- (c3) legacy "speakers" element alone (enabled) does NOT open the window:
    -- the retired code is ignored, so the counseling gate is still closed → 108.
    UPDATE public.occasions SET features =
      '[{"code":"speakers","is_enabled":true,"max_active_bookings":0}]'::jsonb WHERE id = v_oc;
    v_res := public.sign_user_to_event(v_slotB, v_att2);
    PERFORM assert_eq(v_res->>'code', '108', 'legacy speakers element does not gate counseling → 108');

    -- (d) max_active_bookings = 1: att2 already holds slotA? No — reset and test.
    -- Give att2 one future booking, then limit=1 blocks a second with 109.
    UPDATE public.occasions SET features =
      '[{"code":"counseling","is_enabled":true,"max_active_bookings":1}]'::jsonb WHERE id = v_oc;
    PERFORM set_config('request.jwt.claim.sub', v_att2::text, true);
    v_res := public.sign_user_to_event(v_slotB, v_att2);
    PERFORM assert_eq(v_res->>'code', '200', 'first counseling booking under limit → 200');

    INSERT INTO public.events (occasion, title, start_time, end_time, max_participants, type, data)
    VALUES (v_oc, 'Slot C', now() + interval '6 days', now() + interval '6 days' + interval '20 minutes',
            1, 'counseling', '{"is_counseling_slot":true}'::jsonb)
    RETURNING id INTO v_slotC;
    INSERT INTO public.event_speakers (event, speaker) VALUES (v_slotC, v_sp);
    v_res := public.sign_user_to_event(v_slotC, v_att2);
    PERFORM assert_eq(v_res->>'code', '109', 'second future booking over limit → 109');

    -- with limit 0 the same second booking is allowed
    UPDATE public.occasions SET features =
      '[{"code":"counseling","is_enabled":true,"max_active_bookings":0}]'::jsonb WHERE id = v_oc;
    v_res := public.sign_user_to_event(v_slotC, v_att2);
    PERFORM assert_eq(v_res->>'code', '200', 'limit 0 → unlimited → 200');

    -- (e) collisions. att1 already holds slotA (3 days out, 20 min). A second
    -- slot overlapping slotA from a different speaker → 107.
    INSERT INTO public.events (occasion, title, start_time, end_time, max_participants, type, data)
    VALUES (v_oc, 'Slot A-overlap', now() + interval '3 days' + interval '5 minutes',
            now() + interval '3 days' + interval '25 minutes',
            1, 'counseling', '{"is_counseling_slot":true}'::jsonb)
    RETURNING id INTO v_lecture; -- reuse var
    INSERT INTO public.event_speakers (event, speaker) VALUES (v_lecture, v_sp);
    PERFORM set_config('request.jwt.claim.sub', v_att1::text, true);
    v_res := public.sign_user_to_event(v_lecture, v_att1);
    PERFORM assert_eq(v_res->>'code', '107', 'slot×slot time collision → 107');

    -- slot × normal lecture the user already attends → 107
    INSERT INTO public.events (occasion, title, start_time, end_time)
    VALUES (v_oc, 'Normal lecture', now() + interval '8 days', now() + interval '8 days' + interval '1 hour')
    RETURNING id INTO v_lecture;
    INSERT INTO public.event_users (event, "user") VALUES (v_lecture, v_att1);
    -- Partial tail overlap with the lecture (the existing collision loop only
    -- catches partial/boundary overlaps, not a slot fully enclosed by the event).
    INSERT INTO public.events (occasion, title, start_time, end_time, max_participants, type, data)
    VALUES (v_oc, 'Slot during lecture', now() + interval '8 days' + interval '50 minutes',
            now() + interval '8 days' + interval '70 minutes',
            1, 'counseling', '{"is_counseling_slot":true}'::jsonb)
    RETURNING id INTO v_slotC;
    INSERT INTO public.event_speakers (event, speaker) VALUES (v_slotC, v_sp);
    v_res := public.sign_user_to_event(v_slotC, v_att1);
    PERFORM assert_eq(v_res->>'code', '107', 'slot×lecture time collision → 107');

    RAISE NOTICE 'test 7 (sign_user_to_event counseling branch) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 8. GlobalSearch: speakers are core — searchable by name/role/bio WITHOUT any
--    feature (decision R3/R7). Hidden speakers stay excluded. Slots stay out of
--    search (tested via the events branch elsewhere). Needs public.f_unaccent +
--    speakers.search_doc (migration 20260710120000_speakers_searchable.sql).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc  bigint := (SELECT v FROM _spk WHERE k = 'occasion');
    v_n   int;
BEGIN
    -- No speakers/counseling feature at all — speakers must still be searchable.
    UPDATE public.occasions SET features = '[]'::jsonb WHERE id = v_oc;

    INSERT INTO public.speakers (occasion, title, subtitle, description, is_hidden)
    VALUES (v_oc, 'Vyhledatelný Řehoř', 'psycholog', 'Medailonek o úzkostech', false);
    INSERT INTO public.speakers (occasion, title, subtitle, is_hidden)
    VALUES (v_oc, 'Skrytý Poradce', 'knez', true);

    SELECT count(*) INTO v_n FROM public.search_occasion_content(v_oc, 'rehor', 50)
      WHERE entity_type = 'speaker';
    PERFORM assert_true(v_n >= 1, 'speaker found by name without any feature (diacritics-insensitive)');

    SELECT count(*) INTO v_n FROM public.search_occasion_content(v_oc, 'psycholog', 50)
      WHERE entity_type = 'speaker';
    PERFORM assert_true(v_n >= 1, 'speaker found by role/subtitle');

    SELECT count(*) INTO v_n FROM public.search_occasion_content(v_oc, 'uzkost', 50)
      WHERE entity_type = 'speaker';
    PERFORM assert_true(v_n >= 1, 'speaker found by bio text');

    SELECT count(*) INTO v_n FROM public.search_occasion_content(v_oc, 'Skrytý', 50)
      WHERE entity_type = 'speaker';
    PERFORM assert_eq(v_n, 0, 'hidden speaker is not searchable');

    -- Even with the counseling feature disabled, speakers remain searchable.
    UPDATE public.occasions SET features = '[{"code":"counseling","is_enabled":false}]'::jsonb WHERE id = v_oc;
    SELECT count(*) INTO v_n FROM public.search_occasion_content(v_oc, 'rehor', 50)
      WHERE entity_type = 'speaker';
    PERFORM assert_true(v_n >= 1, 'speakers still searchable with counseling disabled');

    RAISE NOTICE 'test 8 (speaker search, ungated) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 9. Migration transform (decision R2): the idempotent UPDATE that rewrites a
--    legacy "speakers" feature element into a "counseling" element. This runs
--    the SAME statement body as
--    supabase/migrations/20260710140000_counseling_feature_split.sql (the CASE
--    expression is identical), scoped to the test occasions.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc1        bigint;  -- speakers enabled, counseling_enabled:false
    v_oc2        bigint;  -- speakers enabled, counseling_enabled:true
    v_oc3        bigint;  -- no speakers element (untouched)
    v_counseling jsonb;
    v_before     jsonb;
    v_after      jsonb;
BEGIN
    INSERT INTO public.occasions (title, link, start_time, end_time, features)
    VALUES ('Mig1', 'spk-mig1-' || gen_random_uuid(), now(), now() + interval '1 day',
            '[{"code":"speakers","is_enabled":true,"counseling_enabled":false,"counseling_event_type":"poradna","max_active_bookings":3,"registration_start_time":"2099-01-01T00:00:00"},
              {"code":"map","is_enabled":true}]'::jsonb)
    RETURNING id INTO v_oc1;

    INSERT INTO public.occasions (title, link, start_time, end_time, features)
    VALUES ('Mig2', 'spk-mig2-' || gen_random_uuid(), now(), now() + interval '1 day',
            '[{"code":"speakers","is_enabled":true,"counseling_enabled":true}]'::jsonb)
    RETURNING id INTO v_oc2;

    INSERT INTO public.occasions (title, link, start_time, end_time, features)
    VALUES ('Mig3', 'spk-mig3-' || gen_random_uuid(), now(), now() + interval '1 day',
            '[{"code":"map","is_enabled":true}]'::jsonb)
    RETURNING id INTO v_oc3;

    v_before := (SELECT features FROM public.occasions WHERE id = v_oc3);

    -- The migration transform (identical CASE), scoped to these occasions.
    UPDATE public.occasions o
    SET features = (
        SELECT COALESCE(jsonb_agg(
            CASE
                WHEN elem->>'code' = 'speakers' THEN
                    jsonb_strip_nulls(jsonb_build_object(
                        'code', 'counseling',
                        'is_enabled', (
                            COALESCE((elem->>'is_enabled')::boolean, false)
                            AND COALESCE((elem->>'counseling_enabled')::boolean, false)
                        ),
                        'counseling_event_type',    elem->'counseling_event_type',
                        'registration_start_time',  elem->'registration_start_time',
                        'max_active_bookings',      elem->'max_active_bookings'
                    ))
                ELSE elem
            END
        ), '[]'::jsonb)
        FROM jsonb_array_elements(o.features) elem
    )
    WHERE o.id IN (v_oc1, v_oc2, v_oc3)
      AND o.features IS NOT NULL
      AND jsonb_typeof(o.features) = 'array'
      AND EXISTS (
          SELECT 1 FROM jsonb_array_elements(o.features) e2
          WHERE e2->>'code' = 'speakers'
      );

    -- oc1: speakers → counseling; is_enabled = true AND false = false; config kept.
    SELECT elem INTO v_counseling
    FROM public.occasions o, jsonb_array_elements(o.features) elem
    WHERE o.id = v_oc1 AND elem->>'code' = 'counseling';
    PERFORM assert_true(v_counseling IS NOT NULL, 'oc1: counseling element created');
    PERFORM assert_eq((v_counseling->>'is_enabled')::boolean, false,
        'oc1: is_enabled = enabled AND counseling_enabled = false');
    PERFORM assert_eq(v_counseling->>'counseling_event_type', 'poradna', 'oc1: event type carried over');
    PERFORM assert_eq((v_counseling->>'max_active_bookings')::int, 3, 'oc1: limit carried over');
    PERFORM assert_eq(v_counseling->>'registration_start_time', '2099-01-01T00:00:00', 'oc1: window carried over');
    PERFORM assert_true(NOT EXISTS (
        SELECT 1 FROM public.occasions o, jsonb_array_elements(o.features) elem
        WHERE o.id = v_oc1 AND elem->>'code' = 'speakers'), 'oc1: speakers element removed');
    PERFORM assert_true(EXISTS (
        SELECT 1 FROM public.occasions o, jsonb_array_elements(o.features) elem
        WHERE o.id = v_oc1 AND elem->>'code' = 'map' AND (elem->>'is_enabled')::boolean IS TRUE),
        'oc1: other features untouched');

    -- oc2: counseling_enabled:true → is_enabled:true.
    SELECT elem INTO v_counseling
    FROM public.occasions o, jsonb_array_elements(o.features) elem
    WHERE o.id = v_oc2 AND elem->>'code' = 'counseling';
    PERFORM assert_eq((v_counseling->>'is_enabled')::boolean, true, 'oc2: enabled AND counseling_enabled → true');

    -- oc3: no speakers element → unchanged.
    v_after := (SELECT features FROM public.occasions WHERE id = v_oc3);
    PERFORM assert_true(v_after = v_before, 'oc3: occasion without speakers element unchanged');

    -- Idempotency: a second run changes nothing.
    v_before := (SELECT features FROM public.occasions WHERE id = v_oc1);
    UPDATE public.occasions o
    SET features = (
        SELECT COALESCE(jsonb_agg(
            CASE
                WHEN elem->>'code' = 'speakers' THEN
                    jsonb_strip_nulls(jsonb_build_object(
                        'code', 'counseling',
                        'is_enabled', (
                            COALESCE((elem->>'is_enabled')::boolean, false)
                            AND COALESCE((elem->>'counseling_enabled')::boolean, false)
                        ),
                        'counseling_event_type',    elem->'counseling_event_type',
                        'registration_start_time',  elem->'registration_start_time',
                        'max_active_bookings',      elem->'max_active_bookings'
                    ))
                ELSE elem
            END
        ), '[]'::jsonb)
        FROM jsonb_array_elements(o.features) elem
    )
    WHERE o.id IN (v_oc1, v_oc2, v_oc3)
      AND o.features IS NOT NULL
      AND jsonb_typeof(o.features) = 'array'
      AND EXISTS (
          SELECT 1 FROM jsonb_array_elements(o.features) e2
          WHERE e2->>'code' = 'speakers'
      );
    v_after := (SELECT features FROM public.occasions WHERE id = v_oc1);
    PERFORM assert_true(v_after = v_before, 'idempotent: second run leaves features unchanged');

    RAISE NOTICE 'test 9 (features migration transform) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 10. delete_event unbinds sign-ups (event_users) and saved rows
--     (event_users_saved) before deleting — counseling slots are ordinary
--     events with attendees. Editor guard (403); missing event (404).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc    bigint := (SELECT v FROM _spk WHERE k = 'occasion');
    v_sp    bigint := (SELECT v FROM _spk WHERE k = 'speaker');
    v_att1  uuid := get_user_id('spk_att1');
    v_att2  uuid := get_user_id('spk_att2');
    v_slot  bigint;
    v_res   jsonb;
BEGIN
    -- A counseling slot with an attendee, a saved row, and a speaker link.
    INSERT INTO public.events (occasion, title, start_time, end_time, max_participants, type, data)
    VALUES (v_oc, 'Slot to delete', now() + interval '9 days', now() + interval '9 days' + interval '20 minutes',
            2, 'counseling', '{"is_counseling_slot":true}'::jsonb)
    RETURNING id INTO v_slot;
    INSERT INTO public.event_speakers (event, speaker) VALUES (v_slot, v_sp);
    INSERT INTO public.event_users (event, "user")       VALUES (v_slot, v_att1), (v_slot, v_att2);
    INSERT INTO public.event_users_saved (event, "user") VALUES (v_slot, v_att1);

    -- (a) non-editor cannot delete → 403, event survives.
    PERFORM set_config('request.jwt.claim.sub', v_att1::text, true);
    v_res := public.delete_event(v_slot);
    PERFORM assert_eq(v_res->>'code', '403', 'delete_event as non-editor → 403');
    PERFORM assert_true(EXISTS(SELECT 1 FROM public.events WHERE id = v_slot),
        'event still present after rejected delete');

    -- (b) editor deletes → 200; event and all child rows gone (no FK error).
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spk_editor')::text, true);
    v_res := public.delete_event(v_slot);
    PERFORM assert_eq(v_res->>'code', '200', 'delete_event as editor unbinds sign-ups → 200');
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.events WHERE id = v_slot),
        'event deleted');
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.event_users WHERE event = v_slot),
        'event_users unbound');
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.event_users_saved WHERE event = v_slot),
        'event_users_saved unbound');
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.event_speakers WHERE event = v_slot),
        'event_speakers cascaded');

    -- (c) missing event → 404.
    v_res := public.delete_event(v_slot);
    PERFORM assert_eq(v_res->>'code', '404', 'delete_event on missing event → 404');

    RAISE NOTICE 'test 10 (delete_event unbinds sign-ups) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 11. The single-slot editor command cannot delete a counseling entry point
--     or any other event, even when that event is linked to the speaker.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc    bigint := (SELECT v FROM _spk WHERE k = 'occasion');
    v_sp    bigint := (SELECT v FROM _spk WHERE k = 'speaker');
    v_entry bigint;
    v_slot  bigint;
    v_res   jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spk_editor')::text, true);

    INSERT INTO public.events (occasion, title, start_time, end_time, type, data)
    VALUES (v_oc, 'Counseling entry', now() + interval '12 days',
            now() + interval '12 days 1 hour', '',
            '{"counseling_entry":true}'::jsonb)
    RETURNING id INTO v_entry;
    INSERT INTO public.event_speakers (event, speaker) VALUES (v_entry, v_sp);

    v_res := public.delete_counseling_slot(v_sp, v_entry);
    PERFORM assert_eq(v_res->>'code', '400',
        'single-slot delete rejects the counseling entry point');
    PERFORM assert_true(EXISTS(SELECT 1 FROM public.events WHERE id = v_entry),
        'counseling entry survives single-slot delete');

    INSERT INTO public.events (occasion, title, start_time, end_time,
                               max_participants, type, data)
    VALUES (v_oc, 'Real counseling slot', now() + interval '12 days',
            now() + interval '12 days 20 minutes', 1, 'counseling',
            '{"is_counseling_slot":true}'::jsonb)
    RETURNING id INTO v_slot;
    INSERT INTO public.event_speakers (event, speaker) VALUES (v_slot, v_sp);

    v_res := public.delete_counseling_slot(v_sp, v_slot);
    PERFORM assert_eq(v_res->>'code', '200',
        'single-slot delete accepts the linked counseling slot');
    PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.events WHERE id = v_slot),
        'linked counseling slot is deleted');

    RAISE NOTICE 'test 11 (guarded single counseling slot delete) passed';
END $$ LANGUAGE plpgsql;

DO $$ BEGIN RAISE NOTICE 'speakers + counseling regression tests passed'; END $$ LANGUAGE plpgsql;

ROLLBACK; -- Always rollback: tests must not mutate data
