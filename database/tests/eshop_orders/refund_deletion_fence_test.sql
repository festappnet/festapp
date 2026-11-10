-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
DO $$
DECLARE x jsonb; oid bigint; command uuid:=extensions.gen_random_uuid(); r jsonb;
BEGIN
 x:=pg_temp.payment_fixture();oid:=(x->>'order')::bigint;
 PERFORM pg_temp.payment_pair(x,1000);
 SET LOCAL ROLE authenticated;
 PERFORM public.get_order_deletion_context_v1(oid,command);
 RESET ROLE;
 PERFORM assert_eq((SELECT command_id FROM eshop.order_deletion_fences WHERE order_id=oid),command,'preflight persists its external deletion fence');
 SET LOCAL ROLE authenticated;
 PERFORM public.get_order_deletion_context_v1(oid,command);
 BEGIN
  PERFORM public.get_order_deletion_context_v1(oid,extensions.gen_random_uuid());
  RAISE EXCEPTION 'second deletion command stole fence';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ORDER_DELETION_IN_PROGRESS' THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.command_payment_operation(jsonb_build_object('operation','prepare_refund','method','cash',
   'orderId',oid,'amount','100.00','receivedAt',now()),extensions.gen_random_uuid());
  RAISE EXCEPTION 'refund entered external deletion gap';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ORDER_DELETION_IN_PROGRESS' THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.delete_order_client_sync_v1(oid,extensions.gen_random_uuid());
  RAISE EXCEPTION 'different command bypassed fence';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ORDER_DELETION_IN_PROGRESS' THEN RAISE; END IF; END;
 r:=public.delete_order_client_sync_v1(oid,command);
 RESET ROLE;
 PERFORM assert_eq((r->>'code')::integer,200,'original deletion continues after external operation');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=oid),'successful delete removes fence');
 SET LOCAL ROLE authenticated;
 r:=public.get_order_deletion_context_v1(oid,command);
 RESET ROLE;
 PERFORM assert_true(r ? 'response','lost external deletion response recovers completed receipt');
END $$;
