CREATE OR REPLACE FUNCTION public.command_customer_order_request(p_request uuid,p_action text,p_command uuid,p_expected_at timestamptz,p_response text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r eshop.customer_order_change_requests; o eshop.orders; oc public.occasions; actor uuid:=auth.uid();
 hash text; receipt jsonb; preview jsonb; payload jsonb; result jsonb; users uuid[];
BEGIN
 SELECT * INTO r FROM eshop.customer_order_change_requests WHERE id=p_request;
 SELECT * INTO o FROM eshop.orders WHERE id=r.order_id;
 IF actor IS NULL OR o.id IS NULL OR public.can_write_orders(o.occasion) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='customer request unavailable'; END IF;
 IF p_action IS NULL OR p_action NOT IN ('approve','reject','resolve') OR length(p_response)>2000 THEN RAISE invalid_parameter_value; END IF;
 PERFORM public.lock_customer_order_change_internal(o.id,r.target_form_id);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=o.id;
 SELECT * INTO STRICT r FROM eshop.customer_order_change_requests WHERE id=p_request FOR UPDATE;
 IF public.can_write_orders(o.occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 -- Replaying an accepted financial effect also needs today's financial role.
 IF EXISTS(SELECT 1 FROM eshop.refund_requests WHERE id=p_command AND order_id=o.id)
  AND public.can_prepare_order_provider_refund(o.id) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 hash:=encode(extensions.digest(jsonb_build_object('request',p_request,'action',p_action,'expectedAt',p_expected_at,'response',p_response)::text,'sha256'),'hex');
 receipt:=public.begin_client_mutation_v1(p_command,'orders.customer.request.decide',o.occasion,actor,hash);
 IF receipt->>'disposition'='replay' THEN RETURN receipt->'response'; END IF;
 IF r.updated_at IS DISTINCT FROM p_expected_at OR r.status NOT IN ('open','approved') THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
 SELECT coalesce(array_agg("user"),'{}') INTO users FROM public.occasion_users WHERE occasion=o.occasion;
 IF p_action='approve' THEN
  IF r.status<>'open' THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
  payload:=CASE WHEN r.operation='move' THEN jsonb_build_object('targetFormId',r.target_form_id,'reason',coalesce(r.reason,'')) ELSE jsonb_build_object('reason',coalesce(r.reason,'')) END;
  IF r.ticket_ids IS NOT NULL THEN payload:=payload||jsonb_build_object('ticketIds',to_jsonb(r.ticket_ids)); END IF;
  preview:=public.preview_customer_order_change_internal(o.id,r.operation,payload,true);
  IF preview->>'effect' IN ('request_cancel','request_move') THEN
   RAISE EXCEPTION 'CUSTOMER_REQUEST_REQUIRES_MANUAL_ACTION' USING ERRCODE='40001'; END IF;
  IF preview->>'effect'='cancel_refund' AND public.can_prepare_order_provider_refund(o.id) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='financial permission required'; END IF;
  result:=public.apply_customer_order_change_internal(o.id,r.operation,payload,preview,p_command,r.id);
  UPDATE eshop.customer_order_change_requests SET status='approved',response=nullif(btrim(p_response),''),
   decided_by=actor,decision_command=p_command,updated_at=clock_timestamp() WHERE id=r.id;
 ELSIF p_action='reject' THEN
  IF r.status<>'open' THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
  UPDATE eshop.customer_order_change_requests SET status='rejected',response=nullif(btrim(p_response),''),
   decided_by=actor,decision_command=p_command,updated_at=clock_timestamp() WHERE id=r.id;
 ELSE
  IF nullif(btrim(p_response),'') IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='resolution response required'; END IF;
  -- A manual refund obligation cannot be marked paid by a staff click.
  IF r.operation='cancel' AND r.status='approved' AND (coalesce((public.payment_method_context_internal(o.id)->>'net')::numeric,0)>CASE WHEN r.ticket_ids IS NULL OR o.state='storno' THEN 0 ELSE o.price END OR public.payment_method_context_internal(o.id)->'invalidIdentity' IS DISTINCT FROM 'false'::jsonb OR coalesce((public.payment_method_context_internal(o.id)->>'pending')::numeric,0)>0) THEN
   RAISE EXCEPTION 'REFUND_SETTLEMENT_REQUIRED' USING ERRCODE='40001'; END IF;
  UPDATE eshop.customer_order_change_requests SET status='resolved',response=btrim(p_response),decided_by=actor,
   decision_command=p_command,updated_at=clock_timestamp() WHERE id=r.id;
 END IF;
 PERFORM public.publish_customer_order_request_internal(r.id);
 -- Storno owns its confirmation; support decisions use the same existing queue.
 IF (SELECT state FROM eshop.orders WHERE id=o.id)<>'storno' THEN
  PERFORM public.enqueue_order_email('TICKET_ORDER_UPDATE',jsonb_build_object('order_id',o.id),oc.organization,oc.id,oc.unit,now(),'customer-request:'||p_command);
 END IF;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command,o.occasion,'orders.customer.request.decide',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update','changedFields',jsonb_build_array('customerRequests'))),
  users,jsonb_build_object('code',200,'requestId',r.id));
END $$;
REVOKE ALL ON FUNCTION public.command_customer_order_request(uuid,text,uuid,timestamptz,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.command_customer_order_request(uuid,text,uuid,timestamptz,text) TO authenticated;
