-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
BEGIN;
DO $$
DECLARE x jsonb; result jsonb;
BEGIN
 PERFORM assert_true(to_regprocedure('public.customer_move_preview_internal(bigint,bigint)') IS NULL,'move preview has no runtime registration');
 PERFORM assert_true(to_regprocedure('public.move_customer_order_domain_internal(bigint,bigint)') IS NULL,'move effects have no runtime registration');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='forms' AND column_name IN ('term_start_at','term_end_at')),'term columns are absent');
 x:=pg_temp.payment_fixture();
 UPDATE public.occasions SET features=features||'[{"code":"customer_self_service","is_enabled":true}]' WHERE id=(x->>'occasion')::bigint;
 PERFORM public.save_customer_order_policy_internal((x->>'form')::bigint,'{"cancel":{"enabled":true,"allowed_until":"2099-01-01T00:00:00Z","mode":"approval_required","reason_required":false,"refund_mode":"none"}}');
 BEGIN
  PERFORM public.normalize_customer_order_policy_internal('{"move":{"enabled":false,"targets":[]}}');
  RAISE EXCEPTION 'obsolete move policy accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.preview_customer_order_change_internal((x->>'order')::bigint,'move','{}');
  RAISE EXCEPTION 'obsolete move operation accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.apply_customer_order_change_internal((x->>'order')::bigint,'move','{}','{"effect":"move"}',gen_random_uuid());
  RAISE EXCEPTION 'obsolete move effect accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 result:=public.customer_order_actions_internal((x->>'order')::bigint);
 PERFORM assert_eq(jsonb_array_length(result),1,'only cancellation is projected');
 PERFORM assert_eq(result#>>'{0,operation}','cancel','canonical action is cancellation');
END $$;
ROLLBACK;
