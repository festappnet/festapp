-- Verify get_app_config_v218 resolution priorities and security/permission rules.
-- All IDs are auto-generated and passed between DO blocks via session config keys
-- (test.gac_*). Wrapped in BEGIN/ROLLBACK by the runner.

BEGIN;

DO $$
DECLARE
    v_org_id bigint;
    v_unit1_id bigint;
    v_unit2_id bigint;
    v_occ_default_id bigint;
    v_occ_rep_id bigint;
    v_occ_specific_id bigint;
    v_occ_closed_id bigint;
    v_form_id bigint;
    v_form_link text := 'gac_form_' || floor(random()*1000000)::text;
    v_default_link text := 'gac_default_' || floor(random()*1000000)::text;
    v_rep_link text := 'gac_rep_' || floor(random()*1000000)::text;
    v_specific_link text := 'gac_specific_' || floor(random()*1000000)::text;
    v_closed_link text := 'gac_closed_' || floor(random()*1000000)::text;
BEGIN
    RAISE NOTICE 'Running v2 FINAL CHECK (Fixes Applied)';

    -- 1. Org
    INSERT INTO public.organizations (title, data)
    VALUES ('Test Organization', '{"IS_UNIT_CREATION_ENABLED": true, "IS_APP_SUPPORTED": false}'::jsonb)
    RETURNING id INTO v_org_id;

    -- 2. Units
    INSERT INTO public.units (title, organization, data)
    VALUES ('Test Unit 1', v_org_id, '{}'::jsonb)
    RETURNING id INTO v_unit1_id;
    INSERT INTO public.units (title, organization, data)
    VALUES ('Test Unit 2', v_org_id, '{}'::jsonb)
    RETURNING id INTO v_unit2_id;

    -- 3. Occasions
    INSERT INTO public.occasions (title, link, organization, unit, is_open, start_time, end_time)
    VALUES ('Default Occasion', v_default_link, v_org_id, v_unit1_id, true, now(), now() + interval '1 day')
    RETURNING id INTO v_occ_default_id;
    INSERT INTO public.occasions (title, link, organization, unit, is_open, start_time, end_time)
    VALUES ('Representative Occasion', v_rep_link, v_org_id, v_unit1_id, true, now(), now() + interval '1 day')
    RETURNING id INTO v_occ_rep_id;
    INSERT INTO public.occasions (title, link, organization, unit, is_open, start_time, end_time)
    VALUES ('Specific Occasion', v_specific_link, v_org_id, v_unit2_id, true, now(), now() + interval '1 day')
    RETURNING id INTO v_occ_specific_id;
    INSERT INTO public.occasions (title, link, organization, unit, is_open, start_time, end_time)
    VALUES ('Closed Occasion', v_closed_link, v_org_id, v_unit1_id, false, now(), now() + interval '1 day')
    RETURNING id INTO v_occ_closed_id;

    -- 3b. Patch org with DEFAULT_OCCASION / REPRESENTATIVE_OCCASION pointing at created occasions
    UPDATE public.organizations
    SET data = data
        || jsonb_build_object('DEFAULT_OCCASION', v_occ_default_id)
        || jsonb_build_object('REPRESENTATIVE_OCCASION', v_occ_rep_id)
    WHERE id = v_org_id;

    -- 4. Form linked to Specific Occasion
    INSERT INTO public.forms (title, occasion, link, is_open)
    VALUES ('Test Form', v_occ_specific_id, v_form_link, true)
    RETURNING id INTO v_form_id;

    -- 5. Test users
    PERFORM create_user_for_test('gac_testuser', 'gac_test_' || floor(random()*1000000)::text || '@example.com');
    PERFORM create_user_for_test('gac_adminuser', 'gac_admin_' || floor(random()*1000000)::text || '@example.com');
    PERFORM create_user_for_test('gac_randomuser', 'gac_random_' || floor(random()*1000000)::text || '@example.com');

    -- testuser: Unit 1 manager, Unit 2 ordinary
    INSERT INTO public.unit_users (unit, "user", is_manager, is_editor, is_editor_view)
    VALUES
        (v_unit1_id, get_user_id('gac_testuser'), true, true, true),
        (v_unit2_id, get_user_id('gac_testuser'), false, false, false);

    -- adminuser: editor on closed occasion
    INSERT INTO public.occasion_users (occasion, "user", is_editor)
    VALUES (v_occ_closed_id, get_user_id('gac_adminuser'), true);

    -- Share IDs with downstream test blocks
  PERFORM pg_temp.adopt_public_link_fixtures();
    PERFORM set_config('test.gac_org_id', v_org_id::text, false);
    PERFORM set_config('test.gac_unit1_id', v_unit1_id::text, false);
    PERFORM set_config('test.gac_unit2_id', v_unit2_id::text, false);
    PERFORM set_config('test.gac_occ_default_id', v_occ_default_id::text, false);
    PERFORM set_config('test.gac_occ_rep_id', v_occ_rep_id::text, false);
    PERFORM set_config('test.gac_occ_specific_id', v_occ_specific_id::text, false);
    PERFORM set_config('test.gac_occ_closed_id', v_occ_closed_id::text, false);
    PERFORM set_config('test.gac_form_link', v_form_link, false);
    PERFORM set_config('test.gac_default_link', v_default_link, false);
    PERFORM set_config('test.gac_rep_link', v_rep_link, false);
    PERFORM set_config('test.gac_specific_link', v_specific_link, false);
    PERFORM set_config('test.gac_closed_link', v_closed_link, false);
