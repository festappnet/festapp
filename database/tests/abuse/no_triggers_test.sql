DO $$
BEGIN
 PERFORM assert_false(EXISTS(
  SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_proc p ON p.oid=t.tgfoid
  WHERE NOT t.tgisinternal AND n.nspname IN ('public','eshop')
   AND p.proname NOT IN ('moddatetime','update_updated_at_column')
 ),'application schemas have only updated_at row hooks');
 PERFORM assert_true(to_regprocedure('public.deliver_log_notification_v1()') IS NULL,'obsolete notification trigger function is removed');
 PERFORM assert_false(has_function_privilege('authenticated','public.dispatch_log_notification_v1(uuid)','EXECUTE'),'client cannot bypass notification command and dispatch directly');
END $$;
