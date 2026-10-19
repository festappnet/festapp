-- Both canonical copy callers reuse one empty resource/slot configuration owner.
BEGIN;
-- Rollback-only synthetic scenarios use the canonical reviewed test ceiling.
UPDATE public.abuse_policy_rules SET base_limit=hard_cap WHERE budget_key IN ('occasion.creation','occasion.draft');
SELECT set_config('festapp.fixture_form',:'fixture_form',true);
DO $$
DECLARE f public.forms; actor uuid; un bigint; product_id bigint; pool_id bigint; context_id bigint; resource_id bigint; slot_id bigint; i integer;
 source jsonb; plan jsonb; draft jsonb; response jsonb; target bigint; target_context bigint; copied bigint; draft_id uuid:=gen_random_uuid();
BEGIN
 IF (SELECT project FROM festapp_test_support.disposable_environment WHERE singleton) IS DISTINCT FROM 'festapp-blueprint-b-e2e-20261019' THEN RAISE EXCEPTION 'owned fixture required'; END IF;
 SELECT * INTO f FROM public.forms WHERE id=current_setting('festapp.fixture_form')::bigint;
 SELECT unit INTO un FROM public.occasions WHERE id=f.occasion;
 SELECT "user" INTO actor FROM public.occasion_users WHERE occasion=f.occasion AND is_editor ORDER BY "user" LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SELECT product INTO product_id FROM eshop.blueprint_area_bindings WHERE blueprint=f.blueprint LIMIT 1;
 INSERT INTO public.inventory_pools(occasion,title,type,data) VALUES(f.occasion,'Named setup regression','generic','{}') RETURNING id INTO pool_id;
 INSERT INTO public.inventory_contexts(inventory_pool,title,data) VALUES(pool_id,'Named setup context','{}') RETURNING id INTO context_id;
 INSERT INTO public.resources(occasion,unit,inventory_pool,title,capacity,booking_rules,data)
 VALUES(f.occasion,un,pool_id,'Named setup resource',2,'{}','{"regression":"named"}') RETURNING id INTO resource_id;
 FOR i IN 1..2 LOOP
  INSERT INTO public.resource_slots(resource,title,data) VALUES(resource_id,'Named slot '||i,jsonb_build_object('position',i)) RETURNING id INTO slot_id;
  INSERT INTO eshop.spots(occasion,inventory_context,resource,resource_slot,title,secret,secret_expiration_time)
   VALUES(f.occasion,context_id,resource_id,slot_id,'Named physical '||i,gen_random_uuid(),now()+interval '5 minutes');
 END LOOP;
 INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES(product_id,context_id,1);
 SELECT item INTO source FROM jsonb_array_elements(public.get_occasion_setup_sources(un)) item WHERE (item#>>'{occasion,id}')::bigint=f.occasion;
 SELECT item->'blueprintLayoutDraft' INTO plan FROM jsonb_array_elements(source->'blueprints') item WHERE (item->>'id')::bigint=f.blueprint;
 draft:=public.create_occasion_setup_draft(draft_id,un);
 draft:=public.save_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,jsonb_build_object('title','Named setup regression',
  'link','named-setup-'||gen_random_uuid(),'sourceId',f.occasion,'start',now()+interval '1 day','end',now()+interval '2 days',
  'formEnabled',true,'formDraft',source->'forms'->0,'blueprintLayoutDraft',plan,'reviewConfirmed',true),5);
 response:=public.finalize_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,gen_random_uuid());
 target:=(response#>>'{data,occasionId}')::bigint;
 SELECT ic.id INTO target_context FROM public.inventory_contexts ic JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool WHERE ip.occasion=target AND ip.title='Named setup regression';
 IF target_context IS NULL OR target_context=context_id THEN RAISE EXCEPTION 'named context was not cloned'; END IF;
 IF (SELECT count(*) FROM public.resources WHERE occasion=target AND title='Named setup resource' AND capacity=2)<>1
  OR (SELECT count(*) FROM public.resource_slots rs JOIN public.resources r ON r.id=rs.resource WHERE r.occasion=target AND r.title='Named setup resource')<>2
  OR (SELECT count(*) FROM eshop.spots WHERE inventory_context=target_context AND resource IS NOT NULL AND resource_slot IS NOT NULL)<>2 THEN RAISE EXCEPTION 'named setup physical configuration lost'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE inventory_context=target_context AND (secret IS NOT NULL OR order_product_ticket IS NOT NULL)) THEN RAISE EXCEPTION 'named setup copied allocations'; END IF;
 IF NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts pic JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=target AND pic.inventory_context=target_context AND pic.quantity=1) THEN RAISE EXCEPTION 'named PIC requirement lost'; END IF;
 -- Existing full occasion copy must use the same extraction without changing
 -- its slots, metadata, associations or empty reservation policy.
 copied:=public.duplicate_occasion_internal_v1(f.occasion,un,'cs');
 IF (SELECT count(*) FROM public.resources WHERE occasion=copied AND title='Named setup resource' AND capacity=2)<>1
  OR (SELECT count(*) FROM public.resource_slots rs JOIN public.resources r ON r.id=rs.resource WHERE r.occasion=copied AND r.title='Named setup resource' AND rs.data ? 'position')<>2
  OR (SELECT count(*) FROM eshop.spots s JOIN public.inventory_contexts ic ON ic.id=s.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool WHERE ip.occasion=copied AND ip.title='Named setup regression' AND s.resource_slot IS NOT NULL)<>2 THEN RAISE EXCEPTION 'existing duplicate slot configuration regressed'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE occasion=copied AND (secret IS NOT NULL OR order_product_ticket IS NOT NULL)) THEN RAISE EXCEPTION 'existing duplicate copied live state'; END IF;
 RAISE NOTICE 'named resource capacity2+slots exact physical copy through setup and existing duplicate owner PASS';
END $$;
ROLLBACK;
