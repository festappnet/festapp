-- Canonical sources: database/functions/security/data_security_defaults.sql

-- Discover real application owners and owners with application default ACLs.
-- Global function defaults are required: a schema REVOKE cannot undo PUBLIC EXECUTE.
DO $$
DECLARE owner_name text; schema_name text; object_kind text; t record;
BEGIN
 FOR owner_name IN
   SELECT DISTINCT r.rolname FROM pg_roles r WHERE r.oid IN (
     SELECT c.relowner FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','eshop')
     UNION SELECT p.proowner FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','eshop')
     UNION SELECT a.defaclrole FROM pg_default_acl a JOIN pg_namespace n ON n.oid=a.defaclnamespace WHERE n.nspname IN ('public','eshop'))
 LOOP
   EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC,anon,authenticated',owner_name);
   FOREACH schema_name IN ARRAY ARRAY['public','eshop'] LOOP
     FOREACH object_kind IN ARRAY ARRAY['TABLES','SEQUENCES','FUNCTIONS'] LOOP
       EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I REVOKE ALL ON %s FROM PUBLIC,anon,authenticated',owner_name,schema_name,object_kind);
     END LOOP;
   END LOOP;
 END LOOP;
 -- Vendor-managed storage: preserve service DML and ownership.
 IF (SELECT count(*) FROM pg_class c WHERE c.relnamespace='storage'::regnamespace AND c.relname IN ('buckets','objects','buckets_analytics') AND pg_get_userbyid(c.relowner)='supabase_storage_admin')<>3 THEN
   RAISE EXCEPTION 'Storage ownership/catalog mismatch; review before grant hardening';
 END IF;
 FOR t IN SELECT c.oid::regclass AS name FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='storage' AND c.relname IN ('buckets','objects','buckets_analytics') LOOP
   EXECUTE format('REVOKE TRUNCATE,REFERENCES,TRIGGER ON TABLE %s FROM PUBLIC,anon,authenticated',t.name);
 END LOOP;
END $$;
