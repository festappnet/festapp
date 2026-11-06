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
 before_effective bigint; before_modes bigint; before_measurement bigint; before_runtime bigint;
 effective_calls bigint; mode_calls bigint; measurement_calls bigint; runtime_calls bigint;
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

 -- Reproduce the real catalogue projection with multiple forms and schedule
 -- fields. PostgreSQL may expand LATERAL aliases for every JSON reference.
 INSERT INTO public.forms(occasion,link,is_open,data)
 SELECT (fixture->>'occasion')::bigint,'evaluation-scope-'||n,true,
  jsonb_build_object('schedule',jsonb_build_object('start_time',now()-interval '1 day',
   'end_time',now()+interval '1 day','enable_countdown',true))
 FROM generate_series(1,4) n;
 SELECT coalesce(sum(calls) FILTER(WHERE funcname='get_effective_form_data'),0),
  coalesce(sum(calls) FILTER(WHERE funcname='get_form_registration_mode_internal'),0),
  coalesce(sum(calls) FILTER(WHERE funcname='form_measurement_status_internal'),0),
  coalesce(sum(calls) FILTER(WHERE funcname='form_measurement_runtime_internal'),0)
 INTO before_effective,before_modes,before_measurement,before_runtime
 FROM pg_stat_xact_user_functions;
 summary := public.get_occasion_sale_forms_internal((fixture->>'occasion')::bigint);
 SELECT coalesce(sum(calls) FILTER(WHERE funcname='get_effective_form_data'),0)-before_effective,
  coalesce(sum(calls) FILTER(WHERE funcname='get_form_registration_mode_internal'),0)-before_modes,
  coalesce(sum(calls) FILTER(WHERE funcname='form_measurement_status_internal'),0)-before_measurement,
  coalesce(sum(calls) FILTER(WHERE funcname='form_measurement_runtime_internal'),0)-before_runtime
 INTO effective_calls,mode_calls,measurement_calls,runtime_calls
 FROM pg_stat_xact_user_functions;
 PERFORM assert_eq(jsonb_array_length(summary),5,'All catalogue forms retained');
 PERFORM assert_eq(mode_calls,5::bigint,'Registration mode is evaluated once per form');
 PERFORM assert_eq(effective_calls,10::bigint,'Each form loads metadata once for its card and once for its time gate');
 PERFORM assert_eq(runtime_calls,effective_calls,'One runtime projection per metadata read');
 PERFORM assert_eq(measurement_calls,runtime_calls,'One measurement status per runtime projection');
END $$;
ROLLBACK;
