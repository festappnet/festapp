DO $$
DECLARE
  v_unit_id bigint := 99999;
  v_occasion_json jsonb;
  v_features_json jsonb;
  v_form_json jsonb;
  v_user_id uuid;
BEGIN
  -- 1. Setup Data with "Heavy" fields
  INSERT INTO public.units (id, organization, title)
  VALUES (v_unit_id, 1, 'Test Unit')
  ON CONFLICT (id) DO NOTHING;

  -- Setup Auth
  SELECT id INTO v_user_id FROM auth.users LIMIT 1;
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'No users found for testing'; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);

  -- Ensure permissions
  INSERT INTO public.unit_users ("user", unit, is_manager)
  VALUES (v_user_id, v_unit_id, true)
  ON CONFLICT ON CONSTRAINT unit_users_pkey DO UPDATE SET is_manager = true;

  -- Heavy Data
  INSERT INTO public.occasions (id, unit, title, data, features, link, start_time, end_time)
  VALUES (
    v_unit_id, 
    v_unit_id, 
    'Heavy Occasion', 
    '{"data_timezone": "UTC", "heavy_field": "SHOULD_BE_REMOVED"}'::jsonb,
    '[{"code": "form", "is_enabled": true, "heavy_config": "REMOVE_ME"}]'::jsonb,
    'test-link-payload',
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, features = EXCLUDED.features;

  INSERT INTO public.forms (id, occasion, header)
  VALUES (
    v_unit_id, 
    v_unit_id, 
    '{"image": "HUGE_BASE64_STRING"}' -- Treated as text/string
  )
  ON CONFLICT (id) DO UPDATE SET header = EXCLUDED.header;

  -- 2. Call the function
  SELECT 
    elem->'data', 
    elem->'features',
    elem->'form'
  INTO 
    v_occasion_json,
    v_features_json,
    v_form_json
  FROM jsonb_array_elements(get_all_occasions_for_edit_v212(v_unit_id)) elem
  LIMIT 1;

  -- 3. Assertions
  
  -- Assertion 1: Occasion Data should only contain timezone
  IF (v_occasion_json::text <> '{"data_timezone": "UTC"}') AND (v_occasion_json IS NOT NULL) THEN
     RAISE EXCEPTION 'Occasion Data Failed. Expected {"data_timezone": "UTC"}, Got: %', v_occasion_json;
  END IF;

  -- Assertion 2: Heavy field removal
  IF (v_occasion_json->>'heavy_field') IS NOT NULL THEN
     RAISE EXCEPTION 'Heavy field NOT removed from occasion data';
  END IF;

  -- Assertion 3: Features projection (Should only have code + is_enabled)
  IF (v_features_json->0->>'code' <> 'form') THEN
     RAISE EXCEPTION 'Feature code missing';
  END IF;
  
  IF (v_features_json->0->>'heavy_config') IS NOT NULL THEN
     RAISE EXCEPTION 'Feature heavy config NOT removed';
  END IF;

  -- Assertion 4: Form Header removal
  IF (v_form_json->>'header') IS NOT NULL THEN
     RAISE EXCEPTION 'Form Header NOT removed';
  END IF;

  -- Assertion 5: Form Blueprint removal
  IF (v_form_json->>'blueprint') IS NOT NULL THEN
     RAISE EXCEPTION 'Form Blueprint NOT removed';
  END IF;

  RAISE NOTICE 'Payload Size Optimization Test Passed';

END $$ LANGUAGE plpgsql;
