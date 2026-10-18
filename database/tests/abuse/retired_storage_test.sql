-- A permissive historical policy must not reopen the retired file service.
DO $$
DECLARE client text;
BEGIN
 PERFORM assert_true(to_regprocedure('public.can_delete_legacy_image_v1(text)') IS NULL,'legacy deletion authority is retired');
 EXECUTE 'CREATE POLICY retired_storage_fixture ON storage.objects AS PERMISSIVE FOR ALL TO anon,authenticated,service_role USING (true) WITH CHECK (true)';
 FOREACH client IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM assert_false(has_table_privilege(client,'storage.objects','SELECT,INSERT,UPDATE,DELETE'),'application role cannot use retired objects');
  PERFORM assert_false(has_table_privilege(client,'storage.buckets','SELECT,INSERT,UPDATE,DELETE'),'application role cannot use retired buckets');
  EXECUTE format('SET LOCAL ROLE %I',client);
  BEGIN
   PERFORM 1 FROM storage.objects LIMIT 1;
   RAISE EXCEPTION 'retired Storage metadata remains accessible to %',client;
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  EXECUTE 'RESET ROLE';
 END LOOP;
END $$;
