DO $$
DECLARE actor uuid; org bigint; un bigint; own_occ bigint; other_occ bigint; own_key text:=gen_random_uuid()||'.png'; foreign_key text:=gen_random_uuid()||'.png'; bucket text; changed bigint;
BEGIN
 PERFORM create_user_for_test('storage-abuse','storage-abuse@example.invalid');actor:=get_user_id('storage-abuse');
 INSERT INTO public.organizations(title) VALUES('Storage fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Storage Unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time)
 VALUES('Own storage fixture',gen_random_uuid()::text,org,un,now(),now()+interval '1 day') RETURNING id INTO own_occ;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time)
 VALUES('Foreign storage fixture',gen_random_uuid()::text,org,un,now(),now()+interval '1 day') RETURNING id INTO other_occ;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view) VALUES(own_occ,actor,true,true);
 INSERT INTO storage.buckets(id,name,public) VALUES('public-files','public-files',true),('images-temp','images-temp',false),('editor-files','editor-files',false) ON CONFLICT DO NOTHING;
 INSERT INTO storage.objects(bucket_id,name) VALUES('public-files',own_key),('public-files',foreign_key);
 INSERT INTO public.images(link,occasion) VALUES('https://api.festapp.net/storage/v1/object/public/public-files/'||own_key,own_occ),('https://api.festapp.net/storage/v1/object/public/public-files/'||foreign_key,other_occ);
 -- A forged second owner record must not authorize deleting the foreign file.
 INSERT INTO public.images(link,occasion) VALUES('https://api.festapp.net/storage/v1/object/public/public-files/'||foreign_key,own_occ);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 -- Simulate a previously deployed permissive Storage policy. The new boundary
 -- must still reject writes and foreign metadata even if another policy grants.
 EXECUTE 'CREATE POLICY abuse_storage_legacy_fixture ON storage.objects AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true)';
 EXECUTE 'SET LOCAL ROLE authenticated';
 -- The Storage API sets this guard before deleting metadata. Keep RLS active.
 PERFORM set_config('storage.allow_delete_query','true',true);
 FOREACH bucket IN ARRAY ARRAY['public-files','images-temp','editor-files'] LOOP
  BEGIN
   INSERT INTO storage.objects(bucket_id,name) VALUES(bucket,gen_random_uuid()||'.png');
   RAISE EXCEPTION 'legacy Storage writer still reachable: %',bucket;
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 UPDATE storage.objects SET name=own_key||'-copied' WHERE bucket_id='public-files' AND name=own_key;
 GET DIAGNOSTICS changed=ROW_COUNT;
 PERFORM assert_eq(changed,0::bigint,'legacy move/update cannot bypass the canonical writer');
 PERFORM assert_false(public.can_delete_legacy_image_v1(foreign_key),'forged owned record cannot authorize a foreign object');
 DELETE FROM storage.objects WHERE bucket_id='public-files' AND name=foreign_key;
 GET DIAGNOSTICS changed=ROW_COUNT;
 PERFORM assert_eq(changed,0::bigint,'foreign legacy delete rejected');
 PERFORM assert_true(public.can_delete_legacy_image_v1(own_key),'real owner retains historical cleanup');
 DELETE FROM storage.objects WHERE bucket_id='public-files' AND name=own_key;
 GET DIAGNOSTICS changed=ROW_COUNT;
 PERFORM assert_eq(changed,1::bigint,'owned historical delete succeeds');
 EXECUTE 'RESET ROLE';
 PERFORM assert_true(EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='public-files' AND name=foreign_key),'foreign object preserved');
END $$;
