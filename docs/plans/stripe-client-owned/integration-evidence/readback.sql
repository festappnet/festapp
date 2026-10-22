SELECT jsonb_build_object(
 'migrationHead',(SELECT max(version) FROM supabase_migrations.schema_migrations),
 'stripeMigrations',(SELECT jsonb_agg(version ORDER BY version) FROM supabase_migrations.schema_migrations WHERE version IN ('20261022160000','20261022170000','20261022180000')),
 'schedulerEnabled',current_setting('cron.launch_active_jobs')::boolean,
 'enabledStripePolicies',(SELECT count(*) FROM eshop.stripe_runtime_policy WHERE new_payments_enabled),
 'reservedRoots',to_jsonb(public.occasion_reserved_public_paths_internal()),
 'privateTables',(SELECT jsonb_agg(jsonb_build_object('table',c.relname,'owner',c.relowner::regrole::text,'rls',c.relrowsecurity,
   'clientPolicies',(SELECT count(*) FROM pg_policy WHERE polrelid=c.oid),
   'clientGrants',has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE'),
   'persistentTriggers',(SELECT count(*) FROM pg_trigger WHERE tgrelid=c.oid AND NOT tgisinternal)) ORDER BY c.relname)
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='eshop' AND c.relkind='r' AND c.relname LIKE 'stripe_%'),
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',p.proowner::regrole::text,'bodyMd5',md5(p.prosrc),
   'definer',p.prosecdef,'configuration',p.proconfig,'acl',p.proacl::text) ORDER BY p.oid::regprocedure::text)
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND
    (p.proname LIKE '%stripe%' OR p.proname IN ('finalize_ticket_order_internal_v1','mark_order_and_tickets_paid_internal_v1',
     'update_order_and_tickets_to_paid','get_orders','get_order_history','get_form_by_link','get_form_by_id_internal',
     'apply_transaction_pairing','scanner_ticket_projection_internal','scanner_admit_ticket_internal','get_report_ws','acquire_email_message_send_permit')))
);
