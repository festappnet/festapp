-- Canonical source: database/functions/account_deletion/retire_storage.sql
-- Apply only after canonical reference, new backup/restore and producer gates.
-- Historical Storage metadata remains readable to the isolated v1 restore owner;
-- application roles have no live file-storage contract.
-- Execute as the protected database owner supabase_admin. PostgreSQL grants
-- from the Storage owner cannot be revoked by the non-superuser postgres role.
DO $$ BEGIN
 IF current_setting('is_superuser') <> 'on' THEN
  RAISE EXCEPTION 'Storage retirement requires the protected database administrator';
 END IF;
END $$;
DROP POLICY IF EXISTS image_storage_write_cutover_insert ON storage.objects;
DROP POLICY IF EXISTS image_storage_write_cutover_update ON storage.objects;
DROP POLICY IF EXISTS image_storage_legacy_select ON storage.objects;
DROP POLICY IF EXISTS image_storage_legacy_delete ON storage.objects;
DROP POLICY IF EXISTS image_storage_listing_owner ON storage.objects;
DROP POLICY IF EXISTS image_storage_no_anonymous_listing ON storage.objects;
DROP POLICY IF EXISTS image_storage_delete_owner ON storage.objects;
DROP FUNCTION IF EXISTS public.can_delete_legacy_image_v1(text);
REVOKE ALL ON storage.objects,storage.buckets FROM PUBLIC,anon,authenticated,service_role;
DO $$
DECLARE client text;
BEGIN
 FOREACH client IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  IF has_table_privilege(client,'storage.objects','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     OR has_table_privilege(client,'storage.buckets','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
   RAISE EXCEPTION 'Storage retirement left application privileges for %',client;
  END IF;
 END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
