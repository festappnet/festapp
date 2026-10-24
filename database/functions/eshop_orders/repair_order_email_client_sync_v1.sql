-- Shared recipient validation. Preserve aliases and local-part spelling.
CREATE OR REPLACE FUNCTION public.normalize_order_email_contact(p_email text)
RETURNS text LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=public,extensions AS $$
DECLARE v_email text:=btrim(p_email);
BEGIN
 IF length(v_email)>320 OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid_email_contact'; END IF;
 RETURN v_email;
END $$;
REVOKE ALL ON FUNCTION public.normalize_order_email_contact(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_order_email_contact(text) TO service_role;

-- A read token over the existing payment facts, not a stored/global version.
CREATE OR REPLACE FUNCTION public.order_email_payment_fingerprint(p_order bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT encode(extensions.digest(jsonb_build_array(o.payment_info,p.payment_method,p.amount,p.paid,p.returned,
  p.currency_code,p.deadline,p.deposit_amount,p.deposit_deadline,p.variable_symbol,p.creditor_reference,
  p.bank_account,b.account_number,b.account_number_human_readable,b.creditor_name)::text,'sha256'),'hex')
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info
 LEFT JOIN eshop.bank_accounts b ON b.id=p.bank_account WHERE o.id=p_order;
$$;
REVOKE ALL ON FUNCTION public.order_email_payment_fingerprint(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_email_payment_fingerprint(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.repair_order_email_client_sync_v1(
 p_order bigint,p_expected_email text,p_expected_state text,p_expected_payment_version bigint,
 p_email text,p_source_message uuid,p_resend boolean,p_command_id uuid,p_expected_payment_fingerprint text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; oc public.occasions; src public.email_messages; active public.email_messages;
 v_begin jsonb; v_hash text; v_email text; v_form bigint; v_field bigint; v_fields jsonb;
 v_kind text; v_intent jsonb; v_users uuid[]; v_payload jsonb; v_details jsonb; v_origin text;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO oc FROM public.occasions WHERE id=o.occasion;
 IF auth.uid() IS NULL OR o.id IS NULL OR NOT coalesce(public.can_write_orders(o.occasion),false) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 -- Re-authorize the object relationship even on receipt replay.
 IF p_source_message IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.email_messages m
  WHERE m.message_id=p_source_message AND m.order_id=o.id AND m.occasion=o.occasion
   AND m.organization=oc.organization AND public.email_report_allowed(m.organization,m.occasion,m.recipient_user)) THEN
  RAISE insufficient_privilege USING MESSAGE='order email unavailable'; END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('order',p_order,'expectedEmail',p_expected_email,
  'expectedState',p_expected_state,'expectedVersion',p_expected_payment_version,'email',p_email,
  'source',p_source_message,'resend',p_resend,'paymentFingerprint',p_expected_payment_fingerprint)::text,'sha256'),'hex');
 v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.order.repair_email',o.occasion,auth.uid(),v_hash);
 IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
 v_form:=o.form;
 -- Same form -> order -> message order as response editing / send fencing.
 IF v_form IS NOT NULL THEN PERFORM 1 FROM public.forms WHERE id=v_form FOR SHARE; END IF;
 SELECT * INTO o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 IF o.id IS NULL OR o.form IS DISTINCT FROM v_form OR o.data->>'email' IS DISTINCT FROM p_expected_email
  OR o.state IS DISTINCT FROM p_expected_state OR o.email_payment_version IS DISTINCT FROM p_expected_payment_version
  OR p_expected_payment_fingerprint IS DISTINCT FROM public.order_email_payment_fingerprint(o.id) THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','order_changed')); END IF;
 PERFORM public.check_occasion_writable(o.occasion);
 IF o.state NOT IN ('ordered','paid','sent') THEN RAISE EXCEPTION 'ORDER_ACTION_NOT_ALLOWED'; END IF;
 IF p_resend IS NULL OR p_email IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invalid_email_contact'; END IF;
 v_email:=public.normalize_order_email_contact(p_email);
 v_kind:=CASE WHEN o.state='ordered' THEN 'order_confirmation' ELSE 'order_tickets' END;
 PERFORM 1 FROM public.email_messages WHERE order_id=o.id ORDER BY id FOR UPDATE;
 SELECT * INTO src FROM public.email_messages WHERE message_id=p_source_message;
 IF p_resend AND src.id IS NOT NULL AND (src.message_kind<>v_kind OR src.last_error='post_action_failed') THEN
  RAISE EXCEPTION 'source_not_resendable'; END IF;
 -- An issued permit or unknown outcome cannot be bypassed by changing contact.
 IF p_resend AND EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=o.id AND message_kind IN ('order_confirmation','order_tickets')
  AND workflow_state IN ('sending','unknown')) THEN RAISE EXCEPTION 'email_outcome_unresolved'; END IF;
 IF p_resend AND EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_email)) THEN
  RAISE EXCEPTION 'email_recipient_suppressed'; END IF;
 IF p_resend THEN
  SELECT * INTO active FROM public.email_messages WHERE order_id=o.id AND message_kind=v_kind
   AND workflow_state IN ('pending','preparing','retry_wait','blocked')
   AND recipient=o.data->>'email' AND source_version=o.email_payment_version
   AND (expires_at IS NULL OR expires_at>now())
   ORDER BY id DESC LIMIT 1;
  IF active.id IS NOT NULL THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
    jsonb_build_object('reason','active_email_intent','messageId',active.message_id)); END IF;
 END IF;
 -- Repair chains have one successor per source. A stale source cannot fork
 -- around a newer failed/waiting attempt, even after its active lease ended.
 IF p_resend AND src.id IS NOT NULL AND EXISTS(SELECT 1 FROM public.email_messages
  WHERE order_id=o.id AND data->>'repair_source_message_id'=src.message_id::text) THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
   jsonb_build_object('reason','source_replaced')); END IF;
 -- Update only the existing contact projection, without invoking pricing/stock.
 SELECT min(id) INTO v_field FROM public.form_fields WHERE form=v_form AND type='email';
 IF (SELECT count(*) FROM public.form_fields WHERE form=v_form AND type='email')>1 THEN
  RAISE EXCEPTION 'ambiguous_contact_field'; END IF;
 IF v_field IS NOT NULL THEN
  SELECT coalesce(jsonb_agg(e - v_field::text) FILTER (WHERE e - v_field::text<>'{}'::jsonb),'[]') INTO v_fields
   FROM jsonb_array_elements(coalesce(o.data->'fields','[]')) e;
  o.data:=jsonb_set(o.data,'{fields}',v_fields||jsonb_build_array(jsonb_build_object(v_field::text,v_email)));
 END IF;
 UPDATE eshop.orders SET data=jsonb_set(o.data,'{email}',to_jsonb(v_email)),updated_at=now()
  WHERE id=o.id RETURNING * INTO o;
 INSERT INTO eshop.orders_history("order",state,price,currency_code,data,created_by)
  VALUES(o.id,o.state,o.price,o.currency_code,o.data,auth.uid());
 -- A prepared payload is a snapshot of its recipient; retire pre-permit old
 -- contacts explicitly, including legacy manual ticket snapshots.
 UPDATE public.email_messages SET workflow_state='cancelled',last_error='contact_changed',lease_token=NULL,lease_until=NULL
  WHERE order_id=o.id AND recipient IS DISTINCT FROM v_email
   AND workflow_state IN ('pending','preparing','retry_wait','blocked');
 IF p_resend THEN
  v_payload:=jsonb_build_object('order_id',o.id,'requested_by',auth.uid(),'repair_source_message_id',p_source_message,'repair_payment_fingerprint',p_expected_payment_fingerprint);
  IF v_kind='order_confirmation' THEN
   -- The existing confirmation renderer consumes the canonical checkout shape,
   -- not an order ID. Rebuild it from current facts without a checkout mutation.
   v_details:=public.get_order_details_for_email(o.id)->'data';
   SELECT data->>'command_id' INTO v_origin FROM public.email_messages
    WHERE order_id=o.id AND message_kind='order_confirmation' AND data->>'command_id' IS NOT NULL
    ORDER BY id LIMIT 1;
   v_payload:=v_payload||jsonb_build_object('command_id',v_origin,
    'ticket_order',jsonb_build_object('order',v_details->'order'||jsonb_build_object(
     'occasion',v_details->'occasion','reply_to',v_details->'reply_to',
     'form',jsonb_build_object('id',o.form,'data',v_details->'form_data'),
     'payment_info',coalesce(v_details->'payment_info','{}')||jsonb_build_object(
      'account_number',v_details#>'{bank_account,account_number}',
      'account_number_human_readable',v_details#>'{bank_account,account_number_human_readable}',
      'creditor_name',v_details#>'{bank_account,creditor_name}'))));
  END IF;
  v_intent:=public.enqueue_order_email(CASE v_kind WHEN 'order_confirmation' THEN 'TICKET_ORDER_CONFIRMATION' ELSE 'ORDER_TICKETS' END,
   v_payload,
   oc.organization,oc.id,oc.unit,now(),'repair:'||p_command_id);
  IF v_intent->>'message_id' IS NULL OR coalesce((v_intent->>'replayed')::boolean,false) THEN
   RAISE EXCEPTION 'email_enqueue_rejected'; END IF;
 END IF;
 SELECT coalesce(array_agg("user"),'{}') INTO v_users FROM public.occasion_users WHERE occasion=o.occasion;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,o.occasion,'inventory.order.repair_email',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update',
    'safeLabel','Order contact','changedFields',jsonb_build_array('data'))),v_users,
  jsonb_build_object('order',to_jsonb(o)||jsonb_build_object('email_payment_fingerprint',public.order_email_payment_fingerprint(o.id)),'intent',v_intent,'sendingRequested',p_resend));
END $$;
REVOKE ALL ON FUNCTION public.repair_order_email_client_sync_v1(bigint,text,text,bigint,text,uuid,boolean,uuid,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.repair_order_email_client_sync_v1(bigint,text,text,bigint,text,uuid,boolean,uuid,text) TO authenticated;

-- Extend the current registry row in place; no readiness/version transition.
UPDATE public.client_sync_component_sources SET canonical_writers=array_append(canonical_writers,'repair_order_email_client_sync_v1')
 WHERE source_relation='eshop.orders'::regclass AND NOT ('repair_order_email_client_sync_v1'=ANY(canonical_writers));
