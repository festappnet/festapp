-- save_place_location regression tests.
-- Covers the permission model of the move-a-place RPC: an editor may move any
-- place of the occasion; a group admin may move only their private hidden group
-- point, never a shared catalog place linked to the group. Everyone else is
-- refused. Also the 401
-- (signed out) and 404 (missing place) envelopes.
-- Auto-rollback runner; impersonation via request.jwt.claim.sub.

-- ---------------------------------------------------------------------------
-- Fixture: one occasion with an editor, a group admin (admin of a group whose
-- assigned place is "Own WC"), a second group admin for a foreign group, and a
-- plain attendee. Places: "Generic" (no group) and "Own WC" (group's place).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc       bigint;
    v_generic  bigint;
    v_own      bigint;
    v_group    bigint;
    v_group2   bigint;
BEGIN
    PERFORM create_user_for_test('spl_editor',  'spl_editor@test.local');
    PERFORM create_user_for_test('spl_gadmin',  'spl_gadmin@test.local');
    PERFORM create_user_for_test('spl_gadmin2', 'spl_gadmin2@test.local');
    PERFORM create_user_for_test('spl_plain',   'spl_plain@test.local');

    INSERT INTO public.occasions (title, link, start_time, end_time, is_open)
    VALUES ('Save Place Test Occasion', 'spl-' || gen_random_uuid(),
            now(), now() + interval '30 days', true)
    RETURNING id INTO v_oc;

    INSERT INTO public.occasion_users (occasion, "user", is_editor, is_editor_view, is_approved)
    VALUES (v_oc, get_user_id('spl_editor'), true, true, true);
    INSERT INTO public.occasion_users (occasion, "user", is_approved)
    VALUES (v_oc, get_user_id('spl_gadmin'), true);
    INSERT INTO public.occasion_users (occasion, "user", is_approved)
    VALUES (v_oc, get_user_id('spl_gadmin2'), true);
    INSERT INTO public.occasion_users (occasion, "user", is_approved)
    VALUES (v_oc, get_user_id('spl_plain'), true);

    -- Two places; both start at lat/lng = 1.
    INSERT INTO public.places (title, occasion, coordinates)
    VALUES ('Generic', v_oc, '{"latLng":{"lat":1,"lng":1}}'::jsonb) RETURNING id INTO v_generic;
    INSERT INTO public.places
        (title, occasion, coordinates, type, is_hidden)
    VALUES
        (gen_random_uuid()::text, v_oc, '{"latLng":{"lat":1,"lng":1}}'::jsonb,
         'group', true)
    RETURNING id INTO v_own;

    -- Group whose assigned place is "Own WC"; spl_gadmin is its admin.
    INSERT INTO public.user_group_info (title, occasion, place)
    VALUES ('Group Own', v_oc, v_own) RETURNING id INTO v_group;
    INSERT INTO public.user_groups ("user", "group", is_admin)
    VALUES (get_user_id('spl_gadmin'), v_group, true);

    -- A second group (assigned no place) with spl_gadmin2 as admin — proves a
    -- group admin cannot move a place that isn't their group's place.
    INSERT INTO public.user_group_info (title, occasion, place)
    VALUES ('Group Other', v_oc, NULL) RETURNING id INTO v_group2;
    INSERT INTO public.user_groups ("user", "group", is_admin)
    VALUES (get_user_id('spl_gadmin2'), v_group2, true);

    CREATE TEMP TABLE IF NOT EXISTS _spl (
        occasion bigint,
        generic_place bigint,
        private_place bigint,
        group_id bigint
    );
    INSERT INTO _spl VALUES (v_oc, v_generic, v_own, v_group);

    RAISE NOTICE 'fixture built: occasion=%, generic=%, own=%', v_oc, v_generic, v_own;
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- a) An editor moves any place of the occasion → 200 and the coordinates change.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_generic bigint := (SELECT generic_place FROM _spl);
    v_res jsonb;
    v_lat float;
    v_lng float;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spl_editor')::text, true);

    v_res := public.save_place_location(v_generic, 10, 20);
    PERFORM assert_eq(v_res->>'code', '200', 'editor moves place → 200');
    PERFORM assert_eq((v_res->'data'->>'id')::bigint, v_generic, 'result echoes the place id');

    SELECT (coordinates->'latLng'->>'lat')::float, (coordinates->'latLng'->>'lng')::float
      INTO v_lat, v_lng FROM public.places WHERE id = v_generic;
    PERFORM assert_eq(v_lat, 10::float, 'editor move persisted the new lat');
    PERFORM assert_eq(v_lng, 20::float, 'editor move persisted the new lng');

    RAISE NOTICE 'test a (editor move) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- b) A group admin moves the place assigned to their own group → 200 + changed.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_own bigint := (SELECT private_place FROM _spl);
    v_res jsonb;
    v_lat float;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spl_gadmin')::text, true);

    v_res := public.save_place_location(v_own, 30, 40);
    PERFORM assert_eq(v_res->>'code', '200', 'group admin moves own place → 200');

    SELECT (coordinates->'latLng'->>'lat')::float INTO v_lat FROM public.places WHERE id = v_own;
    PERFORM assert_eq(v_lat, 30::float, 'group admin move persisted the new lat');

    RAISE NOTICE 'test b (group admin own place) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- c) Linking a shared catalog place to the group does not grant its admin the
