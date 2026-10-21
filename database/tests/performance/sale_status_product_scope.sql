-- Standalone privileged performance regression check on a disposable local DB:
-- psql "$LOCAL_ADMIN_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f database/tests/performance/sale_status_product_scope.sql
-- Supabase's supabase_admin role is needed only to enable function statistics.
BEGIN;
\ir ../helpers/assertions.sql
\ir ../blueprint/fixtures.sql
-- Count real availability evaluations rather than relying on machine timings.
SET LOCAL track_functions = 'all';
-- Exercise the hash-join plan observed in production, independently of the
-- disposable database's size and planner statistics.
SET LOCAL enable_nestloop = off;
DO $$
DECLARE
 fixture jsonb; summary jsonb; unrelated_type bigint; before_calls bigint; after_calls bigint;
BEGIN
 fixture := public.blueprint_test_fixture_internal();
 PERFORM set_config('request.jwt.claim.sub',fixture->>'actor',true);
 PERFORM public.update_blueprint_client_sync_v1(fixture->'request',gen_random_uuid());
 INSERT INTO eshop.product_types(occasion,title,type)
 VALUES ((fixture->>'occasion')::bigint,'Unrelated products','food') RETURNING id INTO unrelated_type;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden,maximum)
 SELECT (fixture->>'occasion')::bigint,unrelated_type,'Unrelated '||n,10,'CZK',false,10
 FROM generate_series(1,1000) n;
 ANALYZE eshop.products;

 SELECT coalesce(sum(calls),0) INTO before_calls FROM pg_stat_xact_user_functions
 WHERE funcid='public.blueprint_product_availability_internal(bigint)'::regprocedure;
 summary := public.get_occasion_sale_forms_internal((fixture->>'occasion')::bigint);
 SELECT coalesce(sum(calls),0) INTO after_calls FROM pg_stat_xact_user_functions
 WHERE funcid='public.blueprint_product_availability_internal(bigint)'::regprocedure;
 PERFORM assert_true((summary->0->>'has_availability')::boolean,'Offered seat remains available');
 PERFORM assert_true(after_calls>before_calls,'Availability instrumentation observes real evaluations');
 PERFORM assert_true(after_calls-before_calls<=10,
   'Blueprint summary must evaluate offered products only; calls='||(after_calls-before_calls));

 -- The same bound applies to ordinary product fields without a seating plan.
 UPDATE public.forms SET blueprint=NULL WHERE id=(fixture->>'form')::bigint;
 before_calls := after_calls;
 summary := public.get_occasion_sale_forms_internal((fixture->>'occasion')::bigint);
 SELECT coalesce(sum(calls),0) INTO after_calls FROM pg_stat_xact_user_functions
 WHERE funcid='public.blueprint_product_availability_internal(bigint)'::regprocedure;
 PERFORM assert_true((summary->0->>'has_availability')::boolean,'Regular admission remains available');
 PERFORM assert_true(after_calls>before_calls AND after_calls-before_calls<=10,
   'Regular summary must evaluate field products only; calls='||(after_calls-before_calls));
END $$;
ROLLBACK;
