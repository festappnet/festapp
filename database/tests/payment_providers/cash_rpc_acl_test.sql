-- Public compatibility readers and authenticated financial writers have explicit
-- role grants. The internal overview can never bypass the capability fence.
DO $$
DECLARE contract record; role_name text; expected boolean; actual boolean; function_id oid;
BEGIN
 FOR contract IN SELECT * FROM (VALUES
  ('public.get_form_by_link(jsonb)',true,true,true),
  ('public.get_form_by_link(text)',true,true,true),
  ('public.get_customer_order_overview(jsonb)',true,true,true),
  ('public.get_customer_order_overview(text,bigint)',true,true,true),
  ('public.get_customer_order_overview_internal(text,bigint)',false,false,false),
  ('public.insert_manual_transaction(jsonb,uuid)',false,true,false),
  ('public.get_bank_transaction_history(bigint)',false,true,false),
  ('public.can_read_bank_transactions(bigint)',false,true,true)
 ) AS permissions(signature,anon,authenticated,service_role) LOOP
  function_id:=to_regprocedure(contract.signature);
  PERFORM assert_true(function_id IS NOT NULL,'cash RPC exists: '||contract.signature);
  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM pg_proc p,
   LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid=function_id AND a.grantee=0 AND a.privilege_type='EXECUTE'),
   'cash RPC has no implicit PUBLIC execution: '||contract.signature);
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   expected:=(to_jsonb(contract)->>role_name)::boolean;
   actual:=has_function_privilege(role_name,function_id,'EXECUTE');
   PERFORM assert_eq(actual,expected,'cash role ACL: '||role_name||' '||contract.signature);
  END LOOP;
 END LOOP;
END $$;
