-- test-setup: database/tests/blueprint/fixtures.sql
-- test-setup: database/tests/helpers/canonical_blueprint_order_fixture.sql
DO $test$
DECLARE v_org_id bigint; v_unit_id bigint; v_secret_id bigint; v_bank_account_id bigint;
 v_occasion_id bigint; v_form_json jsonb; v_form_id bigint; v_form_key uuid;
 main_field bigint; ticket_field bigint; rejected boolean; bad text;
BEGIN
    -- 1. Build a self-contained occasion (org + unit + CZK bank account), like
    --    create_ticket_order_test.sql — do not rely on pre-seeded data. The
    --    spot product type + product are created by create_form below.
    INSERT INTO public.organizations (title) VALUES ('Test Org Eshop Errors')
    RETURNING id INTO v_org_id;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit Eshop Errors', v_org_id)
    RETURNING id INTO v_unit_id;

    INSERT INTO eshop.secrets (secret) VALUES ('error-test-secret-' || floor(random()*100000)::text)
    RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank CZK Errors', ARRAY['CZK'], v_secret_id, 'FIO')
    RETURNING id INTO v_bank_account_id;
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
    VALUES (v_unit_id, v_bank_account_id, 1);

    INSERT INTO public.occasions (title, unit, link, start_time, end_time)
    VALUES ('Test Occasion Eshop Errors', v_unit_id,
            'test-occ-eshop-errors-' || floor(random()*100000)::text,
            now(), now() + interval '1 day')
    RETURNING id INTO v_occasion_id;

    PERFORM create_user_for_test('form_create_fixture','form-create-fixture@example.invalid');
    UPDATE public.user_info SET organization=v_org_id WHERE id=get_user_id('form_create_fixture');
    UPDATE public.occasions SET organization=v_org_id WHERE id=v_occasion_id;
    INSERT INTO public.unit_users(unit,"user",is_editor,is_editor_view)
      VALUES(v_unit_id,get_user_id('form_create_fixture'),true,true);
    PERFORM set_config('request.jwt.claim.sub',get_user_id('form_create_fixture')::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    SELECT create_form(v_occasion_id, 'error-test-' || floor(random()*100000)::text, 'Error Test Form')
    INTO v_form_json;

    v_form_id := (v_form_json->>'id')::bigint;
    v_form_key := (v_form_json->>'key')::uuid;

    -- Open the form by default
    UPDATE public.forms SET is_open = true WHERE id = v_form_id;


 UPDATE public.form_fields SET is_required=false WHERE form=v_form_id;
 INSERT INTO public.form_fields(form,type,is_ticket_field) VALUES(v_form_id,'email',false) RETURNING id INTO main_field;
 INSERT INTO public.form_fields(form,type,is_ticket_field) VALUES(v_form_id,'email',true) RETURNING id INTO ticket_field;
 FOREACH bad IN ARRAY ARRAY['bujnmi@co','a..b@example.cz','a@-example.cz'] LOOP
  rejected:=false;
  BEGIN
   PERFORM public.validate_waitlist_answers_internal(v_form_id,jsonb_build_object('email',bad),'[{}]',true);
  EXCEPTION WHEN raise_exception THEN rejected:=SQLERRM LIKE '%INVALID_EMAIL%'; END;
  IF NOT rejected THEN RAISE EXCEPTION 'Invalid primary email accepted'; END IF;
  rejected:=false;
  BEGIN
   PERFORM public.validate_waitlist_answers_internal(v_form_id,jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(main_field::text,bad))),'[{}]',true);
  EXCEPTION WHEN raise_exception THEN rejected:=SQLERRM LIKE '%INVALID_EMAIL%'; END;
  IF NOT rejected THEN RAISE EXCEPTION 'Invalid custom main email accepted'; END IF;
  rejected:=false;
  BEGIN
   PERFORM public.validate_waitlist_answers_internal(v_form_id,'{}',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(ticket_field::text,bad)))),true);
  EXCEPTION WHEN raise_exception THEN rejected:=SQLERRM LIKE '%INVALID_EMAIL%'; END;
  IF NOT rejected THEN RAISE EXCEPTION 'Invalid participant email accepted'; END IF;
 END LOOP;
 PERFORM public.validate_waitlist_answers_internal(v_form_id,'{"email":"valid@example.co"}','[{}]',false);
 PERFORM public.validate_waitlist_answers_internal(v_form_id,'{"email":"valid@example.czz"}','[{}]',true);
 PERFORM public.validate_waitlist_answers_internal(v_form_id,'{}','[{"fields":[]}]',true);
 IF public.normalize_order_email_contact(' plus+tag@example.cz ') <> 'plus+tag@example.cz' THEN RAISE EXCEPTION 'Repair normalization regressed'; END IF;
 rejected:=false;
 BEGIN PERFORM public.normalize_order_email_contact('bujnmi@co');
 EXCEPTION WHEN invalid_parameter_value THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Repair accepted invalid email'; END IF;
END $test$;
