-- This is an observation hook, never a source of application permissions.
DO $$
DECLARE id text; before_versions bigint; before_receipts bigint;
BEGIN
 PERFORM assert_true(NOT has_function_privilege('authenticated','public.log_canonical_mutation_scope_internal_v1(bigint)','EXECUTE'),'scope logging cannot be forged through RPC');
 PERFORM assert_true(NOT has_function_privilege('anon','public.log_canonical_mutation_scope_internal_v1(bigint)','EXECUTE'),'anonymous scope helper denied');
 PERFORM assert_true(has_function_privilege('authenticated','public.log_canonical_mutation_request_v1()','EXECUTE'),'request hook executes after role switch');
 SELECT count(*) INTO before_versions FROM public.client_aggregate_versions;
 SELECT count(*) INTO before_receipts FROM public.client_mutation_receipts;
 PERFORM set_config('request.method','GET',true);
 PERFORM set_config('festapp.mutation_audit_request_id','',true);
 PERFORM public.log_canonical_mutation_request_v1();
 PERFORM assert_eq(current_setting('festapp.mutation_audit_request_id',true),'','read does not create write observation');
 PERFORM set_config('request.method','POST',true);
 PERFORM set_config('request.path','/rpc/save_user_group_client_sync_v1',true);
 PERFORM set_config('request.headers','{"authorization":"never-export-this-token","cookie":"never-export-this-cookie","x-client-info":"festapp/0.20.135+619/web"}',true);
 PERFORM public.log_canonical_mutation_request_v1();
 id:=current_setting('festapp.mutation_audit_request_id',true);
 PERFORM assert_true(id::uuid IS NOT NULL,'write gets a server-generated correlation identity');
 PERFORM public.log_canonical_mutation_scope_internal_v1(123);
 PERFORM assert_eq(current_setting('festapp.mutation_audit_request_id',true),id,'domain scope correlates to its existing request');
 PERFORM set_config('request.headers','malformed',true);
 PERFORM set_config('request.path',E'/rpc/save\nforged-entry?authorization=private',true);
 PERFORM public.log_canonical_mutation_request_v1();
 PERFORM assert_true(current_setting('festapp.mutation_audit_request_id',true)<>id,'malformed metadata does not break persistence or reuse another request');
 PERFORM assert_eq((SELECT count(*) FROM public.client_aggregate_versions),before_versions,'hook does not mutate aggregate clocks');
 PERFORM assert_eq((SELECT count(*) FROM public.client_mutation_receipts),before_receipts,'hook does not manufacture receipts');
END $$;

-- Execute the hook under the actual ordinary role, without definer privileges.
SET LOCAL ROLE authenticated;
SELECT public.log_canonical_mutation_request_v1();
RESET ROLE;
