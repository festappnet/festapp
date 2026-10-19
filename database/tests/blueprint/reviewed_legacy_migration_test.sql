BEGIN;
SELECT set_config('festapp.fixture_form',:'fixture_form',true);
DO $$
DECLARE f public.forms; actor uuid; bid bigint; ids bigint[]; ordered_id bigint; used_id bigint; held_id bigint; held_secret uuid:=gen_random_uuid(); grp uuid; node uuid;
 old_objects jsonb:='[]'; nodes jsonb:='[]'; changes jsonb:='[]'; spot eshop.spots; i integer:=0; source_text text; source_sha text; request jsonb; bad jsonb;
 response jsonb; replay jsonb; command_id uuid:=gen_random_uuid(); before_spots jsonb; after_spots jsonb; before_tickets jsonb; before_payments jsonb;
BEGIN
 IF (SELECT project FROM festapp_test_support.disposable_environment WHERE singleton) IS DISTINCT FROM 'festapp-blueprint-b-e2e-20261019' THEN RAISE EXCEPTION 'owned fixture required'; END IF;
 SELECT * INTO f FROM public.forms WHERE id=current_setting('festapp.fixture_form')::bigint;
 SELECT "user" INTO actor FROM public.occasion_users WHERE occasion=f.occasion AND is_editor ORDER BY "user" LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SELECT s.id INTO used_id FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket JOIN eshop.tickets t ON t.id=opt.ticket WHERE s.blueprint=f.blueprint AND t.state='used' ORDER BY s.id LIMIT 1;
 SELECT s.id INTO ordered_id FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket JOIN eshop.tickets t ON t.id=opt.ticket WHERE s.blueprint=f.blueprint AND t.state<>'used' ORDER BY s.id LIMIT 1;
 SELECT id INTO held_id FROM eshop.spots WHERE blueprint=f.blueprint AND order_product_ticket IS NULL AND product IS NOT NULL AND id NOT IN(used_id,ordered_id) ORDER BY id LIMIT 1;
 IF used_id IS NULL OR ordered_id IS NULL OR held_id IS NULL THEN RAISE EXCEPTION 'ordered used free source required'; END IF;
 ids:=ARRAY[used_id,ordered_id,held_id];
 INSERT INTO eshop.blueprints(occasion,organization,title,configuration,groups) SELECT f.occasion,organization,'Reviewed migration regression','{"dimensions":{"width":8,"height":4}}','[{"id":7,"title":"Legacy reviewed group"}]' FROM public.occasions WHERE id=f.occasion RETURNING id INTO bid;
 DELETE FROM eshop.blueprint_seat_bindings binding WHERE binding.spot=ANY(ids);
 UPDATE eshop.spots SET blueprint=bid WHERE id=ANY(ids);
 UPDATE eshop.spots SET title=NULL,secret=held_secret,secret_expiration_time=statement_timestamp()+interval '5 minutes' WHERE id=held_id;
 grp:=extensions.uuid_generate_v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8',format('festapp:occasion:%s:blueprint:%s:group:7',f.occasion,bid));
 nodes:=jsonb_build_array(jsonb_build_object('id',grp,'kind','group','label','Legacy reviewed group','transform',jsonb_build_object('x',0,'y',0,'rotation',0),'width',200,'height',100));
 FOREACH i IN ARRAY ARRAY[1,2,3] LOOP
  SELECT * INTO spot FROM eshop.spots WHERE id=ids[i];
  node:=extensions.uuid_generate_v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8',format('festapp:occasion:%s:blueprint:%s:spot:%s',f.occasion,bid,spot.id));
  old_objects:=old_objects||jsonb_build_array(jsonb_build_object('id',spot.id,'type','spot','group',7,'x',i-1,'y',0));
  nodes:=nodes||jsonb_build_array(jsonb_build_object('id',node,'kind','seat','parentId',grp,'label',coalesce(spot.title,''),'transform',jsonb_build_object('x',(i-1)*48+24,'y',24,'rotation',0),'width',36,'height',36));
  changes:=changes||jsonb_build_array(jsonb_build_object('nodeId',node,'spotId',spot.id,'productId',spot.product,'title',coalesce(spot.title,''),'groupNodeId',grp,'selectionUnitId',NULL,'blocked',coalesce(spot.state='black',false),'operation','upsert'));
 END LOOP;
 UPDATE eshop.blueprints SET objects=old_objects WHERE id=bid;
 source_text:=public.blueprint_legacy_migration_source_internal(bid)::text;source_sha:=encode(extensions.digest(convert_to(source_text,'UTF8'),'sha256'),'hex');
 request:=jsonb_build_object('id',bid,'occasion',f.occasion,'organization',(SELECT organization FROM public.occasions WHERE id=f.occasion),'title','Reviewed migration regression','expected_layout_revision',0,
  'layout',jsonb_build_object('schemaVersion',1,'symbolSetVersion',1,'canvas',jsonb_build_object('x',0,'y',0,'width',400,'height',200,'fill','#FFFFFFFF'),'defaultTextStyle',jsonb_build_object('fontId','builtin:futura-pt-book:571b3803a43928d59f695acb37e73c9dc89666f5d541183e2b53c19c8986ab44','size',24,'color','#222222FF'),'nodes',nodes),'seatChanges',changes,'groupProductChanges','[]'::jsonb,'areaBindingChanges','[]'::jsonb);
 -- Live reservation churn after review is deliberately outside its hash.
 UPDATE eshop.spots SET secret=gen_random_uuid(),secret_expiration_time=statement_timestamp()+interval '7 minutes' WHERE id=held_id;
 SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) INTO before_spots FROM eshop.spots s WHERE s.id=ANY(ids);
 SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) INTO before_tickets FROM eshop.tickets t WHERE t.id IN(SELECT opt.ticket FROM eshop.order_product_ticket opt JOIN eshop.spots s ON s.order_product_ticket=opt.id WHERE s.id=ANY(ids));
 SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) INTO before_payments FROM eshop.payment_info p WHERE p.id IN(SELECT o.payment_info FROM eshop.orders o JOIN eshop.order_product_ticket opt ON opt."order"=o.id JOIN eshop.spots s ON s.order_product_ticket=opt.id WHERE s.id=ANY(ids));
 BEGIN PERFORM public.migrate_blueprint_layout_reviewed_internal(source_text,repeat('0',64),request,gen_random_uuid());RAISE EXCEPTION 'wrong source hash accepted';EXCEPTION WHEN check_violation THEN IF SQLERRM<>'BLUEPRINT_MIGRATION_SOURCE_HASH_MISMATCH' THEN RAISE;END IF;END;
 BEGIN
  UPDATE eshop.blueprints SET objects=jsonb_set(objects,'{0,x}','99') WHERE id=bid;
  PERFORM public.migrate_blueprint_layout_reviewed_internal(source_text,source_sha,request,gen_random_uuid());
  RAISE EXCEPTION 'stale geometry review accepted';
 EXCEPTION WHEN check_violation THEN IF SQLERRM<>'BLUEPRINT_MIGRATION_REVIEW_STALE' THEN RAISE;END IF;END;
 bad:=jsonb_set(request,'{seatChanges,0,groupNodeId}',to_jsonb(gen_random_uuid()));
 BEGIN PERFORM public.migrate_blueprint_layout_reviewed_internal(source_text,source_sha,bad,gen_random_uuid());RAISE EXCEPTION 'group mapping changed';EXCEPTION WHEN check_violation THEN IF SQLERRM<>'BLUEPRINT_MIGRATION_GROUP_MAPPING_CHANGED' THEN RAISE;END IF;END;
 bad:=jsonb_set(request,'{seatChanges,1,title}','"Changed protected title"');
 BEGIN PERFORM public.migrate_blueprint_layout_reviewed_internal(source_text,source_sha,bad,gen_random_uuid());RAISE EXCEPTION 'protected facts changed';EXCEPTION WHEN check_violation THEN IF SQLERRM<>'BLUEPRINT_MIGRATION_SPOT_FACTS_CHANGED' THEN RAISE;END IF;END;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings WHERE blueprint=bid) OR (SELECT layout IS NOT NULL FROM eshop.blueprints WHERE id=bid) THEN RAISE EXCEPTION 'rejected migration left partial bindings'; END IF;
 response:=public.migrate_blueprint_layout_reviewed_internal(source_text,source_sha,request,command_id);
 replay:=public.migrate_blueprint_layout_reviewed_internal(source_text,source_sha,request,command_id);
 IF replay<>response OR response->>'code'<>'200' OR response#>>'{data,layout_revision}'<>'1' THEN RAISE EXCEPTION 'migration/replay failed'; END IF;
 SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) INTO after_spots FROM eshop.spots s WHERE s.id=ANY(ids);
 IF after_spots IS DISTINCT FROM before_spots THEN RAISE EXCEPTION 'migration changed spot metadata/hold/ordered identity'; END IF;
 IF before_tickets IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM eshop.tickets t WHERE t.id IN(SELECT opt.ticket FROM eshop.order_product_ticket opt JOIN eshop.spots s ON s.order_product_ticket=opt.id WHERE s.id=ANY(ids))) OR before_payments IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM eshop.payment_info p WHERE p.id IN(SELECT o.payment_info FROM eshop.orders o JOIN eshop.order_product_ticket opt ON opt."order"=o.id JOIN eshop.spots s ON s.order_product_ticket=opt.id WHERE s.id=ANY(ids))) THEN RAISE EXCEPTION 'migration changed ticket/used/payment metadata'; END IF;
 IF has_function_privilege('authenticated','public.migrate_blueprint_layout_reviewed_internal(text,text,jsonb,uuid)','EXECUTE') OR has_function_privilege('service_role','public.migrate_blueprint_layout_reviewed_internal(text,text,jsonb,uuid)','EXECUTE') THEN RAISE EXCEPTION 'operational migration exposed to API roles'; END IF;
 RAISE NOTICE 'reviewed initial migration protected ordered+used+activehold exact metadata, group mapping, atomic rejects and immutable receipt replay PASS';
END $$;
ROLLBACK;
