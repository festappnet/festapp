CREATE TABLE public.notification_center_maintenance (
 name text PRIMARY KEY, lease_token uuid, lease_until timestamptz, next_at timestamptz NOT NULL DEFAULT '-infinity', cursor bigint NOT NULL DEFAULT 0
);
CREATE TABLE public.notification_center_bank_health (
 connection_id bigint PRIMARY KEY, lease_token uuid, lease_until timestamptz,next_at timestamptz NOT NULL DEFAULT '-infinity',
 failure_since timestamptz, failures integer NOT NULL DEFAULT 0,last_success timestamptz,reason text
);
ALTER TABLE public.notification_center_maintenance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_center_bank_health ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_center_maintenance,public.notification_center_bank_health FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.set_notification_center_activation(p_organization bigint,p_enabled boolean,p_timezone text DEFAULT 'Europe/Prague')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$

BEGIN
 PERFORM public.notification_center_require_service();
 PERFORM pg_advisory_xact_lock(hashtextextended('notification-center-activation:'||p_organization,0));
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN RAISE EXCEPTION 'notification_timezone_invalid'; END IF;
 INSERT INTO public.notification_center_activation(organization,enabled,timezone) VALUES(p_organization,false,p_timezone)
 ON CONFLICT DO NOTHING;
 PERFORM 1 FROM public.notification_center_activation WHERE organization=p_organization FOR UPDATE;
 IF p_enabled AND NOT (SELECT enabled FROM public.notification_center_activation WHERE organization=p_organization) THEN
  -- Pauses collect no history. Rebaseline on resume, preserving the first activation timestamp.
  INSERT INTO public.notification_center_source_state(organization,source_key,state)
   SELECT p_organization,'email:'||message_id,jsonb_build_object('reason',public.email_reporting_state(m),'dueAt',m.target_time,'seen',
    CASE WHEN m.workflow_state IN ('pending','preparing','sending','retry_wait','unknown') AND m.target_time<=clock_timestamp()-interval '30 minutes' THEN '["delayed"]'::jsonb WHEN public.email_reporting_state(m) IN ('complaint','bounce','reject','rendering_failure','dead','suppressed')
    THEN jsonb_build_array(CASE WHEN public.email_reporting_state(m) IN ('unknown','retry_wait','delay') THEN 'delayed' ELSE public.email_reporting_state(m) END) ELSE '[]'::jsonb END)
   FROM public.email_messages m WHERE organization=p_organization
   ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state||jsonb_build_object('seen',coalesce(notification_center_source_state.state->'seen','[]')||(excluded.state->'seen'),'eventId',notification_center_source_state.state->>'eventId','dueAt',coalesce(notification_center_source_state.state->'dueAt',excluded.state->'dueAt')),observed_at=clock_timestamp();
  INSERT INTO public.notification_center_source_state(organization,source_key,state)
   SELECT DISTINCT p_organization,'bank:'||c.id,jsonb_build_object('problem',c.last_error IS NOT NULL OR
    coalesce(c.bank_pull_at,c.created_at)<clock_timestamp()-interval '30 minutes','reason',CASE WHEN c.last_error IS NOT NULL THEN 'existing_problem' END)
   FROM eshop.bank_sync_connections c JOIN eshop.unit_bank_accounts uba ON uba.bank_account=c.bank_account_id OR uba.bank_account IN
    (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
   JOIN public.units u ON u.id=uba.unit WHERE u.organization=p_organization
   ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state||jsonb_build_object('eventId',notification_center_source_state.state->>'eventId'),observed_at=clock_timestamp();
  INSERT INTO public.notification_center_source_state(organization,source_key,state)
   SELECT p_organization,'schedule-event:'||e.id,jsonb_build_object('eventId',e.id,'title',e.title,
    'limit',CASE WHEN e.split_for_men_women THEN 2*(e.max_participants/2) ELSE e.max_participants END,
    'full',coalesce(e.max_participants>0 AND CASE WHEN e.split_for_men_women THEN
      count(eu."user") FILTER(WHERE ui.sex='male')>=e.max_participants/2 AND count(eu."user") FILTER(WHERE ui.sex<>'male')>=e.max_participants/2
      ELSE count(eu."user")>=e.max_participants END,false))
   FROM public.events e JOIN public.occasions o ON o.id=e.occasion
   LEFT JOIN public.event_users eu ON eu.event=e.id LEFT JOIN public.user_info ui ON ui.id=eu."user"
   WHERE o.organization=p_organization GROUP BY e.id
   ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,observed_at=clock_timestamp();
  -- Seed exact authoritative capacities before enabling publication.
  INSERT INTO public.notification_center_source_state(organization,source_key,state)
   SELECT p_organization,'form:'||f.id,public.get_form_capacity_snapshot_internal(f.id)||jsonb_build_object('high',
    coalesce((f.participant_capacity-(public.get_form_capacity_snapshot_internal(f.id)->>'remainingPublic')::numeric)/nullif(f.participant_capacity,0)>=0.9,false))
   FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE oc.organization=p_organization
   ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,observed_at=clock_timestamp();
  INSERT INTO public.notification_center_source_state(organization,source_key,state)
   SELECT p_organization,'product:'||p.id,jsonb_build_object('limit',p.maximum,'remainingPublic',greatest(p.maximum-count(x.id),0),
     'high',coalesce(count(x.id)::numeric/nullif(p.maximum,0)>=0.9,false)) FROM eshop.products p JOIN public.occasions oc ON oc.id=p.occasion
   LEFT JOIN eshop.order_product_ticket x ON x.product=p.id WHERE oc.organization=p_organization GROUP BY p.id
   ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,observed_at=clock_timestamp();
  INSERT INTO public.notification_center_source_state(organization,source_key,state)
   SELECT p_organization,'inventory:'||ctx.id,jsonb_build_object('limit',least(count(s.id),coalesce(ip.sellable_capacity,count(s.id))),
    'remainingPublic',greatest(least(count(s.id),coalesce(ip.sellable_capacity,count(s.id)))-count(s.id) FILTER(WHERE s.order_product_ticket IS NOT NULL),0),
    'high',coalesce(count(s.id) FILTER(WHERE s.order_product_ticket IS NOT NULL)::numeric/nullif(least(count(s.id),coalesce(ip.sellable_capacity,count(s.id))),0)>=0.9,false))
   FROM public.inventory_contexts ctx JOIN public.inventory_pools ip ON ip.id=ctx.inventory_pool JOIN public.occasions oc ON oc.id=ip.occasion
   LEFT JOIN eshop.spots s ON s.inventory_context=ctx.id WHERE oc.organization=p_organization GROUP BY ctx.id,ip.id
   ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,observed_at=clock_timestamp();
  INSERT INTO public.notification_center_source_state(organization,source_key,state)
   SELECT p_organization,'blueprint:'||bp.id,jsonb_build_object('limit',count(s.id),
    'remainingPublic',count(s.id) FILTER(WHERE s.order_product_ticket IS NULL),'high',
    coalesce(count(s.id) FILTER(WHERE s.order_product_ticket IS NOT NULL)::numeric/nullif(count(s.id),0)>=0.9,false))
   FROM eshop.blueprints bp LEFT JOIN eshop.blueprint_seat_bindings sb ON sb.blueprint=bp.id AND NOT sb.blocked
   LEFT JOIN eshop.spots s ON s.id=sb.spot AND s.blueprint=bp.id AND s.occasion=bp.occasion
   WHERE bp.organization=p_organization GROUP BY bp.id
   ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,observed_at=clock_timestamp();
 END IF;
 UPDATE public.notification_center_activation SET enabled=p_enabled,collection_started_at=CASE WHEN p_enabled AND NOT enabled THEN clock_timestamp() ELSE collection_started_at END WHERE organization=p_organization;
END $$;
CREATE OR REPLACE FUNCTION public.maintain_notification_center(p_limit integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m record; maximum bigint; after_id bigint; processed integer:=0; projected integer;
BEGIN
 PERFORM public.notification_center_require_service();
 INSERT INTO public.notification_center_maintenance(name) VALUES('email') ON CONFLICT DO NOTHING;
 SELECT cursor INTO after_id FROM public.notification_center_maintenance WHERE name='email' FOR UPDATE SKIP LOCKED;
 IF FOUND THEN
  FOR m IN SELECT em.id,em.message_id FROM public.email_messages em JOIN public.notification_center_activation a ON a.organization=em.organization AND a.enabled
   LEFT JOIN public.notification_center_source_state ns ON ns.organization=em.organization AND ns.source_key='email:'||em.message_id
   WHERE em.id>after_id AND em.workflow_state IN ('pending','preparing','sending','retry_wait','unknown')
   AND (coalesce((ns.state->>'dueAt')::timestamptz,em.target_time)<=clock_timestamp()-interval '30 minutes' OR (em.message_kind='waitlist_offer' AND em.expires_at<=clock_timestamp()+interval '5 minutes'))
   ORDER BY em.id LIMIT greatest(1,least(p_limit,500)) LOOP
   PERFORM public.notification_center_email_internal(m.message_id); maximum:=m.id; processed:=processed+1;
  END LOOP;
  UPDATE public.notification_center_maintenance SET cursor=coalesce(maximum,0) WHERE name='email';
 END IF;
 projected:=public.project_notification_center(p_limit);
 -- Retain active incidents; cleanup is projection-only, never business/email history.
 DELETE FROM public.notification_center_deliveries WHERE (event_id,recipient,attention_revision) IN (
  SELECT d.event_id,d.recipient,d.attention_revision FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
  WHERE d.delivered_at<clock_timestamp()-interval '90 days' AND (e.status='recovered' OR e.kind NOT IN ('email_problem','bank_problem','capacity_full','capacity_warning')) LIMIT greatest(1,least(p_limit,500)));
 DELETE FROM public.notification_center_events WHERE id IN(SELECT e.id FROM public.notification_center_events e
  WHERE e.occurred_at<clock_timestamp()-interval '90 days' AND (e.status='recovered' OR e.kind NOT IN ('email_problem','bank_problem','capacity_full','capacity_warning'))
  AND NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries WHERE event_id=e.id) AND e.projected_revision=e.attention_revision LIMIT greatest(1,least(p_limit,500)));
 RETURN jsonb_build_object('evaluated',processed,'projected',projected);
END $$;
REVOKE ALL ON FUNCTION public.set_notification_center_activation(bigint,boolean,text),public.maintain_notification_center(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_notification_center_activation(bigint,boolean,text),public.maintain_notification_center(integer) TO service_role;