--    right to move that shared place → 403 and coordinates stay unchanged.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_generic bigint := (SELECT generic_place FROM _spl);
    v_group bigint := (SELECT group_id FROM _spl);
    v_res jsonb;
    v_lat float;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spl_gadmin')::text, true);

    UPDATE public.user_group_info SET place = v_generic WHERE id = v_group;

    v_res := public.save_place_location(v_generic, 99, 99);
    PERFORM assert_eq(v_res->>'code', '403', 'group admin moving a linked shared place → 403');

    SELECT (coordinates->'latLng'->>'lat')::float INTO v_lat FROM public.places WHERE id = v_generic;
    PERFORM assert_eq(v_lat, 10::float, 'foreign place coordinates left unchanged');

    -- A group admin of a place-less group is likewise refused.
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spl_gadmin2')::text, true);
    v_res := public.save_place_location(v_generic, 99, 99);
    PERFORM assert_eq(v_res->>'code', '403', 'place-less group admin → 403');

    RAISE NOTICE 'test c (group admin foreign place) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- d) A plain signed-in attendee → 403.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_generic bigint := (SELECT generic_place FROM _spl);
    v_res jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spl_plain')::text, true);
    v_res := public.save_place_location(v_generic, 5, 5);
    PERFORM assert_eq(v_res->>'code', '403', 'plain attendee → 403');

    RAISE NOTICE 'test d (plain attendee) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- e) Signed out → 401; a missing place (as an editor) → 404.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_generic bigint := (SELECT generic_place FROM _spl);
    v_res jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    v_res := public.save_place_location(v_generic, 5, 5);
    PERFORM assert_eq(v_res->>'code', '401', 'signed out → 401');

    PERFORM set_config('request.jwt.claim.sub', get_user_id('spl_editor')::text, true);
    v_res := public.save_place_location(999999999, 5, 5);
    PERFORM assert_eq(v_res->>'code', '404', 'missing place → 404');

    RAISE NOTICE 'test e (401 + 404) passed';
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- f) The group-editor RPC returns only visible, map-capable places from the
--    requested occasion and keeps its editor-view authorization boundary.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_oc bigint := (SELECT occasion FROM _spl);
    v_generic bigint := (SELECT generic_place FROM _spl);
    v_private bigint := (SELECT private_place FROM _spl);
    v_payload jsonb;
    v_rejected boolean := false;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', get_user_id('spl_editor')::text, true);
    v_payload := public.get_all_user_groups(v_oc, NULL);

    PERFORM assert_eq(
        jsonb_typeof(v_payload->'places'),
        'array',
        'group editor returns a places array');
    PERFORM assert_eq(
        EXISTS (
            SELECT 1
            FROM jsonb_array_elements(v_payload->'places') place_item
            WHERE (place_item->>'id')::bigint = v_generic
        ),
        true,
        'visible place with coordinates is included');
    PERFORM assert_eq(
        EXISTS (
            SELECT 1
            FROM jsonb_array_elements(v_payload->'places') place_item
            WHERE (place_item->>'id')::bigint = v_private
        ),
        false,
        'private hidden group point is excluded');

    PERFORM set_config('request.jwt.claim.sub', get_user_id('spl_plain')::text, true);
    BEGIN
        PERFORM public.get_all_user_groups(v_oc, NULL);
    EXCEPTION WHEN OTHERS THEN
        v_rejected := SQLERRM = 'NOT_AUTHORIZED';
    END;
    PERFORM assert_eq(v_rejected, true, 'non-editor-view user is rejected');
END $$ LANGUAGE plpgsql;