END $$;

-- =========================================================
-- TESTS
-- =========================================================

-- Test 1: Resolve by Form Link (Priority 1)
DO $$
DECLARE
    result jsonb;
    payload jsonb := jsonb_build_object(
        'organization', current_setting('test.gac_org_id')::bigint,
        'form_link', current_setting('test.gac_form_link'),
        'platform', jsonb_build_object('platform', 'web')
    );
BEGIN
    result := get_app_config_v218(payload);
    PERFORM assert_eq((result->'occasion'->>'id')::bigint, current_setting('test.gac_occ_specific_id')::bigint, 'Priority 1: Should resolve specific occasion via form_link');
    PERFORM assert_eq((result->'code')::int, 200, 'Priority 1: Code should be 200');
    PERFORM assert_true((result->>'version_recommended') IS NULL, 'Version fields should be removed');
END $$;

-- Test 2: Resolve by Link (Priority 2)
DO $$
DECLARE
    result jsonb;
    payload jsonb := jsonb_build_object(
        'organization', current_setting('test.gac_org_id')::bigint,
        'link', current_setting('test.gac_specific_link'),
        'platform', jsonb_build_object('platform', 'web')
    );
BEGIN
    result := get_app_config_v218(payload);
    PERFORM assert_eq((result->'occasion'->>'id')::bigint, current_setting('test.gac_occ_specific_id')::bigint, 'Priority 2: Should resolve specific occasion via link');
END $$;

-- Test 3: Link Not Found (404)
DO $$
DECLARE
    result jsonb;
    payload jsonb := jsonb_build_object(
        'organization', current_setting('test.gac_org_id')::bigint,
        'link', 'non_existent_occ_' || floor(random()*1000000)::text,
        'platform', jsonb_build_object('platform', 'web')
    );
BEGIN
    result := get_app_config_v218(payload);
    PERFORM assert_eq((result->'code')::int, 404, 'Link 404: Should return 404 for unknown link');
END $$;

-- Test 4: Resolve by Representative Occasion (Priority 3)
DO $$
DECLARE
    result jsonb;
    payload jsonb := jsonb_build_object(
        'organization', current_setting('test.gac_org_id')::bigint,
        'platform', jsonb_build_object('platform', 'web')
    );
BEGIN
    result := get_app_config_v218(payload);
    PERFORM assert_eq((result->'occasion'->>'id')::bigint, current_setting('test.gac_occ_rep_id')::bigint, 'Priority 3: Should resolve Representative Occasion');
