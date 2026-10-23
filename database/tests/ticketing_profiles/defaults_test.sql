DO $$
DECLARE en_org bigint; cs_org bigint; en_unit bigint; cs_unit bigint; en_event bigint; cs_event bigint; en_form bigint; cs_form bigint;
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('EN default test','{"DEFAULT_FORM_PAYMENT_METHOD":"stripe","DEFAULT_LANGUAGE":"en"}') RETURNING id INTO en_org;
 INSERT INTO public.organizations(title) VALUES('CS default test') RETURNING id INTO cs_org;
 INSERT INTO public.units(title,organization) VALUES('EN',en_org) RETURNING id INTO en_unit;
 INSERT INTO public.units(title,organization) VALUES('CS',cs_org) RETURNING id INTO cs_unit;
 INSERT INTO public.occasions(link,start_time,end_time,title,organization,unit) VALUES('en-'||gen_random_uuid(),now(),now()+interval '1 day','EN',en_org,en_unit) RETURNING id INTO en_event;
 INSERT INTO public.occasions(link,start_time,end_time,title,organization,unit) VALUES('cs-'||gen_random_uuid(),now(),now()+interval '1 day','CS',cs_org,cs_unit) RETURNING id INTO cs_event;
 en_form:=(public.insert_form_for_occasion_internal_v1(en_event,NULL,'English form')->>'id')::bigint;
 cs_form:=(public.insert_form_for_occasion_internal_v1(cs_event,NULL,'Czech form')->>'id')::bigint;
 IF (SELECT data#>'{payments,bankEnabled}' FROM public.forms WHERE id=en_form) IS DISTINCT FROM 'false'::jsonb THEN RAISE EXCEPTION 'EN silently enabled bank'; END IF;
 IF (SELECT data->'payments' FROM public.forms WHERE id=cs_form) IS NOT NULL THEN RAISE EXCEPTION 'Legacy default changed'; END IF;
 PERFORM public.validate_form_payment_configuration_internal(en_form);
 IF public.form_payment_availability_internal(en_form)->'available'<>'[]'::jsonb THEN RAISE EXCEPTION 'Unconnected EN draft offered a paid method'; END IF;
 IF public.form_payment_availability_internal(cs_form)->'available'<>'["bank"]'::jsonb THEN RAISE EXCEPTION 'CS bank regression'; END IF;
 UPDATE public.forms SET is_open=true WHERE id=en_form;
 BEGIN
  PERFORM public.validate_form_payment_configuration_internal(en_form);
  RAISE EXCEPTION 'Incomplete paid form published';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'PAYMENT_CONFIGURATION_INCOMPLETE' THEN RAISE; END IF;
 END;
 UPDATE eshop.products SET price=0 WHERE occasion=en_event;
 PERFORM public.validate_form_payment_configuration_internal(en_form);
 IF NOT public.stripe_unit_feature_enabled_internal(en_unit) OR public.stripe_unit_feature_enabled_internal(cs_unit) THEN RAISE EXCEPTION 'Discovery defaults leaked'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.stripe_runtime_policy WHERE organization_id=en_org AND new_payments_enabled) THEN RAISE EXCEPTION 'New sales activated by default'; END IF;
END $$;
