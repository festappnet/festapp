DO $$ DECLARE t record; BEGIN
 PERFORM assert_true('stripe'=ANY(public.occasion_reserved_public_paths_internal()),'private Stripe root is reserved');
 PERFORM assert_true('order'=ANY(public.occasion_reserved_public_paths_internal()),'main customer order root remains reserved');
 FOR t IN SELECT c.relname,c.relrowsecurity,c.relowner::regrole::text owner FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='eshop' AND c.relkind='r' AND c.relname LIKE 'stripe_%' LOOP
  PERFORM assert_true(t.relrowsecurity,'private Stripe table has RLS: '||t.relname);
  PERFORM assert_eq(t.owner,'postgres','canonical commands own private table: '||t.relname);
  PERFORM assert_true(NOT has_table_privilege('anon','eshop.'||t.relname,'SELECT,INSERT,UPDATE,DELETE')
   AND NOT has_table_privilege('authenticated','eshop.'||t.relname,'SELECT,INSERT,UPDATE,DELETE'),'no direct client grants: '||t.relname);
 END LOOP;
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM eshop.stripe_runtime_policy WHERE new_payments_enabled),'rehearsed installation has no active Stripe sales');
END $$;
