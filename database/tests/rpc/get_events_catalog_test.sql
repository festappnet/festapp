BEGIN;

-- Tests for get_events_catalog: the lightweight event catalog RPC used by
-- admin pickers (exclusivity editor). Editor-only; includes hidden events;
-- chronological order; only id/title/start_time/end_time are exposed.
--
-- Style follows database/tests/speakers_test.sql: fixtures built inline,
-- callers impersonated via request.jwt.claim.sub, auto-rollback.

-- ---------------------------------------------------------------------------
-- Fixture: one occasion with an editor, an attendee, and three events
-- (one hidden, deliberately inserted out of chronological order).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc     bigint;
    v_editor uuid;
    v_att    uuid;
BEGIN
    PERFORM create_user_for_test('cat_editor', 'cat_editor@test.local');
    PERFORM create_user_for_test('cat_att',    'cat_att@test.local');
    v_editor := get_user_id('cat_editor');
    v_att    := get_user_id('cat_att');

    INSERT INTO public.occasions (title, link, start_time, end_time, is_open)
    VALUES ('Events Catalog Test Occasion',
            'cat-' || gen_random_uuid(),
            now(), now() + interval '30 days',
            true)
    RETURNING id INTO v_oc;

    INSERT INTO public.occasion_users (occasion, "user", is_editor, is_editor_view, is_approved)
    VALUES (v_oc, v_editor, true, true, true);
    INSERT INTO public.occasion_users (occasion, "user", is_approved)
    VALUES (v_oc, v_att, true);

    INSERT INTO public.events (occasion, title, start_time, end_time, is_hidden)
    VALUES
        (v_oc, 'Later Workshop',  now() + interval '2 days', now() + interval '2 days 1 hour', false),
        (v_oc, 'Early Workshop',  now() + interval '1 day',  now() + interval '1 day 1 hour',  false),
        (v_oc, 'Hidden Workshop', now() + interval '3 days', now() + interval '3 days 1 hour', true);

    CREATE TEMP TABLE IF NOT EXISTS _cat (k text PRIMARY KEY, v bigint);
    INSERT INTO _cat VALUES ('occasion', v_oc);

    RAISE NOTICE 'fixture built: occasion=%', v_oc;
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 1. Non-editor is rejected with 403.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc  bigint := (SELECT v FROM _cat WHERE k = 'occasion');
    v_res jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cat_att')::text, true);

    v_res := public.get_events_catalog(v_oc);
    PERFORM assert_eq(v_res->>'code', '403', 'get_events_catalog as non-editor → 403');

    RAISE NOTICE 'test 1 (editor guard) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 2. Editor gets all events (hidden included) in chronological order,
--    with exactly the catalog fields.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc   bigint := (SELECT v FROM _cat WHERE k = 'occasion');
    v_res  jsonb;
    v_data jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cat_editor')::text, true);

    v_res := public.get_events_catalog(v_oc);
    PERFORM assert_eq(v_res->>'code', '200', 'get_events_catalog as editor → 200');

    v_data := v_res->'data';
    PERFORM assert_eq(jsonb_array_length(v_data)::text, '3',
        'catalog contains all 3 events (hidden included)');

    PERFORM assert_eq(v_data->0->>'title', 'Early Workshop',  'events ordered by start_time (1st)');
    PERFORM assert_eq(v_data->1->>'title', 'Later Workshop',  'events ordered by start_time (2nd)');
    PERFORM assert_eq(v_data->2->>'title', 'Hidden Workshop', 'hidden event present (3rd)');

    -- Only the catalog fields are exposed.
    PERFORM assert_true(
        (SELECT bool_and(k IN ('id', 'title', 'start_time', 'end_time'))
         FROM jsonb_object_keys(v_data->0) AS k),
        'catalog rows expose only id/title/start_time/end_time');

    RAISE NOTICE 'test 2 (editor read) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 3. Other occasions' events never leak into the catalog.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc    bigint := (SELECT v FROM _cat WHERE k = 'occasion');
    v_other bigint;
    v_res   jsonb;
BEGIN
    INSERT INTO public.occasions (title, link, start_time, end_time, is_open)
    VALUES ('Other Occasion', 'cat-other-' || gen_random_uuid(),
            now(), now() + interval '30 days', true)
    RETURNING id INTO v_other;

    INSERT INTO public.events (occasion, title, start_time, end_time, is_hidden)
    VALUES (v_other, 'Foreign Workshop', now() + interval '1 day', now() + interval '1 day 1 hour', false);

    PERFORM set_config('request.jwt.claim.sub', get_user_id('cat_editor')::text, true);
    v_res := public.get_events_catalog(v_oc);

    PERFORM assert_eq(jsonb_array_length(v_res->'data')::text, '3',
        'foreign occasion events are not included');

    RAISE NOTICE 'test 3 (cross-occasion isolation) passed';
END $$ LANGUAGE plpgsql;

ROLLBACK;
