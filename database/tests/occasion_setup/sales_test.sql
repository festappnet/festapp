UPDATE public.abuse_policy_rules SET base_limit=hard_cap WHERE budget_key IN ('occasion.creation','occasion.draft');
DO $$
DECLARE actor uuid; org bigint; unit_id bigint; draft uuid; d jsonb; payload jsonb; response jsonb;
 event_id bigint; form_id bigint; product_id bigint; order_id bigint; ticket_id bigint; mode text; form_row public.forms; before_count bigint; summary jsonb;
BEGIN
 PERFORM create_user_for_test('setup_sale_manager','setup_sale@test.local');
 actor:=get_user_id('setup_sale_manager');
 INSERT INTO public.organizations(title,data) VALUES('Setup sale choices','{"IS_APP_SUPPORTED":false}') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Setup sale choices',org) RETURNING id INTO unit_id;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(unit_id,actor,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 FOREACH mode IN ARRAY ARRAY['preparation','scheduled','immediate'] LOOP
  draft:=gen_random_uuid();
  EXECUTE 'SET LOCAL ROLE authenticated';
  d:=public.create_occasion_setup_draft(draft,unit_id);
  payload:=d->'data'||jsonb_build_object('title','Sale choice '||mode,'start',now()+interval '10 days',
   'end',now()+interval '11 days','reviewConfirmed',true,'formEnabled',true,'saleMode',mode,
   'saleStart',now()+interval '1 day','saleCountdown',false,'blueprintMode','Bez plánku');
  payload:=jsonb_set(payload,'{formDraft,fields,2,product_type_data,products,0,price}','0');
  -- Source schedule cannot silently replace the new event's window.
  payload:=jsonb_set(payload,'{formDraft,data}',jsonb_build_object('schedule',jsonb_build_object(
    'start_time',now()-interval '1 year','end_time',now()-interval '10 months','enable_countdown',true),
    'start_time',now()+interval '20 days','end_time',now()+interval '21 days'));
  d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
  response:=public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid());
  PERFORM assert_eq(public.finalize_occasion_setup_draft(draft,0,gen_random_uuid()),response,'Finalization replays the original form link and sale intent');
  event_id:=(response#>>'{data,occasionId}')::bigint;
  EXECUTE 'RESET ROLE';
  SELECT * INTO form_row FROM public.forms WHERE occasion=event_id ORDER BY id LIMIT 1;
  form_id:=form_row.id;
  PERFORM assert_eq(response#>>'{data,formLink}',form_row.link,'Completion uses the saved public form address');
  PERFORM assert_eq(form_row.is_open,mode<>'preparation','Sale mode writes the form flag');
  PERFORM assert_eq((form_row.data#>>'{schedule,end_time}')::timestamptz,(payload->>'end')::timestamptz,'Sale end follows the new event');
  PERFORM assert_eq((form_row.data#>>'{schedule,enable_countdown}')::boolean,false,'Countdown is independent from scheduling');
  PERFORM assert_false(form_row.data ? 'start_time' OR form_row.data ? 'end_time','Legacy source dates are cleared');
  PERFORM assert_eq((SELECT is_hidden FROM public.occasions WHERE id=event_id),true,'Opening a form does not publish the event catalogue entry');
  IF mode='scheduled' THEN
   PERFORM assert_eq(public.get_form_registration_mode_internal(form_id,now()),'closed','Scheduled form is closed before start');
   PERFORM assert_eq(public.get_form_registration_mode_internal(form_id,now()+interval '2 days'),'regular','Scheduled form opens without a cron mutation');
  ELSIF mode='immediate' THEN
   PERFORM assert_eq(public.get_form_registration_mode_internal(form_id),'regular','Immediate form accepts orders');
   PERFORM set_config('request.jwt.claim.sub','',true);
   PERFORM set_config('request.jwt.claim.role','anon',true);
   EXECUTE 'SET LOCAL ROLE anon';
   response:=public.get_form_by_link(form_row.link)::jsonb;
   PERFORM assert_eq(response->>'code','200','Anonymous visitor can open the immediate sales form while the occasion is hidden');
   EXECUTE 'RESET ROLE';
   PERFORM set_config('request.jwt.claim.sub',actor::text,true);
   PERFORM set_config('request.jwt.claim.role','authenticated',true);

  ELSE
   PERFORM assert_true((form_row.data#>>'{schedule,sale_preparation}')::boolean,'Initial closed form is in preparation');
   EXECUTE 'SET LOCAL ROLE authenticated';
   response:=public.update_form_client_sync_v1(jsonb_build_object('id',form_id,'occasion',event_id,'is_open',true),gen_random_uuid());
   PERFORM assert_eq(response->>'status','applied','Normal form command opens preparation');
   response:=public.update_form_client_sync_v1(jsonb_build_object('id',form_id,'occasion',event_id,'is_open',false),gen_random_uuid());
   PERFORM assert_eq(response->>'status','applied','Normal form command pauses sale');
   EXECUTE 'RESET ROLE';
   PERFORM assert_false((SELECT (data#>>'{schedule,sale_preparation}')::boolean FROM public.forms WHERE id=form_id),'First opening ends preparation; closing later is paused');
  END IF;
  PERFORM assert_eq(public.get_form_registration_mode_internal(form_id,now()+interval '12 days'),'closed','Form stops accepting new orders after sale end');
 END LOOP;
 -- Invalid schedule rejection must not leave a partially created occasion.
 SELECT count(*) INTO before_count FROM public.occasions WHERE unit=unit_id;
 EXECUTE 'SET LOCAL ROLE authenticated';
 draft:=gen_random_uuid();d:=public.create_occasion_setup_draft(draft,unit_id);
 payload:=d->'data'||jsonb_build_object('title','Invalid sale','start',now()+interval '10 days','end',now()+interval '11 days',
  'reviewConfirmed',true,'saleMode','scheduled','saleStart',now()-interval '1 day');
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 BEGIN PERFORM public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid());RAISE EXCEPTION 'Expired schedule accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.occasions WHERE unit=unit_id),before_count,'Invalid sale leaves no occasion');
 -- All forms contribute to the catalogue, with the canonical capacity modes.
 UPDATE public.forms SET is_open=true,participant_capacity=1,waitlist_enabled=true,waitlist_offer_duration_seconds=3600 WHERE id=form_id;
 INSERT INTO eshop.orders(occasion,form,state,order_sequence,order_symbol)
 VALUES(event_id,form_id,'ordered',public.next_order_sequence(event_id),public.generate_order_symbol()) RETURNING id INTO order_id;
 INSERT INTO eshop.tickets(occasion,state) VALUES(event_id,'ordered') RETURNING id INTO ticket_id;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(order_id,ticket_id);
 INSERT INTO public.forms(occasion,link,is_open,data) VALUES(event_id,'sale-extra-'||event_id,true,'{}');
 summary:=public.get_occasion_sale_forms_internal(event_id);
 PERFORM assert_eq(jsonb_array_length(summary),2,'Projection includes every form');
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(summary) f WHERE f->>'registration_mode'='waitlist'),'Projection includes waiting-list acceptance');
 -- Admission products are attached to the nested product_type field, not to
 -- the outer ticket field. A product quota must affect the same sale badge.
 SELECT p.id INTO product_id FROM eshop.products p JOIN public.form_fields ff ON ff.product_type=p.product_type
  JOIN eshop.product_types pt ON pt.id=p.product_type WHERE ff.form=form_id AND pt.type='spot' LIMIT 1;
 UPDATE public.forms SET participant_capacity=NULL,waitlist_enabled=false WHERE id=form_id;
 UPDATE eshop.products SET maximum=1 WHERE id=product_id;
 UPDATE eshop.order_product_ticket SET product=product_id WHERE "order"=order_id AND ticket=ticket_id;
 PERFORM assert_false((SELECT (f->>'has_availability')::boolean FROM jsonb_array_elements(public.get_occasion_sale_forms_internal(event_id)) f
  WHERE (f->>'id')::bigint=form_id),'Exhausted admission product is not advertised as on sale');
 UPDATE eshop.products SET maximum=2 WHERE id=product_id;
 PERFORM assert_true((SELECT (f->>'has_availability')::boolean FROM jsonb_array_elements(public.get_occasion_sale_forms_internal(event_id)) f
  WHERE (f->>'id')::bigint=form_id),'Available admission variant restores sale availability');

 EXECUTE 'SET LOCAL ROLE authenticated';
 summary:=public.get_all_occasions_for_edit_v212(unit_id);
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(summary) o WHERE (o->>'id')::bigint=event_id AND jsonb_array_length(o->'sale_forms')=2),'Authorized catalogue includes the summary');
 EXECUTE 'RESET ROLE';
 PERFORM assert_false(has_function_privilege('authenticated','public.get_occasion_sale_forms_internal(bigint,timestamptz)','EXECUTE'),'Private summary is not a new RPC');
END $$;
