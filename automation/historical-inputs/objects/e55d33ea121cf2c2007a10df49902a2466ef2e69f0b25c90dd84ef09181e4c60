CREATE OR REPLACE FUNCTION public.get_email_occasion_context(p_occasion bigint) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT jsonb_build_object('organization',organization,'unit',unit) FROM public.occasions WHERE id=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.get_email_occasion_context(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_occasion_context(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.email_reporting_state(m public.email_messages) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN m.complained_at IS NOT NULL THEN 'complaint' WHEN m.bounced_at IS NOT NULL THEN 'bounce'
 WHEN m.last_error='post_action_failed' THEN 'post_action_failed' WHEN m.provider_failure IN ('reject','rendering_failure') THEN m.provider_failure
 WHEN m.workflow_state IN ('unknown','dead','suppressed','retry_wait') THEN m.workflow_state
 WHEN m.clicked_at IS NOT NULL THEN 'click' WHEN m.opened_at IS NOT NULL THEN 'open' WHEN m.delivered_at IS NOT NULL THEN 'delivery'
 WHEN m.provider_failure='delay' THEN 'delay' ELSE m.workflow_state END;
$$;
REVOKE ALL ON FUNCTION public.email_reporting_state(public.email_messages) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.email_reporting_state(public.email_messages) TO service_role;

CREATE OR REPLACE FUNCTION public.get_order_email_summaries(p_occasion bigint,p_orders bigint[]) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_summary jsonb;
BEGIN
 IF NOT coalesce(public.get_is_editor_order_view_on_occasion(p_occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=ANY(p_orders) AND occasion<>p_occasion) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 WITH messages AS (
 SELECT m.*,public.email_reporting_state(m) reporting_state FROM public.email_messages m WHERE m.order_id=ANY(p_orders) AND m.occasion=p_occasion
  AND workflow_state NOT IN ('cancelled','expired')),
 ranked AS (
 SELECT *,CASE WHEN reporting_state IN ('complaint','bounce','reject','rendering_failure','unknown','dead','suppressed','retry_wait','post_action_failed') THEN 0
 WHEN workflow_state IN ('pending','preparing','sending','blocked') AND target_time<=now() THEN 1
 WHEN workflow_state='accepted' THEN 2 ELSE 3 END rank FROM messages)
 SELECT coalesce(jsonb_object_agg(r.order_id,jsonb_build_object('state',r.reporting_state,'kind',r.message_kind,'message_id',r.message_id,'at',coalesce(r.clicked_at,r.opened_at,r.delivered_at,r.accepted_at,r.created_at),
 'scheduled_at',r.target_time,'attention_count',(SELECT count(*) FROM ranked n WHERE n.order_id=r.order_id AND rank=0),'loaded_at',now(),
 'messages',(SELECT coalesce(jsonb_agg(jsonb_build_object('kind',message_kind,'state',reporting_state,'at',coalesce(delivered_at,accepted_at,created_at)) ORDER BY created_at DESC),'[]') FROM ranked n WHERE n.order_id=r.order_id))
),'{}'::jsonb) INTO v_summary FROM (SELECT DISTINCT ON (order_id) * FROM ranked ORDER BY order_id,rank,created_at DESC,id DESC) r;
 RETURN v_summary;
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_summaries(bigint,bigint[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_email_summaries(bigint,bigint[]) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_order_email_summary(p_order bigint) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_occ bigint;
BEGIN
 SELECT occasion INTO v_occ FROM eshop.orders WHERE id=p_order;
 IF v_occ IS NULL THEN RAISE EXCEPTION 'order_not_found'; END IF;
 RETURN coalesce(public.get_order_email_summaries(v_occ,ARRAY[p_order])->p_order::text,jsonb_build_object('state','unavailable','messages','[]'::jsonb,'loaded_at',now()));
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_summary(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_email_summary(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.email_report_allowed(p_org bigint,p_occasion bigint,p_user uuid DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce(public.get_is_admin_on_organization(p_org),false) OR
 (p_occasion IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion AND organization=p_org)
 AND coalesce(public.get_is_editor_order_view_on_occasion(p_occasion),false)
 AND (p_user IS NULL OR EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user)));
$$;
REVOKE ALL ON FUNCTION public.email_report_allowed(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.email_report_allowed(bigint,bigint,uuid) TO authenticated,service_role;

DROP FUNCTION IF EXISTS public.get_email_delivery_page(bigint,bigint,integer,bigint,text,text,bigint,uuid,timestamptz);
CREATE OR REPLACE FUNCTION public.get_email_delivery_page(p_occasion bigint,p_before bigint DEFAULT NULL,p_limit integer DEFAULT 30,p_order bigint DEFAULT NULL,p_kind text DEFAULT NULL,p_state text DEFAULT NULL,p_organization bigint DEFAULT NULL,p_user uuid DEFAULT NULL,p_since timestamptz DEFAULT NULL,p_orders_only boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;v_org bigint;
BEGIN
 v_org:=coalesce(p_organization,(SELECT organization FROM public.occasions WHERE id=p_occasion));
 IF NOT coalesce(public.email_report_allowed(v_org,p_occasion,p_user),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 IF p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_page_limit'; END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 SELECT coalesce(jsonb_agg(x ORDER BY id DESC),'[]') INTO v_result FROM (
 SELECT id,message_id,message_kind,order_id,(SELECT o.order_symbol FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=m.order_id AND oc.organization=m.organization AND o.occasion=m.occasion) order_symbol,created_at,accepted_at,delivered_at,bounced_at,complained_at,opened_at,clicked_at,
 public.email_reporting_state(m) state,tracking_policy,post_action_state,last_error FROM public.email_messages m
 WHERE organization=v_org AND (p_occasion IS NULL OR occasion=p_occasion OR (p_user IS NOT NULL AND occasion IS NULL))
 AND (p_user IS NULL OR recipient_user=p_user) AND (p_since IS NULL OR created_at>=p_since) AND (p_before IS NULL OR id<p_before) AND (p_order IS NULL OR order_id=p_order)
 AND (NOT coalesce(p_orders_only,false) OR order_id IS NOT NULL)
 AND (p_kind IS NULL OR message_kind=p_kind) AND (p_state IS NULL OR public.email_reporting_state(m)=p_state)
 ORDER BY id DESC LIMIT p_limit) x;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_page(bigint,bigint,integer,bigint,text,text,bigint,uuid,timestamptz,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_page(bigint,bigint,integer,bigint,text,text,bigint,uuid,timestamptz,boolean) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_email_delivery_detail(p_message uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages;
BEGIN
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF m.message_id IS NULL THEN RAISE EXCEPTION 'email_detail_not_available'; END IF;
 IF NOT coalesce(public.email_report_allowed(m.organization,m.occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 RETURN jsonb_build_object('message',jsonb_build_object('id',m.message_id,'kind',m.message_kind,'state',public.email_reporting_state(m),'tracking_policy',m.tracking_policy,'opened_at',m.opened_at,'clicked_at',m.clicked_at,'post_action',m.post_action_state,'last_error',m.last_error,'provider_id',m.provider_message_id,'requested_by',m.data->>'requested_by'),
 'attempts',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',attempt_id,'state',state,'at',created_at,'error',error_code,'provider_id',provider_message_id) ORDER BY created_at),'[]') FROM public.email_attempts WHERE message_id=p_message),
 'events',(SELECT coalesce(jsonb_agg(jsonb_build_object('type',event_type,'at',provider_time) ORDER BY provider_time),'[]') FROM (SELECT event_type,provider_time FROM public.email_delivery_events WHERE message_id=p_message ORDER BY provider_time DESC LIMIT 100) e));
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_detail(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_detail(uuid) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.create_email_confirmation_receipt(p_command uuid,p_order bigint,p_hash text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_message uuid;
BEGIN
 PERFORM public.require_service_role();
 SELECT message_id INTO v_message FROM public.email_messages WHERE message_kind='order_confirmation' AND data->>'command_id'=p_command::text AND order_id=p_order;
 IF v_message IS NULL THEN RETURN false; END IF;
 INSERT INTO public.email_confirmation_receipts(token_hash,message_id,expires_at) VALUES(p_hash,v_message,now()+interval '15 minutes');
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.create_email_confirmation_receipt(uuid,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_email_confirmation_receipt(uuid,bigint,text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_email_confirmation_status(p_hash text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_message uuid; m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_confirmation_receipts SET reads=reads+1 WHERE token_hash=p_hash AND expires_at>now() AND reads<15 RETURNING message_id INTO v_message;
 IF v_message IS NULL THEN RETURN 'unavailable'; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=v_message;
 RETURN CASE WHEN EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=m.message_id AND e.invalid_recipient AND e.recipient=lower(m.recipient)) THEN 'invalid_email'
 WHEN m.bounced_at IS NOT NULL OR m.complained_at IS NOT NULL OR m.provider_failure IN ('reject','rendering_failure') THEN 'failed'
 WHEN m.delivered_at IS NOT NULL THEN 'delivered' WHEN m.workflow_state='accepted' THEN 'accepted' WHEN m.workflow_state IN ('unknown','dead','suppressed','expired','cancelled','retry_wait') THEN m.workflow_state ELSE 'queued' END;
END $$;
REVOKE ALL ON FUNCTION public.get_email_confirmation_status(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_confirmation_status(text) TO service_role;
CREATE OR REPLACE FUNCTION public.get_auth_email_context(p_user uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT jsonb_build_object('organization',organization,'recipient',public.get_user_delivery_email(id)) FROM public.user_info WHERE id=p_user);
END $$;
REVOKE ALL ON FUNCTION public.get_auth_email_context(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_email_context(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.get_email_delivery_overview(p_occasion bigint,p_organization bigint DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_org bigint;
BEGIN
 v_org:=coalesce(p_organization,(SELECT organization FROM public.occasions WHERE id=p_occasion));
 IF NOT coalesce(public.email_report_allowed(v_org,p_occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 RETURN (SELECT jsonb_build_object('messages',count(*),'accepted',count(*) FILTER(WHERE accepted_at IS NOT NULL),
 'delivered',count(*) FILTER(WHERE delivered_at IS NOT NULL),'bounced',count(*) FILTER(WHERE bounced_at IS NOT NULL),
 'complained',count(*) FILTER(WHERE complained_at IS NOT NULL),'opened_messages',count(*) FILTER(WHERE opened_at IS NOT NULL),
 'clicked_messages',count(*) FILTER(WHERE clicked_at IS NOT NULL),'tracking_coverage',count(*) FILTER(WHERE tracking_policy<>'disabled'),
 'unknown',count(*) FILTER(WHERE workflow_state='unknown'),'dead',count(*) FILTER(WHERE workflow_state='dead'),
 'feedback_overdue',count(*) FILTER(WHERE accepted_at BETWEEN now()-interval '1 day' AND now()-interval '30 minutes' AND NOT EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=email_messages.message_id))) FROM public.email_messages WHERE organization=v_org AND (p_occasion IS NULL OR occasion=p_occasion));
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_overview(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_overview(bigint,bigint) TO authenticated,service_role;
