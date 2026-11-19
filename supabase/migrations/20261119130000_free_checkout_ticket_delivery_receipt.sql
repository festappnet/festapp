-- Track the ticket email when it replaces a free checkout confirmation.

-- SOURCE: emails/email_domain.sql (order_email_automatic_key_internal, enqueue_order_email)
-- Automatic confirmations and ticket emails share the same order snapshot identity.
CREATE OR REPLACE FUNCTION public.order_email_automatic_key_internal(p_order bigint,p_version bigint,p_recipient text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT p_order||':'||p_version||':'||coalesce(p_recipient,'')||':false';
$$;
REVOKE ALL ON FUNCTION public.order_email_automatic_key_internal(bigint,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_email_automatic_key_internal(bigint,bigint,text) TO service_role;

-- Invoker-only helper. Its ACL prevents public use; public domain commands own permissions.
CREATE OR REPLACE FUNCTION public.enqueue_order_email(p_code text,p_data jsonb,p_org bigint,p_occ bigint,p_unit bigint,p_time timestamptz DEFAULT now(),p_request text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_kind text; v_version bigint; v_key text; v_recipient text; v_existing public.email_messages; v_base_key text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=coalesce((p_data->>'order_id')::bigint,(p_data#>>'{ticket_order,order,id}')::bigint) FOR UPDATE;
 SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
 IF v_order.id IS NULL OR v_order.occasion<>p_occ THEN RAISE EXCEPTION 'invalid_order_email'; END IF;
 IF v_order.state='stock' THEN RAISE EXCEPTION 'ORDER_ACTION_NOT_ALLOWED'; END IF;
 IF v_order.data ? 'ticketBatchOrigin' AND nullif(trim(v_order.data->>'email'),'') IS NULL THEN
  RETURN jsonb_build_object('state','skipped','reason','no_recipient'); END IF;
 IF v_order.state='storno' AND p_code<>'TICKET_ORDER_STORNO' THEN
  RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
 END IF;
 v_kind:=CASE p_code WHEN 'TICKET_ORDER_CONFIRMATION' THEN 'order_confirmation' WHEN 'TICKET_ORDER_PAYMENT_DONE' THEN 'order_payment_notice'
  WHEN 'TICKET_ORDER_REMINDER' THEN 'order_reminder' WHEN 'TICKET_ORDER_STORNO' THEN 'order_storno' WHEN 'TICKET_ORDER_UPDATE' THEN 'order_update'
  WHEN 'ORDER_TICKETS' THEN 'order_tickets' END;
 IF v_kind IS NULL THEN RAISE EXCEPTION 'unsupported_order_email'; END IF;
 v_version:=CASE WHEN v_kind='order_reminder' THEN v_pi.email_reminder_version ELSE v_order.email_payment_version END;
 v_recipient:=coalesce(p_data->>'recipient',v_order.data->>'email');
 v_key:=coalesce(p_request,p_data->>'command_id',v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':'||coalesce(p_data->>'is_deposit_reminder','false'));
 IF v_kind='order_storno' AND coalesce(p_request,'') NOT LIKE 'manual:%' THEN
  -- requested_by is audit metadata, never proof of an explicit resend.
  v_recipient:=v_order.data->>'email';
  p_data:=jsonb_build_object('order_id',v_order.id);
  v_key:=v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':storno';
  -- Older Edge follow-ups carried requested_by but no explicit resend ID and
  -- used the generic :false key. Reuse that committed identity rather than
  -- manufacture a second automatic message, including cancelled/expired rows.
  SELECT * INTO v_existing FROM public.email_messages
    WHERE organization=p_org AND order_id=v_order.id AND message_kind='order_storno'
      AND recipient=v_recipient AND source_version=v_version
      AND dedupe_key IN (v_key,v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':false')
    ORDER BY (dedupe_key=v_key) DESC,id LIMIT 1;
  IF v_existing.id IS NOT NULL THEN v_key:=v_existing.dedupe_key; END IF;
 END IF;
 IF v_kind IN ('order_tickets','order_confirmation') THEN
  SELECT * INTO v_existing FROM public.email_messages WHERE order_id=v_order.id AND message_kind=v_kind AND recipient=v_recipient AND source_version=v_version
    AND workflow_state IN ('pending','preparing','sending','retry_wait','unknown') ORDER BY id DESC LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
   IF p_data->>'requested_by' IS NOT NULL THEN UPDATE public.email_messages SET post_action=post_action||jsonb_build_object('last_manual_request',jsonb_build_object('actor',p_data->>'requested_by','request',p_request,'at',now())) WHERE id=v_existing.id; END IF;
   RETURN jsonb_build_object('message_id',v_existing.message_id,'state',v_existing.workflow_state,'replayed',true);END IF;
  v_base_key:=public.order_email_automatic_key_internal(v_order.id,v_version,v_recipient);
  IF p_request IS NULL OR NOT EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=v_order.id AND message_kind=v_kind AND recipient=v_recipient AND source_version=v_version) THEN v_key:=v_base_key;END IF;
 END IF;
 RETURN public.enqueue_email(v_kind,jsonb_build_object('organization',p_org,'occasion',p_occ,'unit',p_unit),v_recipient,p_data,v_key,
 CASE WHEN p_code='ORDER_TICKETS' THEN 'TICKET_ORDER_PAYMENT_DONE' ELSE p_code END,p_time,
 CASE WHEN v_kind='order_reminder' THEN p_time+interval '7 days' ELSE NULL END,v_order.id,v_version);
END $$;

-- SOURCE: emails/email_reporting.sql (create_email_confirmation_receipt)
CREATE OR REPLACE FUNCTION public.create_email_confirmation_receipt(p_command uuid,p_order bigint,p_hash text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_message uuid;
BEGIN
 PERFORM public.require_service_role();
 -- The checkout confirmation still proves that this command owns the order.
 -- For free orders that issue tickets immediately, observe the replacement email.
 SELECT coalesce(tickets.message_id,confirmation.message_id) INTO v_message
 FROM public.email_messages confirmation
 JOIN eshop.orders o ON o.id=confirmation.order_id
 LEFT JOIN public.email_messages tickets ON o.price=0
   AND public.order_checkout_email_kind_internal(o.id)='order_tickets'
   AND tickets.organization=confirmation.organization
   AND tickets.occasion=confirmation.occasion
   AND tickets.order_id=o.id AND tickets.message_kind='order_tickets'
   AND tickets.recipient=confirmation.recipient AND tickets.source_version=confirmation.source_version
   AND tickets.dedupe_key=public.order_email_automatic_key_internal(o.id,confirmation.source_version,o.data->>'email')
 WHERE confirmation.message_kind='order_confirmation'
   AND confirmation.data->>'command_id'=p_command::text AND confirmation.order_id=p_order
 ORDER BY confirmation.id
 LIMIT 1;
 IF v_message IS NULL THEN RETURN false; END IF;
 INSERT INTO public.email_confirmation_receipts(token_hash,message_id,expires_at) VALUES(p_hash,v_message,now()+interval '15 minutes');
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.create_email_confirmation_receipt(uuid,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_email_confirmation_receipt(uuid,bigint,text) TO service_role;
