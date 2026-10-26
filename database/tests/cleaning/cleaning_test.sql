-- Cleaning service (úklidová služba) regression tests.
-- Covers report_cleaning_issue (happy path + crew notification, dedup, rate
-- limit, non-toilet / foreign-occasion errors), get_cleaning_status (derived
-- severity), get_cleaning_reports / resolve_cleaning_place (crew-only), and the
-- get_is_cleaning_crew_on_occasion helper (flag vs editor).
-- Auto-rollback runner; impersonation via request.jwt.claim.sub.

-- ---------------------------------------------------------------------------
-- Fixture: one occasion with the cleaning feature enabled, a toilet place_type,
-- two toilets (WC 01 / WC 02) + a non-toilet place, and users:
--   reporter (plain attendee), crew + crew2 (is_cleaning_crew), editor,
--   outsider (attendee, no crew), and nonparticipant (no occasion membership).
--   Plus a second occasion WITHOUT the feature.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc        bigint;
    v_oc2       bigint;
    v_wc1       bigint;
    v_wc2       bigint;
    v_wc3       bigint;
    v_room      bigint;
    v_wc_other  bigint;
BEGIN
    PERFORM create_user_for_test('cln_reporter', 'cln_reporter@test.local');
    PERFORM create_user_for_test('cln_crew',     'cln_crew@test.local');
    PERFORM create_user_for_test('cln_crew2',    'cln_crew2@test.local');
    PERFORM create_user_for_test('cln_editor',   'cln_editor@test.local');
    PERFORM create_user_for_test('cln_outsider', 'cln_outsider@test.local');
    PERFORM create_user_for_test('cln_nonparticipant', 'cln_nonparticipant@test.local');
    PERFORM create_user_for_test('cln_rl',       'cln_rl@test.local');

    INSERT INTO public.occasions (title, link, start_time, end_time, is_open, features)
    VALUES ('Cleaning Test Occasion', 'cln-' || gen_random_uuid(),
            now(), now() + interval '30 days', true,
            '[{"code":"cleaning","is_enabled":true}]'::jsonb)
    RETURNING id INTO v_oc;

    -- Second occasion: cleaning feature NOT enabled.
    INSERT INTO public.occasions (title, link, start_time, end_time, is_open, features)
    VALUES ('Cleaning Test Occasion 2', 'cln2-' || gen_random_uuid(),
            now(), now() + interval '30 days', true, '[]'::jsonb)
    RETURNING id INTO v_oc2;

    INSERT INTO public.occasion_users (occasion, "user", is_editor, is_editor_view, is_approved)
    VALUES (v_oc, get_user_id('cln_editor'), true, true, true);
    INSERT INTO public.occasion_users (occasion, "user", is_cleaning_crew, is_approved)
    VALUES (v_oc, get_user_id('cln_crew'), true, true);
    INSERT INTO public.occasion_users (occasion, "user", is_cleaning_crew, is_approved)
    VALUES (v_oc, get_user_id('cln_crew2'), true, true);
    INSERT INTO public.occasion_users (occasion, "user", is_approved)
    VALUES (v_oc, get_user_id('cln_reporter'), true);
    INSERT INTO public.occasion_users (occasion, "user", is_approved)
    VALUES (v_oc, get_user_id('cln_outsider'), true);
    INSERT INTO public.occasion_users (occasion, "user", is_approved)
    VALUES (v_oc, get_user_id('cln_rl'), true);
    INSERT INTO public.occasion_users (occasion, "user", is_approved)
    VALUES (v_oc2, get_user_id('cln_reporter'), true);

    -- Toilets are flagged purely via places.type = 'toilet' (the admin "WC"
    -- checkbox) — no place_types catalog row is required.
    INSERT INTO public.places (title, occasion, type, coordinates)
    VALUES ('WC 01', v_oc, 'toilet', '{"latLng":{"lat":0,"lng":0}}'::jsonb) RETURNING id INTO v_wc1;
    INSERT INTO public.places (title, occasion, type, coordinates)
    VALUES ('WC 02', v_oc, 'toilet', '{"latLng":{"lat":0,"lng":0}}'::jsonb) RETURNING id INTO v_wc2;
    INSERT INTO public.places (title, occasion, type, coordinates)
    VALUES ('WC 03', v_oc, 'toilet', '{"latLng":{"lat":0,"lng":0}}'::jsonb) RETURNING id INTO v_wc3;
    INSERT INTO public.places (title, occasion, type, coordinates)
    VALUES ('Room A', v_oc, NULL, '{"latLng":{"lat":0,"lng":0}}'::jsonb) RETURNING id INTO v_room;
    INSERT INTO public.places (title, occasion, type, coordinates)
    VALUES ('WC 01', v_oc2, 'toilet', '{"latLng":{"lat":0,"lng":0}}'::jsonb) RETURNING id INTO v_wc_other;

    CREATE TEMP TABLE IF NOT EXISTS _cln (k text PRIMARY KEY, v bigint);
    INSERT INTO _cln VALUES
        ('occasion', v_oc), ('occasion2', v_oc2),
        ('wc1', v_wc1), ('wc2', v_wc2), ('wc3', v_wc3),
        ('room', v_room), ('wc_other', v_wc_other);

    RAISE NOTICE 'fixture built: occasion=%, wc1=%, wc2=%', v_oc, v_wc1, v_wc2;
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 1. Happy path: a report is created AND a crew notification is logged with
--    data.path='cleaning' and "to" listing both crew members.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc   bigint := (SELECT v FROM _cln WHERE k = 'occasion');
    v_wc1  bigint := (SELECT v FROM _cln WHERE k = 'wc1');
    v_res  jsonb;
    v_note jsonb;
    v_open int;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_reporter')::text, true);

    v_res := public.report_cleaning_issue(v_wc1, 'paper', 'Doslel papir');
    PERFORM assert_eq(v_res->>'code', '200', 'report happy path → 200');
    PERFORM assert_eq(v_res->'data'->>'duplicate', 'false', 'first report is not a duplicate');

    SELECT count(*) INTO v_open FROM public.cleaning_reports
     WHERE place = v_wc1 AND problem_type = 'paper' AND resolved_at IS NULL;
    PERFORM assert_eq(v_open::text, '1', 'exactly one open paper report on WC 01');

    SELECT data INTO v_note FROM public.log_notifications
     WHERE occasion = v_oc ORDER BY created_at DESC LIMIT 1;
    PERFORM assert_not_null(v_note::text, 'a notification row was inserted');
    PERFORM assert_eq(v_note->>'path', 'cleaning', 'notification data.path = cleaning');

    PERFORM assert_true(
      (SELECT "to" ? get_user_id('cln_crew')::text  FROM public.log_notifications WHERE occasion = v_oc ORDER BY created_at DESC LIMIT 1),
      'notification addressed to crew');
    PERFORM assert_true(
      (SELECT "to" ? get_user_id('cln_crew2')::text FROM public.log_notifications WHERE occasion = v_oc ORDER BY created_at DESC LIMIT 1),
      'notification addressed to crew2');

    RAISE NOTICE 'test 1 (happy path + notification) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 2. Dedup: a second identical report inserts nothing, sends no new
