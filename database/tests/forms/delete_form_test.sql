DO $$
DECLARE
    v_user_id uuid;
    v_org_id bigint;
    v_unit_id bigint;
    v_occasion_id bigint;
    v_form_id bigint;
    v_form_link text := 'test-form-delete-' || floor(random() * 100000)::text;
    v_full_json jsonb;
    v_form_data jsonb;
    v_order_id bigint;
    v_delete_result jsonb;
BEGIN
    -- 1. Setup Context
    SELECT id INTO v_user_id FROM auth.users LIMIT 1;
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No users found for test'; END IF;
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);

    -- Create Org, Unit, Occasion
    -- Note: We use ad-hoc inserts to avoid dependency on specific RPCs which might change
    INSERT INTO public.organizations (title) VALUES ('Test Org Delete Form') RETURNING id INTO v_org_id;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit Delete Form', v_org_id) RETURNING id INTO v_unit_id;

    INSERT INTO public.occasions (title, link, unit, start_time, end_time)
    VALUES ('Test Occasion Delete Form', 'occ-del-form-' || floor(random()*100000)::text, v_unit_id, now(), now() + interval '1 day')
    RETURNING id INTO v_occasion_id;

    -- Assign user as editor on occasion (CRITICAL for permission checks)
    -- We set ALL editor flags to ensure permissions pass regardless of which specific check is used
    INSERT INTO public.occasion_users (occasion, "user", is_editor, is_manager, is_editor_order_view)
    VALUES (v_occasion_id, v_user_id, true, true, true)
    ON CONFLICT (occasion, "user") DO UPDATE SET is_editor = true, is_manager = true, is_editor_order_view = true;

    -- 2. Create Form
    INSERT INTO public.forms (title, link, occasion, key)
    VALUES ('Test Form Delete', v_form_link, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_form_id;

    -- 3. Check can_delete = true (initially)
    v_full_json := get_form_for_edit(v_form_link);
    v_form_data := v_full_json->'data'->'form';

    IF (v_form_data->>'can_delete')::boolean IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'Form should be deletable initially. Data: %', v_form_data->>'can_delete';
    END IF;

    -- 4. Create Order (Response)
    INSERT INTO eshop.orders (order_symbol, form, data, created_at, updated_at, price, state)
    VALUES (public.generate_order_symbol(), v_form_id, jsonb_build_object('form', (SELECT key FROM public.forms WHERE id = v_form_id)), now(), now(), 0, 'created')
    RETURNING id INTO v_order_id;

    -- 5. Check can_delete = false (after order)
    v_full_json := get_form_for_edit(v_form_link);
    v_form_data := v_full_json->'data'->'form';

    IF (v_form_data->>'can_delete')::boolean IS TRUE THEN
        RAISE EXCEPTION 'Form should NOT be deletable with orders';
    END IF;

    -- 6. The canonical receipt-backed command reports the conflict explicitly.
    v_delete_result := public.delete_form_client_sync_v1(
        v_form_id, gen_random_uuid());
    PERFORM assert_eq(v_delete_result->>'status', 'conflict',
        'form with responses should return conflict');
    PERFORM assert_eq((v_delete_result->>'code')::integer, 409,
        'form with responses should return HTTP-like code 409');

    -- 7. Delete Order (cleanup)
    DELETE FROM eshop.orders WHERE id = v_order_id;

    -- 8. Check can_delete = true (after cleanup)
    v_full_json := get_form_for_edit(v_form_link);
    v_form_data := v_full_json->'data'->'form';

    IF (v_form_data->>'can_delete')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'Form should be deletable after order removal';
    END IF;

    -- 9. Delete Form -> Success
    v_delete_result := public.delete_form_client_sync_v1(
        v_form_id, gen_random_uuid());
    PERFORM assert_eq(v_delete_result->>'status', 'applied',
        'deletable form should be removed');

    -- 10. Verify deletion
    PERFORM * FROM public.forms WHERE id = v_form_id;
    IF FOUND THEN
        RAISE EXCEPTION 'Form should have been deleted (found row)';
    END IF;

    -- Cleanup Org/Unit/Occasion
    DELETE FROM public.occasion_users WHERE occasion = v_occasion_id;
    DELETE FROM public.occasions WHERE id = v_occasion_id;
    DELETE FROM public.unit_users WHERE unit = v_unit_id; -- Just in case
    DELETE FROM public.units WHERE id = v_unit_id;
    DELETE FROM public.organizations WHERE id = v_org_id;

END $$;
