-- Confirmed seat replacements and administrative form orders share this owner.
-- Their order allocation is already committed. Provider
-- preparation retries keep the new allocation and fence invoice POST separately.
CREATE TABLE IF NOT EXISTS eshop.replacement_invoice_preparations(
 command_id uuid PRIMARY KEY,
 order_id bigint NOT NULL UNIQUE REFERENCES eshop.orders(id) ON DELETE CASCADE,
 state text NOT NULL CHECK(state IN('claimed','retryable','unknown','complete')),
 dispatch_started boolean NOT NULL DEFAULT false,
 lease_token uuid,
 lease_until timestamptz,
 attempts integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK((lease_token IS NULL)=(lease_until IS NULL))
);
ALTER TABLE eshop.replacement_invoice_preparations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE eshop.replacement_invoice_preparations FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.claim_replacement_invoice_preparation(p_order bigint,p_command uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE attempt eshop.replacement_invoice_preparations;receipt jsonb;token uuid:=extensions.gen_random_uuid();state text;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT o.state INTO state FROM eshop.orders o WHERE o.id=p_order FOR UPDATE;
 SELECT r.response INTO receipt FROM public.client_mutation_receipts r
  WHERE r.command_id=p_command AND (r.command_name='inventory.order.replace' OR (r.command_name IN('inventory.order.create','inventory.waitlist.accept') AND r.response#>'{data,adminQuote}' IS NOT NULL)) AND r.status='completed'
  AND r.response->>'status'='applied' AND (r.response#>>'{data,order,id}')::bigint=p_order;
 IF receipt IS NULL AND NOT EXISTS(SELECT 1 FROM eshop.replacement_invoice_preparations a
  WHERE a.command_id=p_command AND a.order_id=p_order) THEN
  RAISE insufficient_privilege USING MESSAGE='replacement receipt unavailable'; END IF;
 IF state IN('ordered','paid') THEN RETURN jsonb_build_object('status','complete'); END IF;
 IF state IS DISTINCT FROM 'preparing_payment' THEN RETURN jsonb_build_object('status','closed'); END IF;
 PERFORM 1 FROM public.email_messages q WHERE q.code='TICKET_ORDER_CONFIRMATION'
  AND q.data->>'command_id'=p_command::text AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order
  AND q.data->>'fakturoid_pending'='true' FOR UPDATE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='invoice preparation claim unavailable'; END IF;
 SELECT * INTO attempt FROM eshop.replacement_invoice_preparations WHERE command_id=p_command FOR UPDATE;
 IF NOT FOUND THEN
  -- Legacy pending receipts may already have dispatched an invoice. They are
  -- lookup-only; absence in one GET is not proof that a POST never executed.
  INSERT INTO eshop.replacement_invoice_preparations(command_id,order_id,state,dispatch_started)
   VALUES(p_command,p_order,'retryable',receipt#>>'{data,paymentPreparationPolicy}' IS DISTINCT FROM 'leased_keep_pending');
  SELECT * INTO STRICT attempt FROM eshop.replacement_invoice_preparations WHERE command_id=p_command FOR UPDATE;
 END IF;
 IF attempt.order_id<>p_order THEN RAISE insufficient_privilege USING MESSAGE='invoice order mismatch'; END IF;
 IF attempt.state='complete' THEN RETURN jsonb_build_object('status','complete'); END IF;
 IF attempt.lease_until>clock_timestamp() THEN RETURN jsonb_build_object('status','busy'); END IF;
 UPDATE eshop.replacement_invoice_preparations SET state='claimed',lease_token=token,
  lease_until=clock_timestamp()+interval '180 seconds',attempts=attempts+1,updated_at=clock_timestamp()
 WHERE command_id=p_command;
 RETURN jsonb_build_object('status','claimed','token',token,'allowCreate',NOT attempt.dispatch_started);
END $$;
REVOKE ALL ON FUNCTION public.claim_replacement_invoice_preparation(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_replacement_invoice_preparation(bigint,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.mark_replacement_invoice_dispatch(p_order bigint,p_command uuid,p_token uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 UPDATE eshop.replacement_invoice_preparations SET dispatch_started=true,updated_at=clock_timestamp()
 WHERE command_id=p_command AND order_id=p_order AND lease_token=p_token AND lease_until>clock_timestamp()
  AND state='claimed' AND NOT dispatch_started;
 IF NOT FOUND THEN RAISE check_violation USING MESSAGE='invoice dispatch lease unavailable'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.mark_replacement_invoice_dispatch(bigint,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mark_replacement_invoice_dispatch(bigint,uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.release_replacement_invoice_preparation(p_order bigint,p_command uuid,p_token uuid,p_not_created boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_not_created IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invoice outcome required'; END IF;
 UPDATE eshop.replacement_invoice_preparations SET
  dispatch_started=dispatch_started AND NOT p_not_created,
  state=CASE WHEN dispatch_started AND NOT p_not_created THEN 'unknown' ELSE 'retryable' END,
  lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp()
 WHERE command_id=p_command AND order_id=p_order AND lease_token=p_token AND state='claimed';
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.release_replacement_invoice_preparation(bigint,uuid,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.release_replacement_invoice_preparation(bigint,uuid,uuid,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_replacement_invoice_preparation(p_order bigint,p_command uuid,p_token uuid,p_variable_symbol bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE symbol bigint;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 PERFORM 1 FROM public.email_messages q WHERE q.code='TICKET_ORDER_CONFIRMATION'
  AND q.data->>'command_id'=p_command::text AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order FOR UPDATE;
 PERFORM 1 FROM eshop.replacement_invoice_preparations WHERE command_id=p_command AND order_id=p_order
  AND lease_token=p_token AND lease_until>clock_timestamp() AND state='claimed' FOR UPDATE;
 IF NOT FOUND THEN RAISE check_violation USING MESSAGE='invoice completion lease unavailable'; END IF;
 symbol:=public.complete_fakturoid_ticket_order_v1(p_order,p_command,p_variable_symbol);
 UPDATE eshop.replacement_invoice_preparations SET state='complete',lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp()
 WHERE command_id=p_command AND order_id=p_order;
 RETURN symbol;
END $$;
REVOKE ALL ON FUNCTION public.complete_replacement_invoice_preparation(bigint,uuid,uuid,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_replacement_invoice_preparation(bigint,uuid,uuid,bigint) TO service_role;
