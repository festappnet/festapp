-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- test-setup: database/tests/helpers/refund_operation_fixture.sql
-- Cached plans must continue reading live identities, memberships and ledgers.
DO $$
DECLARE x jsonb:=pg_temp.refund_fixture(); other_actor uuid; i integer; facts record;
BEGIN
 FOR i IN 1..8 LOOP
  PERFORM assert_true(public.can_read_orders((x->>'occasion')::bigint),'warm order permission');
  PERFORM assert_true(public.get_is_manager_on_unit((x->>'unit')::bigint),'warm unit permission');
  PERFORM assert_true(public.can_manage_bank_account((x->>'bank')::bigint),'warm bank permission');
  SELECT * INTO STRICT facts FROM public.payment_financial_totals_internal((x->>'payment')::bigint);
 END LOOP;
 PERFORM assert_eq(facts.gross_received,1000::numeric,'warm financial projection');
 PERFORM assert_eq(facts.net_received,1000::numeric,'warm net');
 PERFORM assert_false(facts.invalid_identity,'matching movement identity');

 -- The filtered branch has exactly the same movement classification as the
 -- full report branch, including when the prepared plan becomes generic.
 PERFORM assert_false(EXISTS(
  (SELECT * FROM public.payment_transaction_movements_internal((x->>'payment')::bigint)
   EXCEPT ALL SELECT * FROM public.payment_transaction_movements_internal(NULL) WHERE payment_info=(x->>'payment')::bigint)
  UNION ALL
  (SELECT * FROM public.payment_transaction_movements_internal(NULL) WHERE payment_info=(x->>'payment')::bigint
   EXCEPT ALL SELECT * FROM public.payment_transaction_movements_internal((x->>'payment')::bigint))
 ),'filtered and report movement projections agree');
 PERFORM assert_eq((SELECT count(*) FROM public.payment_transaction_movements_internal(-1)),0::bigint,'unrelated payment has no movements');

 PERFORM pg_temp.payment_pair(x,125);
 SELECT * INTO STRICT facts FROM public.payment_financial_totals_internal((x->>'payment')::bigint);
 PERFORM assert_eq(facts.gross_received,1125::numeric,'cached plan reads new ledger facts');

 PERFORM public.create_user_for_test('order_read_cache_other','order-read-cache-other@example.invalid');
 other_actor:=public.get_user_id('order_read_cache_other');
 UPDATE public.user_info SET organization=(x->>'organization')::bigint WHERE id=other_actor;
 PERFORM set_config('request.jwt.claim.sub',other_actor::text,true);
 PERFORM assert_false(public.can_read_orders((x->>'occasion')::bigint),'cached order plan reads new JWT');
 PERFORM assert_false(public.get_is_manager_on_unit((x->>'unit')::bigint),'cached unit plan reads new JWT');
 PERFORM assert_false(public.can_manage_bank_account((x->>'bank')::bigint),'cached bank plan reads new JWT');

 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 UPDATE public.occasion_users SET is_editor_order_view=false WHERE occasion=(x->>'occasion')::bigint AND "user"=(x->>'actor')::uuid;
 PERFORM assert_false(public.can_read_orders((x->>'occasion')::bigint),'cached plan observes order-role revocation');
 UPDATE public.occasion_users SET is_editor_order_view=true WHERE occasion=(x->>'occasion')::bigint AND "user"=(x->>'actor')::uuid;
 PERFORM assert_true(public.can_read_orders((x->>'occasion')::bigint),'cached plan observes order-role grant');
 UPDATE eshop.bank_account_users SET is_admin=false WHERE bank_account=(x->>'bank')::bigint AND "user"=(x->>'actor')::uuid;
 PERFORM assert_false(public.can_manage_bank_account((x->>'bank')::bigint),'cached plan observes bank-role revocation');
 UPDATE eshop.bank_account_users SET is_admin=true WHERE bank_account=(x->>'bank')::bigint AND "user"=(x->>'actor')::uuid;
 UPDATE public.unit_users SET is_manager=false WHERE unit=(x->>'unit')::bigint AND "user"=(x->>'actor')::uuid;
 PERFORM assert_false(public.get_is_manager_on_unit((x->>'unit')::bigint),'cached plan observes unit-role revocation');
 PERFORM assert_false(public.can_manage_bank_account((x->>'bank')::bigint),'bank authority still requires linked unit management');
END $$;
