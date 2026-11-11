-- Production migrations run as postgres. Local extension setup needs the
-- separate supabase_admin, so align application table owners as well as routines.
-- API roles still exercise their real RLS; no role receives BYPASSRLS.
SELECT format('ALTER TABLE %s OWNER TO postgres',c.oid::regclass)
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('public','eshop','analytics') AND c.relkind IN ('r','p')
AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_class'::regclass AND d.objid=c.oid AND d.deptype='e')
\gexec
-- Match the migration operator for schema CREATE/reapply as well as tables.
ALTER SCHEMA analytics OWNER TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA public,eshop,analytics TO postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public,eshop,analytics TO postgres;
SELECT format('ALTER FUNCTION %s OWNER TO postgres',p.oid::regprocedure)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prokind IN ('f','w')
AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')
\gexec
