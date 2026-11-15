CREATE OR REPLACE FUNCTION public.lock_customer_order_change_internal(p_order bigint,p_target bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE oc public.occasions; fid bigint;
BEGIN
 SELECT occasion,form INTO oc.id,fid FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=oc.id;
 PERFORM public.payment_policy_fence_internal(oc.organization);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[oc.id]);
 PERFORM 1 FROM public.forms WHERE id IN(fid,p_target) AND occasion=oc.id ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.orders WHERE id=p_order FOR UPDATE;
 -- Form saves take this same occasion fence before their product locks.
 PERFORM 1 FROM eshop.products WHERE occasion=oc.id ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=p_order) FOR UPDATE;
 PERFORM 1 FROM eshop.tickets WHERE id IN(SELECT id FROM public.get_order_tickets_internal(p_order)) ORDER BY id FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION public.lock_customer_order_change_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.publish_customer_order_request_internal(p_request uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE r eshop.customer_order_change_requests; oc public.occasions;
BEGIN
 SELECT * INTO STRICT r FROM eshop.customer_order_change_requests WHERE id=p_request;
 SELECT occ.* INTO STRICT oc FROM public.occasions occ JOIN eshop.orders o ON o.occasion=occ.id WHERE o.id=r.order_id;
 -- Request reasons/answers never enter notification payloads or technical audit.
 PERFORM public.notification_center_order_internal(r.order_id,'customer_order_request','customer-request:'||r.id||':'||r.status,
  NULL,jsonb_build_object('customerRequestId',r.id,'customerRequestOperation',r.operation,'customerRequestStatus',r.status));
END $$;
REVOKE ALL ON FUNCTION public.publish_customer_order_request_internal(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.apply_customer_order_change_internal(p_order bigint,p_operation text,p_payload jsonb,p_preview jsonb,p_command uuid,p_existing_request uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; oc public.occasions; effect text:=p_preview->>'effect'; request_id uuid:=p_existing_request;
 item record; t eshop.tickets; merged jsonb; fields jsonb; result jsonb; request_status text:='open';
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
 IF effect='edit' THEN
  IF coalesce(p_payload->'order','{}')<>'{}'::jsonb THEN PERFORM public.update_order_responses_domain_internal(o.id,p_payload->'order'); END IF;
  FOR item IN SELECT * FROM jsonb_each(coalesce(p_payload->'tickets','{}')) LOOP
   SELECT * INTO STRICT t FROM eshop.tickets WHERE id=item.key::bigint FOR UPDATE;
   SELECT coalesce(jsonb_object_agg(a.key,a.value),'{}') INTO merged FROM jsonb_array_elements(coalesce(t.data->'fields','[]')) f CROSS JOIN LATERAL jsonb_each(f) a;
   SELECT coalesce(jsonb_agg(jsonb_build_object(key,value) ORDER BY key),'[]') INTO fields FROM jsonb_each(merged||item.value);
   UPDATE eshop.tickets SET data=jsonb_set(coalesce(t.data,'{}'),'{fields}',fields) WHERE id=t.id;
  END LOOP;
  IF coalesce(p_payload->'tickets','{}')<>'{}'::jsonb THEN
   UPDATE eshop.orders ord SET data=jsonb_set(ord.data,'{tickets}',(SELECT coalesce(jsonb_agg(
    CASE WHEN p_payload->'tickets' ? (snapshot->>'id') THEN jsonb_set(snapshot,'{fields}',(SELECT data->'fields' FROM eshop.tickets WHERE id=(snapshot->>'id')::bigint)) ELSE snapshot END),'[]')
    FROM jsonb_array_elements(coalesce(ord.data->'tickets','[]')) snapshot)),updated_at=clock_timestamp() WHERE ord.id=o.id;
   INSERT INTO eshop.orders_history("order",state,price,data,currency_code) SELECT id,state,price,data,currency_code FROM eshop.orders WHERE id=o.id;
  END IF;
  -- Materialized ticket documents and Wallet share the existing delivery owner.
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.cancel_order_email_intents(o.id);
  PERFORM public.enqueue_order_wallet_internal(o.id);
  IF o.state IN ('paid','sent') THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
 ELSIF effect IN ('request_cancel','request_move','cancel_manual_refund') OR (p_operation IN ('cancel','move') AND nullif(btrim(p_payload->>'reason'),'') IS NOT NULL) THEN
  IF effect IN ('cancel_manual_refund','cancel_refund') THEN request_status:='approved'; ELSIF effect IN ('cancel','move') THEN request_status:='resolved'; END IF;
  IF p_existing_request IS NULL THEN
  INSERT INTO eshop.customer_order_change_requests(order_id,organization_id,operation,reason,target_form_id,customer_command,status,ticket_ids)
  VALUES(o.id,oc.organization,p_operation,nullif(btrim(p_payload->>'reason'),''),nullif(p_payload->>'targetFormId','')::bigint,p_command,request_status,CASE WHEN p_payload ? 'ticketIds' THEN ARRAY(SELECT value::bigint FROM jsonb_array_elements_text(p_payload->'ticketIds')) END)
  ON CONFLICT(order_id,operation) WHERE status='open' DO NOTHING RETURNING id INTO request_id;
  IF request_id IS NULL THEN SELECT id INTO request_id FROM eshop.customer_order_change_requests WHERE order_id=o.id AND operation=p_operation AND status='open'; END IF;
  PERFORM public.publish_customer_order_request_internal(request_id);
  END IF;
 END IF;
 IF effect IN ('cancel','cancel_refund','cancel_manual_refund') THEN
  IF effect='cancel_refund' THEN
   PERFORM public.prepare_order_refund_internal(o.id,(SELECT payment_method FROM eshop.payment_info WHERE id=o.payment_info),
    (p_preview->>'refundAmount')::numeric,p_command,'{}');
   INSERT INTO eshop.payment_operation_events(request_id,operation,actor,details) VALUES(p_command,'prepare_refund',auth.uid(),jsonb_build_object('source','customer_order_change','commandId',p_command));
  END IF;
  IF p_preview->'partial'='true'::jsonb THEN
   PERFORM public.cancel_ticket_selection_domain_internal(ARRAY(SELECT value::bigint FROM jsonb_array_elements_text(p_preview->'ticketIds')),true);
  ELSIF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=o.payment_info AND public.payment_method_is_online_internal(payment_method)) THEN
   PERFORM public.cancel_online_order_admission_internal(o.id,'storno');
   INSERT INTO eshop.orders_history("order",state,price,data,currency_code) SELECT id,state,price,data,currency_code FROM eshop.orders WHERE id=o.id;
   PERFORM public.notification_center_order_state_internal(o.id);
   PERFORM public.enqueue_order_email('TICKET_ORDER_STORNO',jsonb_build_object('order_id',o.id),oc.organization,oc.id,oc.unit);
  ELSE PERFORM public.cancel_order_domain_internal_v1(o.id,true); END IF;
  PERFORM public.enqueue_order_wallet_internal(o.id);
 ELSIF effect='move' THEN
  PERFORM public.move_customer_order_domain_internal(o.id,(p_payload->>'targetFormId')::bigint);
 ELSIF effect='withdraw' THEN
  UPDATE eshop.customer_order_change_requests SET status='withdrawn',updated_at=clock_timestamp()
   WHERE id=(p_payload->>'requestId')::uuid AND order_id=o.id AND status='open' RETURNING id INTO request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
 END IF;
 IF (effect IN ('edit','move','request_cancel','request_move','withdraw') OR p_preview->'partial'='true'::jsonb) AND (SELECT state FROM eshop.orders WHERE id=o.id)<>'storno' THEN
  PERFORM public.enqueue_order_email('TICKET_ORDER_UPDATE',jsonb_build_object('order_id',o.id),oc.organization,oc.id,oc.unit,now(),'customer-change:'||p_command);
 END IF;
 INSERT INTO eshop.customer_order_change_events(command_id,order_id,operation,outcome,request_id)
 VALUES(p_command,o.id,p_operation,effect,request_id);
 RETURN jsonb_build_object('code',200,'effect',effect,'requestId',request_id,'orderId',o.id);
END $$;
REVOKE ALL ON FUNCTION public.apply_customer_order_change_internal(bigint,text,jsonb,jsonb,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;


CREATE OR REPLACE FUNCTION public.customer_order_change_gateway(p_action text,p_token text,p_order bigint DEFAULT NULL,
 p_operation text DEFAULT NULL,p_payload jsonb DEFAULT '{}',p_command uuid DEFAULT NULL,p_fingerprint text DEFAULT NULL,
 p_delivery jsonb DEFAULT NULL,p_ip_hash text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE parent eshop.waitlist_capabilities; cap eshop.customer_order_change_capabilities;
 o eshop.orders; oc public.occasions; preview jsonb; limits eshop.customer_order_change_limits; receipt jsonb; result jsonb; users uuid[];
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_action IS NULL OR p_action NOT IN ('challenge_context','challenge','resolve','preview','command') THEN RAISE invalid_parameter_value; END IF;
 IF p_action IN ('challenge_context','challenge') THEN
  parent:=public.customer_change_read_scope_internal(p_token,p_order);
  PERFORM public.lock_customer_order_change_internal(parent.order_id,nullif(p_payload->>'targetFormId','')::bigint);
  parent:=public.customer_change_read_scope_internal(p_token,p_order);
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=parent.order_id;
  SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
  preview:=public.preview_customer_order_change_internal(o.id,p_operation,p_payload);
  IF p_action='challenge' THEN
   IF p_ip_hash IS NULL OR p_ip_hash!~'^[a-f0-9]{64}$' OR p_delivery->>'tokenHash' IS NULL OR p_delivery->>'tokenHash'!~'^[a-f0-9]{64}$'
    OR jsonb_typeof(p_delivery->'source') IS DISTINCT FROM 'object' OR jsonb_typeof(p_delivery->'email') IS DISTINCT FROM 'object'
    OR p_delivery->>'contentHash' IS NULL OR p_delivery->>'contentHash'!~'^[a-f0-9]{64}$' THEN RAISE invalid_parameter_value; END IF;
   PERFORM pg_advisory_xact_lock(hashtextextended('customer-change-order:'||o.id,0));
   PERFORM pg_advisory_xact_lock(hashtextextended('customer-change-ip:'||p_ip_hash,0));
   SELECT * INTO STRICT limits FROM eshop.customer_order_change_limits WHERE singleton;
   IF EXISTS(SELECT 1 FROM eshop.customer_order_change_attempts WHERE (order_id=o.id OR ip_hash=p_ip_hash)
     AND created_at>clock_timestamp()-make_interval(secs=>limits.minimum_seconds))
    OR (SELECT count(*) FROM eshop.customer_order_change_attempts WHERE order_id=o.id AND created_at>clock_timestamp()-interval '1 hour')>=limits.hourly_limit
    OR (SELECT count(*) FROM eshop.customer_order_change_attempts WHERE ip_hash=p_ip_hash AND created_at>clock_timestamp()-interval '1 hour')>=limits.hourly_limit THEN
     RETURN jsonb_build_object('code',202); END IF;
   INSERT INTO eshop.customer_order_change_attempts(order_id,ip_hash) VALUES(o.id,p_ip_hash);
   INSERT INTO eshop.customer_order_change_capabilities(token_hash,parent_hash,organization_id,form_id,order_id,operation,proposal_hash,
    policy_revision,feature_epoch,expires_at)
   VALUES(p_delivery->>'tokenHash',parent.token_hash,oc.organization,o.form,o.id,p_operation,
    encode(extensions.digest(p_payload::text,'sha256'),'hex'),(preview->>'policyRevision')::bigint,oc.customer_self_service_epoch,clock_timestamp()+interval '10 minutes') RETURNING * INTO cap;
   INSERT INTO eshop.customer_order_change_sources VALUES(cap.id,p_delivery->'source',p_delivery->>'contentHash');
   PERFORM public.enqueue_prepared_email('custom',jsonb_build_object('organization',oc.organization,'occasion',oc.id,'unit',oc.unit,'tracking_policy','none'),
    o.data->>'email',p_delivery->'email','customer-change:'||cap.id,p_delivery->>'contentHash','CUSTOMER_ORDER_CHANGE',cap.expires_at);
   RETURN jsonb_build_object('code',202);
  END IF;
  RETURN jsonb_build_object('code',200,'orderId',o.id,'recipient',o.data->>'email','organization',oc.organization,'occasion',oc.id,'unit',oc.unit,
   'webLink',(SELECT data->>'DEFAULT_URL' FROM public.organizations WHERE id=oc.organization),
   'locale',coalesce((SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=oc.organization),'cs'),'preview',preview);
 END IF;
 -- A customer scope is always recovered from the stored credential, never orderId.
 cap:=public.authorize_customer_change_internal(p_token,p_command);
 IF p_order IS NOT NULL AND p_order<>cap.order_id THEN RAISE insufficient_privilege USING MESSAGE='INVALID_CAPABILITY'; END IF;
 IF p_action='resolve' THEN
  RETURN jsonb_build_object('code',200,'orderId',cap.order_id,'operation',cap.operation,
    'source',(SELECT sealed FROM eshop.customer_order_change_sources WHERE capability_id=cap.id));
 END IF;
 PERFORM public.lock_customer_order_change_internal(cap.order_id,nullif(p_payload->>'targetFormId','')::bigint);
 cap:=public.authorize_customer_change_internal(p_token,p_command);
 IF p_operation IS DISTINCT FROM cap.operation OR encode(extensions.digest(p_payload::text,'sha256'),'hex') IS DISTINCT FROM cap.proposal_hash THEN
  RAISE insufficient_privilege USING MESSAGE='INVALID_CAPABILITY'; END IF;
 IF p_action='preview' THEN
  preview:=public.preview_customer_order_change_internal(cap.order_id,cap.operation,p_payload);
  UPDATE eshop.customer_order_change_capabilities SET preview_hash=preview->>'fingerprint',preview_expires_at=(preview->>'expiresAt')::timestamptz WHERE id=cap.id;
  RETURN preview;
 END IF;
 IF p_command IS NULL THEN RAISE invalid_parameter_value; END IF;
 receipt:=public.begin_anonymous_client_mutation_v1(p_command,'orders.customer.'||cap.operation,
  (SELECT occasion FROM eshop.orders WHERE id=cap.order_id),cap.id,encode(extensions.digest(jsonb_build_object('capability',cap.id,'operation',cap.operation,'payload',p_payload,'fingerprint',p_fingerprint)::text,'sha256'),'hex'));
 IF receipt->>'disposition'='replay' THEN RETURN receipt->'response'; END IF;
 preview:=public.preview_customer_order_change_internal(cap.order_id,cap.operation,p_payload);
 IF p_fingerprint IS NULL OR cap.preview_expires_at IS NULL OR cap.preview_expires_at<=clock_timestamp() OR cap.preview_hash IS DISTINCT FROM p_fingerprint OR preview->>'fingerprint' IS DISTINCT FROM p_fingerprint THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
 PERFORM public.admit_order_mutation_scope_internal((SELECT occasion FROM eshop.orders WHERE id=cap.order_id),(SELECT count(*) FROM public.get_order_tickets_internal(cap.order_id)),'customer-order:'||cap.order_id);
 SELECT coalesce(array_agg("user"),'{}') INTO users FROM public.occasion_users WHERE occasion=(SELECT occasion FROM eshop.orders WHERE id=cap.order_id);
 result:=public.apply_customer_order_change_internal(cap.order_id,cap.operation,p_payload,preview,p_command);
 UPDATE eshop.customer_order_change_capabilities SET consumed_by=p_command,consumed_form_id=(SELECT form FROM eshop.orders WHERE id=cap.order_id) WHERE id=cap.id;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command,(SELECT occasion FROM eshop.orders WHERE id=cap.order_id),
  'orders.customer.'||cap.operation,jsonb_build_array(jsonb_build_object('entityType','order','entityId',cap.order_id,'operation','update',
  'changedFields',jsonb_build_array(cap.operation))),users,result,'unknown');
END $$;
REVOKE ALL ON FUNCTION public.customer_order_change_gateway(text,text,bigint,text,jsonb,uuid,text,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.customer_order_change_gateway(text,text,bigint,text,jsonb,uuid,text,jsonb,text) TO service_role;