--    notification, and returns duplicate=true. The dup note is preserved.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc    bigint := (SELECT v FROM _cln WHERE k = 'occasion');
    v_wc1   bigint := (SELECT v FROM _cln WHERE k = 'wc1');
    v_res   jsonb;
    v_reports_before int;
    v_reports_after  int;
    v_notif_before int;
    v_notif_after  int;
    v_extra jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_reporter')::text, true);

    SELECT count(*) INTO v_reports_before FROM public.cleaning_reports WHERE occasion = v_oc;
    SELECT count(*) INTO v_notif_before   FROM public.log_notifications WHERE occasion = v_oc;

    v_res := public.report_cleaning_issue(v_wc1, 'paper', 'Fakt tam neni papir');
    PERFORM assert_eq(v_res->>'code', '200', 'dedup report → 200');
    PERFORM assert_eq(v_res->'data'->>'duplicate', 'true', 'second identical report is a duplicate');

    SELECT count(*) INTO v_reports_after FROM public.cleaning_reports WHERE occasion = v_oc;
    SELECT count(*) INTO v_notif_after   FROM public.log_notifications WHERE occasion = v_oc;
    PERFORM assert_eq(v_reports_after::text, v_reports_before::text, 'dedup inserts no new report');
    PERFORM assert_eq(v_notif_after::text,   v_notif_before::text,   'dedup sends no new notification');

    SELECT data->'extra_notes' INTO v_extra FROM public.cleaning_reports
     WHERE place = v_wc1 AND problem_type = 'paper' AND resolved_at IS NULL;
    PERFORM assert_true(v_extra @> '["Fakt tam neni papir"]'::jsonb, 'dup note appended to existing report');

    RAISE NOTICE 'test 2 (dedup) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 3. Status derives the highest open severity; other toilets stay green.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc   bigint := (SELECT v FROM _cln WHERE k = 'occasion');
    v_wc1  bigint := (SELECT v FROM _cln WHERE k = 'wc1');
    v_wc2  bigint := (SELECT v FROM _cln WHERE k = 'wc2');
    v_res  jsonb;
    v_status jsonb;
    v_s_wc1 text;
    v_s_wc2 text;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_reporter')::text, true);

    -- WC 01 already has an open paper report; add hygiene then contamination.
    PERFORM public.report_cleaning_issue(v_wc1, 'hygiene', NULL);
    PERFORM public.report_cleaning_issue(v_wc1, 'contamination', NULL);

    v_res := public.get_cleaning_status(v_oc);
    PERFORM assert_eq(v_res->>'code', '200', 'get_cleaning_status → 200');
    v_status := v_res->'data';

    SELECT elem->>'status' INTO v_s_wc1
      FROM jsonb_array_elements(v_status) elem WHERE (elem->>'place')::bigint = v_wc1;
    SELECT elem->>'status' INTO v_s_wc2
      FROM jsonb_array_elements(v_status) elem WHERE (elem->>'place')::bigint = v_wc2;

    PERFORM assert_eq(v_s_wc1, 'contamination', 'WC 01 status = highest severity (contamination)');
    PERFORM assert_eq(v_s_wc2, 'green', 'WC 02 with no reports = green');

    RAISE NOTICE 'test 3 (status severity) passed';
