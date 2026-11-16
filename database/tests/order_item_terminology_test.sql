DO $$
DECLARE org bigint; unit_id bigint; occasion_id bigint; form_id bigint; fixture jsonb; session jsonb;
BEGIN
 PERFORM assert_true(NOT public.uses_ticket_terminology_internal(NULL),'missing features use applications');
 PERFORM assert_true(NOT public.uses_ticket_terminology_internal('[]'),'empty features use applications');
 PERFORM assert_true(NOT public.uses_ticket_terminology_internal('[{"code":"blueprint","is_enabled":true}]'),'blueprint does not select ticket wording');
 PERFORM assert_true(NOT public.uses_ticket_terminology_internal('[{"code":"ticket","is_enabled":false}]'),'disabled ticket feature uses applications');
 PERFORM assert_true(public.uses_ticket_terminology_internal('[{"code":"ticket","is_enabled":true}]'),'enabled ticket feature uses tickets');
 INSERT INTO public.organizations(title) VALUES('Názvosloví - test') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Pořadatel',org) RETURNING id INTO unit_id;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time,features)
 VALUES('Setkání','terminology-'||gen_random_uuid(),org,unit_id,now()+interval '2 days',now()+interval '3 days',
 '[{"code":"ticket","is_enabled":false}]') RETURNING id INTO occasion_id;
 INSERT INTO public.forms(occasion,title,link,data) VALUES(occasion_id,'Přihláška','terminology-'||gen_random_uuid(),'{}') RETURNING id INTO form_id;
 INSERT INTO public.form_fields(form,type,title,is_hidden) VALUES(form_id,'ticket','Přihláška',false);
 PERFORM assert_true(NOT public.sale_opening_has_tickets_internal(form_id),'visible field does not override application terminology');
 UPDATE public.occasions SET features='[{"code":"ticket","is_enabled":true}]' WHERE id=occasion_id;
 UPDATE public.form_fields SET is_hidden=true WHERE form=form_id AND type='ticket';
 PERFORM assert_true(public.sale_opening_has_tickets_internal(form_id),'hidden field does not override ticket terminology');
 PERFORM assert_true((public.get_occasion_sale_forms_internal(occasion_id)->0->>'has_tickets')::boolean,'sale overview shares the occasion decision');
 fixture:=public.scanner_test_fixture(1);
 session:=public.open_scanner_session(fixture->>'scan_code');
 PERFORM assert_true(session#>>'{data,hasTickets}'='false','scanner receives application terminology from its own occasion');
 UPDATE public.occasions SET features='[{"code":"ticket","is_enabled":true}]' WHERE id=(fixture->>'occasion')::bigint;
 session:=public.open_scanner_session(fixture->>'scan_code');
 PERFORM assert_true(session#>>'{data,hasTickets}'='true','scanner receives ticket terminology from its own occasion');
END $$;
