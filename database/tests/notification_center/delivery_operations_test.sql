BEGIN;
DO $$
DECLARE p regprocedure; t regclass; fk record;
BEGIN
 FOREACH p IN ARRAY ARRAY['public.get_notification_center_delivery_health()'::regprocedure,
 'public.retry_notification_center_delivery(bigint,uuid,uuid)'::regprocedure,
 'public.project_notification_center(integer)'::regprocedure,
 'public.prepare_notification_center(integer)'::regprocedure,
 'public.prepare_notification_center_views(integer)'::regprocedure,
 'public.get_notification_center_projection_health(bigint)'::regprocedure,
 'public.retry_notification_center_projection(bigint,uuid,integer)'::regprocedure,
 'public.configure_notification_center_worker(text)'::regprocedure] LOOP
  PERFORM assert_false(has_function_privilege('authenticated',p,'execute'),'no client delivery operation');
  PERFORM assert_false(has_function_privilege('anon',p,'execute'),'no anonymous delivery operation');
  PERFORM assert_true(has_function_privilege('service_role',p,'execute'),'service delivery operation');
  PERFORM assert_true((SELECT prosecdef AND proconfig @> ARRAY['search_path=public, extensions'] FROM pg_proc WHERE oid=p),'definer has fixed search path');
 END LOOP;
 FOREACH t IN ARRAY ARRAY['public.notification_center_recipients'::regclass,'public.notification_center_maintenance'::regclass,
 'public.notification_center_projection_scopes'::regclass,
 'public.notification_center_view_members'::regclass,
 'public.notification_center_member_subjects'::regclass,
 'public.notification_center_batch_summaries'::regclass,
 'public.notification_center_summary_scopes'::regclass,
 'public.notification_center_group_repairs'::regclass,
 'public.notification_center_views'::regclass,
 'public.notification_center_view_rows'::regclass] LOOP
  PERFORM assert_true((SELECT relrowsecurity FROM pg_class WHERE oid=t),'retry and cursor tables have RLS');
  PERFORM assert_false(has_table_privilege('authenticated',t,'select'),'no private queue access');
 END LOOP;
 FOR p IN SELECT oid::regprocedure FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'notification_center_prepared_%' LOOP
  PERFORM assert_false(has_function_privilege('authenticated',p,'execute'),'no client private prepared helper');
  PERFORM assert_false(has_function_privilege('service_role',p,'execute'),'service must use controlled worker entrypoints');
 END LOOP;
 FOR fk IN SELECT conrelid,conkey,conname FROM pg_constraint WHERE contype='f'
  AND conrelid IN ('public.notification_center_projection_scopes'::regclass,'public.notification_center_view_members'::regclass,
   'public.notification_center_member_subjects'::regclass,'public.notification_center_batch_summaries'::regclass,
   'public.notification_center_summary_scopes'::regclass,'public.notification_center_group_repairs'::regclass,
   'public.notification_center_views'::regclass,'public.notification_center_view_rows'::regclass) LOOP
  PERFORM assert_true(EXISTS(SELECT 1 FROM pg_index i WHERE i.indrelid=fk.conrelid AND i.indisvalid AND i.indpred IS NULL
   AND ARRAY(SELECT x FROM unnest(i.indkey::smallint[]) WITH ORDINALITY a(x,n) WHERE n<=cardinality(fk.conkey))=fk.conkey::smallint[]), 'prepared cascade has leading lookup index: '||fk.conname);
 END LOOP;
END $$;
ROLLBACK;
