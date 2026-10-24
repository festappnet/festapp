-- Close original delivery recovery on order cancellation; retain provider audit facts.
-- Source: database/functions/emails/email_reporting.sql
CREATE OR REPLACE FUNCTION public.order_email_current_issues(p_order bigint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH RECURSIVE messages AS (
  SELECT m.*,CASE WHEN m.complained_at IS NULL AND m.last_error IS DISTINCT FROM 'post_action_failed'
   AND coalesce(m.provider_failure,'') NOT IN ('reject','rendering_failure')
   AND greatest(m.bounced_at,events.bounce) IS NOT NULL
   AND greatest(m.delivered_at,events.delivery)>greatest(m.bounced_at,events.bounce)
   THEN 'delivery' ELSE public.email_reporting_state(m) END rs FROM public.email_messages m
  LEFT JOIN LATERAL (SELECT max(provider_time) FILTER(WHERE event_type='bounce') bounce,
   max(provider_time) FILTER(WHERE event_type='delivery') delivery
   FROM public.email_delivery_events e WHERE e.message_id=m.message_id) events ON true
  JOIN eshop.orders o ON o.id=m.order_id AND o.occasion=m.occasion
  JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=m.organization
  WHERE m.order_id=p_order AND o.state<>'storno'),
 chain AS (
  SELECT m.message_id root,m.message_id leaf,ARRAY[m.message_id] path FROM messages m
  WHERE NOT EXISTS(SELECT 1 FROM messages parent WHERE parent.message_id::text=m.data->>'repair_source_message_id' AND parent.message_kind=m.message_kind)
  UNION ALL
  SELECT c.root,m.message_id,c.path||m.message_id FROM chain c JOIN messages parent ON parent.message_id=c.leaf
  JOIN messages m ON m.data->>'repair_source_message_id'=c.leaf::text AND m.message_kind=parent.message_kind
  WHERE NOT m.message_id=ANY(c.path)),
 leaves AS (SELECT DISTINCT ON (root) * FROM chain ORDER BY root,cardinality(path) DESC,leaf),
 issues AS (
  SELECT root.message_id source_message_id,leaf.message_id,root.message_kind kind,root.recipient original_recipient,
   leaf.recipient,leaf.rs state,
   coalesce(leaf.last_error,CASE WHEN leaf.workflow_state IN ('pending','preparing','blocked') THEN
    (SELECT CASE WHEN paused THEN 'queue_paused' WHEN daily_quota<=provider_sent_24h THEN 'queue_limit' END FROM public.email_capacity) END) reason,
   (SELECT reason FROM public.email_suppressions WHERE recipient=lower(leaf.recipient)) suppression_reason,
   CASE WHEN o.state='storno' THEN 'cancelled'
    WHEN leaf.rs IN ('delivery','open','click') AND leaf.delivered_at IS NOT NULL
     AND (leaf.recipient IS DISTINCT FROM o.data->>'email' OR leaf.source_version IS DISTINCT FROM o.email_payment_version
      OR (leaf.data->>'repair_payment_fingerprint' IS NOT NULL AND leaf.data->>'repair_payment_fingerprint' IS DISTINCT FROM public.order_email_payment_fingerprint(o.id))) THEN 'stale_delivery'
    WHEN leaf.message_id<>root.message_id AND leaf.rs IN ('pending','preparing','accepted','open','click','sending','blocked') THEN 'waiting_repair'
    ELSE leaf.rs END resolution,
   (root.message_kind<>CASE WHEN o.state='ordered' THEN 'order_confirmation' ELSE 'order_tickets' END) obsolete
  FROM leaves c JOIN messages root ON root.message_id=c.root JOIN messages leaf ON leaf.message_id=c.leaf
  JOIN eshop.orders o ON o.id=p_order
  WHERE (EXISTS(SELECT 1 FROM messages m WHERE m.message_id=ANY(c.path)
    AND (m.rs IN ('bounce','complaint','reject','rendering_failure','dead','suppressed','unknown','retry_wait','delay','blocked','sending','post_action_failed')
     OR (m.message_kind IN ('order_confirmation','order_tickets') AND m.workflow_state IN ('pending','preparing') AND m.target_time<=now()))))
   AND NOT (leaf.delivered_at IS NOT NULL AND leaf.rs IN ('delivery','open','click')
    AND leaf.recipient=o.data->>'email' AND leaf.source_version=o.email_payment_version
    AND (leaf.data->>'repair_payment_fingerprint' IS NULL OR leaf.data->>'repair_payment_fingerprint'=public.order_email_payment_fingerprint(o.id))))
 SELECT coalesce(jsonb_agg(to_jsonb(issues) ORDER BY source_message_id),'[]'::jsonb) FROM issues;
$$;
REVOKE ALL ON FUNCTION public.order_email_current_issues(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_email_current_issues(bigint) TO service_role;


-- Source: database/functions/notification_center/email.sql
CREATE OR REPLACE FUNCTION public.notification_center_email_internal(p_message uuid,p_at timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; a public.notification_center_activation; old public.notification_center_source_state;
 reason text; fact_at timestamptz; ev uuid; seen jsonb; key text:='email:'||p_message; due_at timestamptz;
BEGIN
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF NOT FOUND THEN RETURN; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-activation:'||m.organization,0));
 p_at:=coalesce(p_at,clock_timestamp());
 SELECT * INTO a FROM public.notification_center_activation WHERE organization=m.organization FOR SHARE;
 IF NOT FOUND OR NOT a.enabled THEN RETURN; END IF;
 -- Cancellation retires recovery of the original order messages. Provider
 -- callbacks can arrive later; preserve their audit facts without re-alerting.
 -- A failed cancellation notice is a separate, still relevant incident.
 IF m.order_id IS NOT NULL AND m.message_kind<>'order_storno' AND EXISTS(
  SELECT 1 FROM eshop.orders o WHERE o.id=m.order_id AND o.occasion=m.occasion AND o.state='storno') THEN
  UPDATE public.notification_center_events SET status='recovered'
   WHERE organization=m.organization AND source_key=key AND kind='email_problem';
  RETURN;
 END IF;
 reason:=public.email_reporting_state(m);
 SELECT * INTO old FROM public.notification_center_source_state WHERE organization=m.organization AND source_key=key FOR UPDATE;
 due_at:=coalesce((old.state->>'dueAt')::timestamptz,m.target_time);
 IF reason IN ('unknown','retry_wait','pending','preparing','delay') THEN
  IF m.expires_at<=p_at OR m.workflow_state IN ('cancelled','expired') THEN reason:=NULL;
  ELSIF p_at<due_at+interval '30 minutes' AND NOT coalesce((m.message_kind='waitlist_offer' AND m.expires_at<=p_at+interval '5 minutes'),false) THEN reason:=NULL;
  ELSE reason:='delayed'; END IF;
 END IF;
 IF reason='suppressed' AND EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(m.recipient) AND created_at<m.created_at) THEN reason:=NULL; END IF;
 IF reason NOT IN ('complaint','bounce','reject','rendering_failure','dead','suppressed','delayed','post_action_failed') THEN reason:=NULL; END IF;
 fact_at:=CASE reason WHEN 'complaint' THEN m.complained_at WHEN 'bounce' THEN m.bounced_at
 WHEN 'reject' THEN (SELECT min(provider_time) FROM public.email_delivery_events WHERE message_id=m.message_id AND event_type='reject')
 WHEN 'rendering_failure' THEN (SELECT min(provider_time) FROM public.email_delivery_events WHERE message_id=m.message_id AND event_type='rendering_failure')
 WHEN 'delayed' THEN least(p_at,due_at+interval '30 minutes') ELSE p_at END;
 seen:=coalesce(old.state->'seen','[]');
 IF reason IS NOT NULL AND coalesce(fact_at,p_at)>=a.activated_at AND NOT seen ? reason THEN
  ev:=public.notification_center_publish_internal(m.organization,m.occasion,'email_problem',key,
    jsonb_build_object('messageId',m.message_id,'messageKind',m.message_kind,'reason',reason),NULL,coalesce(fact_at,p_at));
  IF ev IS NOT NULL AND old.state->>'eventId'=ev::text THEN
   UPDATE public.notification_center_events SET attention_revision=attention_revision+1,status='active',
    data=data||jsonb_build_object('reason',reason) WHERE id=(old.state->>'eventId')::uuid;
   PERFORM public.notification_center_capture_recipients_internal((old.state->>'eventId')::uuid,NULL);
  END IF;
  seen:=seen||jsonb_build_array(reason);
 ELSIF reason IS NULL AND old.state->>'eventId' IS NOT NULL AND public.email_reporting_state(m) IN ('delivery','open','click','accepted') THEN
  UPDATE public.notification_center_events SET status='recovered' WHERE id=(old.state->>'eventId')::uuid;
 END IF;
 INSERT INTO public.notification_center_source_state(organization,source_key,state)
 VALUES(m.organization,key,jsonb_build_object('reason',reason,'seen',seen,'dueAt',due_at,'eventId',coalesce(ev::text,old.state->>'eventId')))
 ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,observed_at=p_at;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_email_internal(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/eshop_orders/update_order_and_tickets_to_storno.sql
CREATE OR REPLACE FUNCTION public.cancel_order_domain_internal_v1(order_id BIGINT,p_notify boolean)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    ticket_ids BIGINT[];
    updated_order_data jsonb;
    v_order eshop.orders;
    v_occasion public.occasions;
    v_notice jsonb;
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM eshop.orders WHERE id=order_id)]);
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
    SELECT * INTO v_order FROM eshop.orders WHERE id=order_id FOR UPDATE;
    IF v_order.id IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;
    IF v_order.state='storno' THEN RETURN; END IF;
    PERFORM public.check_order_is_mutable(order_id);
    -- Card finances and admission are resolved by provider facts and the
    -- audited refund decision, never by resetting an order's original price.
    IF EXISTS(SELECT 1 FROM eshop.payment_info pi
      WHERE pi.id=v_order.payment_info AND pi.payment_method='stripe') THEN
        RAISE EXCEPTION 'STRIPE_USE_REFUND_ADMISSION_DECISION';
    END IF;
    PERFORM public.cancel_order_email_intents(order_id);
    -- Retrieve all ticket ids associated with the order
    SELECT ARRAY_AGG(t.id) INTO ticket_ids
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    WHERE opt."order" = order_id;

    -- Check if the order exists and has associated tickets
    IF ticket_ids IS NULL THEN
        -- This is not an error, just an order with no tickets yet.
        -- But we can still storno the order itself.
        RAISE NOTICE 'No tickets found for order %, proceeding to storno order shell.', order_id;
    END IF;

    -- Call the helper to storno all tickets and their relations
    -- The helper function gracefully handles an empty/NULL array
    PERFORM internal_storno_tickets_221(ticket_ids);

    -- Set the order state to 'storno', price to 0, and update the data field
    UPDATE eshop.orders
    SET state = 'storno',
        price = 0,
        data = COALESCE(data, '{}'::jsonb) || jsonb_build_object('tickets', '[]'::jsonb),
        updated_at = NOW()
    WHERE id = order_id
    RETURNING data INTO updated_order_data;

    -- Finish the original email recovery task in the same cancellation transaction.
    -- Keep provider messages and delivery history intact.
    UPDATE public.notification_center_events e SET status='recovered'
    FROM public.email_messages m
    WHERE m.order_id=v_order.id AND m.occasion=v_order.occasion
      AND m.message_kind<>'order_storno' AND e.organization=m.organization
      AND e.kind='email_problem' AND e.source_key='email:'||m.message_id;


    -- Save the change to orders_history by inserting the updated order row
    INSERT INTO eshop.orders_history (
        "order",
        state,
        price,
        data,
        created_at
    )
    VALUES (
        order_id,
        'storno',
        0,
        updated_order_data,
        NOW()
    );

    -- The full transition owns the durable automatic commitment for every caller.
    SELECT * INTO v_occasion FROM public.occasions WHERE id=v_order.occasion;
    IF p_notify AND position('@' in v_order.data->>'email')>0
      AND length(v_order.data->>'email')<=320 THEN
      v_notice:=public.enqueue_order_email('TICKET_ORDER_STORNO',
        jsonb_build_object('order_id',order_id),v_occasion.organization,
        v_occasion.id,v_occasion.unit);
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_order_domain_internal_v1(bigint,boolean)
 FROM PUBLIC,anon,authenticated,service_role;
-- Compatibility for trusted SQL callers; domain logic exists only above.
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno_221(order_id bigint)
RETURNS void LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.cancel_order_domain_internal_v1(order_id,true);
$$;
REVOKE ALL ON FUNCTION public.update_order_and_tickets_to_storno_221(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
