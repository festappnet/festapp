-- Real authorized saves/finalization, rollback-only test harness, no provider I/O.
DO $$
DECLARE actor uuid; org bigint; target bigint; d jsonb; payload jsonb; result jsonb; event_id bigint;
 draft_id uuid:=gen_random_uuid(); mode text; f jsonb; before_messages bigint; paid_order bigint;
BEGIN
 SELECT "user",unit INTO actor,target FROM public.unit_users WHERE is_editor AND is_manager LIMIT 1;
 SELECT organization INTO org FROM public.units WHERE id=target;
 IF actor IS NULL THEN RAISE EXCEPTION 'Needs isolated seeded editor'; END IF;
 IF public.ticket_delivery_mode('{}')<>'pdf_attachment' OR public.ticket_delivery_mode(NULL)<>'pdf_attachment' THEN RAISE EXCEPTION 'Missing default'; END IF;
 FOREACH mode IN ARRAY ARRAY['pdf_attachment','inline_qr','both'] LOOP
  f:=jsonb_build_object('code','ticket','is_enabled',true,'delivery_mode',mode);
  IF public.ticket_delivery_mode(f)<>mode THEN RAISE EXCEPTION 'Mode mismatch'; END IF;
  IF public.merge_ticket_layout_features(jsonb_build_array(f),'[{"code":"ticket","is_enabled":true}]')->0->>'delivery_mode'<>mode THEN
   RAISE EXCEPTION 'Old client reset mode'; END IF;
 END LOOP;
 BEGIN PERFORM public.ticket_delivery_mode('{"delivery_mode":null}'); RAISE EXCEPTION 'null accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.ticket_delivery_mode('{"delivery_mode":"bad"}'); RAISE EXCEPTION 'bad mode accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.create_occasion_setup_draft(draft_id,target);
 payload:=jsonb_build_object('title','Inline concert','link','inline-'||draft_id,
  'start',now()+interval '20 days','end',now()+interval '21 days','reviewConfirmed',true,'formEnabled',true,
  'blueprintMode','none','saleMode','preparation',
  'ticketDraft','{"code":"ticket","is_enabled":true,"delivery_mode":"inline_qr"}'::jsonb,
  'formDraft',jsonb_build_object('title','Registration','link','','fields','[{"type":"ticket","is_hidden":false,"is_required":true,"order":0}]'::jsonb,
   'data',jsonb_build_object('design',jsonb_build_object('primary_color','#112233','secondary_color','#445566','font_family','Roboto','background_mode','solid'))),
  'appearance','{"primary":"112233","secondary":"445566","fontFamily":"Roboto","gradient":false,"id":"custom"}'::jsonb);
 d:=public.save_occasion_setup_draft(draft_id,(d->>'revision')::bigint,payload,5);
 result:=public.get_occasion_setup_email_preview(draft_id,(d->>'revision')::bigint,'order_tickets',NULL,NULL);
 IF result->>'deliveryMode'<>'inline_qr' OR result->>'messageType'<>'order_tickets' THEN RAISE EXCEPTION 'Preview lost mode'; END IF;
 BEGIN PERFORM public.get_occasion_setup_email_preview(draft_id,(d->>'revision')::bigint+1,'order_tickets',NULL,NULL);
  RAISE EXCEPTION 'Stale preview accepted'; EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 BEGIN PERFORM public.save_occasion_setup_draft(draft_id,(d->>'revision')::bigint,jsonb_set(payload,'{ticketDraft,delivery_mode}','"bad"'),5);
  RAISE EXCEPTION 'Invalid mode draft accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 result:=public.finalize_occasion_setup_draft(draft_id,(d->>'revision')::bigint,gen_random_uuid());
 event_id:=(result#>>'{data,occasionId}')::bigint;
 EXECUTE 'RESET ROLE';
 IF NOT EXISTS(SELECT 1 FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) feature
   WHERE o.id=event_id AND feature->>'delivery_mode'='inline_qr' AND NOT (feature ? 'layout')) THEN RAISE EXCEPTION 'Inline finalization needs PDF'; END IF;
 UPDATE public.occasions SET is_order_synchronization_enabled=true WHERE id=event_id;
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,price,currency_code,data)
 VALUES(event_id,public.next_order_sequence(event_id),public.generate_order_symbol(),'paid',100,'CZK','{"email":"settings@example.invalid"}') RETURNING id INTO paid_order;
 SELECT count(*) INTO before_messages FROM public.email_messages;
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.get_occasion_setup_email_preview(NULL,NULL,'order_tickets',event_id,'both');
 IF result->>'deliveryMode'<>'both' THEN RAISE EXCEPTION 'Unsaved override ignored'; END IF;
 PERFORM public.update_occasion_203(jsonb_build_object('id',event_id,'features',jsonb_build_array(jsonb_build_object('code','ticket','is_enabled',true,'delivery_mode','both'))));
 EXECUTE 'RESET ROLE';
 IF (SELECT count(*) FROM public.email_messages)<>before_messages THEN RAISE EXCEPTION 'Setting enqueued email'; END IF;
 UPDATE public.occasions SET features='[]' WHERE id=event_id;
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.get_occasion_setup_email_preview(NULL,NULL,'order_tickets',event_id,'inline_qr');
 IF (result->>'ticketsEnabled')::boolean THEN RAISE EXCEPTION 'Missing ticket feature enabled preview'; END IF;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.get_occasion_setup_email_preview(NULL,NULL,'order_tickets',event_id,NULL);
  RAISE EXCEPTION 'Foreign occasion accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
END $$;