END $$;

-- Test 5: Resolve by Unit ID (Priority 4) — no occasion, but unit object
DO $$
DECLARE
    result jsonb;
    payload jsonb := jsonb_build_object(
        'organization', current_setting('test.gac_org_id')::bigint,
        'unit_id', current_setting('test.gac_unit2_id')::bigint,
        'platform', jsonb_build_object('platform', 'web')
    );
BEGIN
    result := get_app_config_v218(payload);
    PERFORM assert_true((result->'occasion'->>'id') IS NULL, 'Priority 4: Should NOT have an occasion ID when resolving by Unit');
    PERFORM assert_eq((result->'unit'->>'id')::bigint, current_setting('test.gac_unit2_id')::bigint, 'Priority 4: Should return correct Unit');
END $$;

-- Test 6: Default Occasion (Priority 5 — Fallback)
DO $$
DECLARE
    result jsonb;
    v_org_id bigint := current_setting('test.gac_org_id')::bigint;
    v_default_id bigint := current_setting('test.gac_occ_default_id')::bigint;
    v_rep_id bigint := current_setting('test.gac_occ_rep_id')::bigint;
    payload jsonb := jsonb_build_object(
        'organization', v_org_id,
        'platform', jsonb_build_object('platform', 'web')
    );
BEGIN
    UPDATE public.organizations SET data = (data - 'REPRESENTATIVE_OCCASION') WHERE id = v_org_id;
    result := get_app_config_v218(payload);
    PERFORM assert_eq((result->'occasion'->>'id')::bigint, v_default_id, 'Priority 5: Should fallback to Default Occasion');

    -- Restore for subsequent tests
    UPDATE public.organizations
    SET data = jsonb_set(data, '{REPRESENTATIVE_OCCASION}', to_jsonb(v_rep_id))
    WHERE id = v_org_id;
END $$;

-- Test 7: Platform Mapping (pwa -> web should succeed)
DO $$
DECLARE
    result jsonb;
    payload jsonb := jsonb_build_object(
        'organization', current_setting('test.gac_org_id')::bigint,
        'link', current_setting('test.gac_specific_link'),
        'platform', jsonb_build_object('platform', 'pwa')
    );
BEGIN
    result := get_app_config_v218(payload);
    PERFORM assert_eq((result->'code')::int, 200, 'Platform Mapping: Should handle pwa input');
END $$;

-- Test 8: Security — Closed Occasion (Anonymous, IS_APP_SUPPORTED=false) -> 200
DO $$
DECLARE
    result jsonb;
    payload jsonb := jsonb_build_object(
        'organization', current_setting('test.gac_org_id')::bigint,
        'link', current_setting('test.gac_closed_link'),
        'platform', jsonb_build_object('platform', 'web')
    );
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '', false);
    result := get_app_config_v218(payload);
    PERFORM assert_eq((result->'code')::int, 200, 'Security: Closed occasion returns 200 when IS_APP_SUPPORTED=false');
END $$;

-- Test 9: Security — Closed Occasion (Authorized Editor) -> 200
DO $$
DECLARE
    result jsonb;
    payload jsonb := jsonb_build_object(
        'organization', current_setting('test.gac_org_id')::bigint,
        'link', current_setting('test.gac_closed_link'),
        'platform', jsonb_build_object('platform', 'web')
    );
    admin_uid text := get_user_id('gac_adminuser')::text;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', admin_uid, false);
    result := get_app_config_v218(payload);
    PERFORM assert_eq((result->'code')::int, 200, 'Security: Editor should access closed occasion (200)');
    PERFORM assert_eq((result->'is_admin')::boolean, false, 'Security: Editor is not Org Admin');
END $$;

-- Test 11: Auto-Join Logic
DO $$
DECLARE
    result jsonb;
    payload jsonb := jsonb_build_object(
        'organization', current_setting('test.gac_org_id')::bigint,
        'link', current_setting('test.gac_default_link'),
        'platform', jsonb_build_object('platform', 'web')
    );
    test_uid uuid := get_user_id('gac_testuser');
    v_default_id bigint := current_setting('test.gac_occ_default_id')::bigint;
    occ_user_exists boolean;
