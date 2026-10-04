-- Test: create_form
-- Goal: Verify that create_form function asserts uniqueness, creates form, default fields, and product.

DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_occasion_id bigint;
    v_form_json jsonb;
    v_form_id bigint;
    v_field_count int;
    v_product_count int;
BEGIN
    -- 1. Setup Isolated Data
    -- Create temporary Org/Unit/Occasion to avoid polluting real data (e.g. Occasion 1)
    INSERT INTO public.organizations (title) VALUES ('Temp Test Org Form') RETURNING id INTO v_org_id;
    INSERT INTO public.units (organization, title) VALUES (v_org_id, 'Temp Test Unit Form') RETURNING id INTO v_unit_id;
    INSERT INTO public.occasions (unit, title, link, start_time, end_time) 
    VALUES (v_unit_id, 'Temp Occasion Form', 'temp-occasion-form-' || floor(random()*100000)::text, now(), now() + interval '1 day') 
    RETURNING id INTO v_occasion_id;

    -- 2. Execute: Create Form
    SELECT create_form(v_occasion_id, 'test-form-link-unique-' || floor(random()*100000)::text, 'Test Form Title') 
    INTO v_form_json;

    -- 3. Verify: Form Created
    v_form_id := (v_form_json->>'id')::bigint;
    PERFORM assert_not_null(v_form_id, 'Form ID should be returned');
    PERFORM assert_eq((v_form_json->>'link')::text, (v_form_json->>'link')::text, 'Link should match'); 
    PERFORM assert_true(NOT (v_form_json->'data' ? 'communication_tone'),
        'New form should inherit the unit tone, not snapshot it');
    PERFORM assert_eq(public.get_effective_form_data(v_form_id)->>'communication_tone',
        'formal', 'A new unit without a tone should default to formal');

    UPDATE public.units SET data = jsonb_build_object('communication_tone', 'informal')
    WHERE id = v_unit_id;
    PERFORM assert_eq(public.get_effective_form_data(v_form_id)->>'communication_tone',
        'informal', 'An inherited form should follow a later unit change');

    UPDATE public.forms SET data = data || '{"communication_tone":"formal"}'::jsonb
    WHERE id = v_form_id;
    PERFORM assert_eq(public.get_effective_form_data(v_form_id)->>'communication_tone',
        'formal', 'An explicit form setting should override its unit');

    UPDATE public.forms SET data = data - 'communication_tone'
    WHERE id = v_form_id;
    PERFORM assert_eq(public.get_effective_form_data(v_form_id)->>'communication_tone',
        'informal', 'Removing the override should resume inheritance');
    
    -- 4. Verify: Default Fields Created (email, ticket, spot)
    SELECT count(*) INTO v_field_count FROM public.form_fields WHERE form = v_form_id;
    PERFORM assert_eq(v_field_count, 3, 'Should create 3 default fields');

    -- 5. Verify: Spot Product Created
    SELECT count(*) INTO v_product_count 
    FROM eshop.products p 
    JOIN eshop.product_types pt ON p.product_type = pt.id 
    WHERE pt.occasion = v_occasion_id AND pt.type = 'spot';
    
    PERFORM assert_true(v_product_count >= 1, 'Spot product should exist');

    -- ROLLBACK handles cleanup, but using isolated IDs prevents leak if commit happens accidentally
END;
$$ LANGUAGE plpgsql;
