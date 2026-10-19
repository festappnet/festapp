-- Actual disposable full-backend integration. psql -v fixture_form=<manifest.form>.
BEGIN;
-- Rollback-only synthetic scenarios use the canonical reviewed test ceiling.
UPDATE public.abuse_policy_rules SET base_limit=hard_cap WHERE budget_key IN ('occasion.creation','occasion.draft');
SELECT set_config('festapp.fixture_form',:'fixture_form',true);
DO $$
DECLARE fid bigint:=current_setting('festapp.fixture_form')::bigint; source_occ bigint; un bigint; actor uuid; source jsonb; plan jsonb; draft jsonb; payload jsonb; response jsonb; replay jsonb;
 new_occ bigint; new_bp bigint; source_bp bigint; old_product bigint; new_product bigint; old_context bigint; new_context bigint; cmd uuid:=gen_random_uuid(); draft_id uuid:=gen_random_uuid();
BEGIN
 IF (SELECT project FROM festapp_test_support.disposable_environment WHERE singleton) IS DISTINCT FROM 'festapp-blueprint-b-e2e-20261019' THEN RAISE EXCEPTION 'owned full fixture required'; END IF;
 SELECT f.occasion,o.unit,f.blueprint INTO source_occ,un,source_bp FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=fid;
 SELECT "user" INTO actor FROM public.occasion_users WHERE occasion=source_occ AND is_editor ORDER BY "user" LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true); PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SELECT item INTO source FROM jsonb_array_elements(public.get_occasion_setup_sources(un)) item WHERE (item#>>'{occasion,id}')::bigint=source_occ;
 SELECT item->'blueprintLayoutDraft' INTO plan FROM jsonb_array_elements(source->'blueprints') item WHERE (item->>'id')::bigint=source_bp;
 IF plan IS NULL OR plan::text LIKE '%spotId%' OR plan::text LIKE '%secret%' OR plan::text LIKE '%Synthetic private fixture note%' THEN RAISE EXCEPTION 'setup source leaked private state or omitted V2'; END IF;
 draft:=public.create_occasion_setup_draft(draft_id,un);
 payload:=jsonb_build_object('title','V2 setup test','link','v2-setup-'||gen_random_uuid(),'start',now()+interval '1 day','end',now()+interval '2 days',
   'sourceId',source_occ,'formEnabled',true,'formDraft',source->'forms'->0,'blueprintLayoutDraft',plan,'reviewConfirmed',true);
 draft:=public.save_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,payload,5);
 IF public.get_occasion_setup_blueprint_resources(draft_id)#>'{resources,fonts}' IS NULL THEN RAISE EXCEPTION 'safe draft resources missing'; END IF;
 IF public.admit_occasion_setup_blueprint_resources_v1(draft_id,128)->'abuseLimits' IS NULL THEN RAISE EXCEPTION 'draft preview admission missing'; END IF;
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN PERFORM public.get_occasion_setup_blueprint_resources(draft_id); RAISE EXCEPTION 'anonymous draft resources allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 response:=public.finalize_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,cmd);
 IF response->>'status'<>'applied' THEN RAISE EXCEPTION 'setup finalization failed: %',response; END IF;
 new_occ:=(response#>>'{data,occasionId}')::bigint;
 SELECT blueprint INTO new_bp FROM public.forms WHERE occasion=new_occ ORDER BY id LIMIT 1;
 IF new_bp IS NULL OR (SELECT layout_revision FROM eshop.blueprints WHERE id=new_bp)<>1 THEN RAISE EXCEPTION 'setup bypassed aggregate owner'; END IF;
 IF (SELECT count(*) FROM eshop.blueprint_seat_bindings WHERE blueprint=new_bp)<>jsonb_array_length(plan->'seatBindings') THEN RAISE EXCEPTION 'setup lost seat bindings'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings a JOIN eshop.blueprint_seat_bindings b ON a.spot=b.spot OR a.node_id=b.node_id WHERE a.blueprint=source_bp AND b.blueprint=new_bp) THEN RAISE EXCEPTION 'copy reused node/spot identity'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE blueprint=new_bp AND (secret IS NOT NULL OR order_product_ticket IS NOT NULL)) THEN RAISE EXCEPTION 'setup copied live bookings'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings a JOIN eshop.spots s ON s.id=a.spot JOIN eshop.products p ON p.id=s.product WHERE a.blueprint=new_bp AND p.occasion<>new_occ) THEN RAISE EXCEPTION 'setup failed product remap'; END IF;
 SELECT inventory_context,product INTO old_context,old_product FROM eshop.blueprint_area_bindings WHERE blueprint=source_bp LIMIT 1;
 SELECT inventory_context,product INTO new_context,new_product FROM eshop.blueprint_area_bindings WHERE blueprint=new_bp LIMIT 1;
 IF old_context=new_context OR old_product=new_product OR new_context IS NULL THEN RAISE EXCEPTION 'standing context/product not remapped'; END IF;
 IF (SELECT ip.occasion FROM public.inventory_contexts ic JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool WHERE ic.id=new_context)<>new_occ THEN RAISE EXCEPTION 'standing context foreign'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.spots s JOIN public.inventory_contexts ic ON ic.id=s.inventory_context WHERE ic.id=new_context AND (s.secret IS NOT NULL OR s.order_product_ticket IS NOT NULL)) THEN RAISE EXCEPTION 'standing copied reservations'; END IF;
 replay:=public.finalize_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,cmd);
 IF replay<>response THEN RAISE EXCEPTION 'setup finalize replay changed receipt'; END IF;
 RAISE NOTICE 'V2 setup source/save/resources/quota/finalize/replay + new node/spot/product/context identity PASS';
