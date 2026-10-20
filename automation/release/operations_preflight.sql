-- Read-only evidence only. Run through the approved target-identity workflow.
-- Required psql variables: organization_id, occasion_id. Never infers a tenant.
\set ON_ERROR_STOP on
\if :{?organization_id}
\else
  DO $$ BEGIN RAISE EXCEPTION 'organization_id is required'; END $$;
\endif
\if :{?occasion_id}
\else
  DO $$ BEGIN RAISE EXCEPTION 'occasion_id is required'; END $$;
\endif
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
SELECT EXISTS(SELECT 1 FROM public.occasions
  WHERE id=:'occasion_id'::bigint AND organization=:'organization_id'::bigint)
  AS target_matches \gset
\if :target_matches
\else
  DO $$ BEGIN RAISE EXCEPTION 'Target organization/occasion mismatch'; END $$;
\endif
WITH target AS (
  SELECT id,organization,unit FROM public.occasions
  WHERE id=:'occasion_id'::bigint AND organization=:'organization_id'::bigint
), recent_clients AS (
  SELECT coalesce(client_version,'unreported') AS version,count(*) AS commits
  FROM public.client_commits c,target t
  WHERE (c.occasion=t.id OR c.unit=t.unit OR c.organization=t.organization)
    AND occurred_at>=now()-interval '30 days'
  GROUP BY 1
), receipts AS (
  SELECT command_name,status,count(*) AS receipts,
    count(*) FILTER (WHERE expired_at IS NOT NULL) AS expired,
    min(created_at) AS oldest
  FROM public.client_mutation_receipts r,target t
  WHERE r.occasion=t.id OR r.unit=t.unit
  GROUP BY command_name,status
), signatures(signature) AS (VALUES
  ('public.update_product(jsonb)'),
  ('public.update_product_inventory_contexts(bigint,jsonb)'),
  ('public.update_blueprint(jsonb)'),
  ('public.delete_product_client_sync_v1(bigint,uuid)'),
  ('public.delete_form_client_sync_v1(bigint,uuid)'),
  ('public.update_inventory_pool_bundle(jsonb)'),
  ('public.update_resource(jsonb)'),
  ('public.import_occasion_users_from_csv_apply_v1(bigint,jsonb,jsonb)'),
  ('public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb)')
), grants AS (
  SELECT signature,to_regprocedure(signature) IS NOT NULL AS present,
    coalesce(has_function_privilege('anon',to_regprocedure(signature),'EXECUTE'),false) AS anon,
    coalesce(has_function_privilege('authenticated',to_regprocedure(signature),'EXECUTE'),false) AS authenticated,
    coalesce(has_function_privilege('service_role',to_regprocedure(signature),'EXECUTE'),false) AS service_role
  FROM signatures
), dml AS (
  SELECT table_schema,table_name,grantee,privilege_type
  FROM information_schema.role_table_grants
  WHERE grantee IN ('anon','authenticated') AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE')
    AND (table_schema,table_name) IN (
      ('public','occasions'),('public','units'),('public','forms'),('public','form_fields'),
      ('public','user_info'),('public','occasion_users'),('public','user_groups'),
      ('public','user_group_info'),('public','places'),('public','events'),
      ('eshop','products'),('eshop','product_types'),('eshop','product_inventory_contexts'),
      ('eshop','blueprints'),('eshop','spots'))
)
SELECT jsonb_build_object(
  'target',(SELECT to_jsonb(t) FROM target t),
  'foundationApplied',EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE version='20261020120000'),
  'recentObservedClientCommits',coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY version) FROM recent_clients c),'[]'::jsonb),
  'receiptSummary',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY command_name,status) FROM receipts r),'[]'::jsonb),
  'compatibilitySignatureSamples',(SELECT jsonb_agg(to_jsonb(g) ORDER BY signature) FROM grants g),
  'remainingSampledOrdinaryDmlGrants',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY table_schema,table_name,grantee,privilege_type) FROM dml d),'[]'::jsonb),
  'installedClientInventoryComplete',false,
  'offlinePendingIntentInventoryComplete',false,
  'productionReady',false,
  'mcpWritesEnabled',false,
  'limitation','Observed commits and server receipts cannot prove installed versions or offline device intents. Signature/table samples are not the full operation allowlist.'
);
COMMIT;
