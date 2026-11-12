-- The changed public boundaries retain their exact role contracts after both forwards.
DO $$
DECLARE signature text; role_name text; table_name text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['public.get_payment_method_policy(bigint,bigint)','public.preview_payment_method_policy(jsonb)',
  'public.command_payment_method_policy(jsonb,uuid,text)','public.get_payment_template_audit(bigint)','public.review_payment_templates(bigint,text)',
  'public.get_bank_transaction_history(bigint,bigint)'] LOOP
  PERFORM assert_true(has_function_privilege('authenticated',signature,'EXECUTE'),'authenticated explicit API: '||signature);
  PERFORM assert_false(has_function_privilege('anon',signature,'EXECUTE'),'anonymous has no scoped management API: '||signature);
  PERFORM assert_false(has_function_privilege('service_role',signature,'EXECUTE'),'service role does not inherit user API: '||signature);
 END LOOP;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  FOREACH signature IN ARRAY ARRAY['public.resolve_payment_method_policy_internal(bigint,bigint)','public.payment_collection_action_internal(bigint)',
   'public.payment_template_audit_internal(bigint)','public.payment_template_write_scope_internal(jsonb,boolean)'] LOOP
   PERFORM assert_false(has_function_privilege(role_name,signature,'EXECUTE'),'internal owner remains private: '||signature);
  END LOOP;
  FOREACH table_name IN ARRAY ARRAY['organization_payment_method_policies','unit_payment_method_policies','payment_method_policy_scopes',
   'payment_method_policy_unit_preferences','payment_method_policy_commands','payment_template_reviews','payment_template_epochs'] LOOP
   PERFORM assert_false(has_table_privilege(role_name,'eshop.'||table_name,'SELECT,INSERT,UPDATE,DELETE'),'policy table remains private: '||table_name);
  END LOOP;
 END LOOP;
 PERFORM assert_true(has_function_privilege('service_role','public.get_linkable_bank_accounts(bigint)','EXECUTE'),'service caller still enters the typed scope-checked picker');
 PERFORM assert_true(to_regprocedure('public.get_my_admin_bank_accounts()') IS NOT NULL,'issued picker is an unambiguous scoped adapter');
 PERFORM assert_true(to_regprocedure('public.get_bank_transaction_history(bigint)') IS NOT NULL,'issued history delegates the explicit linked scope');
 PERFORM assert_true(to_regprocedure('public.payment_template_policy_fence_internal()') IS NULL,'obsolete trigger function removed');
 PERFORM assert_true(to_regclass('eshop.stripe_unit_features') IS NULL,'duplicate Stripe policy storage removed');
END $$;