END $$;
ROLLBACK;

BEGIN;
-- Rollback-only synthetic scenarios use the canonical reviewed test ceiling.
UPDATE public.abuse_policy_rules SET base_limit=hard_cap WHERE budget_key IN ('occasion.creation','occasion.draft');
SELECT set_config('festapp.fixture_form',:'fixture_form',true);
DO $$
DECLARE fid bigint:=current_setting('festapp.fixture_form')::bigint; source_occ bigint; un bigint; actor uuid; source jsonb; plan jsonb; draft jsonb; payload jsonb; response jsonb;
 draft_id uuid:=gen_random_uuid(); invalid_id uuid:=gen_random_uuid(); new_occ bigint; new_bp bigint; context_id bigint; count_before bigint; bad_plan jsonb;
BEGIN
 SELECT f.occasion,o.unit INTO source_occ,un FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=fid;
 SELECT "user" INTO actor FROM public.occasion_users WHERE occasion=source_occ AND is_editor ORDER BY "user" LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true); PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SELECT item INTO source FROM jsonb_array_elements(public.get_occasion_setup_sources(un)) item WHERE (item#>>'{occasion,id}')::bigint=source_occ;
 SELECT item->'blueprintLayoutDraft' INTO plan FROM jsonb_array_elements(source->'blueprints') item WHERE item->'blueprintLayoutDraft' IS NOT NULL LIMIT 1;
 plan:=jsonb_set(plan,'{areaBindings}',(SELECT jsonb_agg((a-'inventoryContextId')||jsonb_build_object('capacity',3)) FROM jsonb_array_elements(plan->'areaBindings') a));
 payload:=jsonb_build_object('title','V2 new setup test','link','v2-new-setup-'||gen_random_uuid(),'start',now()+interval '1 day','end',now()+interval '2 days',
   'formEnabled',true,'formDraft',(source->'forms'->0)-'link','blueprintLayoutDraft',plan,'reviewConfirmed',true);
 draft:=public.create_occasion_setup_draft(draft_id,un);
 draft:=public.save_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,payload,5);
 response:=public.finalize_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,gen_random_uuid());
 new_occ:=(response#>>'{data,occasionId}')::bigint;
 SELECT blueprint INTO new_bp FROM public.forms WHERE occasion=new_occ ORDER BY id LIMIT 1;
 SELECT inventory_context INTO context_id FROM eshop.blueprint_area_bindings WHERE blueprint=new_bp LIMIT 1;
 IF (SELECT count(*) FROM eshop.spots WHERE inventory_context=context_id)<>3 OR EXISTS(SELECT 1 FROM eshop.spots WHERE inventory_context=context_id AND (secret IS NOT NULL OR order_product_ticket IS NOT NULL)) THEN RAISE EXCEPTION 'new explicit area did not use normal empty capacity'; END IF;
 -- Invalid finalization must not leave a partial event, product or inventory.
 SELECT count(*) INTO count_before FROM public.occasions;
 bad_plan:=jsonb_set(plan,'{areaBindings,0,capacity}','-1');
 payload:=payload||jsonb_build_object('title','Invalid V2 setup test','link','invalid-v2-setup-'||gen_random_uuid(),'blueprintLayoutDraft',bad_plan);
 draft:=public.create_occasion_setup_draft(invalid_id,un);
 draft:=public.save_occasion_setup_draft(invalid_id,(draft->>'revision')::bigint,payload,5);
 BEGIN
  PERFORM public.finalize_occasion_setup_draft(invalid_id,(draft->>'revision')::bigint,gen_random_uuid());
  RAISE EXCEPTION 'negative area accepted';
 EXCEPTION WHEN check_violation THEN IF SQLERRM<>'BLUEPRINT_SETUP_AREA_CAPACITY_REQUIRED' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM public.occasions)<>count_before OR EXISTS(SELECT 1 FROM public.occasion_setup_drafts WHERE id=invalid_id AND data ? 'finalizedOccasion') THEN RAISE EXCEPTION 'failed setup left partial aggregate'; END IF;
 RAISE NOTICE 'V2 fresh setup explicit normal inventory capacity and rejected-finalize rollback PASS';
END $$;
ROLLBACK;
