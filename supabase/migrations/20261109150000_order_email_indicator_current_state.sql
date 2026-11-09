-- Keep resolved delivery failures in history without overriding the current indicator.
CREATE OR REPLACE FUNCTION public.get_order_email_summaries(p_occasion bigint,p_orders bigint[]) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_summary jsonb;
BEGIN
 IF NOT coalesce(public.can_read_orders(p_occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=ANY(p_orders) AND occasion<>p_occasion) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 WITH messages AS (
 SELECT m.*,public.email_reporting_state(m) reporting_state FROM public.email_messages m WHERE m.order_id=ANY(p_orders) AND m.occasion=p_occasion
  AND workflow_state NOT IN ('cancelled','expired')),
 current_issues AS MATERIALIZED (
 SELECT order_id,public.order_email_current_issues(order_id) issues FROM (SELECT DISTINCT order_id FROM messages) orders),
 ranked AS (
 -- Historical failures remain visible in messages, but only unresolved failures
 -- may outrank successfully delivered replacement messages in the indicator.
 SELECT m.*,i.issues,CASE WHEN reporting_state IN ('complaint','bounce','reject','rendering_failure','unknown','dead','suppressed','retry_wait','post_action_failed')
 AND EXISTS(SELECT 1 FROM jsonb_array_elements(i.issues) issue WHERE issue->>'message_id'=m.message_id::text) THEN 0
 WHEN workflow_state IN ('pending','preparing','sending','blocked') AND target_time<=now() THEN 1
 WHEN workflow_state='accepted' AND reporting_state NOT IN ('complaint','bounce','reject','rendering_failure') THEN 2 ELSE 3 END rank FROM messages m JOIN current_issues i USING(order_id))
 SELECT coalesce(jsonb_object_agg(r.order_id,jsonb_build_object('state',r.reporting_state,'kind',r.message_kind,'recipient',r.recipient,'message_id',r.message_id,'at',coalesce(r.clicked_at,r.opened_at,r.delivered_at,r.accepted_at,r.created_at),
 'current_issues',r.issues,'scheduled_at',r.target_time,'attention_count',(SELECT count(*) FROM ranked n WHERE n.order_id=r.order_id AND rank=0),'loaded_at',now(),
 'messages',(SELECT coalesce(jsonb_agg(jsonb_build_object('kind',message_kind,'state',reporting_state,'at',coalesce(delivered_at,accepted_at,created_at)) ORDER BY created_at DESC),'[]') FROM ranked n WHERE n.order_id=r.order_id))
),'{}'::jsonb) INTO v_summary FROM (SELECT DISTINCT ON (order_id) * FROM ranked ORDER BY order_id,rank,created_at DESC,id DESC) r;
 SELECT v_summary||coalesce(jsonb_object_agg(o.id,jsonb_build_object('state','unavailable','messages','[]'::jsonb,
  'current_issues',public.order_email_current_issues(o.id),'loaded_at',now())),'{}') INTO v_summary
 FROM eshop.orders o WHERE o.id=ANY(p_orders) AND o.occasion=p_occasion AND NOT v_summary ? o.id::text;
 RETURN v_summary;
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_summaries(bigint,bigint[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_email_summaries(bigint,bigint[]) TO authenticated,service_role;