END $$ LANGUAGE plpgsql;

-- Hidden toilets disappear from the map but remain actionable in the cleaning
-- workflow, so the status RPC must continue returning them.
DO $$
DECLARE
    v_oc bigint := (SELECT v FROM _cln WHERE k = 'occasion');
    v_wc2 bigint := (SELECT v FROM _cln WHERE k = 'wc2');
    v_res jsonb;
BEGIN
    UPDATE public.places SET is_hidden = true WHERE id = v_wc2;
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('cln_reporter')::text, true);

    v_res := public.get_cleaning_status(v_oc);
    PERFORM assert_true(
        EXISTS (
            SELECT 1
            FROM jsonb_array_elements(v_res->'data') elem
            WHERE (elem->>'place')::bigint = v_wc2
        ),
        'hidden toilet remains visible to the cleaning workflow');

    UPDATE public.places SET is_hidden = false WHERE id = v_wc2;
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 4. A nonparticipant cannot report; a participant report on a non-toilet
--    place → 400; report on an occasion with the feature disabled → 404.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_room     bigint := (SELECT v FROM _cln WHERE k = 'room');
    v_wc_other bigint := (SELECT v FROM _cln WHERE k = 'wc_other');
    v_res jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_nonparticipant')::text, true);
    v_res := public.report_cleaning_issue(v_room, 'paper', NULL);
    PERFORM assert_eq(v_res->>'code', '403', 'nonparticipant report → 403');

    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_reporter')::text, true);

    v_res := public.report_cleaning_issue(v_room, 'paper', NULL);
    PERFORM assert_eq(v_res->>'code', '400', 'report on non-toilet → 400');

    v_res := public.report_cleaning_issue(v_wc_other, 'paper', NULL);
    PERFORM assert_eq(v_res->>'code', '404', 'report on feature-disabled occasion → 404');

    v_res := public.report_cleaning_issue(v_wc_other, 'nonsense', NULL);
    PERFORM assert_eq(v_res->>'code', '400', 'invalid problem_type → 400');

    RAISE NOTICE 'test 4 (validation errors) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 5. get_is_cleaning_crew_on_occasion: crew flag → true, editor → true,
--    plain attendee → false. get_cleaning_reports is crew-only.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc bigint := (SELECT v FROM _cln WHERE k = 'occasion');
    v_res jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_crew')::text, true);
    PERFORM assert_true(public.get_is_cleaning_crew_on_occasion(v_oc), 'crew flag → crew');

    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_editor')::text, true);
    PERFORM assert_true(public.get_is_cleaning_crew_on_occasion(v_oc), 'editor → crew (implicit)');

    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_outsider')::text, true);
    PERFORM assert_true(NOT public.get_is_cleaning_crew_on_occasion(v_oc), 'plain attendee → not crew');

    -- non-crew cannot read detailed reports
    v_res := public.get_cleaning_reports(v_oc);
    PERFORM assert_eq(v_res->>'code', '403', 'get_cleaning_reports as non-crew → 403');

    -- crew can, and sees the open reports with notes
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_crew')::text, true);
    v_res := public.get_cleaning_reports(v_oc);
    PERFORM assert_eq(v_res->>'code', '200', 'get_cleaning_reports as crew → 200');
    PERFORM assert_true(jsonb_array_length(v_res->'data') >= 1, 'crew sees open reports');

    RAISE NOTICE 'test 5 (crew permission helper) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 6. Resolve: non-crew → 403; the receipted client-sync command resolves the
