\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT jsonb_build_object('kind','identity','database',current_database(),'snapshot',txid_current_snapshot()::text,'at',clock_timestamp());
SELECT jsonb_build_object('kind','schema','name',nspname,
 'classification',CASE WHEN nspname IN ('public','eshop') THEN 'application'
 WHEN nspname='festapp_merge' OR nspname LIKE 'festapp_stage_%' THEN 'retained-merge-history'
 WHEN nspname IN ('information_schema','net','vault','_realtime','graphql','graphql_public','supabase_migrations','auth','realtime','storage','supabase_functions','cron','extensions') THEN 'managed'
 ELSE 'unclassified' END)
FROM pg_namespace WHERE nspname NOT LIKE 'pg_%';
SELECT jsonb_build_object('kind','bucket','value',to_jsonb(b)) FROM storage.buckets b;
SELECT jsonb_build_object('kind','object','value',to_jsonb(o)) FROM storage.objects o ORDER BY bucket_id,name;
SELECT jsonb_build_object('kind','storage_policy','value',to_jsonb(p)) FROM pg_policies p
 WHERE schemaname='storage' AND tablename='objects' ORDER BY policyname;
SELECT jsonb_build_object('kind','storage_security','rls',c.relrowsecurity,
 'client_roles',(SELECT jsonb_agg(jsonb_build_object('name',rolname,'bypass',rolbypassrls,'superuser',rolsuper) ORDER BY rolname)
 FROM pg_roles WHERE rolname IN ('anon','authenticated')))
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='storage' AND c.relname='objects';
-- Catalog-driven, including text domains, JSON and arrays: scanning the row's
-- JSON representation also discovers future application columns without a
-- hand-maintained allowlist. Staging/merge/auth schemas are retention boundaries.
SELECT jsonb_build_object('kind','relation','schema',n.nspname,'table',c.relname,
 'relation_kind',c.relkind,'primary_key',COALESCE((
 SELECT jsonb_agg(a.attname ORDER BY k.ordinality)
 FROM pg_index i CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY k(attnum,ordinality)
 JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.attnum
 WHERE i.indrelid=c.oid AND i.indisprimary),'[]'::jsonb),
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'generated',a.attgenerated))
 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped))
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('public','eshop') AND c.relkind IN ('r','p','m') AND NOT c.relispartition;
SELECT format('SELECT jsonb_build_object(''kind'',''row'',''schema'',%L,''table'',%L,''value'',to_jsonb(t)) FROM %I.%I t WHERE to_jsonb(t)::text ~ %L;',
 n.nspname,c.relname,n.nspname,c.relname,'storage|img[.]festapp[.]net|image-api[.]festapp[.]net')
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('public','eshop') AND c.relkind IN ('r','p','m') AND NOT c.relispartition
ORDER BY n.nspname,c.relname
\gexec
COMMIT;
