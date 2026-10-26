BEGIN;

-- Regression tests for the event feedback time gate (submit_event_feedback):
-- before the event starts feedback is rejected with 409 for regular users and
-- anonymous clients, while editors may submit (editor preview); after start
-- everyone may submit. Aggregated results (get_event_feedback_for_edit) are
-- editor-only (403 otherwise).
--
-- Backend objects come from the canonical database/tables/event_feedback.sql
-- and database/functions/events/*event_feedback*.sql sources.
-- Style follows database/tests/speakers_test.sql: fixtures built inline,
-- callers impersonated via request.jwt.claim.sub, auto-rollback.

DO $$
DECLARE
    v_oc       bigint;
    v_editor   uuid;
    v_user     uuid;
    v_future   bigint;
    v_past     bigint;
    v_res      jsonb;
BEGIN
    PERFORM create_user_for_test('fb_editor', 'fb_editor@test.local');
    PERFORM create_user_for_test('fb_user',   'fb_user@test.local');
    v_editor := get_user_id('fb_editor');
    v_user   := get_user_id('fb_user');

    INSERT INTO public.occasions (title, link, start_time, end_time, is_open, features)
    VALUES ('Feedback Gate Occasion',
            'fbg-' || gen_random_uuid(),
            now(), now() + interval '30 days',
            true,
            '[{"code":"event_feedback","is_enabled":true}]'::jsonb)
    RETURNING id INTO v_oc;

    INSERT INTO public.occasion_users (occasion, "user", is_editor, is_editor_view, is_approved)
    VALUES (v_oc, v_editor, true, true, true);
    INSERT INTO public.occasion_users (occasion, "user", is_approved)
    VALUES (v_oc, v_user, true);

    -- event starting in the future, feedback enabled
    INSERT INTO public.events (occasion, title, start_time, end_time, data)
    VALUES (v_oc, 'Future event', now() + interval '2 days', now() + interval '2 days' + interval '1 hour',
            '{"feedback_enabled":"true"}'::jsonb)
    RETURNING id INTO v_future;

    -- event that already started
    INSERT INTO public.events (occasion, title, start_time, end_time, data)
    VALUES (v_oc, 'Started event', now() - interval '1 hour', now() + interval '1 hour',
            '{"feedback_enabled":"true"}'::jsonb)
    RETURNING id INTO v_past;

    -- 1. regular signed-in user, event not started -> 409
    PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
    v_res := public.submit_event_feedback(v_future, 'happy', 'too early');
    PERFORM assert_eq(v_res->>'code', '409', 'regular user before start -> 409');

    -- 2. anonymous user (client_id), event not started -> 409
    PERFORM set_config('request.jwt.claim.sub', '', true);
    v_res := public.submit_event_feedback(v_future, 'happy', NULL, gen_random_uuid());
    PERFORM assert_eq(v_res->>'code', '409', 'anonymous before start -> 409');

    -- 3. editor, event not started -> 200 (editor preview may rate)
    PERFORM set_config('request.jwt.claim.sub', v_editor::text, true);
    v_res := public.submit_event_feedback(v_future, 'neutral', 'editor preview');
    PERFORM assert_eq(v_res->>'code', '200', 'editor before start -> 200');

    -- 4. regular user, event started -> 200
    PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
    v_res := public.submit_event_feedback(v_past, 'happy', 'after start');
    PERFORM assert_eq(v_res->>'code', '200', 'regular user after start -> 200');

    -- 5. anonymous, event started -> 200
    PERFORM set_config('request.jwt.claim.sub', '', true);
    v_res := public.submit_event_feedback(v_past, 'sad', NULL, gen_random_uuid());
    PERFORM assert_eq(v_res->>'code', '200', 'anonymous after start -> 200');

    -- 6. results RPC: regular user -> 403, editor -> 200
    PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
    v_res := public.get_event_feedback_for_edit(v_past);
    PERFORM assert_eq(v_res->>'code', '403', 'results for regular user -> 403');

    PERFORM set_config('request.jwt.claim.sub', v_editor::text, true);
    v_res := public.get_event_feedback_for_edit(v_past);
    PERFORM assert_eq(v_res->>'code', '200', 'results for editor -> 200');

    RAISE NOTICE 'event feedback gate tests passed';
END $$ LANGUAGE plpgsql;

ROLLBACK;
