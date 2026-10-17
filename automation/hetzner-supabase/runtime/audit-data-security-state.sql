-- Read-only companion to audit-security-state.sql; run both after these phases.
DO $$
DECLARE p record; r text; bad boolean;
BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('set_user_password','create_user','create_user_with_data','create_user_in_organization_with_data')) THEN
 RAISE EXCEPTION 'retired Auth writer drift'; END IF;
 FOR p IN SELECT oid FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('create_user_from_registration','create_user_in_organization_with_data_ws','create_user_in_organization_with_data_pure') LOOP
 IF has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') THEN
 RAISE EXCEPTION 'internal Auth writer ACL drift'; END IF; END LOOP;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP
 IF has_table_privilege(r,'public.email_templates','SELECT') OR has_table_privilege(r,'public.user_news','INSERT,UPDATE,DELETE')
 OR has_table_privilege(r,'public.user_groups','INSERT,UPDATE,DELETE') OR has_table_privilege(r,'public.user_group_info','INSERT,UPDATE,DELETE')
 OR has_table_privilege(r,'public.news','INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'data-security table grant drift: %',r; END IF;
 END LOOP;
 IF has_table_privilege('anon','public.occasions','SELECT') OR has_table_privilege('anon','public.user_news','SELECT') THEN
 RAISE EXCEPTION 'anonymous private table grant drift'; END IF;
 IF EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename IN ('user_group_info','user_groups','user_news','occasions','places','email_templates')
 AND cmd IN ('SELECT','ALL') AND permissive='PERMISSIVE' AND qual='true' AND roles && ARRAY['public','anon','authenticated']::name[]) THEN
 RAISE EXCEPTION 'permissive read policy drift'; END IF;
 IF EXISTS(SELECT 1 FROM pg_default_acl a CROSS JOIN LATERAL aclexplode(a.defaclacl) x
 LEFT JOIN pg_namespace n ON n.oid=a.defaclnamespace
 WHERE (n.nspname IN ('public','eshop') OR a.defaclnamespace=0 AND a.defaclobjtype='f')
 AND (x.grantee=0 OR x.grantee IN (SELECT oid FROM pg_roles WHERE rolname IN ('anon','authenticated')))) THEN
 RAISE EXCEPTION 'default ACL drift'; END IF;
 IF EXISTS(SELECT 1 FROM (SELECT DISTINCT proowner AS owner FROM pg_proc WHERE pronamespace IN ('public'::regnamespace,'eshop'::regnamespace)
 UNION SELECT DISTINCT relowner FROM pg_class WHERE relnamespace IN ('public'::regnamespace,'eshop'::regnamespace)) owners
 WHERE NOT EXISTS(SELECT 1 FROM pg_default_acl a WHERE a.defaclrole=owners.owner AND a.defaclnamespace=0 AND a.defaclobjtype='f')) THEN
 RAISE EXCEPTION 'implicit PUBLIC EXECUTE default drift'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='news'
 AND policyname='data_security_news_context_read' AND permissive='RESTRICTIVE') THEN
 RAISE EXCEPTION 'hidden news fence drift'; END IF;
END $$;
SELECT 'data-security-state: pass';