--    whole place, records a valid update audit item, and returns the toilet to
--    green.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc   bigint := (SELECT v FROM _cln WHERE k = 'occasion');
    v_wc1  bigint := (SELECT v FROM _cln WHERE k = 'wc1');
    v_res  jsonb;
    v_command uuid := gen_random_uuid();
    v_commit uuid;
    v_open int;
    v_s_wc1 text;
    v_operation text;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_reporter')::text, true);
    v_res := public.resolve_cleaning_place(v_wc1);
    PERFORM assert_eq(v_res->>'code', '403', 'resolve as non-crew → 403');

    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_crew')::text, true);
    v_res := public.resolve_cleaning_place_client_sync_v1(v_wc1, v_command);
    PERFORM assert_eq(v_res->>'status', 'applied', 'client-sync resolve is applied');
    PERFORM assert_eq(v_res->>'code', '200', 'client-sync resolve as crew → 200');
    PERFORM assert_true((v_res->'data'->>'resolved')::int >= 1, 'resolve closed at least one report');
    v_commit := (v_res#>>'{mutation,commitId}')::uuid;

    SELECT operation INTO v_operation
    FROM public.client_commit_items
    WHERE commit_id = v_commit AND entity_type = 'cleaning_place';
    PERFORM assert_eq(v_operation, 'update', 'resolve audit uses the valid update operation');

    SELECT count(*) INTO v_open FROM public.cleaning_reports
     WHERE place = v_wc1 AND resolved_at IS NULL;
    PERFORM assert_eq(v_open::text, '0', 'no open reports remain on WC 01');

    SELECT elem->>'status' INTO v_s_wc1
      FROM jsonb_array_elements(public.get_cleaning_status(v_oc)->'data') elem
     WHERE (elem->>'place')::bigint = v_wc1;
    PERFORM assert_eq(v_s_wc1, 'green', 'resolved toilet is green again');

    RAISE NOTICE 'test 6 (resolve) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 7. Rate limit: the 6th report from one user within 15 minutes → 429.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_wc1 bigint := (SELECT v FROM _cln WHERE k = 'wc1');
    v_wc2 bigint := (SELECT v FROM _cln WHERE k = 'wc2');
    v_res jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_rl')::text, true);

    -- 5 distinct (place, type) reports succeed (WC 01 was just resolved → open again).
    PERFORM assert_eq((public.report_cleaning_issue(v_wc1, 'paper', NULL))->>'code',         '200', 'rl #1 → 200');
    PERFORM assert_eq((public.report_cleaning_issue(v_wc1, 'hygiene', NULL))->>'code',       '200', 'rl #2 → 200');
    PERFORM assert_eq((public.report_cleaning_issue(v_wc1, 'contamination', NULL))->>'code', '200', 'rl #3 → 200');
    PERFORM assert_eq((public.report_cleaning_issue(v_wc2, 'paper', NULL))->>'code',         '200', 'rl #4 → 200');
    PERFORM assert_eq((public.report_cleaning_issue(v_wc2, 'hygiene', NULL))->>'code',       '200', 'rl #5 → 200');

    v_res := public.report_cleaning_issue(v_wc2, 'contamination', NULL);
    PERFORM assert_eq(v_res->>'code', '429', 'rl #6 → 429 (rate limited)');

    RAISE NOTICE 'test 7 (rate limit) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 8. Blocking (feature B): a plain attendee cannot block; the crew can block a
--    reporter (with audit into occasion_users.data); a blocked reporter gets 403
--    from report_cleaning_issue and is_blocked=true in get_cleaning_status;
--    only an editor can unblock (crew unblock → 403); after unblock reporting
--    works again and is_blocked=false.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc    bigint := (SELECT v FROM _cln WHERE k = 'occasion');
    v_wc2   bigint := (SELECT v FROM _cln WHERE k = 'wc2');
    v_res   jsonb;
    v_blocked boolean;
    v_data  jsonb;
BEGIN
    -- A plain attendee (outsider) must not be able to block anyone.
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_outsider')::text, true);
    v_res := public.set_cleaning_reporter_blocked(v_oc, get_user_id('cln_reporter'), true);
    PERFORM assert_eq(v_res->>'code', '403', 'non-crew cannot block a reporter');

    -- Crew blocks the reporter.
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_crew')::text, true);
    v_res := public.set_cleaning_reporter_blocked(v_oc, get_user_id('cln_reporter'), true);
    PERFORM assert_eq(v_res->>'code', '200', 'crew blocks reporter → 200');
    PERFORM assert_eq(v_res->'data'->>'blocked', 'true', 'result reports blocked=true');

    SELECT is_cleaning_blocked, data INTO v_blocked, v_data
      FROM public.occasion_users
     WHERE occasion = v_oc AND "user" = get_user_id('cln_reporter');
    PERFORM assert_true(v_blocked, 'flag is set on occasion_users');
    PERFORM assert_eq(v_data->>'cleaning_blocked_by', get_user_id('cln_crew')::text, 'audit records who blocked');
    PERFORM assert_not_null(v_data->>'cleaning_blocked_at', 'audit records when blocked');

    -- Blocked reporter cannot report and sees is_blocked=true in the status.
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_reporter')::text, true);
    v_res := public.report_cleaning_issue(v_wc2, 'paper', 'still spamming');
    PERFORM assert_eq(v_res->>'code', '403', 'blocked reporter → 403');

    v_res := public.get_cleaning_status(v_oc);
    PERFORM assert_eq(v_res->>'is_blocked', 'true', 'status reports is_blocked=true for blocked reporter');

    -- A non-blocked attendee sees is_blocked=false.
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_outsider')::text, true);
    v_res := public.get_cleaning_status(v_oc);
    PERFORM assert_eq(v_res->>'is_blocked', 'false', 'status reports is_blocked=false for others');

    -- Crew cannot UNblock (editor-only, asymmetric rights).
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_crew')::text, true);
    v_res := public.set_cleaning_reporter_blocked(v_oc, get_user_id('cln_reporter'), false);
    PERFORM assert_eq(v_res->>'code', '403', 'crew cannot unblock (editor-only)');

    -- Editor unblocks; audit keys are cleared and reporting works again.
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_editor')::text, true);
    v_res := public.set_cleaning_reporter_blocked(v_oc, get_user_id('cln_reporter'), false);
    PERFORM assert_eq(v_res->>'code', '200', 'editor unblocks → 200');

    SELECT is_cleaning_blocked, data INTO v_blocked, v_data
      FROM public.occasion_users
     WHERE occasion = v_oc AND "user" = get_user_id('cln_reporter');
    PERFORM assert_true(NOT v_blocked, 'flag cleared on unblock');
    PERFORM assert_true(NOT (v_data ? 'cleaning_blocked_by'), 'audit blocked_by cleared on unblock');

    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_reporter')::text, true);
    v_res := public.get_cleaning_status(v_oc);
    PERFORM assert_eq(v_res->>'is_blocked', 'false', 'unblocked reporter is_blocked=false');

    RAISE NOTICE 'test 8 (blocking) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 9. get_cleaning_reports exposes created_by (uuid) and created_by_blocked so
--    the crew card can offer/label the block action.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc   bigint := (SELECT v FROM _cln WHERE k = 'occasion');
    v_wc2  bigint := (SELECT v FROM _cln WHERE k = 'wc2');
    v_res  jsonb;
    v_row  jsonb;
BEGIN
    -- Fresh open report by the reporter (wc2 contamination has no open report —
    -- test 7's 6th report was rate-limited, not created), then block them.
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_reporter')::text, true);
    PERFORM public.report_cleaning_issue(v_wc2, 'contamination', 'reporter note');

    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_crew')::text, true);
    PERFORM public.set_cleaning_reporter_blocked(v_oc, get_user_id('cln_reporter'), true);

    v_res := public.get_cleaning_reports(v_oc, true);
    PERFORM assert_eq(v_res->>'code', '200', 'get_cleaning_reports → 200');

    SELECT elem INTO v_row
      FROM jsonb_array_elements(v_res->'data') elem
     WHERE elem->>'created_by' = get_user_id('cln_reporter')::text
       AND (elem->>'place')::bigint = v_wc2 AND elem->>'problem_type' = 'contamination'
     LIMIT 1;
    PERFORM assert_not_null(v_row::text, 'report row present');
    PERFORM assert_eq(v_row->>'created_by', get_user_id('cln_reporter')::text, 'report exposes created_by uuid');
    PERFORM assert_eq(v_row->>'created_by_blocked', 'true', 'report flags a blocked reporter');

    RAISE NOTICE 'test 9 (report exposes created_by + blocked) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 10. Notification opt-out: a crew member mutes cleaning notifications for
--     themselves; a fresh report then addresses only the non-muted crew.
--     get_cleaning_status reports notifications_muted; unmuting restores them.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc   bigint := (SELECT v FROM _cln WHERE k = 'occasion');
    v_wc3  bigint := (SELECT v FROM _cln WHERE k = 'wc3');
    v_res  jsonb;
    v_to   jsonb;
BEGIN
    -- Crew member mutes their own cleaning notifications.
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_crew')::text, true);
    v_res := public.set_cleaning_notifications_muted(v_oc, true);
    PERFORM assert_eq(v_res->>'code', '200', 'mute → 200');
    PERFORM assert_eq(v_res->'data'->>'muted', 'true', 'result reports muted=true');

    v_res := public.get_cleaning_status(v_oc);
    PERFORM assert_eq(v_res->>'notifications_muted', 'true', 'status reports notifications_muted for the muter');

    -- crew2 (not muted) still sees notifications_muted=false.
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_crew2')::text, true);
    v_res := public.get_cleaning_status(v_oc);
    PERFORM assert_eq(v_res->>'notifications_muted', 'false', 'non-muter sees notifications_muted=false');

    -- A fresh report (WC 03 paper) notifies only the non-muted crew.
    -- (log_notifications.id is a UUID, so we identify the row by its heading,
    -- not by id/created_at ordering.)
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_outsider')::text, true);
    PERFORM public.report_cleaning_issue(v_wc3, 'paper', NULL);
    SELECT "to" INTO v_to FROM public.log_notifications
     WHERE occasion = v_oc AND heading LIKE 'WC 03%papír%';
    PERFORM assert_not_null(v_to::text, 'WC 03 paper notification exists');
    PERFORM assert_true(NOT (v_to ? get_user_id('cln_crew')::text), 'muted crew is NOT notified');
    PERFORM assert_true(v_to ? get_user_id('cln_crew2')::text, 'non-muted crew IS notified');

    -- Unmute → back among the recipients.
    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_crew')::text, true);
    v_res := public.set_cleaning_notifications_muted(v_oc, false);
    PERFORM assert_eq(v_res->>'code', '200', 'unmute → 200');

    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_outsider')::text, true);
    PERFORM public.report_cleaning_issue(v_wc3, 'hygiene', NULL);
    SELECT "to" INTO v_to FROM public.log_notifications
     WHERE occasion = v_oc AND heading LIKE 'WC 03%hygien%';
    PERFORM assert_true(v_to ? get_user_id('cln_crew')::text, 'unmuted crew is notified again');

    RAISE NOTICE 'test 10 (notification opt-out) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 11. A toilet owns its cleaning history. Deleting the toilet through the
--     canonical map command must also remove its reports instead of failing on
--     cleaning_reports_place_fkey.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc bigint := (SELECT v FROM _cln WHERE k = 'occasion');
    v_wc3 bigint := (SELECT v FROM _cln WHERE k = 'wc3');
    v_res jsonb;
BEGIN
    PERFORM assert_true(
      EXISTS (SELECT 1 FROM public.cleaning_reports WHERE place = v_wc3),
      'WC 03 has cleaning history before deletion'
    );

    PERFORM set_config('request.jwt.claim.sub', get_user_id('cln_editor')::text, true);
    v_res := public.delete_place_client_sync_v1(
      v_oc,
      v_wc3,
      gen_random_uuid(),
      0
    );

    PERFORM assert_eq(v_res->>'status', 'applied', 'toilet deletion is applied');
    PERFORM assert_true(
      NOT EXISTS (SELECT 1 FROM public.places WHERE id = v_wc3),
      'toilet is deleted'
    );
    PERFORM assert_true(
      NOT EXISTS (SELECT 1 FROM public.cleaning_reports WHERE place = v_wc3),
      'owned cleaning history is deleted with the toilet'
    );

    RAISE NOTICE 'test 11 (delete toilet with cleaning history) passed';
END $$ LANGUAGE plpgsql;
