-- Only this task-owned, email-fenced local catalog may be recorded here.
DO $$ BEGIN
 IF (SELECT project FROM festapp_test_support.disposable_environment) IS DISTINCT FROM 'festapp-authz-20261020'
   OR current_setting('cron.launch_active_jobs')<>'off'
   OR EXISTS(SELECT 1 FROM public.email_capacity WHERE NOT paused OR worker_url IS NOT NULL) THEN
   RAISE EXCEPTION 'task-owned email-fenced authorization database required';
 END IF;
END $$;
-- Keep deparser qualification stable across fresh connections and role defaults.
SET search_path=public,extensions;
-- Run only on the marker-verified disposable authorization database.
SELECT jsonb_build_object(
 'server',version(),
 'project',(SELECT project FROM festapp_test_support.disposable_environment),
 'cronLaunchActiveJobs',current_setting('cron.launch_active_jobs'),
 'emailPaused',(SELECT bool_and(paused AND worker_url IS NULL) FROM public.email_capacity),
 'cronJobs',(SELECT jsonb_agg(jsonb_build_object('name',jobname,'schedule',schedule,'database',database,'role',username,'active',active,'commandMd5',md5(command),'commandFunctionCandidates',(SELECT jsonb_agg(name[1]) FROM regexp_matches(command,'(?:public\.|net\.)([a-z_][a-z0-9_]*)[[:space:]]*\(','g') name),'commandRelationCandidates',(SELECT jsonb_agg(name[1]) FROM regexp_matches(command,'(?:FROM|UPDATE|INTO)[[:space:]]+([a-z_][a-z0-9_.]*)','gi') name))) FROM cron.job),
 'writerRegistry',(SELECT jsonb_agg(to_jsonb(r) ORDER BY registry_version,component,source_relation) FROM public.client_sync_component_sources r),
 'functions',(SELECT jsonb_agg(jsonb_build_object(
  'signature',p.oid::regprocedure::text,'definer',p.prosecdef,'owner',pg_get_userbyid(p.proowner),
  'settings',p.proconfig,'acl',p.proacl,'grants',(SELECT jsonb_agg(jsonb_build_object(
    'grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
    'grantor',pg_get_userbyid(a.grantor),'privilege',a.privilege_type,'grantable',a.is_grantable)
    ORDER BY a.grantee,a.privilege_type) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a),
  'bodyMd5',md5(p.prosrc),'definition',pg_get_functiondef(p.oid),
  'execute',jsonb_build_object('anon',has_function_privilege('anon',p.oid,'EXECUTE'),
   'authenticated',has_function_privilege('authenticated',p.oid,'EXECUTE'),
   'service_role',has_function_privilege('service_role',p.oid,'EXECUTE'))
 ) ORDER BY p.oid::regprocedure::text) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','eshop') AND p.prokind='f'
 AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')),
 'policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY schemaname,tablename,policyname) FROM pg_policies p
 WHERE schemaname IN ('public','eshop','storage')),
 'tableGrants',(SELECT jsonb_agg(to_jsonb(g) ORDER BY table_schema,table_name,grantee,privilege_type)
 FROM information_schema.table_privileges g WHERE table_schema IN ('public','eshop','storage')),
 'columnGrants',(SELECT jsonb_agg(to_jsonb(g) ORDER BY table_schema,table_name,column_name,grantee,privilege_type)
 FROM information_schema.column_privileges g WHERE table_schema IN ('public','eshop','storage')),
 'schemaGrants',(SELECT jsonb_agg(jsonb_build_object('schema',n.nspname,
  'grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
  'privilege',a.privilege_type,'grantable',a.is_grantable) ORDER BY n.nspname,a.grantee,a.privilege_type)
 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a
 WHERE n.nspname IN ('public','eshop','storage','graphql_public')),
 'defaultGrants',(SELECT jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),
  'schema',n.nspname,'kind',d.defaclobjtype,'acl',d.defaclacl) ORDER BY d.oid)
 FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace),
 'roles',(SELECT jsonb_agg(jsonb_build_object('role',rolname,'superuser',rolsuper,
  'inherit',rolinherit,'login',rolcanlogin,'bypassRls',rolbypassrls) ORDER BY rolname) FROM pg_roles),
 'roleMemberships',(SELECT jsonb_agg(jsonb_build_object('member',pg_get_userbyid(m.member),
  'role',pg_get_userbyid(m.roleid),'admin',m.admin_option) ORDER BY m.member,m.roleid) FROM pg_auth_members m),
 'platformExtensions',(SELECT jsonb_agg(jsonb_build_object('extension',e.extname,
  'schema',n.nspname,'version',e.extversion) ORDER BY e.extname)
 FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace),
 'relations',(SELECT jsonb_agg(jsonb_build_object('relation',c.oid::regclass::text,
  'rls',c.relrowsecurity,'forceRls',c.relforcerowsecurity) ORDER BY c.oid::regclass::text)
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('public','eshop','storage') AND c.relkind IN ('r','p','v')),
 'indexes',(SELECT jsonb_agg(to_jsonb(i) ORDER BY schemaname,tablename,indexname)
 FROM pg_indexes i WHERE schemaname IN ('public','eshop')),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('table',t.tgrelid::regclass::text,
  'definition',pg_get_triggerdef(t.oid)) ORDER BY t.tgrelid::regclass::text,t.tgname)
 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE NOT t.tgisinternal AND n.nspname IN ('public','eshop')),
 'dependencies',(SELECT jsonb_agg(jsonb_build_object('class',d.classid::regclass::text,
  'objectId',d.objid,'object',pg_describe_object(d.classid,d.objid,d.objsubid),
  'referencedClass',d.refclassid::regclass::text,'referencedId',d.refobjid,
  'referencedObject',pg_describe_object(d.refclassid,d.refobjid,d.refobjsubid),'type',d.deptype))
 FROM pg_depend d WHERE d.refclassid='pg_proc'::regclass AND d.refobjid IN
 (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'))
);
