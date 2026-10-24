BEGIN READ ONLY;
SET LOCAL statement_timeout='10s';
WITH candidate AS (
 SELECT m."user" actor,t."user" target,m.occasion FROM public.occasion_users m
 JOIN public.occasions o ON o.id=m.occasion AND o.organization=1
 JOIN public.occasion_users t ON t.occasion=m.occasion AND t."user"<>m."user"
 WHERE m.is_manager IS TRUE AND NOT public.is_demo_occasion(m.occasion)
 AND EXISTS(SELECT 1 FROM public.organization_users a WHERE a."user"=t."user" AND a.is_admin IS TRUE)
 AND NOT EXISTS(SELECT 1 FROM public.organization_users a WHERE a."user"=m."user" AND a.is_admin IS TRUE)
 LIMIT 1
) SELECT set_config('request.jwt.claims',json_build_object('role','authenticated','sub',actor)::text,true) IS NOT NULL AND set_config('audit.target',target::text,true) IS NOT NULL AND set_config('audit.occasion',occasion::text,true) IS NOT NULL AS candidate_selected FROM candidate;
SET LOCAL ROLE authenticated;
SELECT json_build_object('probe','legacy_password_hierarchy','candidate_selected',nullif(current_setting('audit.target',true),'') IS NOT NULL,'legacy_guard_allows',
 (public.get_is_manager_on_occasion(nullif(current_setting('audit.occasion',true),'')::bigint) OR public.get_is_admin_on_occasion(nullif(current_setting('audit.occasion',true),'')::bigint))
 AND public.get_exists_on_occasion_user(nullif(current_setting('audit.target',true),'')::uuid,nullif(current_setting('audit.occasion',true),'')::bigint),
 'canonical_guard_allows',public.get_can_reset_user_password(nullif(current_setting('audit.target',true),'')::uuid));
RESET ROLE;
SELECT json_build_object('probe','legacy_owner','function',p.proname,'definer',p.prosecdef,'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),'auth_execute',has_function_privilege('authenticated',p.oid,'EXECUTE'),'owner_can_update_auth_users',has_table_privilege(p.proowner,'auth.users','UPDATE'),'owner_can_insert_auth_users',has_table_privilege(p.proowner,'auth.users','INSERT')) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN('set_user_password','create_user_in_organization_with_data');
SELECT json_build_object('probe','registration_org1','explicitly_enabled',coalesce((data->>'IS_REGISTRATION_ENABLED')::boolean,false)) FROM public.organizations WHERE id=1;
ROLLBACK;