BEGIN
    SELECT EXISTS(SELECT 1 FROM occasion_users WHERE occasion = v_default_id AND "user" = test_uid) INTO occ_user_exists;
    PERFORM assert_eq(occ_user_exists, false, 'Pre-Test: User should not be on default occasion');

    PERFORM set_config('request.jwt.claim.sub', test_uid::text, false);
    result := get_app_config_v218(payload);
    PERFORM assert_not_null(result->'occasion_user', 'Auto-Join: occasion_user should be returned');
END $$;

-- Test 12: Bank Account Admin
DO $$
DECLARE
    result jsonb;
    payload jsonb := jsonb_build_object(
        'organization', current_setting('test.gac_org_id')::bigint,
        'platform', jsonb_build_object('platform', 'web')
    );
    test_uid uuid := get_user_id('gac_testuser');
    v_unit1_id bigint := current_setting('test.gac_unit1_id')::bigint;
    v_bank_id bigint;
BEGIN
    INSERT INTO eshop.bank_accounts (supported_currencies, type, title)
    VALUES (ARRAY['CZK'], 'FIO', 'Test Bank')
    RETURNING id INTO v_bank_id;
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit1_id, v_bank_id, 1);
    INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin) VALUES (v_bank_id, test_uid, true);

    PERFORM set_config('request.jwt.claim.sub', test_uid::text, false);
    result := get_app_config_v218(payload);

    PERFORM assert_jsonb_contains(result->'bank_accounts_admin', to_jsonb(ARRAY[v_bank_id]), 'Bank Accounts: Should contain admin bank account id');
END $$;

-- Test 13: Data Lists (Occasions/Units) for a Manager
DO $$
DECLARE
    result jsonb;
    payload jsonb := jsonb_build_object(
        'organization', current_setting('test.gac_org_id')::bigint,
        'link', current_setting('test.gac_default_link'),
        'platform', jsonb_build_object('platform', 'web')
    );
    test_uid text := get_user_id('gac_testuser')::text;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', test_uid, false);
    result := get_app_config_v218(payload);

    PERFORM assert_true(jsonb_array_length(result->'user_info'->'units') > 0, 'Data Lists: Should return units');
    PERFORM assert_true(jsonb_array_length(result->'user_info'->'occasions') > 0, 'Data Lists: Should return occasions');
END $$;

-- Test 10a: IS_APP_SUPPORTED=false (default) -> closed occasion accessible
DO $$
DECLARE
    result jsonb;
    payload jsonb := jsonb_build_object(
        'organization', current_setting('test.gac_org_id')::bigint,
        'link', current_setting('test.gac_closed_link'),
        'platform', jsonb_build_object('platform', 'web')
    );
    random_uid text := get_user_id('gac_randomuser')::text;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', random_uid, false);
    result := get_app_config_v218(payload);
    PERFORM assert_eq((result->'code')::int, 200, 'Security: IS_APP_SUPPORTED=false bypasses closed-occasion check');
END $$;

-- Test 10b: IS_APP_SUPPORTED=true -> strict permissions
DO $$
DECLARE
    result jsonb;
    v_org_id bigint := current_setting('test.gac_org_id')::bigint;
    payload jsonb := jsonb_build_object(
        'organization', v_org_id,
        'link', current_setting('test.gac_closed_link'),
        'platform', jsonb_build_object('platform', 'web')
    );
    random_uid text := get_user_id('gac_randomuser')::text;
BEGIN
    UPDATE public.organizations SET data = jsonb_set(data, '{IS_APP_SUPPORTED}', 'true') WHERE id = v_org_id;
    PERFORM set_config('request.jwt.claim.sub', random_uid, false);
    result := get_app_config_v218(payload);
    PERFORM assert_eq((result->'code')::int, 403, 'Security: IS_APP_SUPPORTED=true enforces strict permissions');
END $$;

ROLLBACK;
