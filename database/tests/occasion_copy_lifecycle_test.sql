-- test-setup: database/functions/others/delete_occasion.sql
BEGIN;
DO $$
DECLARE actor uuid; org bigint; un bigint; source bigint; copied bigint;
 command uuid:=gen_random_uuid(); job jsonb; result jsonb; pool bigint; place bigint; resource bigint;
BEGIN
 PERFORM create_user_for_test('copy_lifecycle_manager','copy_lifecycle_manager@test.local');
 actor:=get_user_id('copy_lifecycle_manager');
 INSERT INTO public.organizations(title) VALUES('Copy lifecycle') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Copy lifecycle',org) RETURNING id INTO un;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,actor,true,true);
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,data,features)
 VALUES(org,un,'Source','copy-lifecycle-'||command,now(),now()+interval '1 day',
 '{"image":"https://img.festapp.net/images/event.jpg"}',
 '[{"code":"ticket","is_enabled":true,"background":"https://img.festapp.net/images/ticket.jpg"}]') RETURNING id INTO source;
 INSERT INTO public.scanner_settings(occasion_id,config) VALUES(source,public.scanner_default_settings_internal(source));
 INSERT INTO public.inventory_pools(title,occasion,sellable_capacity) VALUES('Capacity',source,17) RETURNING id INTO pool;
 INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES(pool,'Admission');
 INSERT INTO public.places(occasion,unit,title) VALUES(source,un,'Hall') RETURNING id INTO place;
 INSERT INTO public.resources(title,inventory_pool,occasion,unit,place) VALUES('Chair',pool,source,un,place) RETURNING id INTO resource;
 INSERT INTO public.resource_slots(resource,title) VALUES(resource,'Seat');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 result:=public.start_occasion_lifecycle(un,org,source,'copy',command);
 copied:=(result#>>'{data,occasionId}')::bigint;
 PERFORM assert_true(copied IS NOT NULL,'copy committed');
 job:=public.get_occasion_media_job(command);
 PERFORM assert_eq(jsonb_array_length(job->'media'),2,'cover and ticket background need copying');
 PERFORM public.record_occasion_media_step(command,0);
 PERFORM public.record_occasion_media_step(command,1);
 job:=public.finish_occasion_media_job(command);
 PERFORM assert_eq(job->>'state','complete','media references applied');
 PERFORM assert_true((SELECT data->>'image' LIKE 'https://img.festapp.net/images/lifecycle/%' FROM public.occasions WHERE id=copied),'cover points to copied object');
 result:=public.start_occasion_lifecycle(un,org,copied,'delete',gen_random_uuid());
 PERFORM assert_eq(result->>'code','200','copied occasion can be deleted');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=copied),'copy removed');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.resources WHERE id=resource),'source inventory retained');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.occasions WHERE id=source),'source retained');
 -- A failed/interrupted media copy must not prevent deleting the committed event.
 command:=gen_random_uuid();
 result:=public.start_occasion_lifecycle(un,org,source,'copy',command);
 copied:=(result#>>'{data,occasionId}')::bigint;
 PERFORM assert_eq(result#>>'{data,mediaJob,state}','pending','second copy has unfinished media');
 result:=public.start_occasion_lifecycle(un,org,copied,'delete',gen_random_uuid());
 PERFORM assert_eq(result->>'code','200','pending-media copy can be deleted');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.inventory_pools WHERE occasion=copied),'copied inventory removed');
 -- Existing orders continue to block deletion, before any inventory is removed.
 INSERT INTO eshop.orders(occasion,order_symbol,order_sequence) VALUES(source,'1A2C3E4F5G',1);
 BEGIN
  PERFORM public.start_occasion_lifecycle(un,org,source,'delete',gen_random_uuid());
  RAISE EXCEPTION 'deletion accepted an occasion containing orders';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'Cannot delete occasion % because it contains orders%' THEN RAISE; END IF;
 END;
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.resources WHERE id=resource),'blocked deletion preserves inventory');
END $$;
ROLLBACK;
