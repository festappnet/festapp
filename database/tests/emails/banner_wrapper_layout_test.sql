-- test-setup: database/functions/others/update_entity_email_banner.sql
BEGIN;
DO $test$
DECLARE
  v_org bigint; v_unit bigint; v_occasion bigint; v_actor uuid;
  v_html text; v_unit_wrapper bigint; v_occasion_wrapper bigint;
BEGIN
  INSERT INTO public.organizations(title) VALUES('Banner layout fixture') RETURNING id INTO v_org;
  INSERT INTO public.units(title,organization) VALUES('Banner unit',v_org) RETURNING id INTO v_unit;
  INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
    VALUES('Banner occasion',v_org,v_unit,'banner-fixture-'||gen_random_uuid(),now(),now()+interval '1 day')
    RETURNING id INTO v_occasion;
  PERFORM create_user_for_test('banner_editor','banner-editor@example.invalid');
  v_actor:=get_user_id('banner_editor');
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  BEGIN
    PERFORM public.update_entity_email_banner('occasion',v_occasion,'https://img.festapp.net/images/banner.png');
    RAISE EXCEPTION 'An unauthorized editor changed the banner';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='An unauthorized editor changed the banner' THEN RAISE; END IF;
  END;
  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_wrappers WHERE occasion=v_occasion),'denied write has no wrapper');
  INSERT INTO public.unit_users(unit,"user",is_editor) VALUES(v_unit,v_actor,true);
  INSERT INTO public.occasion_users(occasion,"user",is_editor) VALUES(v_occasion,v_actor,true);
  PERFORM public.update_entity_email_banner('unit',v_unit,'https://img.festapp.net/images/unit-banner.png');
  SELECT id,html INTO v_unit_wrapper,v_html FROM public.email_wrappers WHERE unit=v_unit AND occasion IS NULL;
  PERFORM assert_true(v_html LIKE '%padding: 0 24px;%','unit body has horizontal content bounds');
  PERFORM assert_true(v_html LIKE '%width: 100%; height: auto; display: block;%','banner remains full width');
  PERFORM assert_true(v_html LIKE '%margin-top: 10px; margin-bottom: 10px;%','vertical spacing remains');
  PERFORM public.update_entity_email_banner('occasion',v_occasion,'https://img.festapp.net/images/occasion-banner.png');
  SELECT id,html INTO v_occasion_wrapper,v_html FROM public.email_wrappers WHERE occasion=v_occasion;
  PERFORM assert_true(v_html LIKE '%padding: 0 24px;%','occasion body has the same bounds');
  PERFORM assert_eq((length(v_html)-length(replace(v_html,'{{content}}','')))/length('{{content}}'),1,'one content slot');
  PERFORM assert_eq((public.get_email_template_and_wrapper('TICKET_ORDER_REMINDER',jsonb_build_object('occasion',v_occasion))#>>'{wrapper,id}')::bigint,v_occasion_wrapper,'occasion wrapper is authoritative');
  PERFORM public.update_entity_email_banner('occasion',v_occasion,NULL);
  PERFORM assert_eq((public.get_email_template_and_wrapper('TICKET_ORDER_REMINDER',jsonb_build_object('occasion',v_occasion))#>>'{wrapper,id}')::bigint,v_unit_wrapper,'removing occasion banner restores inherited unit wrapper');
END;
$test$;
ROLLBACK;
