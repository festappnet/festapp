-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); actions jsonb; un bigint; bank bigint:=(x->>'bank')::bigint;
 payment bigint:=(x->>'payment')::bigint; oid bigint:=(x->>'order')::bigint;
 actor uuid:=(x->>'actor')::uuid; attached bigint; unrelated bigint; cash bigint; result jsonb;
BEGIN
 SELECT unit INTO un FROM public.occasions WHERE id=(x->>'occasion')::bigint;
 SET LOCAL ROLE authenticated;
 actions:=public.get_transactions_for_order(oid)->'actions';
 PERFORM assert_eq(actions->>'bankState','configured','empty active bank is configured');
 PERFORM assert_true((actions->>'canAddCash')::boolean,'manager can add cash without bank admin');
 PERFORM assert_true(actions->>'pairingAccountId' IS NULL,'manager alone has no bank pairing');
 PERFORM assert_eq(actions->'historyAccounts','[]'::jsonb,'no personal bank history without membership');
 RESET ROLE;
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,actor,true);
 SET LOCAL ROLE authenticated;
 actions:=public.get_transactions_for_order(oid)->'actions';
 PERFORM assert_eq((actions->>'pairingAccountId')::bigint,bank,'empty bank still allows authorized search');
 PERFORM assert_true(public.get_transactions_for_order_all_available(payment) IS NULL,'empty search is not absent configuration');
 RESET ROLE;
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,transaction_type,payment_info)
 VALUES(bank,100,'CZK',now(),'bank',payment) RETURNING id INTO attached;
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,transaction_type)
 VALUES(bank,25,'CZK',now(),'bank') RETURNING id INTO unrelated;
 UPDATE public.forms SET is_open=false WHERE id=(x->>'form')::bigint;
 DELETE FROM eshop.unit_bank_accounts WHERE unit=un AND bank_account=bank;
 SET LOCAL ROLE authenticated;
 actions:=public.get_transactions_for_order(oid)->'actions';
 PERFORM assert_true(actions->>'pairingAccountId' IS NULL,'disconnection removes write capability');
 PERFORM assert_eq(jsonb_array_length(actions->'historyAccounts'),1,'personal detached account is discoverable');
 PERFORM assert_eq(jsonb_array_length(public.get_bank_transaction_history(bank)),2,'bank admin can read detached history');
 PERFORM assert_eq(jsonb_array_length(public.get_transactions_for_order(oid)->'transactions'),1,'linked movement survives disconnection');
 BEGIN
  PERFORM public.remove_transaction_from_payment_info_ws(attached,payment);
  RAISE EXCEPTION 'disconnected unlink accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 BEGIN
  DELETE FROM eshop.bank_accounts WHERE id=bank;
  RAISE EXCEPTION 'ledger account was deleted';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 -- Cash keeps bank history distinct from payment pairing, even with a retained personal account.
 UPDATE eshop.payment_info SET payment_method='cash',bank_account=NULL,variable_symbol=NULL,deadline=NULL,
  data='{"payment_policy":{"mode":"none","cashInstructions":"U vstupu"}}' WHERE id=payment;
 SET LOCAL ROLE authenticated;
 actions:=public.get_transactions_for_order(oid)->'actions';
 PERFORM assert_true(actions->>'pairingAccountId' IS NULL,'cash never offers bank pairing');
 PERFORM assert_eq(jsonb_array_length(actions->'historyAccounts'),1,'cash preserves personal history discovery');
 BEGIN
  PERFORM public.get_transactions_for_order_all_available(payment);
  RAISE EXCEPTION 'cash bank search accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 SET LOCAL ROLE authenticated;
 PERFORM assert_eq(public.get_transactions_for_order(oid)#>>'{actions,bankState}','absent','absence is based on active non-CASH accounts');
 RESET ROLE;
 cash:=public.insert_manual_transaction_internal_v1(250.50,'CZK',un,NULL,now(),'Cash',payment);
 SET LOCAL ROLE authenticated;
 PERFORM assert_true((public.get_transactions_for_order(oid)#>'{actions,removableTransactionIds}') @> jsonb_build_array(cash),'manager can correct actual CASH movement');
 PERFORM assert_eq(public.get_transactions_for_order(oid)#>>'{actions,bankState}','absent','only CASH account does not supply a bank');
 PERFORM public.delete_manual_transaction_ws(cash,payment);
 RESET ROLE;
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM eshop.transactions WHERE id=cash),'manual deletion uses existing ledger');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.transaction_pairing_events WHERE transaction_snapshot_id=cash AND action='manual_deleted'),'deletion audit retained');
 -- Revoke bank membership and management, retaining only order read permission.
 DELETE FROM eshop.bank_account_users WHERE bank_account=bank AND "user"=actor;
 DELETE FROM public.unit_users WHERE unit=un AND "user"=actor;
 UPDATE public.occasion_users SET is_editor=false,is_editor_order=false,is_editor_order_view=true WHERE occasion=(x->>'occasion')::bigint AND "user"=actor;
 SET LOCAL ROLE authenticated;
 result:=public.get_transactions_for_order(oid); actions:=result->'actions';
 PERFORM assert_eq(jsonb_array_length(result->'transactions'),1,'order reader sees attached bank movement');
 PERFORM assert_eq(actions->'historyAccounts','[]'::jsonb,'order read does not grant statement access');
 PERFORM assert_true(NOT (actions->>'canAddCash')::boolean,'order reader cannot add cash');
 PERFORM assert_true(NOT (actions->>'canConfigureBank')::boolean,'order reader cannot configure bank');
 PERFORM assert_eq(actions->>'bankState','restricted','lack of rights is not absent configuration');
 BEGIN
  PERFORM public.get_bank_transaction_history(bank);
  RAISE EXCEPTION 'statement leaked to order reader';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
END $$;
