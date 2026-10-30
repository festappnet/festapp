-- Resolve obsolete confirmation failures after verified current ticket delivery.
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
   -- Delivered current tickets supersede the obsolete checkout confirmation,
   -- even though confirmation and ticket repairs intentionally have separate chains.
   -- Acceptance/open tracking alone, stale snapshots and unrelated message kinds
   -- must never clear an actionable delivery failure.
   AND NOT (root.message_kind='order_confirmation' AND o.state IN ('paid','sent')
    AND EXISTS(SELECT 1 FROM messages tickets WHERE tickets.message_kind='order_tickets'
     AND tickets.rs IN ('delivery','open','click') AND tickets.delivered_at IS NOT NULL
     AND tickets.recipient=o.data->>'email' AND tickets.source_version=o.email_payment_version
     AND (tickets.data->>'repair_payment_fingerprint' IS NULL
      OR tickets.data->>'repair_payment_fingerprint'=public.order_email_payment_fingerprint(o.id))
     AND tickets.delivered_at>greatest(leaf.created_at,leaf.bounced_at,leaf.complained_at,
      (SELECT max(provider_time) FROM public.email_delivery_events
       WHERE message_id=leaf.message_id AND event_type IN ('bounce','complaint','reject','rendering_failure')))))
   AND NOT (leaf.delivered_at IS NOT NULL AND leaf.rs IN ('delivery','open','click')
    AND leaf.recipient=o.data->>'email' AND leaf.source_version=o.email_payment_version
    AND (leaf.data->>'repair_payment_fingerprint' IS NULL OR leaf.data->>'repair_payment_fingerprint'=public.order_email_payment_fingerprint(o.id))))
 SELECT coalesce(jsonb_agg(to_jsonb(issues) ORDER BY source_message_id),'[]'::jsonb) FROM issues;
$$;
REVOKE ALL ON FUNCTION public.order_email_current_issues(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_email_current_issues(bigint) TO service_role;
