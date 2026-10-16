-- Read-only catalog gate. Production caller MUST use BEGIN READ ONLY / COMMIT.
-- Fails on real effective privileges, regardless of migration ledger contents.
DO $$
DECLARE bad text;
BEGIN
  SELECT string_agg(oid::regprocedure::text,', ') INTO bad FROM pg_proc
  WHERE pronamespace='public'::regnamespace AND proname IN
    ('migrate_users_to_org','update_spot','apply_allocations_claim_only','send_email_mailersend');
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'Retired RPC drift: %',bad; END IF;
  SELECT string_agg(c.oid::regclass::text || ':' || r.role,', ') INTO bad
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  CROSS JOIN (VALUES ('anon'),('authenticated')) r(role)
  WHERE n.nspname='public' AND c.relname IN ('external_sync_sources','external_sync_maps','external_occasions_cache')
    AND (NOT c.relrowsecurity OR has_table_privilege(r.role,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'));
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'Sync ACL drift: %',bad; END IF;
  IF EXISTS (SELECT 1 FROM pg_class WHERE relnamespace='public'::regnamespace
      AND relname IN ('external_sync_sources','external_sync_maps','external_occasions_cache')
      AND (has_table_privilege('service_role',oid,'TRUNCATE,REFERENCES,TRIGGER') OR
        NOT has_table_privilege('service_role',oid,'SELECT') OR NOT has_table_privilege('service_role',oid,'INSERT') OR
        NOT has_table_privilege('service_role',oid,'UPDATE') OR NOT has_table_privilege('service_role',oid,'DELETE'))) THEN
    RAISE EXCEPTION 'Sync service privilege drift';
  END IF;
  IF (SELECT count(*) FROM pg_policies WHERE schemaname='public'
      AND tablename IN ('external_sync_sources','external_sync_maps','external_occasions_cache')
      AND policyname='service_only' AND roles=ARRAY['service_role']::name[] AND cmd='ALL'
      AND permissive='PERMISSIVE' AND qual='true' AND with_check='true') <> 3
    OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename IN ('external_sync_sources','external_sync_maps','external_occasions_cache')
      AND (roles<>ARRAY['service_role']::name[] OR policyname<>'service_only')) THEN
    RAISE EXCEPTION 'Sync policy drift';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','eshop') AND c.relkind IN ('r','p') AND
      (has_table_privilege('anon',c.oid,'TRUNCATE') OR has_table_privilege('authenticated',c.oid,'TRUNCATE'))) THEN
    RAISE EXCEPTION 'Client TRUNCATE drift';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('public','eshop') AND p.prosecdef
      AND NOT EXISTS(SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')
      AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')) THEN
    RAISE EXCEPTION 'Application definer search_path drift';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_depend d ON d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e'
    JOIN pg_extension e ON e.oid=d.refobjid WHERE e.extname IN ('dblink','http') AND
    (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE'))) THEN
    RAISE EXCEPTION 'Network extension ACL drift';
  END IF;
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='update_spot_assignments')<>1
    OR (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='add_sync_map')<>1 THEN
    RAISE EXCEPTION 'Unexpected assignment/service writer overload';
  END IF;
  IF EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated'),('service_role')) r(role)
    WHERE has_table_privilege(r.role,'public.festapp_monitoring_credentials','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')) THEN
    RAISE EXCEPTION 'Existing monitoring credential boundary drift';
  END IF;
  IF has_function_privilege('anon','public.update_spot_assignments(jsonb)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.update_spot_assignments(jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','public.add_sync_map(text,bigint,bigint,text,bigint,bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'Assignment/service writer ACL drift';
  END IF;
END $$;
SELECT 'server-security-state: pass' AS result;
-- Per-role/database settings can affect execution outside function-local SETs.
-- Return only explicitly safe settings, never arbitrary role configuration.
SELECT coalesce(r.rolname,'ALL') AS role,coalesce(d.datname,'ALL') AS database,setting
FROM pg_db_role_setting s LEFT JOIN pg_roles r ON r.oid=s.setrole
LEFT JOIN pg_database d ON d.oid=s.setdatabase CROSS JOIN LATERAL unnest(s.setconfig) setting
WHERE split_part(setting,'=',1) IN ('search_path','statement_timeout','lock_timeout','idle_in_transaction_session_timeout')
ORDER BY 1,2,3;
