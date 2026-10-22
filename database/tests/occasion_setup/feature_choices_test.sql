UPDATE public.abuse_policy_rules SET base_limit=hard_cap WHERE budget_key IN ('occasion.creation','occasion.draft');
DO $$
DECLARE actor uuid; org bigint; unit_id bigint; draft uuid; d jsonb; payload jsonb; response jsonb;
 event_id bigint; form_id bigint; old_product bigint; plan_id bigint; n integer; before_count bigint;
 seat_node uuid:=gen_random_uuid();
BEGIN
 PERFORM create_user_for_test('setup_feature_manager','setup_features@test.local');
 actor:=get_user_id('setup_feature_manager');
 INSERT INTO public.organizations(title,data) VALUES('Setup feature choices','{"IS_APP_SUPPORTED":false}') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Setup feature choices',org) RETURNING id INTO unit_id;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(unit_id,actor,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 FOR n IN 1..6 LOOP
  IF n=5 THEN UPDATE public.organizations SET data='{"IS_APP_SUPPORTED":true}' WHERE id=org;
  ELSIF n=6 THEN UPDATE public.organizations SET data='{"IS_APP_SUPPORTED":false}' WHERE id=org; END IF;
  draft:=gen_random_uuid();
  EXECUTE 'SET LOCAL ROLE authenticated';
  d:=public.create_occasion_setup_draft(draft,unit_id);
  payload:=d->'data'||jsonb_build_object('title','Feature choice '||n,'start','2090-08-01T18:00:00Z',
   'end','2090-08-02T02:00:00Z','reviewConfirmed',true,'formEnabled',n<>5,
   'blueprintMode','Bez plánku','blueprintObjects','[]'::jsonb,
   'eventKind','regular','eventKindNeedsConfirmation',true);
  payload:=jsonb_set(payload,'{formDraft,fields,2,product_type_data,products,0,price}','0');
  old_product:=(payload#>>'{formDraft,fields,2,product_type_data,products,0,id}')::bigint;
  IF n=1 THEN
   -- Backtracking leaves dormant draft objects; choosing no plan must win.
   payload:=payload||'{"blueprintObjects":[{"type":"spot","title":"Dormant","product":-999}]}'::jsonb;
  ELSIF n=2 THEN
   payload:=payload||'{"ticketDraft":{"code":"schedule","is_enabled":false}}'::jsonb;
  ELSIF n IN (3,4,5) THEN
   payload:=payload||'{"ticketDraft":{"code":"ticket","is_enabled":true,"layout":{"schemaVersion":999,"templates":null}}}'::jsonb;
   IF n=3 THEN
    payload:=jsonb_set(payload,'{formDraft,fields}',(SELECT jsonb_agg(f ORDER BY i) FROM jsonb_array_elements(payload#>'{formDraft,fields}') WITH ORDINALITY x(f,i) WHERE f->>'type'<>'ticket'));
   ELSIF n=4 THEN
    payload:=jsonb_set(payload,'{formDraft,fields,1,is_hidden}','true');
   END IF;
  ELSIF n=6 THEN
   payload:=payload||jsonb_build_object('blueprintMode','Nový','blueprintTitle','Chosen plan',
    'blueprintLayoutDraft',jsonb_build_object(
      'layout',jsonb_build_object('schemaVersion',2,'symbolSetVersion',1,
        'canvas',jsonb_build_object('x',0,'y',0,'width',400,'height',200,'fill','#FFFFFFFF'),
        'styles','{}'::jsonb,'seatingDefaults','{}'::jsonb,'textPolicy',jsonb_build_object('language','und','direction','auto'),
        'nodes',jsonb_build_array(jsonb_build_object('id',seat_node,'kind','seat','width',40,'height',40,
          'transform',jsonb_build_object('x',40,'y',40,'rotation',0)))),
      'seatBindings',jsonb_build_array(jsonb_build_object('nodeId',seat_node,'productId',old_product,'title','A1',
        'groupNodeId',NULL,'selectionUnitId',NULL,'blocked',false,'productAssignmentMode','override')),
      'groupProducts','[]'::jsonb,'areaBindings','[]'::jsonb));
  END IF;
  d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
  response:=public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid());
  event_id:=(response#>>'{data,occasionId}')::bigint;
  EXECUTE 'RESET ROLE';
  PERFORM assert_eq((SELECT count(*) FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f
    WHERE o.id=event_id AND f->>'code'='ticket' AND (f->>'is_enabled')::boolean),
    CASE WHEN n IN (1,2,6) THEN 1 ELSE 0 END::bigint,'Ticket feature follows visible active field, case '||n);
  PERFORM assert_false((SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(o.features) f WHERE f->>'code'='schedule') FROM public.occasions o WHERE o.id=event_id),'Ticket configuration cannot inject a different feature');
  SELECT id,blueprint INTO form_id,plan_id FROM public.forms WHERE occasion=event_id ORDER BY id LIMIT 1;
  IF n=6 THEN
   PERFORM assert_true(plan_id IS NOT NULL,'Chosen plan is linked to the form');
   PERFORM assert_true((SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(o.features) f WHERE f->>'code'='blueprint' AND (f->>'is_enabled')::boolean) FROM public.occasions o WHERE o.id=event_id),'Chosen plan enables blueprint feature');
   PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.spots WHERE occasion=event_id AND blueprint=plan_id),'Chosen plan has owned inventory');
   PERFORM assert_true((public.get_occasion_sale_forms_internal(event_id)->0->>'has_availability')::boolean IS NOT NULL,'Blueprint projection is available');
   UPDATE public.forms SET is_open=true WHERE id=form_id;
   PERFORM assert_true((public.get_occasion_sale_forms_internal(event_id)->0->>'has_availability')::boolean,'Free bound seat is sellable');
   UPDATE eshop.spots SET secret=gen_random_uuid(),secret_expiration_time=now()+interval '1 hour' WHERE blueprint=plan_id;
   PERFORM assert_false((public.get_occasion_sale_forms_internal(event_id)->0->>'has_availability')::boolean,'Held seat is not advertised as sellable');
   UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL,state='black' WHERE blueprint=plan_id;
   PERFORM assert_false((public.get_occasion_sale_forms_internal(event_id)->0->>'has_availability')::boolean,'Blocked seat is not advertised as sellable');

  ELSE
   PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.blueprints WHERE occasion=event_id),'No plan choice creates no blueprint');
   PERFORM assert_false((SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(o.features) f WHERE f->>'code'='blueprint') FROM public.occasions o WHERE o.id=event_id),'Dormant plan does not enable blueprint feature');
  END IF;
 END LOOP;
 -- An explicitly selected but empty plan cannot silently finalize without it.
 SELECT count(*) INTO before_count FROM public.occasions WHERE unit=unit_id;
 EXECUTE 'SET LOCAL ROLE authenticated';
 draft:=gen_random_uuid(); d:=public.create_occasion_setup_draft(draft,unit_id);
 payload:=d->'data'||jsonb_build_object('title','Empty plan','start',now(),'end',now()+interval '1 day','reviewConfirmed',true,'blueprintMode','Nový','blueprintObjects','[]'::jsonb);
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 BEGIN PERFORM public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid()); RAISE EXCEPTION 'Selected empty plan accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.occasions WHERE unit=unit_id),before_count,'Empty plan rejection is atomic');
END $$;
