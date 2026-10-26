-- Apply this migration as supabase_admin (extension owner), not postgres.
-- The local migration CLI may SET ROLE postgres on an admin connection.
RESET ROLE;
DO $$ BEGIN
  IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) THEN
    RAISE EXCEPTION 'Security hygiene requires the extension-owning superuser; no partial ACL repair allowed';
  END IF;
END $$;
-- RLS does not protect TRUNCATE. No application client owns this privilege.
DO $$
DECLARE t record; f record;
BEGIN
  FOR t IN SELECT c.oid::regclass AS name FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('public','eshop') AND c.relkind IN ('r','p') LOOP
    EXECUTE format('REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE %s FROM PUBLIC,anon,authenticated', t.name);
  END LOOP;
  -- Restrict outbound SQL/network and cross-database extension entrypoints.
  -- postgres-owned definers can still call them; application producers use net.http_post.
  FOR f IN SELECT p.oid::regprocedure AS name FROM pg_proc p
      JOIN pg_depend d ON d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e'
      JOIN pg_extension e ON e.oid=d.refobjid WHERE e.extname IN ('dblink','http') LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.name);
  END LOOP;
END $$;
