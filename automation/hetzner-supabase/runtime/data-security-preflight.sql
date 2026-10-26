-- Read-only evidence only. Use the backend-access target assertions first.
BEGIN READ ONLY;
SELECT current_database(),session_user;
SELECT version,name FROM supabase_migrations.schema_migrations
 WHERE version IN ('20261016170000','20261016171000','20261016172000',
 '20261018100000','20261018101000','20261018102000','20261018103000') ORDER BY version;
SELECT paused,minimum_build FROM public.canonical_mutation_write_release_gate;
SELECT p.oid::regprocedure AS signature,p.prosecdef,pg_get_userbyid(p.proowner) AS owner,
 has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
 has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
 (SELECT count(*) FROM pg_depend d WHERE d.refclassid='pg_proc'::regclass AND d.refobjid=p.oid AND d.deptype<>'e') AS dependencies
 FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname IN
 ('set_user_password','create_user','create_user_with_data','create_user_in_organization_with_data',
 'create_user_in_organization_with_data_ws','create_user_from_registration','create_user_in_organization_with_data_pure')
 ORDER BY 1;
-- Textual callers complement pg_depend for PL/pgSQL bodies.
SELECT p.oid::regprocedure AS textual_caller FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
 AND p.proname NOT IN ('set_user_password','create_user','create_user_with_data','create_user_in_organization_with_data')
 AND p.prosrc ~ '\m(set_user_password|create_user|create_user_with_data|create_user_in_organization_with_data)\s*\(';
SELECT schemaname,tablename,policyname,roles,cmd,permissive,qual,with_check FROM pg_policies
 WHERE schemaname='public' AND tablename IN ('user_group_info','user_groups','user_news','occasions','places','news','email_templates')
 ORDER BY tablename,policyname;
SELECT pg_get_userbyid(defaclrole) AS owner,coalesce(n.nspname,'GLOBAL') AS schema,defaclobjtype,defaclacl
 FROM pg_default_acl a LEFT JOIN pg_namespace n ON n.oid=a.defaclnamespace
 WHERE n.nspname IN ('public','eshop') OR a.defaclnamespace=0 ORDER BY 1,2,3;
-- No personal values. Nonhidden group rows require immutable artifact review.
SELECT EXISTS(SELECT 1 FROM public.places WHERE type='group' AND is_hidden IS DISTINCT FROM true)
 AS nonhidden_group_points_require_artifact_review;
SELECT c.oid::regclass AS object,pg_get_userbyid(c.relowner) AS owner,
 has_table_privilege('anon',c.oid,'TRUNCATE,REFERENCES,TRIGGER') AS anon_ddl,
 has_table_privilege('authenticated',c.oid,'TRUNCATE,REFERENCES,TRIGGER') AS authenticated_ddl
 FROM pg_class c WHERE c.relnamespace='storage'::regnamespace AND c.relname IN ('buckets','objects','buckets_analytics');
COMMIT;
