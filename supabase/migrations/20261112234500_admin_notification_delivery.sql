-- Generated forward migration: admin-notification-delivery-2026-11-12
BEGIN;
DO $$ BEGIN IF to_regclass('public.notification_center_view_members') IS NULL OR to_regclass('public.abuse_policy_rules') IS NULL OR to_regprocedure('public.notification_center_prepared_scope(bigint,jsonb)') IS NULL THEN RAISE EXCEPTION 'admin_notification_prerequisites_missing'; END IF; END $$;

-- SOURCE: payment_providers/connection_access.sql
-- Shared connection administration identity; connector commands retain their
-- established error messages and demo guards.
CREATE OR REPLACE FUNCTION public.payment_provider_unit_manager_internal(p_unit bigint,p_actor uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_actor IS NOT NULL AND EXISTS(SELECT 1 FROM public.units u JOIN public.unit_users uu ON uu.unit=u.id
 JOIN public.user_info i ON i.id=uu."user" AND i.organization=u.organization
 WHERE u.id=p_unit AND uu."user"=p_actor AND uu.is_manager);
$$;
REVOKE ALL ON FUNCTION public.payment_provider_unit_manager_internal(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Consecutive transport failures, counted by the existing connector workers.
CREATE OR REPLACE FUNCTION public.payment_provider_connection_failure_threshold_internal()
RETURNS integer LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$ SELECT 3; $$;
REVOKE ALL ON FUNCTION public.payment_provider_connection_failure_threshold_internal() FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/email_policy.sql
-- Fixed product policy, not a recipient setting. Changing a published interval
-- requires a forward migration that handles existing windows.
CREATE OR REPLACE FUNCTION public.notification_center_email_window_internal()
RETURNS interval LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT interval '300 seconds';
$$;
REVOKE ALL ON FUNCTION public.notification_center_email_window_internal() FROM PUBLIC,anon,authenticated,service_role;

-- Required operational alerts ignore optional subscriptions and action muting.
-- Recipient capture, live authorization and the universal queue gate still apply.
CREATE OR REPLACE FUNCTION public.notification_center_email_required_kind_internal(p_kind text)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(p_kind IN ('bank_problem','provider_problem'),false);
$$;
REVOKE ALL ON FUNCTION public.notification_center_email_required_kind_internal(text) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/order_context.sql
CREATE OR REPLACE FUNCTION public.notification_center_order_form_context_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT jsonb_build_object('formId',f.id,'allowsMultiple',least(public.ticket_order_limit(),coalesce(min(
 CASE WHEN ff.data->>'max_tickets' ~ '^[0-9]{1,9}$' THEN greatest(1,(ff.data->>'max_tickets')::integer) ELSE 1 END),1))>1)
 FROM public.forms f LEFT JOIN public.form_fields ff ON ff.form=f.id AND ff.type='ticket' WHERE f.id=p_form GROUP BY f.id),jsonb_build_object('formId',NULL,'allowsMultiple',false));
$$;
REVOKE ALL ON FUNCTION public.notification_center_order_form_context_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/shared.sql
-- Shared notification classification, DTO and receipt grouping.
-- Serving adapters own scopes; these owners retain domain policy and history.
CREATE OR REPLACE FUNCTION public.notification_center_order_activity_internal(p_kind text)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_kind IN ('order_created','order_cancelled','order_payment_received','payment_problem','waitlist_registered','offer_accepted','offer_declined','offer_expired');
$$;

CREATE OR REPLACE FUNCTION public.notification_center_batch_internal(
 e public.notification_center_events,d public.notification_center_deliveries)
RETURNS TABLE(batch_id text,is_read boolean,after_sequence bigint,through_sequence bigint,group_key text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH state AS (
  SELECT coalesce((SELECT read_through_sequence FROM public.notification_center_user_state
   WHERE organization=d.organization AND recipient=d.recipient),0) baseline,
   CASE WHEN e.occasion IS NOT NULL AND e.kind NOT IN ('email_problem','bank_problem','payment_problem','provider_problem')
    THEN 'occasion-kind:'||e.occasion||':'||e.kind ELSE 'event:'||e.id END key),
 receipt AS (
  SELECT b.* FROM public.notification_center_read_batches b,state s
  WHERE b.organization=d.organization AND b.recipient=d.recipient AND b.group_key=s.key
   AND d.sequence>b.after_sequence AND d.sequence<=b.through_sequence
  ORDER BY b.through_sequence,b.read_at,b.id LIMIT 1),
 bounds AS (
  SELECT s.*,greatest(s.baseline,coalesce((SELECT max(b.through_sequence)
   FROM public.notification_center_read_batches b WHERE b.organization=d.organization
    AND b.recipient=d.recipient AND b.group_key=s.key),0)) last_read,
   e.actor=d.recipient AND e.kind IN ('order_created','order_cancelled') own_action FROM state s)
 SELECT CASE WHEN coalesce(s.own_action,false) THEN s.key||':self'
   WHEN d.sequence<=s.baseline THEN s.key||':legacy'
   WHEN r.id IS NOT NULL THEN s.key||':batch:'||r.after_sequence
   ELSE s.key||':batch:'||s.last_read END,
  coalesce(s.own_action,false) OR d.sequence<=s.baseline OR r.id IS NOT NULL,
  CASE WHEN coalesce(s.own_action,false) OR d.sequence<=s.baseline THEN 0
   WHEN r.id IS NOT NULL THEN r.after_sequence ELSE s.last_read END,
  CASE WHEN coalesce(s.own_action,false) THEN d.sequence WHEN d.sequence<=s.baseline THEN s.baseline
   WHEN r.id IS NOT NULL THEN r.through_sequence ELSE d.sequence END,s.key
 FROM bounds s LEFT JOIN receipt r ON true;
$$;
REVOKE ALL ON FUNCTION public.notification_center_batch_internal(public.notification_center_events,public.notification_center_deliveries) FROM PUBLIC,anon,authenticated,service_role;


-- Immutable source contributions are shared by serving and delivery adapters.
-- Only historical events missing a field consult the original domain owner.
CREATE OR REPLACE FUNCTION public.notification_center_event_facts_internal(e public.notification_center_events)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE places bigint; context jsonb; legacy_form bigint;
BEGIN
 places:=CASE WHEN e.data->>'count' ~ '^[0-9]{1,9}$' THEN nullif((e.data->>'count')::bigint,0) END;
 context:=nullif(e.data->'formContext','null'::jsonb);
 IF public.notification_center_order_activity_internal(e.kind) AND e.kind NOT IN ('order_payment_received','payment_problem') AND (e.data->>'count' IS NULL OR context IS NULL) THEN
  SELECT o.form INTO legacy_form FROM eshop.orders o
   JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization
   WHERE o.occasion=e.occasion AND o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (e.data->>'orderId')::bigint END;
  IF FOUND THEN
   IF e.data->>'count' IS NULL THEN
    SELECT nullif(count(DISTINCT x.ticket),0) INTO places FROM eshop.order_product_ticket x
     WHERE x."order"=(e.data->>'orderId')::bigint;
   END IF;
   IF context IS NULL THEN context:=public.notification_center_order_form_context_internal(legacy_form); END IF;
  END IF;
 END IF;
 RETURN jsonb_build_object('count',CASE WHEN e.data->>'count' ~ '^[0-9]{1,9}$' THEN (e.data->>'count')::bigint ELSE places END,'formContext',context,
  'allowsMultiple',coalesce(places>1 OR context->'allowsMultiple'='true'::jsonb,false))||
  jsonb_strip_nulls(jsonb_build_object('amount',e.data->'amount','currency',e.data->'currency','receivedAt',e.data->'receivedAt','reason',e.data->'reason','reassigned',e.data->'reassigned'));
END $$;
REVOKE ALL ON FUNCTION public.notification_center_event_facts_internal(public.notification_center_events) FROM PUBLIC,anon,authenticated,service_role;

-- Safe shared metadata, intentionally excluding customer contacts and bank IDs.
CREATE OR REPLACE FUNCTION public.notification_center_event_display_internal(e public.notification_center_events)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('organizationId',e.organization,'organizationTitle',org.title,
  'occasionId',e.occasion,'occasionLink',oc.link,'occasionTitle',oc.title,'webLink',org.data->>'DEFAULT_URL')
 FROM public.organizations org LEFT JOIN public.occasions oc ON oc.id=e.occasion AND oc.organization=org.id WHERE org.id=e.organization;
$$;
REVOKE ALL ON FUNCTION public.notification_center_event_display_internal(public.notification_center_events) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.notification_center_bank_display_internal(e public.notification_center_events,p_recipient uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE payload jsonb:='{}'; account bigint; un bigint; impacts jsonb;
BEGIN
 IF e.kind<>'bank_problem' THEN RETURN payload; END IF;
  SELECT bu.bank_account,u.id INTO account,un FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu
   ON bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
   JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account JOIN public.units u ON u.id=uba.unit
   WHERE c.id=(e.data->>'bankConnectionId')::bigint AND bu."user"=p_recipient AND public.notification_center_bank_admin(bu.bank_account,p_recipient) AND u.organization=e.organization AND EXISTS(SELECT 1 FROM public.unit_users um WHERE um.unit=u.id AND um."user"=p_recipient AND um.is_manager) ORDER BY u.id LIMIT 1;
  IF account IS NOT NULL THEN payload:=payload||jsonb_build_object('bankAccountId',account,'unitId',un); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',oc.id,'title',oc.title,'link',oc.link)),'[]') INTO impacts
   FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id AND ou."user"=p_recipient AND ou.is_editor_order_view
   WHERE oc.organization=e.organization AND oc.id=ANY(e.affected_occasions);
  payload:=payload||jsonb_build_object('affectedOccasions',impacts);
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_bank_display_internal(public.notification_center_events,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.notification_center_dto(e public.notification_center_events,d public.notification_center_deliveries)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE payload jsonb:=e.data-'bankConnectionId'; customer text; actual_state text; contact jsonb;
BEGIN
 IF NOT public.notification_center_allowed(e,auth.uid()) THEN RETURN NULL; END IF;
 IF e.kind='email_problem' AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT payload||jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,'recipient',m.recipient,'customerName',coalesce(
    nullif(trim(concat_ws(' ',o.data->>'name',o.data->>'surname')),''),
    nullif(trim(concat_ws(' ',u.name,u.surname)),''))) INTO payload
  FROM public.email_messages m
  LEFT JOIN eshop.orders o ON o.id=m.order_id AND o.occasion=m.occasion
    AND coalesce(public.can_read_orders(o.occasion),false)
    AND EXISTS(SELECT 1 FROM public.occasions oc WHERE oc.id=o.occasion AND oc.organization=m.organization)
  LEFT JOIN public.user_info u ON u.id=m.recipient_user AND u.organization=m.organization
  WHERE m.message_id=(e.data->>'messageId')::uuid AND m.organization=e.organization
    AND m.occasion IS NOT DISTINCT FROM e.occasion;
  payload:=coalesce(payload,e.data-'bankConnectionId');
 END IF;
 IF e.kind='occasion_joined' AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT nullif(trim(concat_ws(' ',u.name,u.surname)),'') INTO customer
  FROM public.user_info u JOIN public.occasion_users m ON m."user"=u.id
  WHERE m.occasion=e.occasion AND u.organization=e.organization AND u.id=(e.data->>'userId')::uuid;
  payload:=payload||jsonb_build_object('customerName',customer,'state',CASE WHEN EXISTS(
   SELECT 1 FROM public.occasion_users m WHERE m.occasion=e.occasion AND m."user"=(e.data->>'userId')::uuid) THEN 'membership_active' ELSE 'membership_left' END);
 END IF;
 IF e.data ? 'orderId' AND e.occasion IS NOT NULL AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'),o.state
   INTO contact,actual_state
   FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization
   WHERE o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion;
  payload:=payload||jsonb_build_object('contact',coalesce(contact,'{}'),'customerName',nullif(trim(concat_ws(' ',contact->>'name',contact->>'surname')),''),'state',coalesce(actual_state,e.data->>'state'));
  IF public.notification_center_order_activity_internal(e.kind) THEN
   payload:=payload||(public.notification_center_event_facts_internal(e)-'allowsMultiple');
  END IF;
 END IF;
 IF e.kind='bank_problem' THEN payload:=payload||public.notification_center_bank_display_internal(e,auth.uid()); END IF;
 RETURN public.notification_center_event_display_internal(e)||jsonb_build_object('id',e.id,'sequence',d.sequence,
  'kind',e.kind,'occurredAt',e.occurred_at,'status',e.status,'data',payload);
END $$;

REVOKE ALL ON FUNCTION public.notification_center_order_activity_internal(text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.notification_center_dto(public.notification_center_events,public.notification_center_deliveries) FROM PUBLIC,anon,authenticated;


-- SOURCE: notification_center/payment_sources.sql
-- Payment facts are published by financial owners, never inferred by delivery.
CREATE TABLE IF NOT EXISTS eshop.payment_notification_incidents (
 payment_id bigint PRIMARY KEY REFERENCES eshop.payment_info(id) ON DELETE CASCADE,
 incident_id uuid NOT NULL DEFAULT gen_random_uuid(), active boolean NOT NULL DEFAULT true,
 reason text NOT NULL, opened_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE eshop.payment_notification_incidents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.payment_notification_incidents FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_payment_fact_internal(p_order bigint,p_namespace text,p_fact text,p_amount numeric,p_currency text,p_at timestamptz,p_reassigned boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 IF p_amount<=0 OR p_fact IS NULL OR p_namespace IS NULL THEN RETURN; END IF;
 -- An existing source snapshot wins on replay, including detach/reattach.
 IF EXISTS(SELECT 1 FROM public.notification_center_events e JOIN eshop.orders o ON o.occasion=e.occasion
  WHERE o.id=p_order AND e.source_key='order_payment_received:'||p_order||':'||p_namespace||':'||p_fact) THEN RETURN; END IF;
 PERFORM public.notification_center_order_internal(p_order,'order_payment_received',p_namespace||':'||p_fact,NULL,
  jsonb_build_object('amount',p_amount,'currency',p_currency,'paymentFact',p_namespace||':'||p_fact,'receivedAt',p_at,'reassigned',p_reassigned));
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_payment_problem_internal(p_order bigint,p_problem boolean,p_reason text)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE payment bigint; incident eshop.payment_notification_incidents; event uuid;
BEGIN
 SELECT payment_info INTO payment FROM eshop.orders WHERE id=p_order;
 IF payment IS NULL THEN RETURN; END IF;
 SELECT * INTO incident FROM eshop.payment_notification_incidents WHERE payment_id=payment FOR UPDATE;
 IF p_problem THEN
  IF NOT FOUND THEN
   INSERT INTO eshop.payment_notification_incidents(payment_id,reason) VALUES(payment,p_reason) RETURNING * INTO incident;
  ELSIF NOT incident.active THEN
   UPDATE eshop.payment_notification_incidents SET active=true,incident_id=gen_random_uuid(),reason=p_reason,opened_at=clock_timestamp() WHERE payment_id=payment RETURNING * INTO incident;
  ELSE UPDATE eshop.payment_notification_incidents SET reason=p_reason WHERE payment_id=payment;
  END IF;
  SELECT id INTO event FROM public.notification_center_events WHERE kind='payment_problem'
   AND data->>'orderId'=p_order::text AND data->>'incidentId'=incident.incident_id::text;
  IF FOUND THEN
   IF EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=event AND data->>'reason' IS DISTINCT FROM p_reason) THEN
    PERFORM public.notification_center_prepared_invalidate(event);
    UPDATE public.notification_center_events SET data=data||jsonb_build_object('reason',p_reason) WHERE id=event;
   END IF;
   RETURN;
  END IF;
  PERFORM public.notification_center_order_internal(p_order,'payment_problem',incident.incident_id::text,NULL,
   jsonb_build_object('incidentId',incident.incident_id,'reason',p_reason));
 ELSE
  UPDATE eshop.payment_notification_incidents SET active=false WHERE payment_id=payment;
  FOR event IN SELECT id FROM public.notification_center_events WHERE kind='payment_problem' AND data->>'orderId'=p_order::text AND status NOT IN ('recovered','resolved') LOOP
   PERFORM public.notification_center_prepared_invalidate(event);
   UPDATE public.notification_center_events SET status='recovered' WHERE id=event;
  END LOOP;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_payment_fact_internal(bigint,text,text,numeric,text,timestamptz,boolean),public.notification_center_payment_problem_internal(bigint,boolean,text) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/provider_connections.sql
-- Connector adapters own operational health. This table owns only the episode
-- identity, like payment_notification_incidents; it is not another poller.
CREATE TABLE IF NOT EXISTS eshop.provider_connection_notification_incidents (
 provider text NOT NULL REFERENCES eshop.payment_providers(provider_key), connection_id uuid NOT NULL,
 organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 unit bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
 incident_id uuid NOT NULL DEFAULT gen_random_uuid(), active boolean NOT NULL,
 reason text NOT NULL, opened_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(provider,connection_id)
);
ALTER TABLE eshop.provider_connection_notification_incidents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.provider_connection_notification_incidents FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_provider_connection_internal(p_provider text,p_connection uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE health jsonb; incident eshop.provider_connection_notification_incidents; ev uuid; problem boolean;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('provider-notification:'||p_provider||':'||p_connection,0));
 health:=public.payment_provider_call_internal(p_provider,'notification_connection_health',jsonb_build_object('connectionId',p_connection));
 IF health IS NULL THEN RETURN; END IF;
 problem:=health->>'reason' IS NOT NULL;
 -- All callers already hold their connector mutation lock. The episode lock
 -- also serializes different Barion attempts belonging to the same connection.
 SELECT * INTO incident FROM eshop.provider_connection_notification_incidents WHERE provider=p_provider AND connection_id=p_connection FOR UPDATE;
 IF NOT problem THEN
  IF incident.active THEN
   UPDATE eshop.provider_connection_notification_incidents SET active=false WHERE provider=p_provider AND connection_id=p_connection;
   FOR ev IN SELECT id FROM public.notification_center_events WHERE kind='provider_problem' AND data->>'incidentId'=incident.incident_id::text LOOP
    PERFORM public.notification_center_prepared_invalidate(ev);
    UPDATE public.notification_center_events SET status='recovered' WHERE id=ev;
   END LOOP;
  END IF;
  RETURN;
 END IF;
 IF incident.connection_id IS NULL THEN
  INSERT INTO eshop.provider_connection_notification_incidents(provider,connection_id,organization,unit,active,reason)
  VALUES(p_provider,p_connection,(health->>'organizationId')::bigint,(health->>'unitId')::bigint,true,health->>'reason') RETURNING * INTO incident;
 ELSIF NOT incident.active THEN
  UPDATE eshop.provider_connection_notification_incidents SET active=true,incident_id=gen_random_uuid(),reason=health->>'reason',opened_at=clock_timestamp()
  WHERE provider=p_provider AND connection_id=p_connection RETURNING * INTO incident;
 ELSE
  UPDATE eshop.provider_connection_notification_incidents SET reason=health->>'reason'
  WHERE provider=p_provider AND connection_id=p_connection AND reason IS DISTINCT FROM health->>'reason';
 END IF;
 -- Tenant initialization/activation still determine the publication boundary.
 ev:=public.notification_center_publish_internal(incident.organization,NULL,'provider_problem',
  'provider:'||p_provider||':'||p_connection||':incident:'||incident.incident_id,
  jsonb_build_object('provider',p_provider,'connectionId',p_connection,'incidentId',incident.incident_id,'unitId',incident.unit,
   'title',health->>'title','reason',health->>'reason'),NULL,incident.opened_at);
 IF ev IS NOT NULL AND EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=ev AND data->>'reason' IS DISTINCT FROM health->>'reason') THEN
  PERFORM public.notification_center_prepared_invalidate(ev);
  UPDATE public.notification_center_events SET data=data||jsonb_build_object('reason',health->>'reason') WHERE id=ev;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_provider_connection_internal(text,uuid) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/center_policy.sql
-- Only the current incident for a connection remains actionable. Historical
-- episodes can retain deliveries/read receipts, but must not duplicate alerts.
CREATE OR REPLACE FUNCTION public.notification_center_bank_episode_current(e public.notification_center_events)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT e.kind<>'bank_problem' OR EXISTS(SELECT 1 FROM eshop.bank_sync_health h
  WHERE h.connection_id=CASE WHEN e.data->>'bankConnectionId' ~ '^[0-9]{1,18}$' THEN (e.data->>'bankConnectionId')::bigint END
   AND h.incident_id::text=e.data->>'incidentId' AND public.bank_sync_alert_ready(h.connection_id));
$$;
REVOKE ALL ON FUNCTION public.notification_center_bank_episode_current(public.notification_center_events) FROM PUBLIC,anon,authenticated,service_role;

-- New-order activity follows the current order state, including older panel snapshots.
-- Participant joins remain relevant only while that person belongs to the occasion.
-- Activity expires from the center, not from the order/email audit history.
CREATE OR REPLACE FUNCTION public.notification_center_event_relevant_internal(
 e public.notification_center_events,p_anchor timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN e.kind='provider_problem' THEN e.status NOT IN ('recovered','resolved') AND EXISTS(
  SELECT 1 FROM eshop.provider_connection_notification_incidents i WHERE i.organization=e.organization AND i.provider=e.data->>'provider'
   AND i.connection_id::text=e.data->>'connectionId' AND i.unit::text=e.data->>'unitId' AND i.active AND i.incident_id::text=e.data->>'incidentId')
 WHEN e.kind='payment_problem' THEN e.status NOT IN ('recovered','resolved') AND EXISTS(
  SELECT 1 FROM eshop.payment_notification_incidents i JOIN eshop.orders o ON o.payment_info=i.payment_id
   JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization
  WHERE i.active AND i.incident_id::text=e.data->>'incidentId' AND o.occasion=e.occasion
   AND o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (e.data->>'orderId')::bigint END)
 WHEN e.kind IN ('email_problem','bank_problem')
  THEN e.status NOT IN ('recovered','resolved') AND public.notification_center_bank_episode_current(e)
  ELSE (e.kind<>'order_payment_received' OR e.status NOT IN ('resolved','recovered')) AND e.occurred_at>=p_anchor-interval '30 days'
   AND (e.kind<>'order_created' OR coalesce(
    (SELECT o.state FROM eshop.orders o
     WHERE o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$'
      THEN (e.data->>'orderId')::bigint END AND o.occasion=e.occasion),
    e.status,'')<>'storno')
   AND (e.kind<>'occasion_joined' OR EXISTS(
    SELECT 1 FROM public.occasion_users m
    JOIN public.user_info u ON u.id=m."user" AND u.organization=e.organization
    WHERE m.occasion=e.occasion AND m."user"::text=e.data->>'userId')) END;
$$;
REVOKE ALL ON FUNCTION public.notification_center_event_relevant_internal(public.notification_center_events,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

-- Live reads and cached prepared privacy retain their respective adapters.
CREATE OR REPLACE FUNCTION public.notification_center_in_center_internal(
 e public.notification_center_events,p_anchor timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.notification_center_subject_visible_internal(e.organization,e.kind,e.data)
  AND public.notification_center_event_relevant_internal(e,p_anchor);
$$;
REVOKE ALL ON FUNCTION public.notification_center_in_center_internal(public.notification_center_events,timestamptz) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/core.sql
-- Called by trusted domain owners only. Never accept an actor in a public RPC.
CREATE OR REPLACE FUNCTION public.notification_center_require_service() RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF session_user<>'postgres' AND coalesce(auth.role(),'')<>'service_role' THEN
  RAISE insufficient_privilege USING MESSAGE='notification_service_required'; END IF;
END $$;
-- Match the canonical account write policy: account admin AND linked-unit manager.
CREATE OR REPLACE FUNCTION public.notification_center_bank_admin(p_bank bigint,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.bank_account_write_rule(
  EXISTS(SELECT 1 FROM eshop.bank_account_users m WHERE m.bank_account=p_bank AND m."user"=p_user AND m.is_admin),
  EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l JOIN public.unit_users m ON m.unit=l.unit AND m."user"=p_user AND m.is_manager
   WHERE l.bank_account=p_bank AND NOT EXISTS(SELECT 1 FROM public.demo_unit_ids_internal() d WHERE d.unit_id=m.unit)),
  public.is_demo_bank_account(p_bank));
$$;
REVOKE ALL ON FUNCTION public.notification_center_bank_admin(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_allowed(p_event public.notification_center_events,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_user IS NOT NULL
 AND public.notification_center_subject_visible_internal(p_event.organization,p_event.kind,p_event.data)
 AND (
 CASE WHEN p_event.kind IN ('event_capacity_full','occasion_joined') THEN
 public.notification_center_app_admin_internal(p_event.organization,p_event.occasion,p_user)
 WHEN p_event.kind='provider_problem' THEN
 public.payment_provider_unit_manager_internal((p_event.data->>'unitId')::bigint,p_user)
 AND NOT public.is_demo_unit((p_event.data->>'unitId')::bigint)
 AND EXISTS(SELECT 1 FROM public.units un WHERE un.id=(p_event.data->>'unitId')::bigint AND un.organization=p_event.organization)
 WHEN p_event.kind='email_problem' THEN
 EXISTS(SELECT 1 FROM public.organization_users WHERE organization=p_event.organization AND "user"=p_user AND is_admin) OR (p_event.occasion IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasion_users ou JOIN public.occasions oc ON oc.id=ou.occasion WHERE oc.organization=p_event.organization AND oc.id=p_event.occasion AND ou."user"=p_user AND ou.is_editor_order_view AND NOT public.is_demo_occasion(oc.id)))
 WHEN p_event.kind='bank_problem' THEN (EXISTS(SELECT 1 FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu ON bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
 WHERE c.id=(p_event.data->>'bankConnectionId')::bigint AND bu."user"=p_user AND public.notification_center_bank_admin(bu.bank_account,p_user)
 AND EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit WHERE u.organization=p_event.organization AND uba.bank_account=bu.bank_account))
 OR EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id WHERE oc.organization=p_event.organization AND oc.id=ANY(p_event.affected_occasions) AND ou."user"=p_user AND ou.is_editor_order_view))
 ELSE EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id
 WHERE oc.organization=p_event.organization AND ou."user"=p_user AND ou.is_editor_order_view
 AND NOT public.is_demo_occasion(oc.id)
 AND (oc.id=p_event.occasion OR oc.id=ANY(p_event.affected_occasions))) END
 );
$$;
-- Shared administration capability controls availability, never item access.
CREATE OR REPLACE FUNCTION public.notification_center_administration_internal(p_org bigint,p_occ bigint,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_user IS NOT NULL AND (p_occ IS NULL OR EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occ AND organization=p_org)) AND (
 EXISTS(SELECT 1 FROM public.organization_users WHERE organization=p_org AND "user"=p_user AND is_admin)
 OR EXISTS(SELECT 1 FROM public.units un JOIN public.unit_users um ON um.unit=un.id
 WHERE un.organization=p_org AND um."user"=p_user AND (um.is_manager OR um.is_editor OR um.is_editor_view)
 AND (p_occ IS NULL OR EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occ AND unit=un.id)))
 OR EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id
 WHERE oc.organization=p_org AND ou."user"=p_user AND NOT public.is_demo_occasion(oc.id)
 AND (p_occ IS NULL OR oc.id=p_occ)
 AND (public.administration_navigation_rule(false,ou.is_editor,ou.is_manager,false,false) OR ou.is_editor_view)));
$$;
REVOKE ALL ON FUNCTION public.notification_center_administration_internal(bigint,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_check_context(p_org bigint,p_occ bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (
 public.notification_center_administration_internal(p_org,NULL,auth.uid()) OR
 EXISTS(SELECT 1 FROM eshop.bank_account_users bu JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account
 JOIN public.units u ON u.id=uba.unit WHERE bu."user"=auth.uid() AND public.notification_center_bank_admin(bu.bank_account,auth.uid()) AND u.organization=p_org)
 OR EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id
 WHERE oc.organization=p_org AND ou."user"=auth.uid() AND ou.is_editor_order_view AND NOT public.is_demo_occasion(oc.id))) THEN
 RAISE insufficient_privilege USING MESSAGE='notification_read_denied'; END IF;
 IF p_occ IS NOT NULL AND NOT public.notification_center_administration_internal(p_org,p_occ,auth.uid()) AND NOT EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id
 WHERE oc.id=p_occ AND oc.organization=p_org AND ou."user"=auth.uid() AND ou.is_editor_order_view AND NOT public.is_demo_occasion(oc.id)) THEN
 RAISE insufficient_privilege USING MESSAGE='notification_context_denied'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_capture_recipients_internal(p_event uuid,p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE e public.notification_center_events; u uuid; was_pending boolean;
BEGIN
 SELECT * INTO e FROM public.notification_center_events WHERE id=p_event;
 IF NOT FOUND THEN RETURN; END IF;
 FOR u IN SELECT "user" FROM public.organization_users WHERE organization=e.organization AND is_admin
 UNION SELECT um."user" FROM public.unit_users um JOIN public.units un ON un.id=um.unit
 WHERE e.kind='provider_problem' AND un.organization=e.organization AND um.unit=(e.data->>'unitId')::bigint AND um.is_manager
 UNION SELECT ou."user" FROM public.occasion_users ou JOIN public.occasions oc ON oc.id=ou.occasion WHERE oc.organization=e.organization AND (ou.is_editor_order_view OR public.participant_contacts_read_rule(ou.is_editor,ou.is_manager,false))
 UNION SELECT bu."user" FROM eshop.bank_account_users bu JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account
 JOIN public.units un ON un.id=uba.unit WHERE un.organization=e.organization AND bu.is_admin LOOP
  IF public.notification_center_allowed(e,u) AND (e.kind IN ('order_created','order_cancelled') OR u IS DISTINCT FROM p_actor OR
   CASE WHEN e.kind IN ('event_capacity_full','occasion_joined') THEN
     NOT public.notification_center_app_admin_internal(e.organization,e.occasion,p_actor)
   ELSE NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=e.occasion AND "user"=p_actor AND is_editor_order)
     AND NOT EXISTS(SELECT 1 FROM public.organization_users WHERE organization=e.organization AND "user"=p_actor AND is_admin) END) THEN
   SELECT coalesce(bool_or(processed_revision<eligible_revision),false) INTO was_pending FROM public.notification_center_recipients WHERE event_id=e.id AND recipient=u;
   INSERT INTO public.notification_center_recipients(event_id,recipient,eligible_revision) VALUES(e.id,u,e.attention_revision)
   ON CONFLICT(event_id,recipient) DO UPDATE SET eligible_revision=excluded.eligible_revision,
    pending_since=CASE WHEN notification_center_recipients.eligible_revision<>excluded.eligible_revision
     THEN clock_timestamp() ELSE notification_center_recipients.pending_since END;
   IF NOT was_pending THEN UPDATE public.notification_center_projection_scopes SET pending_delivery=pending_delivery+1,requested_at=CASE WHEN work_requested THEN requested_at ELSE clock_timestamp() END,work_requested=true,next_check_at=CASE WHEN retry_count=0 THEN least(next_check_at,clock_timestamp()) ELSE next_check_at END
    WHERE organization=e.organization AND recipient=u AND delivery_initialized; END IF;
  END IF;
 END LOOP;
 -- A source revision with no captured work is complete immediately. It must
 -- not occupy the delivery candidate index or delay a drain's idle decision.
 UPDATE public.notification_center_events ev SET projected_revision=attention_revision
 WHERE ev.id=p_event AND NOT EXISTS(SELECT 1 FROM public.notification_center_recipients r
  WHERE r.event_id=ev.id AND r.eligible_revision=ev.attention_revision AND r.processed_revision<r.eligible_revision);
 PERFORM public.notification_center_prepared_wake();
END $$;
REVOKE ALL ON FUNCTION public.notification_center_capture_recipients_internal(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_publish_internal(p_org bigint,p_occ bigint,p_kind text,p_key text,
 p_data jsonb DEFAULT '{}',p_actor uuid DEFAULT NULL,p_at timestamptz DEFAULT NULL,p_affected bigint[] DEFAULT '{}')
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a public.notification_center_organizations; e public.notification_center_events; u uuid;
BEGIN
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-organization:'||p_org,0));
 p_at:=coalesce(p_at,clock_timestamp());
 -- Source initialization and domain commits share one organization boundary.
 SELECT * INTO a FROM public.notification_center_organizations WHERE organization=p_org FOR SHARE;
 IF NOT FOUND OR p_at<coalesce(a.collection_started_at,a.initialized_at) THEN RETURN NULL; END IF;
 IF NOT public.notification_center_subject_visible_internal(p_org,p_kind,p_data) THEN RETURN NULL; END IF;
 IF p_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occ AND organization=p_org) THEN
 RAISE EXCEPTION 'notification_scope_mismatch'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_affected) x WHERE NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=x AND organization=p_org)) THEN
 RAISE EXCEPTION 'notification_scope_mismatch'; END IF;
 INSERT INTO public.notification_center_events(organization,occasion,kind,source_key,actor,occurred_at,data,affected_occasions)
 VALUES(p_org,p_occ,p_kind,p_key,p_actor,p_at,p_data,p_affected) ON CONFLICT DO NOTHING RETURNING * INTO e;
 IF NOT FOUND THEN RETURN (SELECT id FROM public.notification_center_events WHERE organization=p_org AND source_key=p_key); END IF;
 PERFORM public.notification_center_capture_recipients_internal(e.id,p_actor);
 RETURN e.id;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_unmuted(p_event public.notification_center_events,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_event.occasion IS NOT NULL THEN NOT EXISTS(SELECT 1 FROM public.notification_center_preferences
 WHERE organization=p_event.organization AND recipient=p_user AND occasion=p_event.occasion AND muted)
 WHEN cardinality(p_event.affected_occasions)=0 THEN true
 ELSE EXISTS(SELECT 1 FROM unnest(p_event.affected_occasions) oc JOIN public.occasion_users ou ON ou.occasion=oc AND ou."user"=p_user AND ou.is_editor_order_view
 WHERE NOT EXISTS(SELECT 1 FROM public.notification_center_preferences p WHERE p.organization=p_event.organization AND p.recipient=p_user AND p.occasion=oc AND p.muted))
 OR (p_event.kind='bank_problem' AND EXISTS(SELECT 1 FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu ON
 bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
 WHERE c.id=(p_event.data->>'bankConnectionId')::bigint AND bu."user"=p_user AND public.notification_center_bank_admin(bu.bank_account,p_user))) END;
$$;
REVOKE ALL ON FUNCTION public.notification_center_unmuted(public.notification_center_events,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.project_notification_center(p_limit integer DEFAULT 100) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE e public.notification_center_events; work record; tenant record; tz text; seq bigint;
 n integer:=0; scanned integer:=0; deferred integer:=0; failed integer:=0; tenant_work integer;
 budget integer:=greatest(1,least(coalesce(p_limit,100),500)); after_org bigint; last_org bigint; tenant_budget integer;
 started_at timestamptz:=clock_timestamp();
 deadline timestamptz:=clock_timestamp()+interval '250 milliseconds'; error_code text;
 previous_lock_timeout text:=current_setting('lock_timeout');
BEGIN
 PERFORM public.notification_center_require_service();
 IF NOT pg_try_advisory_xact_lock(5831290471283) THEN RETURN 0; END IF;
 INSERT INTO public.notification_center_maintenance(name) VALUES('delivery') ON CONFLICT DO NOTHING;
 SELECT cursor INTO after_org FROM public.notification_center_maintenance WHERE name='delivery' FOR UPDATE;
 SELECT greatest(1,budget/least(4,greatest(1,count(*)))) INTO tenant_budget
 FROM public.notification_center_organizations a WHERE EXISTS(SELECT 1 FROM public.notification_center_events pending
 WHERE pending.organization=a.organization AND pending.projected_revision<pending.attention_revision);
 -- Rotate across tenants, with separate work/scan budgets. A busy personal row
 -- never makes a recipient revision processed and never stalls another tenant.
 FOR tenant IN
  SELECT a.organization,a.timezone FROM public.notification_center_organizations a
  WHERE EXISTS(SELECT 1 FROM public.notification_center_events ev
   WHERE ev.organization=a.organization AND ev.projected_revision<ev.attention_revision)
  ORDER BY (a.organization>after_org) DESC,a.organization LIMIT 32
 LOOP
  last_org:=tenant.organization; tz:=tenant.timezone; tenant_work:=0;
  FOR work IN
   SELECT ev.id event_id,r.recipient,r.eligible_revision FROM public.notification_center_events ev
   JOIN public.notification_center_recipients r ON r.event_id=ev.id
   WHERE ev.organization=tenant.organization AND ev.projected_revision<ev.attention_revision
    AND r.eligible_revision=ev.attention_revision AND r.processed_revision<r.eligible_revision
    AND (r.retry_revision<>r.eligible_revision OR (NOT r.quarantined AND r.next_attempt_at<=clock_timestamp()))
   ORDER BY ev.occurred_at,ev.id,r.recipient LIMIT least(500,budget*4)
  LOOP
   EXIT WHEN n>=budget OR tenant_work>=tenant_budget OR scanned>=budget*4 OR clock_timestamp()>=deadline;
   scanned:=scanned+1; tenant_work:=tenant_work+1;
   BEGIN
    -- Bound the first-insert race with an opening client too. Restore the
    -- caller's setting on every return; all successful sequence writes are atomic.
    PERFORM set_config('lock_timeout','5ms',true);
    INSERT INTO public.notification_center_user_state(organization,recipient)
     VALUES(tenant.organization,work.recipient) ON CONFLICT DO NOTHING;
    PERFORM 1 FROM public.notification_center_user_state
     WHERE organization=tenant.organization AND recipient=work.recipient FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN deferred:=deferred+1; PERFORM public.notification_center_prepared_defer(work.event_id,work.recipient,work.eligible_revision); CONTINUE; END IF;
    -- Domain writers own event -> recipient. We acquire personal state first,
    -- then SKIP LOCKED on both, so there is no wait edge back to a producer.
    SELECT * INTO e FROM public.notification_center_events WHERE id=work.event_id FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN deferred:=deferred+1; PERFORM public.notification_center_prepared_defer(work.event_id,work.recipient,work.eligible_revision); CONTINUE; END IF;
    PERFORM 1 FROM public.notification_center_recipients
     WHERE event_id=e.id AND recipient=work.recipient AND eligible_revision=e.attention_revision
      AND processed_revision<eligible_revision FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN deferred:=deferred+1; PERFORM public.notification_center_prepared_defer(work.event_id,work.recipient,work.eligible_revision); CONTINUE; END IF;
    IF public.notification_center_allowed(e,work.recipient)
      AND public.notification_center_unmuted(e,work.recipient)
      AND NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries
       WHERE event_id=e.id AND recipient=work.recipient AND attention_revision=e.attention_revision) THEN
     UPDATE public.notification_center_user_state SET last_delivery_sequence=last_delivery_sequence+1
      WHERE organization=e.organization AND recipient=work.recipient RETURNING last_delivery_sequence INTO seq;
     INSERT INTO public.notification_center_deliveries(event_id,recipient,organization,attention_revision,sequence,group_key)
     VALUES(e.id,work.recipient,e.organization,e.attention_revision,seq,
      CASE WHEN e.kind='email_problem' THEN coalesce(e.occasion::text,'shared')||':email_problem:'||coalesce(e.data->>'reason','problem')||':'||(e.occurred_at AT TIME ZONE tz)::date::text
       WHEN e.kind IN ('order_created','waitlist_registered','order_cancelled','occasion_joined') THEN
        coalesce(e.occasion::text,'shared')||':'||e.kind||':'||(e.occurred_at AT TIME ZONE tz)::date::text ELSE e.id::text END);
     PERFORM public.notification_center_prepared_on_delivery(e,(SELECT d FROM public.notification_center_deliveries d WHERE d.event_id=e.id AND d.recipient=work.recipient AND d.attention_revision=e.attention_revision));
    END IF;
    UPDATE public.notification_center_recipients SET processed_revision=e.attention_revision,
     retry_revision=e.attention_revision,retry_count=0,next_attempt_at='-infinity',last_error_code=NULL,quarantined=false
     WHERE event_id=e.id AND recipient=work.recipient;
    IF NOT EXISTS(SELECT 1 FROM public.notification_center_recipients
     WHERE event_id=e.id AND eligible_revision=e.attention_revision AND processed_revision<e.attention_revision) THEN
     UPDATE public.notification_center_events SET projected_revision=e.attention_revision WHERE id=e.id;
    END IF;
    UPDATE public.notification_center_projection_scopes SET pending_delivery=greatest(0,pending_delivery-1)
     WHERE organization=e.organization AND recipient=work.recipient AND delivery_initialized;
    n:=n+1;
   EXCEPTION
    WHEN lock_not_available THEN deferred:=deferred+1;PERFORM public.notification_center_prepared_defer(work.event_id,work.recipient,work.eligible_revision);
    WHEN OTHERS THEN
     GET STACKED DIAGNOSTICS error_code=RETURNED_SQLSTATE;
     -- The subtransaction rolled back delivery and sequence allocation together.
     -- Store only SQLSTATE, never private payload or exception message.
     UPDATE public.notification_center_recipients r SET
      retry_count=CASE WHEN retry_revision=eligible_revision THEN retry_count+1 ELSE 1 END,
      next_attempt_at=clock_timestamp()+make_interval(secs=>least(300,power(2,least(CASE WHEN retry_revision=eligible_revision THEN retry_count ELSE 0 END,8))*(0.9+random()*0.2))),
      quarantined=retry_revision=eligible_revision AND retry_count>=4,
      retry_revision=eligible_revision,last_error_code=error_code
     WHERE r.event_id=work.event_id AND r.recipient=work.recipient
      AND r.eligible_revision=e.attention_revision;
     failed:=failed+1;
   END;
  END LOOP;
  -- Events with no eligible candidate must also leave the pending index.
  UPDATE public.notification_center_events ev SET projected_revision=attention_revision
   WHERE ev.id IN(SELECT z.id FROM (
    SELECT pending.id,pending.attention_revision FROM public.notification_center_events pending
    WHERE pending.organization=tenant.organization AND pending.projected_revision<pending.attention_revision
    ORDER BY pending.occurred_at,pending.id LIMIT 25 FOR UPDATE SKIP LOCKED) z
    WHERE NOT EXISTS(SELECT 1 FROM public.notification_center_recipients r WHERE r.event_id=z.id
      AND r.eligible_revision=z.attention_revision AND r.processed_revision<z.attention_revision));
  EXIT WHEN n>=budget OR scanned>=budget*4 OR clock_timestamp()>=deadline;
 END LOOP;
 UPDATE public.notification_center_maintenance SET cursor=coalesce(last_org,after_org),
  last_scanned=scanned,last_processed=n,last_deferred=deferred,last_failed=failed,
  last_elapsed_ms=extract(epoch FROM clock_timestamp()-started_at)*1000,last_run_at=clock_timestamp()
  WHERE name='delivery';
 PERFORM set_config('lock_timeout',previous_lock_timeout,true);
 RETURN n;
END $$;
CREATE OR REPLACE FUNCTION public.set_notification_center_muted(p_organization bigint,p_occasion bigint,p_muted boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_occasion);
 IF p_occasion IS NULL OR p_muted IS NULL THEN RAISE EXCEPTION 'notification_invalid_preference'; END IF;
 INSERT INTO public.notification_center_preferences VALUES(p_organization,auth.uid(),p_occasion,p_muted)
 ON CONFLICT(organization,recipient,occasion) DO UPDATE SET muted=excluded.muted;
END $$;
-- Explicitly close every helper; PostgREST cannot publish or project as a user.
REVOKE ALL ON FUNCTION public.notification_center_require_service(),public.notification_center_allowed(public.notification_center_events,uuid),
 public.notification_center_check_context(bigint,bigint),public.notification_center_publish_internal(bigint,bigint,text,text,jsonb,uuid,timestamptz,bigint[]),
 public.project_notification_center(integer)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.project_notification_center(integer) TO service_role;
REVOKE ALL ON FUNCTION public.set_notification_center_muted(bigint,bigint,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_notification_center_muted(bigint,bigint,boolean) TO authenticated;


-- SOURCE: notification_center/prepared_projection.sql
CREATE OR REPLACE FUNCTION public.notification_center_prepared_privacy(p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('user',m."user",'email',nullif(lower(btrim(u.email_readonly)),''),'profile',u.id IS NOT NULL) ORDER BY m."user"),'[]')
 FROM public.organization_users m LEFT JOIN public.user_info u ON u.id=m."user" AND u.organization=m.organization
 WHERE m.organization=p_org AND m.is_hidden;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_privacy_keys(p_state jsonb)
RETURNS SETOF text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT 'u:'||(x->>'user') FROM jsonb_array_elements(p_state) x WHERE x->>'profile'='true'
 UNION SELECT 'e:'||(x->>'email') FROM jsonb_array_elements(p_state) x WHERE x->>'email' IS NOT NULL;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_subjects(e public.notification_center_events)
RETURNS SETOF text LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
BEGIN
 IF public.notification_center_order_activity_internal(e.organization,e.kind,e.data) THEN RETURN; END IF;
 RETURN QUERY WITH orders AS(SELECT o.data->>'email' email FROM eshop.orders o
  WHERE o.occasion=e.occasion AND o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (e.data->>'orderId')::bigint END),
 messages AS(SELECT m.recipient,m.recipient_user,m.order_id FROM public.email_messages m
  WHERE e.kind='email_problem' AND m.organization=e.organization AND m.message_id=CASE WHEN e.data->>'messageId' ~* '^[0-9a-f-]{36}$' THEN (e.data->>'messageId')::uuid END),
 subjects AS(SELECT 'u:'||(e.data->>'userId') subject WHERE e.data->>'userId' IS NOT NULL
  UNION SELECT 'e:'||lower(btrim(email)) FROM orders WHERE nullif(btrim(email),'') IS NOT NULL
  UNION SELECT 'e:'||lower(btrim(recipient)) FROM messages WHERE nullif(btrim(recipient),'') IS NOT NULL
  UNION SELECT 'u:'||recipient_user FROM messages WHERE recipient_user IS NOT NULL
  UNION SELECT 'e:'||lower(btrim(o.data->>'email')) FROM messages m JOIN eshop.orders o ON o.id=m.order_id
   JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization WHERE nullif(btrim(o.data->>'email'),'') IS NOT NULL)
 SELECT subject FROM subjects;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_tags(e public.notification_center_events)
RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN e.kind='bank_problem' THEN
  ARRAY['bank:'||(e.data->>'bankConnectionId')]||
  CASE WHEN cardinality(e.affected_occasions)=0 THEN ARRAY['bank-shared:'||(e.data->>'bankConnectionId')] ELSE '{}'::text[] END||
  ARRAY(SELECT 'bank-occasion:'||x FROM unnest(e.affected_occasions) x)||
  ARRAY(SELECT 'bank-current:'||(e.data->>'bankConnectionId')||':'||x FROM unnest(e.affected_occasions) x)
 WHEN e.kind='provider_problem' THEN ARRAY['provider-unit:'||(e.data->>'unitId')]
 WHEN e.kind='email_problem' THEN ARRAY['email-admin:'||coalesce(e.occasion::text,'shared')]||
  CASE WHEN e.occasion IS NOT NULL THEN ARRAY['orders:'||e.occasion] ELSE '{}'::text[] END
 WHEN e.kind IN ('occasion_joined','event_capacity_full') THEN ARRAY['app:'||e.occasion]
 ELSE ARRAY['orders:'||e.occasion] END;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_allowed_scopes(p_org bigint,p_current bigint,p_user uuid)
RETURNS TABLE(scope text,section integer) LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 -- Candidate discovery reads current roles once. Payloads and selection still
 -- authorize each real event with notification_center_allowed before private reads.
 WITH admin AS MATERIALIZED(SELECT EXISTS(SELECT 1 FROM public.organization_users
  WHERE organization=p_org AND "user"=p_user AND is_admin) is_admin),
 members AS MATERIALIZED(SELECT m.occasion,bool_or(m.is_editor_order_view) orders,
  bool_or(public.participant_contacts_read_rule(m.is_editor,m.is_manager,false)) app
  FROM public.occasion_users m WHERE m."user"=p_user AND (m.is_editor_order_view OR m.is_editor OR m.is_manager)
  GROUP BY m.occasion),
 own AS MATERIALIZED(SELECT occasion id FROM members
  UNION SELECT o.id FROM public.occasions o,admin a WHERE o.organization=p_org AND a.is_admin),
 occasions AS MATERIALIZED(SELECT oc.id,CASE WHEN oc.id=p_current THEN 1 ELSE 2 END priority,
  coalesce(m.orders,false) AND d.occasion IS NULL orders,
  (a.is_admin OR coalesce(m.app,false)) AND d.occasion IS NULL app,
  a.is_admin OR (coalesce(m.orders,false) AND d.occasion IS NULL) email,
  coalesce(m.orders,false) bank
  FROM public.occasions oc JOIN own ON own.id=oc.id CROSS JOIN admin a
  LEFT JOIN members m ON m.occasion=oc.id
  LEFT JOIN public.demo_occasions d ON d.occasion=oc.id
  WHERE oc.organization=p_org),
 bank_access AS MATERIALIZED(SELECT bu.bank_account FROM eshop.bank_account_users bu
  WHERE bu."user"=p_user AND public.notification_center_bank_admin(bu.bank_account,p_user)
   AND EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit
    WHERE uba.bank_account=bu.bank_account AND u.organization=p_org)),
 banks AS MATERIALIZED(SELECT c.id FROM eshop.bank_sync_connections c WHERE EXISTS(
  SELECT 1 FROM bank_access ba WHERE ba.bank_account=c.bank_account_id OR ba.bank_account IN(
   SELECT alias.bank_account_id FROM eshop.bank_sync_account_aliases alias WHERE alias.connection_id=c.id)))
 SELECT 'orders:'||id,priority FROM occasions WHERE orders
 UNION ALL SELECT 'app:'||id,priority FROM occasions WHERE app
 UNION ALL SELECT 'email-admin:'||id,priority FROM occasions WHERE email
 UNION ALL SELECT 'email-admin:shared',0 FROM admin WHERE is_admin
 UNION ALL SELECT 'bank-occasion:'||id,CASE WHEN p_current IS NULL OR id=p_current THEN 0 ELSE 2 END FROM occasions WHERE bank
 UNION ALL SELECT 'provider-unit:'||un.id,0 FROM public.units un JOIN public.unit_users um ON um.unit=un.id
 WHERE un.organization=p_org AND um."user"=p_user AND um.is_manager AND public.payment_provider_unit_manager_internal(un.id,p_user) AND NOT public.is_demo_unit(un.id)
 UNION ALL SELECT 'bank:'||id,CASE WHEN p_current IS NULL THEN 0 ELSE 2 END FROM banks
 UNION ALL SELECT 'bank-shared:'||id,0 FROM banks
 UNION ALL SELECT 'bank-current:'||id||':'||p_current,0 FROM banks WHERE p_current IS NOT NULL;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_refresh_summary(p_org bigint,p_user uuid,p_id text)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE ids uuid[]; latest public.notification_center_events; upper_bound bigint; first_seq bigint; read_state boolean;
BEGIN
 DELETE FROM public.notification_center_batch_summaries WHERE organization=p_org AND recipient=p_user AND id=p_id AND activity_count=0;
 IF NOT EXISTS(SELECT 1 FROM public.notification_center_batch_summaries WHERE organization=p_org AND recipient=p_user AND id=p_id) THEN RETURN; END IF;
 SELECT array_agg(event_id ORDER BY occurred_at DESC,event_id DESC) INTO ids FROM (
  SELECT event_id,occurred_at FROM public.notification_center_view_members WHERE organization=p_org AND recipient=p_user AND batch_id=p_id AND eligible
  ORDER BY occurred_at DESC,event_id DESC LIMIT 3) x;
 SELECT * INTO STRICT latest FROM public.notification_center_events WHERE id=ids[1];
 SELECT sequence INTO upper_bound FROM public.notification_center_view_members WHERE organization=p_org AND recipient=p_user AND batch_id=p_id AND eligible ORDER BY sequence DESC LIMIT 1;
 SELECT sequence INTO first_seq FROM public.notification_center_view_members WHERE organization=p_org AND recipient=p_user AND batch_id=p_id AND eligible ORDER BY sequence LIMIT 1;
 UPDATE public.notification_center_batch_summaries SET first_sequence=first_seq,latest_event=latest.id,latest_at=latest.occurred_at,
  through_sequence=upper_bound,preview_events=ids WHERE organization=p_org AND recipient=p_user AND id=p_id RETURNING is_read INTO read_state;
 DELETE FROM public.notification_center_summary_scopes WHERE organization=p_org AND recipient=p_user AND id=p_id;
 INSERT INTO public.notification_center_summary_scopes(organization,recipient,scope,id,latest_at,sequence,is_read)
 SELECT p_org,p_user,tag,p_id,latest.occurred_at,upper_bound,read_state FROM unnest(public.notification_center_prepared_tags(latest)) tag WHERE tag IS NOT NULL;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_policy(e public.notification_center_events,p_anchor timestamptz,p_privacy jsonb)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT NOT EXISTS(SELECT 1 FROM public.notification_center_prepared_subjects(e) subject
  JOIN (SELECT 'u:'||(x->>'user') subject FROM jsonb_array_elements(p_privacy) x WHERE x->>'profile'='true'
   UNION SELECT 'e:'||(x->>'email') FROM jsonb_array_elements(p_privacy) x WHERE x->>'email' IS NOT NULL) hidden USING(subject))
 AND public.notification_center_event_relevant_internal(e,p_anchor);
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_apply(e public.notification_center_events,d public.notification_center_deliveries,p_anchor timestamptz DEFAULT clock_timestamp(),p_privacy jsonb DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
#variable_conflict use_column
DECLARE old public.notification_center_view_members; b record; id text; visible boolean; places bigint; context jsonb; multi boolean; facts jsonb;
BEGIN
 SELECT * INTO old FROM public.notification_center_view_members WHERE organization=d.organization AND recipient=d.recipient AND event_id=d.event_id;
 IF FOUND AND old.sequence>d.sequence THEN RETURN; END IF;
 SELECT * INTO b FROM public.notification_center_prepared_batch_at(e,d,p_anchor);
 id:=CASE WHEN e.kind IN ('email_problem','bank_problem','payment_problem','provider_problem') OR e.occasion IS NULL THEN e.id::text WHEN b.is_read THEN b.group_key||':history:read' ELSE b.batch_id||':unread' END;
 visible:=public.notification_center_prepared_policy(e,p_anchor,coalesce(p_privacy,(SELECT privacy FROM public.notification_center_projection_scopes WHERE organization=d.organization AND recipient=d.recipient)));
 facts:=public.notification_center_event_facts_internal(e);
 places:=nullif((facts->>'count')::bigint,0);
 context:=facts->'formContext';
 multi:=(facts->>'allowsMultiple')::boolean;
 IF old.eligible THEN
  UPDATE public.notification_center_batch_summaries SET activity_count=activity_count-1,known_count=known_count-(old.places IS NOT NULL)::int,
   places=places-coalesce(old.places,0),multiple_count=multiple_count-old.multiple::int
   WHERE organization=d.organization AND recipient=d.recipient AND id=old.batch_id;
 END IF;
 INSERT INTO public.notification_center_view_members(organization,recipient,event_id,sequence,attention_revision,source_revision,group_key,batch_id,is_read,after_sequence,through_sequence,eligible,occurred_at,expires_at,places,multiple)
 VALUES(d.organization,d.recipient,e.id,d.sequence,d.attention_revision,e.view_revision,b.group_key,id,b.is_read,b.after_sequence,b.through_sequence,visible,e.occurred_at,
  CASE WHEN e.kind NOT IN ('email_problem','bank_problem','payment_problem','provider_problem') THEN e.occurred_at+interval '30 days' END,places,multi)
 ON CONFLICT(organization,recipient,event_id) DO UPDATE SET sequence=excluded.sequence,attention_revision=excluded.attention_revision,source_revision=excluded.source_revision,
 group_key=excluded.group_key,batch_id=excluded.batch_id,is_read=excluded.is_read,after_sequence=excluded.after_sequence,through_sequence=excluded.through_sequence,
 eligible=excluded.eligible,occurred_at=excluded.occurred_at,expires_at=excluded.expires_at,places=excluded.places,multiple=excluded.multiple;
 DELETE FROM public.notification_center_member_subjects WHERE organization=d.organization AND recipient=d.recipient AND event_id=e.id;
 INSERT INTO public.notification_center_member_subjects(organization,recipient,event_id,subject)
 SELECT d.organization,d.recipient,e.id,subject FROM public.notification_center_prepared_subjects(e) subject ON CONFLICT DO NOTHING;
 IF visible THEN
  INSERT INTO public.notification_center_batch_summaries(organization,recipient,id,group_key,kind,occasion,is_read,after_sequence,through_sequence,activity_count,known_count,places,multiple_count,latest_at,latest_event,preview_events)
  VALUES(d.organization,d.recipient,id,b.group_key,e.kind,e.occasion,b.is_read,b.after_sequence,d.sequence,1,(places IS NOT NULL)::int,coalesce(places,0),multi::int,e.occurred_at,e.id,ARRAY[e.id])
  ON CONFLICT(organization,recipient,id) DO UPDATE SET activity_count=notification_center_batch_summaries.activity_count+1,
   known_count=notification_center_batch_summaries.known_count+excluded.known_count,places=notification_center_batch_summaries.places+excluded.places,
   multiple_count=notification_center_batch_summaries.multiple_count+excluded.multiple_count,is_read=excluded.is_read;
 END IF;
 IF old.batch_id IS NOT NULL AND old.batch_id<>id THEN PERFORM public.notification_center_prepared_refresh_summary(d.organization,d.recipient,old.batch_id); END IF;
 PERFORM public.notification_center_prepared_refresh_summary(d.organization,d.recipient,id);
END $$;
CREATE INDEX IF NOT EXISTS notification_center_member_upper ON public.notification_center_view_members(organization,recipient,batch_id,sequence DESC) WHERE eligible;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_invalidate(p_event uuid)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE org bigint; rev bigint; r record;
BEGIN
 -- No delivery means no prepared contribution to retract or invalidate.
 IF NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries WHERE event_id=p_event) THEN RETURN; END IF;
 UPDATE public.notification_center_events SET view_revision=view_revision+1 WHERE id=p_event RETURNING organization,view_revision INTO org,rev;
 FOR r IN SELECT nr.recipient,nr.view_required_revision>nr.view_applied_revision dirty FROM public.notification_center_recipients nr
  JOIN public.notification_center_projection_scopes s ON s.organization=org AND s.recipient=nr.recipient
  WHERE nr.event_id=p_event AND EXISTS(SELECT 1 FROM public.notification_center_deliveries d WHERE d.event_id=p_event AND d.recipient=nr.recipient)
  FOR UPDATE OF nr LOOP
  UPDATE public.notification_center_recipients SET view_required_revision=rev WHERE event_id=p_event AND recipient=r.recipient;
  UPDATE public.notification_center_projection_scopes SET revision=revision+1,
   pending_events=pending_events+CASE WHEN phase='ready' AND NOT r.dirty THEN 1 ELSE 0 END,requested_at=CASE WHEN work_requested THEN requested_at ELSE clock_timestamp() END,work_requested=true,next_check_at=CASE WHEN failed_event=p_event OR retry_count=0 THEN least(next_check_at,clock_timestamp()) ELSE next_check_at END,
   quarantined=CASE WHEN failed_event=p_event THEN false ELSE quarantined END,retry_count=CASE WHEN failed_event=p_event THEN 0 ELSE retry_count END,
   last_error_code=CASE WHEN failed_event=p_event THEN NULL ELSE last_error_code END
   WHERE organization=org AND recipient=r.recipient;
 END LOOP;
 PERFORM public.notification_center_prepared_wake();
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_delete_member(p_org bigint,p_user uuid,p_event uuid)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE old public.notification_center_view_members;
BEGIN
 SELECT * INTO old FROM public.notification_center_view_members WHERE organization=p_org AND recipient=p_user AND event_id=p_event;
 IF NOT FOUND THEN RETURN; END IF;
 IF old.eligible THEN
  UPDATE public.notification_center_batch_summaries b SET activity_count=b.activity_count-1,
   known_count=b.known_count-(old.places IS NOT NULL)::int,places=b.places-coalesce(old.places,0),multiple_count=b.multiple_count-old.multiple::int
   WHERE b.organization=p_org AND b.recipient=p_user AND b.id=old.batch_id;
 END IF;
 DELETE FROM public.notification_center_view_members WHERE organization=p_org AND recipient=p_user AND event_id=p_event;
 PERFORM public.notification_center_prepared_refresh_summary(p_org,p_user,old.batch_id);
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_delete_events(p_events uuid[])
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE m record;
BEGIN
 FOR m IN SELECT ev.organization,r.recipient,r.event_id,r.view_required_revision>r.view_applied_revision dirty,
   r.processed_revision<r.eligible_revision delivery_dirty
  FROM public.notification_center_recipients r JOIN public.notification_center_events ev ON ev.id=r.event_id
  JOIN public.notification_center_projection_scopes ps ON ps.organization=ev.organization AND ps.recipient=r.recipient
  WHERE r.event_id=ANY(p_events) ORDER BY ev.organization,r.recipient,r.event_id FOR UPDATE OF ev,r LOOP
  PERFORM 1 FROM public.notification_center_projection_scopes WHERE organization=m.organization AND recipient=m.recipient FOR UPDATE;
  PERFORM public.notification_center_prepared_delete_member(m.organization,m.recipient,m.event_id);
  UPDATE public.notification_center_projection_scopes SET revision=revision+1,
   pending_events=greatest(0,pending_events-m.dirty::int),
   pending_delivery=greatest(0,pending_delivery-CASE WHEN delivery_initialized AND m.delivery_dirty THEN 1 ELSE 0 END)
   WHERE organization=m.organization AND recipient=m.recipient;
 END LOOP;
 PERFORM public.notification_center_prepared_wake();
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_on_delivery(e public.notification_center_events,d public.notification_center_deliveries)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE s public.notification_center_projection_scopes; read_rev bigint;
BEGIN
 SELECT * INTO s FROM public.notification_center_projection_scopes WHERE organization=d.organization AND recipient=d.recipient FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN
  IF EXISTS(SELECT 1 FROM public.notification_center_projection_scopes WHERE organization=d.organization AND recipient=d.recipient) THEN
   RAISE lock_not_available USING MESSAGE='notification_projection_scope_busy';
  END IF;
  RETURN;
 END IF;
 SELECT view_read_revision INTO read_rev FROM public.notification_center_user_state WHERE organization=d.organization AND recipient=d.recipient;
 IF s.phase<>'ready' OR s.pending_events>0 OR s.pending_groups>0 OR s.privacy_pending
  OR s.applied_read_revision<>read_rev OR s.privacy<>public.notification_center_prepared_privacy(d.organization)
  OR s.prepared_sequence<>d.sequence-1 THEN
  UPDATE public.notification_center_projection_scopes SET requested_at=CASE WHEN work_requested THEN requested_at ELSE clock_timestamp() END,work_requested=true,next_check_at=CASE WHEN retry_count=0 THEN least(next_check_at,clock_timestamp()) ELSE next_check_at END WHERE organization=d.organization AND recipient=d.recipient;
  RETURN;
 END IF;
 PERFORM public.notification_center_prepared_apply(e,d);
 UPDATE public.notification_center_recipients SET view_required_revision=e.view_revision,view_applied_revision=e.view_revision WHERE event_id=e.id AND recipient=d.recipient;
 UPDATE public.notification_center_projection_scopes SET prepared_sequence=d.sequence,
  next_expiry=least(next_expiry,CASE WHEN e.kind NOT IN ('email_problem','bank_problem','payment_problem','provider_problem') AND public.notification_center_prepared_policy(e,clock_timestamp(),s.privacy) THEN e.occurred_at+interval '30 days' END)
  WHERE organization=d.organization AND recipient=d.recipient;
END $$;
-- One receipt owner serves both external serializers after their scope checks.
CREATE OR REPLACE FUNCTION public.notification_center_prepared_record_read(p_org bigint,p_group text,p_after bigint,p_through bigint,p_captured boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE baseline bigint; last_read bigint; lower_bound bigint; inserted boolean;
BEGIN
 SELECT read_through_sequence INTO baseline FROM public.notification_center_user_state WHERE organization=p_org AND recipient=auth.uid() FOR UPDATE;
 SELECT coalesce(max(through_sequence),0) INTO last_read FROM public.notification_center_read_batches WHERE organization=p_org AND recipient=auth.uid() AND group_key=p_group;
 lower_bound:=CASE WHEN p_captured THEN greatest(p_after,baseline) ELSE greatest(p_after,baseline,last_read) END;
 IF p_through<=lower_bound THEN RETURN true; END IF;
 INSERT INTO public.notification_center_read_batches(organization,recipient,group_key,after_sequence,through_sequence)
 VALUES(p_org,auth.uid(),p_group,lower_bound,p_through) ON CONFLICT DO NOTHING;
 IF NOT FOUND THEN RETURN true; END IF;
 UPDATE public.notification_center_user_state SET view_read_revision=view_read_revision+1 WHERE organization=p_org AND recipient=auth.uid();
 INSERT INTO public.notification_center_group_repairs(organization,recipient,group_key)
 SELECT p_org,auth.uid(),p_group WHERE EXISTS(SELECT 1 FROM public.notification_center_projection_scopes WHERE organization=p_org AND recipient=auth.uid())
 ON CONFLICT DO NOTHING RETURNING true INTO inserted;
 IF inserted THEN
  UPDATE public.notification_center_projection_scopes SET pending_groups=pending_groups+1,requested_at=CASE WHEN work_requested THEN requested_at ELSE clock_timestamp() END,work_requested=true,next_check_at=CASE WHEN retry_count=0 THEN least(next_check_at,clock_timestamp()) ELSE next_check_at END WHERE organization=p_org AND recipient=auth.uid();
 ELSE
  UPDATE public.notification_center_group_repairs SET cursor=NULL WHERE organization=p_org AND recipient=auth.uid() AND group_key=p_group;
 END IF;
 PERFORM public.notification_center_prepared_wake();
 RETURN true;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_seal(p_org bigint,p_group text,p_after bigint,p_through bigint)
RETURNS boolean LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.notification_center_prepared_record_read(p_org,p_group,p_after,p_through,false);
$$;

CREATE OR REPLACE FUNCTION public.notification_center_prepared_order_events(p_order bigint)
RETURNS SETOF uuid LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT e.id FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
 JOIN public.notification_center_events e ON e.organization=oc.organization AND e.occasion=o.occasion
 WHERE o.id=p_order AND e.data->>'orderId'=p_order::text
  AND e.kind IN ('order_created','waitlist_registered','order_cancelled','order_payment_received','payment_problem','offer_accepted','offer_declined','offer_expired')
 UNION
 SELECT e.id FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
 JOIN public.email_messages m ON m.order_id=o.id AND m.occasion=o.occasion AND m.organization=oc.organization
 JOIN public.notification_center_events e ON e.organization=m.organization AND e.kind='email_problem' AND e.source_key='email:'||m.message_id
 WHERE o.id=p_order;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_invalidate_order(p_order bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE event_id uuid;
BEGIN
 FOR event_id IN SELECT * FROM public.notification_center_prepared_order_events(p_order) LOOP
  PERFORM public.notification_center_prepared_invalidate(event_id);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_invalidate_user(p_user uuid,p_occasion bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE item record;
BEGIN
 FOR item IN SELECT e.id FROM public.notification_center_events e WHERE e.kind='occasion_joined' AND e.data->>'userId'=p_user::text
  AND (p_occasion IS NULL OR e.occasion=p_occasion) LOOP PERFORM public.notification_center_prepared_invalidate(item.id); END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_defer(p_event uuid,p_recipient uuid,p_revision bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 -- Only retry metadata changes. Never claim work or advance canonical progress.
 UPDATE public.notification_center_recipients r SET next_attempt_at=clock_timestamp()+interval '1 second',
  retry_count=CASE WHEN retry_revision=eligible_revision THEN retry_count ELSE 0 END,
  quarantined=CASE WHEN retry_revision=eligible_revision THEN quarantined ELSE false END,retry_revision=eligible_revision
 WHERE r.event_id=p_event AND r.recipient=p_recipient AND r.eligible_revision=p_revision
  AND r.ctid IN(SELECT ctid FROM public.notification_center_recipients WHERE event_id=p_event AND recipient=p_recipient FOR UPDATE SKIP LOCKED);
END $$;


-- SOURCE: notification_center/prepared_views.sql
CREATE OR REPLACE FUNCTION public.notification_center_prepared_batch_at(
 e public.notification_center_events,d public.notification_center_deliveries,p_anchor timestamptz)
RETURNS TABLE(batch_id text,is_read boolean,after_sequence bigint,through_sequence bigint,group_key text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH state AS (
  SELECT coalesce((SELECT read_through_sequence FROM public.notification_center_user_state
   WHERE organization=d.organization AND recipient=d.recipient),0) baseline,
   CASE WHEN e.occasion IS NOT NULL AND e.kind NOT IN ('email_problem','bank_problem','payment_problem','provider_problem')
    THEN 'occasion-kind:'||e.occasion||':'||e.kind ELSE 'event:'||e.id END key),
 receipt AS (
  SELECT b.* FROM public.notification_center_read_batches b,state s
  WHERE b.organization=d.organization AND b.recipient=d.recipient AND b.group_key=s.key
   AND b.read_at<=p_anchor AND d.sequence>b.after_sequence AND d.sequence<=b.through_sequence
  ORDER BY b.through_sequence,b.read_at,b.id LIMIT 1),
 bounds AS (
  SELECT s.*,greatest(s.baseline,coalesce((SELECT max(b.through_sequence)
   FROM public.notification_center_read_batches b WHERE b.organization=d.organization
    AND b.recipient=d.recipient AND b.group_key=s.key AND b.read_at<=p_anchor),0)) last_read FROM state s)
 SELECT CASE WHEN d.sequence<=s.baseline THEN s.key||':legacy'
   WHEN r.id IS NOT NULL THEN s.key||':batch:'||r.after_sequence
   ELSE s.key||':batch:'||s.last_read END,
  d.sequence<=s.baseline OR r.id IS NOT NULL,
  CASE WHEN d.sequence<=s.baseline THEN 0
   WHEN r.id IS NOT NULL THEN r.after_sequence ELSE s.last_read END,
  CASE WHEN d.sequence<=s.baseline THEN s.baseline
   WHEN r.id IS NOT NULL THEN r.through_sequence ELSE d.sequence END,s.key
 FROM bounds s LEFT JOIN receipt r ON true;
$$;

DROP FUNCTION IF EXISTS public.notification_center_prepared_scope_member(public.notification_center_events,public.notification_center_deliveries,text,text,bigint,bigint);
-- Shared membership predicate. External legacy and token contracts validate
-- their scopes separately before invoking this private owner.
CREATE OR REPLACE FUNCTION public.notification_center_prepared_scope_member(e public.notification_center_events,d public.notification_center_deliveries,p_group text,p_id text,p_after bigint,p_through bigint,p_capture_at timestamptz DEFAULT NULL,p_capture_read boolean DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT d.sequence>p_after AND d.sequence<=p_through AND CASE WHEN p_capture_at IS NULL THEN true WHEN p_group LIKE 'event:%' THEN true ELSE
  EXISTS(SELECT 1 FROM public.notification_center_prepared_batch_at(e,d,p_capture_at) b WHERE (b.batch_id=regexp_replace(p_id,':(read|unread)$','') OR (p_id=p_group||':history:read' AND p_capture_read)) AND b.is_read=p_capture_read) END
 AND CASE WHEN p_group LIKE 'event:%' THEN 'event:'||e.id=p_group
 ELSE 'occasion-kind:'||e.occasion||':'||e.kind=p_group END
 AND CASE WHEN p_id ~ ':self$' THEN coalesce(e.actor=d.recipient,false)
 WHEN p_id ~ ':(batch:[0-9]+|legacy)$' AND e.kind IN ('order_created','order_cancelled') THEN e.actor IS DISTINCT FROM d.recipient ELSE true END;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_contact(e public.notification_center_events)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_strip_nulls(jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'))
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization
 WHERE o.occasion=e.occasion AND o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (e.data->>'orderId')::bigint END;
$$;
-- The scope vector is derived from live roles inside the payload's SQL snapshot.
-- Private subject visibility remains per event; no role result survives a request.
CREATE OR REPLACE FUNCTION public.notification_center_prepared_event_access(e public.notification_center_events,p_org bigint,p_scopes text[])
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(e.organization=p_org AND public.notification_center_subject_visible_internal(e.organization,e.kind,e.data) AND
 CASE WHEN e.kind IN ('occasion_joined','event_capacity_full') THEN ('app:'||e.occasion)=ANY(p_scopes)
 WHEN e.kind='provider_problem' THEN ('provider-unit:'||(e.data->>'unitId'))=ANY(p_scopes)
 WHEN e.kind='email_problem' THEN 'email-admin:shared'=ANY(p_scopes) OR ('email-admin:'||e.occasion)=ANY(p_scopes)
 WHEN e.kind='bank_problem' THEN ('bank:'||(e.data->>'bankConnectionId'))=ANY(p_scopes)
  OR EXISTS(SELECT 1 FROM unnest(e.affected_occasions) oc WHERE ('bank-occasion:'||oc)=ANY(p_scopes))
 ELSE ('orders:'||e.occasion)=ANY(p_scopes)
  OR EXISTS(SELECT 1 FROM unnest(e.affected_occasions) oc WHERE ('orders:'||oc)=ANY(p_scopes)) END,false);
$$;
DROP FUNCTION IF EXISTS public.notification_center_prepared_render(public.notification_center_view_rows,public.notification_center_views);
CREATE OR REPLACE FUNCTION public.notification_center_prepared_render(r public.notification_center_view_rows,v public.notification_center_views,p_scopes text[] DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE e public.notification_center_events; d public.notification_center_deliveries; dto jsonb; contact jsonb; previews jsonb; payload jsonb; grouped boolean;
BEGIN
 IF r.state<>'ready' THEN RETURN jsonb_build_object('id',r.id,'position',r.position,'state',r.state); END IF;
 SELECT * INTO e FROM public.notification_center_events WHERE id=r.latest_event;
 IF NOT FOUND OR e.organization<>v.organization OR NOT (CASE WHEN p_scopes IS NULL THEN public.notification_center_allowed(e,auth.uid())
  ELSE public.notification_center_prepared_event_access(e,v.organization,p_scopes) END) THEN RETURN jsonb_build_object('id',r.id,'position',r.position,'state','removed'); END IF;
 SELECT * INTO d FROM public.notification_center_deliveries WHERE event_id=e.id AND recipient=v.recipient AND sequence<=v.snapshot ORDER BY sequence DESC LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('id',r.id,'position',r.position,'state','removed'); END IF;
 grouped:=e.occasion IS NOT NULL AND e.kind NOT IN ('email_problem','bank_problem','payment_problem','provider_problem');
 IF grouped AND public.notification_center_order_activity_internal(e.kind) THEN
  contact:=coalesce(public.notification_center_prepared_contact(e),'{}');
  SELECT coalesce(jsonb_agg(coalesce(public.notification_center_prepared_contact(ev),'{}') ORDER BY p.position),'[]') INTO previews
   FROM unnest(r.preview_events) WITH ORDINALITY p(id,position) JOIN public.notification_center_events ev ON ev.id=p.id;
  payload:=CASE WHEN r.activity_count=1 THEN e.data-'orderId'-'orderSymbol' ELSE '{}'::jsonb END||
   jsonb_build_object('contact',contact,'previewContacts',previews,'activityCount',r.activity_count,'relatedOrders',true,
    'allowsMultiple',r.multiple_count>0,'afterSequence',r.after_sequence,'throughSequence',r.through_sequence)||
   CASE WHEN r.multiple_count>0 AND r.known_count=r.activity_count THEN jsonb_build_object('placeCount',r.places) ELSE '{}'::jsonb END;
  dto:=public.notification_center_event_display_internal(e)||jsonb_build_object('kind',e.kind,'status',e.status,'data',payload);
 ELSE
  dto:=public.notification_center_dto(e,d);
  IF grouped THEN dto:=jsonb_set(dto,'{data}',coalesce(dto->'data','{}')||jsonb_build_object('eventCount',r.activity_count)); END IF;
 END IF;
 RETURN dto||jsonb_build_object('id',r.id,'position',r.position,'state','ready','sequence',r.through_sequence,
  'section',CASE WHEN e.occasion IS NULL AND (v.current_occasion IS NULL OR cardinality(e.affected_occasions)=0 OR v.current_occasion=ANY(e.affected_occasions)) THEN 0 WHEN e.occasion=v.current_occasion THEN 1 ELSE 2 END,'occurredAt',r.latest_at,'day',(r.latest_at AT TIME ZONE v.timezone)::date,'isRead',r.is_read,
  'isSeen',r.is_read OR r.through_sequence<=v.previous_seen);
END $$;
DROP FUNCTION IF EXISTS public.notification_center_prepared_display_key(uuid,integer,integer);
CREATE OR REPLACE FUNCTION public.notification_center_prepared_display_key(p_token uuid,p_cursor integer,p_limit integer,p_scopes text[] DEFAULT NULL)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH owned AS MATERIALIZED(SELECT * FROM public.notification_center_views WHERE token=p_token AND recipient=auth.uid()),
 rights AS MATERIALIZED(SELECT v.organization,coalesce(p_scopes,ARRAY(SELECT a.scope FROM public.notification_center_prepared_allowed_scopes(v.organization,v.current_occasion,v.recipient) a ORDER BY a.scope)) scopes FROM owned v),
 rows AS MATERIALIZED(SELECT r.*,r.xmin::text row_xid,r.ctid::text row_tid FROM public.notification_center_view_rows r WHERE r.token=p_token AND r.position>p_cursor AND r.position<=p_cursor+p_limit),
 facts AS(SELECT r.position,p.position preview,ev.id,ev.event_xid,ev.event_tid,
  o.xmin::text order_xid,o.ctid::text order_tid,m.xmin::text mail_xid,m.ctid::text mail_tid,
  mo.xmin::text mail_order_xid,mo.ctid::text mail_order_tid,ui.xmin::text profile_xid,ui.ctid::text profile_tid,
  oc.xmin::text occasion_xid,oc.ctid::text occasion_tid,
  CASE WHEN ev.kind='bank_problem' THEN(SELECT jsonb_agg(jsonb_build_array(c.xmin::text,c.ctid::text,uba.unit,uba.bank_account,uba.xmin::text,uba.ctid::text,bu.xmin::text,bu.ctid::text,um.xmin::text,um.ctid::text,u.xmin::text,u.ctid::text) ORDER BY uba.unit,bu.bank_account)
   FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu ON bu."user"=auth.uid() AND (bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id))
   JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account JOIN public.units u ON u.id=uba.unit
   LEFT JOIN public.unit_users um ON um.unit=u.id AND um."user"=auth.uid() WHERE c.id=(ev.data->>'bankConnectionId')::bigint) END bank_versions,
  CASE WHEN ev.kind='bank_problem' THEN(SELECT jsonb_agg(jsonb_build_array(impact.id,impact.xmin::text,impact.ctid::text) ORDER BY impact.id) FROM public.occasions impact
   WHERE impact.organization=ev.organization AND impact.id=ANY(ev.affected_occasions)) END impact_versions
  FROM rows r CROSS JOIN rights ac CROSS JOIN LATERAL unnest(r.preview_events) WITH ORDINALITY p(id,position)
  JOIN LATERAL(SELECT permitted.*,permitted.xmin::text event_xid,permitted.ctid::text event_tid FROM public.notification_center_events permitted WHERE permitted.id=p.id AND public.notification_center_prepared_event_access(permitted,ac.organization,ac.scopes) OFFSET 0) ev ON true
  LEFT JOIN eshop.orders o ON o.occasion=ev.occasion AND o.id=CASE WHEN ev.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (ev.data->>'orderId')::bigint END
  LEFT JOIN public.email_messages m ON m.organization=ev.organization AND m.message_id=CASE WHEN ev.data->>'messageId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (ev.data->>'messageId')::uuid END
  LEFT JOIN eshop.orders mo ON mo.id=m.order_id AND mo.occasion=m.occasion
  LEFT JOIN public.user_info ui ON ui.organization=ev.organization AND ui.id=coalesce(m.recipient_user,CASE WHEN ev.data->>'userId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (ev.data->>'userId')::uuid END)
  LEFT JOIN public.occasions oc ON oc.id=ev.occasion AND oc.organization=ev.organization)
 SELECT md5(jsonb_build_array(
  (SELECT jsonb_agg(jsonb_build_array(position,row_xid,row_tid) ORDER BY position) FROM rows),
  (SELECT jsonb_agg(to_jsonb(f) ORDER BY position,preview) FROM facts f),
  (SELECT to_jsonb(scopes) FROM rights))::text);
$$;

-- One STABLE statement owns privacy/read checks and every payload read, avoiding
-- a generation preflight followed by a different READ COMMITTED snapshot.
DROP FUNCTION IF EXISTS public.notification_center_prepared_payload(uuid,integer,integer);
CREATE OR REPLACE FUNCTION public.notification_center_prepared_payload(p_token uuid,p_cursor integer,p_limit integer,p_revision text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH owned AS MATERIALIZED(SELECT v.*,s.revision current_revision,u.view_read_revision current_read_revision,
  md5(public.notification_center_prepared_privacy(v.organization)::text) current_privacy
  FROM public.notification_center_views v JOIN public.notification_center_projection_scopes s USING(organization,recipient)
  JOIN public.notification_center_user_state u USING(organization,recipient)
  WHERE v.token=p_token AND v.recipient=auth.uid()),
 status AS MATERIALIZED(SELECT o.*,EXISTS(SELECT 1 FROM public.notification_center_view_rows r WHERE r.token=o.token
  AND (r.revision<>o.current_revision OR r.read_revision<>o.current_read_revision OR r.privacy_key<>o.current_privacy OR r.state='preparing')) preparing FROM owned o),
 rights AS MATERIALIZED(SELECT o.token,ARRAY(SELECT a.scope FROM public.notification_center_prepared_allowed_scopes(o.organization,o.current_occasion,o.recipient) a ORDER BY a.scope) scopes FROM status o WHERE NOT o.preparing),
 keyed AS MATERIALIZED(SELECT o.*,a.scopes,CASE WHEN o.preparing THEN NULL ELSE public.notification_center_prepared_display_key(o.token,p_cursor,p_limit,a.scopes) END display_key FROM status o LEFT JOIN rights a USING(token))
 SELECT jsonb_build_object('viewSupported',true,'state',CASE WHEN o.expires_at<=clock_timestamp() THEN 'expired' WHEN o.preparing THEN 'preparing' ELSE 'ready' END,
  'viewToken',o.token,'snapshot',o.snapshot,'snapshotAt',o.anchor,'snapshotDay',(o.anchor AT TIME ZONE o.timezone)::date,'timezone',o.timezone,
  'previousReadThrough',o.previous_seen,'acknowledged',o.acknowledged,'truncated',o.truncated,
  'revision',o.current_revision::text||':'||o.current_read_revision::text||':'||o.current_privacy||':'||o.display_key,
  'unchanged',NOT o.preparing AND p_revision=(o.current_revision::text||':'||o.current_read_revision::text||':'||o.current_privacy||':'||o.display_key),
  'items',CASE WHEN o.expires_at<=clock_timestamp() OR (NOT o.preparing AND p_revision=(o.current_revision::text||':'||o.current_read_revision::text||':'||o.current_privacy||':'||o.display_key)) THEN '[]'::jsonb ELSE coalesce((SELECT jsonb_agg(
   CASE WHEN o.preparing THEN jsonb_build_object('id',r.id,'position',r.position,'state','preparing')
   ELSE public.notification_center_prepared_render(r,ROW(o.token,o.organization,o.recipient,o.current_occasion,o.timezone,o.snapshot,o.anchor,o.previous_seen,o.source_revision,o.read_revision,o.privacy_key,o.created_at,o.expires_at,o.acknowledged,o.truncated)::public.notification_center_views,o.scopes) END ORDER BY r.position)
   FROM public.notification_center_view_rows r WHERE r.token=o.token AND r.position>p_cursor AND r.position<=p_cursor+p_limit),'[]') END,
  'nextCursor',CASE WHEN EXISTS(SELECT 1 FROM public.notification_center_view_rows r WHERE r.token=o.token AND r.position>p_cursor+p_limit) THEN p_cursor+p_limit END,
  'retryAfterMs',CASE WHEN o.preparing THEN 1000 END)
 FROM keyed o;
$$;
DROP FUNCTION IF EXISTS public.get_notification_center_view(bigint,bigint,text,uuid,integer,integer,text);
CREATE OR REPLACE FUNCTION public.get_notification_center_view(p_organization bigint,p_current_occasion bigint DEFAULT NULL,
 p_mode text DEFAULT 'open',p_view uuid DEFAULT NULL,p_cursor integer DEFAULT 0,p_limit integer DEFAULT 30,p_timezone text DEFAULT 'UTC',p_revision text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
#variable_conflict use_variable
DECLARE s public.notification_center_projection_scopes; u public.notification_center_user_state; v public.notification_center_views;
 token uuid:=p_view; payload jsonb; anchor timestamptz:=clock_timestamp(); lim integer:=greatest(1,least(coalesce(p_limit,30),100));
 previous_timeout text:=current_setting('lock_timeout'); total integer;
BEGIN
 BEGIN PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 EXCEPTION WHEN insufficient_privilege THEN RETURN jsonb_build_object('viewSupported',true,'state','denied','items','[]'::jsonb); END;
 IF p_mode IS NULL OR p_cursor IS NULL OR (p_mode IN ('preview','open') AND p_cursor<>0) OR p_mode NOT IN ('preview','open','page','refresh','close','close_all') OR p_cursor<0 OR p_cursor>100
  OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN RAISE invalid_parameter_value USING MESSAGE='notification_invalid_view_request'; END IF;
 IF p_mode IN ('close','close_all') THEN
  DELETE FROM public.notification_center_views WHERE (p_mode='close_all' OR notification_center_views.token=p_view) AND organization=p_organization AND recipient=auth.uid();
  RETURN jsonb_build_object('viewSupported',true,'state','closed','items','[]'::jsonb);
 END IF;
 IF EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_organization AND prepared_paused) THEN RETURN jsonb_build_object('viewSupported',true,'state','preparing','items','[]'::jsonb,'retryAfterMs',1000); END IF;
 PERFORM set_config('lock_timeout','5ms',true);
 BEGIN
  INSERT INTO public.notification_center_user_state(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
  INSERT INTO public.notification_center_projection_scopes(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
  SELECT * INTO s FROM public.notification_center_projection_scopes WHERE organization=p_organization AND recipient=auth.uid() FOR SHARE NOWAIT;
  IF token IS NOT NULL AND p_mode='open' THEN
   SELECT * INTO v FROM public.notification_center_views WHERE notification_center_views.token=token AND organization=p_organization AND recipient=auth.uid()
    AND current_occasion IS NOT DISTINCT FROM p_current_occasion AND timezone=p_timezone;
   SELECT * INTO u FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid();
   IF v.token IS NOT NULL AND NOT v.acknowledged AND (v.snapshot<>u.last_delivery_sequence OR s.pending_delivery>0
     OR v.source_revision<>s.revision OR v.read_revision<>u.view_read_revision OR v.privacy_key<>md5(public.notification_center_prepared_privacy(p_organization)::text)) THEN
    DELETE FROM public.notification_center_views WHERE notification_center_views.token=token;token:=NULL;
   END IF;
  END IF;
  IF token IS NOT NULL THEN
   SELECT * INTO v FROM public.notification_center_views WHERE notification_center_views.token=token AND organization=p_organization AND recipient=auth.uid()
    AND current_occasion IS NOT DISTINCT FROM p_current_occasion AND timezone=p_timezone;
   IF NOT FOUND OR v.expires_at<=anchor THEN payload:=jsonb_build_object('viewSupported',true,'state','expired','items','[]'::jsonb);
   ELSE payload:=public.notification_center_prepared_payload(token,p_cursor,lim,CASE WHEN p_mode='refresh' THEN p_revision END); END IF;
  ELSIF p_mode NOT IN ('preview','open') THEN payload:=jsonb_build_object('viewSupported',true,'state','expired','items','[]'::jsonb);
  ELSE
   SELECT * INTO u FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE NOWAIT;
   anchor:=clock_timestamp();
   -- No lease/catalog is allocated until all required preparation is ready.
   -- A preparing open has no bound to acknowledge and retries as a fresh intent.
   IF s.phase<>'ready' OR NOT s.delivery_initialized OR s.pending_delivery>0 OR s.pending_events>0 OR s.pending_groups>0 OR s.privacy_pending
    OR s.prepared_sequence<>u.last_delivery_sequence OR s.applied_read_revision<>u.view_read_revision OR s.next_expiry<anchor
    OR s.privacy<>public.notification_center_prepared_privacy(p_organization) THEN
    payload:=jsonb_build_object('viewSupported',true,'state','preparing','items','[]'::jsonb,'retryAfterMs',1000);
   ELSE
    DELETE FROM public.notification_center_views WHERE notification_center_views.token IN(SELECT expired.token FROM public.notification_center_views expired
     WHERE expired.organization=p_organization AND expired.recipient=auth.uid() AND expired.expires_at<=anchor LIMIT 100);
    IF (SELECT count(*) FROM public.notification_center_views WHERE organization=p_organization AND recipient=auth.uid())>=4 THEN
     payload:=jsonb_build_object('viewSupported',true,'state','view_limit','items','[]'::jsonb);
    ELSE
     INSERT INTO public.notification_center_views(organization,recipient,current_occasion,timezone,snapshot,anchor,previous_seen,source_revision,read_revision,privacy_key)
     VALUES(p_organization,auth.uid(),p_current_occasion,p_timezone,u.last_delivery_sequence,anchor,greatest(u.seen_through_sequence,u.read_through_sequence),s.revision,u.view_read_revision,md5(s.privacy::text)) RETURNING notification_center_views.token INTO token;
     WITH candidates AS MATERIALIZED(
      SELECT DISTINCT ON(x.id) x.id,a.section,x.latest_at FROM public.notification_center_prepared_allowed_scopes(p_organization,p_current_occasion,auth.uid()) a
      CROSS JOIN LATERAL(SELECT id,latest_at FROM public.notification_center_summary_scopes t WHERE t.organization=p_organization AND t.recipient=auth.uid() AND t.scope=a.scope
       ORDER BY latest_at DESC,id DESC LIMIT 101) x ORDER BY x.id,a.section),
     ranked AS MATERIALIZED(SELECT *,row_number() OVER(ORDER BY section,latest_at DESC,id DESC) position FROM candidates ORDER BY section,latest_at DESC,id DESC LIMIT 101),
     inserted AS(INSERT INTO public.notification_center_view_rows(token,position,id,group_key,after_sequence,through_sequence,kind,occasion,latest_at,latest_event,preview_events,capture_is_read,
      activity_count,known_count,places,multiple_count,is_read,revision,read_revision,privacy_key)
     SELECT token,r.position,r.id,b.group_key,least(b.after_sequence,b.first_sequence-1),b.through_sequence,b.kind,b.occasion,b.latest_at,b.latest_event,b.preview_events,b.is_read,
      b.activity_count,b.known_count,b.places,b.multiple_count,b.is_read,s.revision,u.view_read_revision,md5(s.privacy::text)
      FROM ranked r JOIN public.notification_center_batch_summaries b ON b.organization=p_organization AND b.recipient=auth.uid() AND b.id=r.id WHERE r.position<=100 RETURNING 1)
     -- Catalogue rows and truncation share one authorized candidate discovery.
     SELECT (SELECT count(*) FROM ranked) INTO total FROM (SELECT count(*) FROM inserted) completed;
     UPDATE public.notification_center_views SET truncated=total>100 WHERE notification_center_views.token=token;
     payload:=public.notification_center_prepared_payload(token,p_cursor,lim,CASE WHEN p_mode='refresh' THEN p_revision END);
    END IF;
   END IF;
  END IF;
  IF p_mode='open' AND payload->>'state'='ready' THEN
   SELECT * INTO u FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE NOWAIT;
   UPDATE public.notification_center_user_state SET seen_through_sequence=greatest(seen_through_sequence,(payload->>'snapshot')::bigint) WHERE organization=p_organization AND recipient=auth.uid();
   UPDATE public.notification_center_views SET acknowledged=true WHERE notification_center_views.token=token;
   payload:=payload||jsonb_build_object('acknowledged',true);
  ELSIF payload->>'state'='preparing' THEN
   UPDATE public.notification_center_projection_scopes SET requested_at=CASE WHEN work_requested THEN requested_at ELSE clock_timestamp() END,work_requested=true,next_check_at=CASE WHEN retry_count=0 THEN least(next_check_at,clock_timestamp()) ELSE next_check_at END WHERE organization=p_organization AND recipient=auth.uid();
  END IF;
  IF payload->>'state'='preparing' THEN PERFORM public.notification_center_prepared_wake(); END IF;
  IF payload->>'state'='ready' THEN payload:=payload||jsonb_build_object('unread',public.get_notification_center_prepared_badge(p_organization)->'unread'); END IF;
 EXCEPTION WHEN lock_not_available THEN payload:=jsonb_build_object('viewSupported',true,'state','preparing','items','[]'::jsonb,'retryAfterMs',1000);
 END;
 PERFORM set_config('lock_timeout',previous_timeout,true);
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_view(bigint,bigint,text,uuid,integer,integer,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_notification_center_view(bigint,bigint,text,uuid,integer,integer,text,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_notification_center_prepared_badge(p_organization bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE payload jsonb;
BEGIN
 BEGIN PERFORM public.notification_center_check_context(p_organization);
 EXCEPTION WHEN insufficient_privilege THEN RETURN jsonb_build_object('viewSupported',true,'state','denied','enabled',false); END;
 IF EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_organization AND prepared_paused) THEN RETURN jsonb_build_object('viewSupported',true,'enabled',true,'state','preparing','unread',NULL); END IF;
 INSERT INTO public.notification_center_user_state(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
 INSERT INTO public.notification_center_projection_scopes(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
 -- A single statement provides the current privacy snapshot and all candidates.
 WITH current AS MATERIALIZED(SELECT s.*,u.last_delivery_sequence,greatest(u.seen_through_sequence,u.read_through_sequence) seen,u.view_read_revision,
   public.notification_center_prepared_privacy(p_organization) privacy_now FROM public.notification_center_projection_scopes s
   JOIN public.notification_center_user_state u USING(organization,recipient) WHERE s.organization=p_organization AND s.recipient=auth.uid()),
 status AS(SELECT *,phase<>'ready' OR NOT delivery_initialized OR pending_delivery>0 OR pending_events>0 OR pending_groups>0 OR privacy_pending
   OR prepared_sequence<>last_delivery_sequence OR applied_read_revision<>view_read_revision OR next_expiry<clock_timestamp() OR privacy<>privacy_now preparing FROM current)
 SELECT jsonb_build_object('viewSupported',true,'timelineSupported',true,'enabled',true,'state',CASE WHEN preparing THEN 'preparing' ELSE 'ready' END,
  'lastSequence',last_delivery_sequence,'unread',CASE WHEN preparing THEN NULL WHEN last_delivery_sequence<=seen THEN false ELSE EXISTS(
   SELECT 1 FROM public.notification_center_prepared_allowed_scopes(p_organization,NULL,auth.uid()) a
   CROSS JOIN LATERAL(SELECT t.id FROM public.notification_center_summary_scopes t WHERE t.organization=p_organization AND t.recipient=auth.uid()
    AND t.scope=a.scope AND NOT t.is_read AND t.sequence>status.seen ORDER BY t.sequence DESC LIMIT 1) t
   WHERE CASE WHEN a.scope ~ '^(orders|app|email-admin|bank-occasion):[0-9]+$' THEN NOT EXISTS(SELECT 1 FROM public.notification_center_preferences p
    WHERE p.organization=p_organization AND p.recipient=auth.uid() AND p.occasion=split_part(a.scope,':',2)::bigint AND p.muted)
    ELSE true END) END) INTO payload FROM status;
 IF payload->>'state'='preparing' THEN PERFORM public.notification_center_prepared_wake(); UPDATE public.notification_center_projection_scopes SET requested_at=CASE WHEN work_requested THEN requested_at ELSE clock_timestamp() END,work_requested=true,next_check_at=CASE WHEN retry_count=0 THEN least(next_check_at,clock_timestamp()) ELSE next_check_at END WHERE organization=p_organization AND recipient=auth.uid(); END IF;
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_prepared_badge(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_notification_center_prepared_badge(bigint) TO authenticated;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_scope(p_org bigint,p_scope jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE v public.notification_center_views;r public.notification_center_view_rows; source_revision bigint;read_revision bigint;privacy_key text;
BEGIN
 PERFORM public.notification_center_check_context(p_org);
 IF EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_org AND prepared_paused) THEN RAISE object_not_in_prerequisite_state USING MESSAGE='notification_view_preparing'; END IF;
 SELECT * INTO v FROM public.notification_center_views WHERE token=(p_scope->>'viewToken')::uuid AND organization=p_org AND recipient=auth.uid();
 IF NOT FOUND OR v.expires_at<=clock_timestamp() THEN RAISE object_not_in_prerequisite_state USING MESSAGE='notification_view_expired'; END IF;
 SELECT s.revision,u.view_read_revision,md5(public.notification_center_prepared_privacy(p_org)::text) INTO source_revision,read_revision,privacy_key
  FROM public.notification_center_projection_scopes s JOIN public.notification_center_user_state u USING(organization,recipient) WHERE s.organization=p_org AND s.recipient=auth.uid();
 SELECT * INTO r FROM public.notification_center_view_rows WHERE token=v.token AND id=p_scope->>'id';
 IF NOT FOUND OR r.state='removed' OR r.revision<>source_revision OR r.privacy_key<>privacy_key THEN
  RAISE object_not_in_prerequisite_state USING MESSAGE='notification_view_preparing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.notification_center_events e WHERE e.id=r.latest_event AND public.notification_center_allowed(e,auth.uid())) THEN
  RAISE insufficient_privilege USING MESSAGE='notification_read_denied'; END IF;
 RETURN jsonb_build_object('id',r.id,'organization',p_org,'snapshot',v.snapshot,'snapshotAt',v.anchor,'timezone',v.timezone,
  'capturedAt',v.anchor,'captureIsRead',r.capture_is_read,'afterSequence',r.after_sequence,'throughSequence',r.through_sequence,'markRead',coalesce((p_scope->>'markRead')::boolean,false),'groupKey',r.group_key,'isRead',r.is_read,'occasion',r.occasion);
END $$;
CREATE OR REPLACE FUNCTION public.mark_notification_center_view_item_read(p_organization bigint,p_scope jsonb)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE scope jsonb;
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 PERFORM 1 FROM public.notification_center_projection_scopes WHERE organization=p_organization AND recipient=auth.uid() FOR SHARE NOWAIT;
 PERFORM 1 FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE NOWAIT;
 scope:=public.notification_center_prepared_scope(p_organization,p_scope);
 IF scope->>'isRead'='true' THEN RETURN true; END IF;
 RETURN public.notification_center_prepared_record_read(p_organization,scope->>'groupKey',(scope->>'afterSequence')::bigint,(scope->>'throughSequence')::bigint,true);
EXCEPTION WHEN lock_not_available THEN RETURN false;
END $$;
REVOKE ALL ON FUNCTION public.mark_notification_center_view_item_read(bigint,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.mark_notification_center_view_item_read(bigint,jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_notification_center_settings(p_organization bigint,p_after bigint DEFAULT 0,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;lim integer:=greatest(1,least(coalesce(p_limit,50),100));
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 WITH rows AS(SELECT oc.id,oc.title,coalesce(p.muted,false) muted,row_number() OVER(ORDER BY oc.id) position FROM public.occasions oc
  LEFT JOIN public.notification_center_preferences p ON p.organization=p_organization AND p.recipient=auth.uid() AND p.occasion=oc.id
  WHERE oc.organization=p_organization AND oc.id>p_after AND NOT public.is_demo_occasion(oc.id)
   AND (public.notification_center_app_admin_internal(p_organization,oc.id,auth.uid()) OR EXISTS(SELECT 1 FROM public.occasion_users m WHERE m.occasion=oc.id AND m."user"=auth.uid() AND m.is_editor_order_view)) ORDER BY oc.id LIMIT lim+1)
 SELECT jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'muted',muted) ORDER BY id) FILTER(WHERE position<=lim),'[]'),
  'nextCursor',CASE WHEN count(*)>lim THEN max(id) FILTER(WHERE position<=lim) END) INTO result FROM rows;
 RETURN result||jsonb_build_object('email',public.notification_center_email_settings_internal(p_organization));
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_settings(bigint,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_notification_center_settings(bigint,bigint,integer) TO authenticated;
-- Every helper is private, including default EXECUTE granted by PostgreSQL.
DO $$ DECLARE f regprocedure; BEGIN
 FOR f IN SELECT oid::regprocedure FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'notification_center_prepared_%' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f);
 END LOOP;
END $$;


-- SOURCE: notification_center/email_delivery_schema.sql
-- Recipient locks precede cursor, dispatch and the existing queue locks.
CREATE TABLE public.notification_center_email_profiles (
 recipient uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 stopped boolean NOT NULL DEFAULT true, locale text NOT NULL DEFAULT 'cs' CHECK(locale IN ('cs','en','de','pl','sk','uk')),
 revision bigint NOT NULL DEFAULT 0, collected_at timestamptz NOT NULL DEFAULT '-infinity'
);
CREATE TABLE public.notification_center_email_subscriptions (
 recipient uuid NOT NULL REFERENCES public.notification_center_email_profiles(recipient) ON DELETE CASCADE,
 organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 occasion bigint, kinds jsonb NOT NULL DEFAULT '{}', enabled_from timestamptz NOT NULL DEFAULT clock_timestamp(),
 revision bigint NOT NULL DEFAULT 1,
 UNIQUE NULLS NOT DISTINCT(recipient,organization,occasion),
 CHECK(jsonb_typeof(kinds)='object')
);
-- Stored scope must match the real occasion, including direct privileged inserts.
ALTER TABLE public.occasions ADD CONSTRAINT notification_email_occasion_scope UNIQUE(id,organization);
ALTER TABLE public.notification_center_email_subscriptions ADD FOREIGN KEY(occasion,organization)
 REFERENCES public.occasions(id,organization) ON DELETE CASCADE;
ALTER TABLE public.notification_center_organizations ADD COLUMN email_collection_started_at timestamptz;
ALTER TABLE public.notification_center_user_state ADD COLUMN email_scanned_sequence bigint NOT NULL DEFAULT 0,
 ADD CONSTRAINT notification_email_cursor CHECK(email_scanned_sequence>=0 AND email_scanned_sequence<=last_delivery_sequence);
CREATE INDEX notification_email_unscanned ON public.notification_center_user_state(recipient,organization)
 WHERE email_scanned_sequence<last_delivery_sequence;
CREATE TABLE public.notification_center_email_dispatches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 recipient uuid NOT NULL,
 opened_at timestamptz NOT NULL DEFAULT clock_timestamp(), due_at timestamptz NOT NULL,
 next_attempt_at timestamptz NOT NULL DEFAULT '-infinity',
 state text NOT NULL DEFAULT 'collecting' CHECK(state IN ('collecting','queued','omitted')),
 message_id uuid UNIQUE REFERENCES public.email_messages(message_id),
 UNIQUE(id,recipient), CHECK(due_at=opened_at+public.notification_center_email_window_internal()),
 CHECK((state='queued')=(message_id IS NOT NULL))
);
CREATE UNIQUE INDEX notification_email_collecting ON public.notification_center_email_dispatches(recipient) WHERE state='collecting';
CREATE INDEX notification_email_due ON public.notification_center_email_dispatches(due_at,recipient) WHERE state='collecting';
CREATE TABLE public.notification_center_email_items (
 recipient uuid NOT NULL REFERENCES public.notification_center_email_profiles(recipient) ON DELETE CASCADE,
 delivery_key text NOT NULL, admitted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 dispatch_id uuid, disposition text CHECK(disposition IN ('omitted','baseline')),
 PRIMARY KEY(recipient,delivery_key),
 FOREIGN KEY(dispatch_id,recipient) REFERENCES public.notification_center_email_dispatches(id,recipient) ON DELETE CASCADE,
 CHECK((dispatch_id IS NOT NULL)<>(disposition IS NOT NULL))
);
ALTER TABLE public.notification_center_events ADD CONSTRAINT notification_email_event_scope UNIQUE(id,organization);
ALTER TABLE public.notification_center_deliveries ADD CONSTRAINT notification_email_delivery_source UNIQUE(event_id,recipient,organization,sequence);
CREATE TABLE public.notification_center_email_item_sources (
 event_id uuid NOT NULL, recipient uuid NOT NULL, organization bigint NOT NULL,
 delivery_key text NOT NULL, first_sequence bigint NOT NULL, enabled_from timestamptz NOT NULL,
 PRIMARY KEY(event_id,recipient),
 FOREIGN KEY(recipient,delivery_key) REFERENCES public.notification_center_email_items(recipient,delivery_key) ON DELETE CASCADE,
 FOREIGN KEY(event_id,recipient) REFERENCES public.notification_center_recipients(event_id,recipient) ON DELETE CASCADE,
 FOREIGN KEY(event_id,organization) REFERENCES public.notification_center_events(id,organization) ON DELETE CASCADE,
 FOREIGN KEY(event_id,recipient,organization,first_sequence)
 REFERENCES public.notification_center_deliveries(event_id,recipient,organization,sequence) ON DELETE CASCADE
);
CREATE INDEX notification_email_item_age ON public.notification_center_email_items(recipient,admitted_at);
CREATE INDEX notification_email_sources_item ON public.notification_center_email_item_sources(recipient,delivery_key);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['profiles','subscriptions','dispatches','items','item_sources'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY','notification_center_email_'||t);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated,service_role','notification_center_email_'||t);
 END LOOP;
END $$;

DROP INDEX public.notification_center_order_projection;
CREATE INDEX notification_center_order_projection ON public.notification_center_events(occasion,(data->>'orderId'),id)
 WHERE kind IN ('order_created','waitlist_registered','order_cancelled','order_payment_received','payment_problem','offer_accepted','offer_declined','offer_expired');

INSERT INTO public.notification_center_maintenance(name) VALUES('email-collection') ON CONFLICT DO NOTHING;


-- SOURCE: notification_center/email_queue_schema.sql
-- The dispatch retains an audit UUID after account deletion; it owns no address.
-- Account deletion removes profiles, memberships and subscriptions, invalidating
-- unsent intents without a queue/identity FK cycle.
ALTER TABLE public.email_messages ALTER COLUMN organization DROP NOT NULL;
ALTER TABLE public.email_messages ADD COLUMN notification_dispatch_id uuid;
ALTER TABLE public.email_messages ADD CONSTRAINT email_recipient_scope CHECK(
 (message_kind='admin_notification_digest' AND organization IS NULL AND recipient_user IS NOT NULL
  AND occasion IS NULL AND unit IS NULL AND order_id IS NULL AND notification_dispatch_id IS NOT NULL AND tracking_policy='disabled')
 OR (message_kind<>'admin_notification_digest' AND organization IS NOT NULL AND notification_dispatch_id IS NULL));
ALTER TABLE public.email_messages ADD CONSTRAINT email_dispatch_recipient FOREIGN KEY(notification_dispatch_id,recipient_user)
 REFERENCES public.notification_center_email_dispatches(id,recipient);
CREATE UNIQUE INDEX email_notification_dedupe ON public.email_messages(recipient_user,message_kind,dedupe_key) WHERE message_kind='admin_notification_digest';
CREATE UNIQUE INDEX email_notification_active ON public.email_messages(recipient_user) WHERE message_kind='admin_notification_digest'
 AND workflow_state IN ('blocked','pending','preparing','sending','retry_wait','unknown');
ALTER TABLE public.email_messages DROP CONSTRAINT email_messages_admission_class_check;
ALTER TABLE public.email_messages ADD CONSTRAINT email_messages_admission_class_check CHECK(admission_class IN ('ordinary','auth','commitment','notification'));
-- A dispatch can link only its own recipient's queue intent, in both directions.
CREATE UNIQUE INDEX email_notification_dispatch_identity ON public.email_messages(message_id,recipient_user,notification_dispatch_id);
ALTER TABLE public.notification_center_email_dispatches DROP CONSTRAINT notification_center_email_dispatches_message_id_fkey;
ALTER TABLE public.notification_center_email_dispatches ADD CONSTRAINT notification_email_message_owner
 FOREIGN KEY(message_id,recipient,id) REFERENCES public.email_messages(message_id,recipient_user,notification_dispatch_id);


-- SOURCE: notification_center/email_preferences.sql
CREATE OR REPLACE FUNCTION public.notification_center_email_category_internal(p_kind text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_kind IN ('email_problem','bank_problem','payment_problem','provider_problem') THEN 'problems'
 WHEN p_kind IN ('occasion_joined','waitlist_registered') THEN 'registrations'
 WHEN p_kind='order_payment_received' THEN 'payments'
 WHEN p_kind IN ('order_created','order_cancelled','offer_accepted','offer_declined','offer_expired') THEN 'orders' END;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_email_enabled_internal(e public.notification_center_events,p_user uuid,p_scopes text[])
RETURNS timestamptz LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT min(policy.enabled) FROM (
 SELECT a.email_collection_started_at FROM public.notification_center_organizations a
 WHERE a.organization=e.organization AND a.email_collection_started_at IS NOT NULL
  AND public.notification_center_email_required_kind_internal(e.kind)
  AND CASE WHEN e.kind='bank_problem' THEN ('bank:'||(e.data->>'bankConnectionId'))=ANY(p_scopes)
   WHEN e.kind='provider_problem' THEN ('provider-unit:'||(e.data->>'unitId'))=ANY(p_scopes) ELSE false END
  AND e.occurred_at>=a.email_collection_started_at
 UNION ALL
 SELECT optional.enabled FROM (WITH source_scopes AS MATERIALIZED(
  SELECT e.occasion WHERE e.occasion IS NOT NULL
  UNION ALL SELECT oc FROM unnest(e.affected_occasions) oc WHERE e.occasion IS NULL
   AND (('bank:'||(e.data->>'bankConnectionId'))=ANY(p_scopes) OR ('bank-occasion:'||oc)=ANY(p_scopes))
  UNION ALL SELECT NULL::bigint WHERE e.occasion IS NULL AND cardinality(e.affected_occasions)=0),
 subscriptions AS MATERIALIZED(
  SELECT s.*,scope.occasion source_occasion FROM source_scopes scope
  CROSS JOIN LATERAL(SELECT s.* FROM public.notification_center_email_subscriptions s
   WHERE s.recipient=p_user AND s.organization=e.organization AND (s.occasion IS NULL OR s.occasion=scope.occasion)
   ORDER BY s.occasion NULLS LAST LIMIT 1) s
  JOIN public.notification_center_email_profiles p ON p.recipient=s.recipient AND NOT p.stopped)
 SELECT min(greatest(s.enabled_from,(s.kinds->e.kind->>'enabledFrom')::timestamptz,a.email_collection_started_at))
 FROM subscriptions s JOIN public.notification_center_organizations a ON a.organization=s.organization
 WHERE a.email_collection_started_at IS NOT NULL
  AND public.notification_center_email_category_internal(e.kind) IS NOT NULL
  AND s.kinds->e.kind->>'enabled'='true'
  AND e.occurred_at>=greatest(s.enabled_from,(s.kinds->e.kind->>'enabledFrom')::timestamptz,a.email_collection_started_at)
  AND public.notification_center_unmuted(jsonb_populate_record(e,jsonb_build_object('occasion',s.source_occasion)),p_user)
  AND NOT public.notification_center_email_required_kind_internal(e.kind)) optional(enabled)) policy(enabled)
$$;
-- All runtime profile creation uses this owner. Try-lock keeps enrollment from
-- blocking a second collector behind an uncommitted first-profile insertion.
CREATE OR REPLACE FUNCTION public.notification_center_email_ensure_profile_internal(p_recipient uuid,p_try boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.notification_center_email_profiles WHERE recipient=p_recipient) THEN RETURN true; END IF;
 IF p_try THEN
  IF NOT pg_try_advisory_xact_lock(hashtextextended('notification-email-profile:'||p_recipient,0)) THEN RETURN false; END IF;
 ELSE PERFORM pg_advisory_xact_lock(hashtextextended('notification-email-profile:'||p_recipient,0));
 END IF;
 INSERT INTO public.notification_center_email_profiles(recipient,locale)
 SELECT ui.id,CASE WHEN ui.data->>'locale' IN ('cs','en','de','pl','sk','uk') THEN ui.data->>'locale' ELSE 'cs' END
 FROM public.user_info ui WHERE ui.id=p_recipient ON CONFLICT DO NOTHING;
 RETURN EXISTS(SELECT 1 FROM public.notification_center_email_profiles WHERE recipient=p_recipient);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_email_ensure_profile_internal(uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.save_notification_center_email_settings(
 p_organization bigint,p_occasion bigint,p_revision bigint,p_stopped boolean,p_locale text,p_kinds jsonb)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE profile public.notification_center_email_profiles; previous jsonb; kinds jsonb; item record; at timestamptz:=clock_timestamp();
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 IF p_occasion IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.notification_center_prepared_allowed_scopes(p_organization,NULL,auth.uid()) a
  WHERE a.scope IN ('orders:'||p_occasion,'app:'||p_occasion,'bank-occasion:'||p_occasion)) THEN RAISE EXCEPTION 'notification_email_scope_denied'; END IF;
 IF jsonb_typeof(p_kinds) IS DISTINCT FROM 'object' OR p_stopped IS NULL OR p_locale NOT IN ('cs','en','de','pl','sk','uk') THEN RAISE EXCEPTION 'notification_email_settings_invalid'; END IF;
 PERFORM public.notification_center_email_ensure_profile_internal(auth.uid());
 SELECT * INTO STRICT profile FROM public.notification_center_email_profiles WHERE recipient=auth.uid() FOR UPDATE;
 IF p_revision IS DISTINCT FROM profile.revision THEN RAISE serialization_failure USING MESSAGE='notification_email_revision_conflict'; END IF;
 SELECT s.kinds INTO previous FROM public.notification_center_email_subscriptions s
 WHERE s.recipient=auth.uid() AND s.organization=p_organization AND s.occasion IS NOT DISTINCT FROM p_occasion;
 kinds:='{}';
 FOR item IN SELECT key,value FROM jsonb_each(p_kinds) LOOP
  IF public.notification_center_email_required_kind_internal(item.key) THEN RAISE EXCEPTION 'notification_email_kind_required'; END IF;
  IF public.notification_center_email_category_internal(item.key) IS NULL OR jsonb_typeof(item.value)<>'boolean' THEN RAISE EXCEPTION 'notification_email_kind_invalid'; END IF;
  kinds:=kinds||jsonb_build_object(item.key,jsonb_build_object('enabled',item.value,
   'enabledFrom',CASE WHEN previous->item.key->>'enabled'='true' AND NOT profile.stopped THEN previous->item.key->>'enabledFrom' ELSE at::text END));
 END LOOP;
 INSERT INTO public.notification_center_email_subscriptions(recipient,organization,occasion,kinds,enabled_from)
 VALUES(auth.uid(),p_organization,p_occasion,kinds,at)
 ON CONFLICT(recipient,organization,occasion) DO UPDATE SET kinds=excluded.kinds,revision=notification_center_email_subscriptions.revision+1;
 IF profile.stopped AND NOT p_stopped THEN
  UPDATE public.notification_center_email_subscriptions SET enabled_from=at WHERE recipient=auth.uid();
 END IF;
 UPDATE public.notification_center_email_profiles SET stopped=p_stopped,locale=p_locale,revision=revision+1 WHERE recipient=auth.uid() RETURNING revision INTO p_revision;
 RETURN p_revision;
END $$;
REVOKE ALL ON FUNCTION public.save_notification_center_email_settings(bigint,bigint,bigint,boolean,text,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.save_notification_center_email_settings(bigint,bigint,bigint,boolean,text,jsonb) TO authenticated;

-- Separate activation of selected tenant scope, never implicit in a delivery.
CREATE OR REPLACE FUNCTION public.activate_notification_center_emails(p_organization bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 PERFORM 1 FROM public.notification_center_organizations WHERE organization=p_organization FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'notification_email_organization_inactive'; END IF;
 IF EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_organization AND email_collection_started_at IS NOT NULL) THEN RETURN; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.email_capacity c CROSS JOIN public.abuse_policy_rules r
  WHERE r.rule_key='email.send.notification.global.day' AND c.quota_at>now()-interval '15 minutes'
   AND r.base_limit<=floor(least(c.daily_quota,CASE WHEN c.shared_account THEN c.allocated_daily ELSE c.daily_quota END)*0.1)) THEN
  RAISE EXCEPTION 'notification_capacity_policy_unverified';
 END IF;
 UPDATE public.notification_center_user_state SET email_scanned_sequence=last_delivery_sequence WHERE organization=p_organization;
 UPDATE public.notification_center_organizations SET email_collection_started_at=clock_timestamp() WHERE organization=p_organization;
END $$;
REVOKE ALL ON FUNCTION public.activate_notification_center_emails(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.activate_notification_center_emails(bigint) TO service_role;
REVOKE ALL ON FUNCTION public.notification_center_email_category_internal(text),public.notification_center_email_enabled_internal(public.notification_center_events,uuid,text[]) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_email_catalog_internal(p_scopes text[],p_occasion bigint)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 WITH kinds AS(SELECT kind,public.notification_center_email_category_internal(kind) category FROM unnest(ARRAY['occasion_joined','waitlist_registered','order_created','order_cancelled','offer_accepted','offer_declined','offer_expired','order_payment_received','payment_problem','bank_problem','email_problem','provider_problem']) kind)
 SELECT coalesce(jsonb_object_agg(kind,category),'{}') FROM kinds k WHERE EXISTS(SELECT 1 FROM unnest(p_scopes) x
  WHERE CASE WHEN k.kind='occasion_joined' THEN CASE WHEN p_occasion IS NULL THEN x LIKE 'app:%' ELSE x='app:'||p_occasion END
   WHEN k.kind='provider_problem' THEN x LIKE 'provider-unit:%'
   WHEN k.kind='bank_problem' THEN x LIKE 'bank:%'
   WHEN k.kind='email_problem' THEN x='email-admin:shared' OR CASE WHEN p_occasion IS NULL THEN x LIKE 'email-admin:%' ELSE x='email-admin:'||p_occasion END
   ELSE CASE WHEN p_occasion IS NULL THEN x LIKE 'orders:%' ELSE x='orders:'||p_occasion END END);
$$;
REVOKE ALL ON FUNCTION public.notification_center_email_catalog_internal(text[],bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Self-only status: no message payload, address or provider diagnostics.
CREATE OR REPLACE FUNCTION public.notification_center_email_settings_internal(p_organization bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH scopes AS MATERIALIZED(SELECT array_agg(a.scope) allowed FROM public.notification_center_prepared_allowed_scopes(p_organization,NULL,auth.uid()) a),
 catalog AS MATERIALIZED(SELECT public.notification_center_email_catalog_internal((SELECT allowed FROM scopes),NULL) kinds)
 SELECT jsonb_build_object('windowSeconds',extract(epoch FROM public.notification_center_email_window_internal())::integer,'revision',coalesce(p.revision,0),'stopped',coalesce(p.stopped,true),'locale',coalesce(p.locale,'cs'),
 'catalog',(SELECT kinds FROM catalog),
 'requiredKinds',coalesce((SELECT jsonb_agg(key ORDER BY key) FROM catalog,jsonb_object_keys(kinds) key WHERE public.notification_center_email_required_kind_internal(key)),'[]'::jsonb),
 'scopeCatalogs',(SELECT jsonb_object_agg(oc.id,public.notification_center_email_catalog_internal((SELECT allowed FROM scopes),oc.id)) FROM public.occasions oc WHERE oc.organization=p_organization),
 'subscriptions',coalesce((SELECT jsonb_agg(jsonb_build_object('occasion',s.occasion,'kinds',s.kinds)) FROM public.notification_center_email_subscriptions s WHERE s.recipient=auth.uid() AND s.organization=p_organization),'[]'),
 'state',CASE WHEN EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d WHERE d.recipient=auth.uid() AND d.state='collecting') AND public.get_user_delivery_email(auth.uid()) IS NULL THEN 'no_address'
  ELSE (SELECT m.workflow_state FROM public.email_messages m WHERE m.recipient_user=auth.uid() AND m.message_kind='admin_notification_digest' ORDER BY m.id DESC LIMIT 1) END)
 FROM (SELECT 1) seed LEFT JOIN public.notification_center_email_profiles p ON p.recipient=auth.uid();
$$;
REVOKE ALL ON FUNCTION public.notification_center_email_settings_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/email_context.sql
-- All context is read in one SQL snapshot. No UI scope/backfill/read receipt.
CREATE OR REPLACE FUNCTION public.notification_center_email_context_internal(p_dispatch uuid,p_recipient uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH envelope AS MATERIALIZED(
  SELECT d.id,p.recipient,p.locale,p.revision,public.get_user_delivery_email(p.recipient) address
  FROM public.notification_center_email_dispatches d
  JOIN public.notification_center_email_profiles p ON p.recipient=d.recipient
  WHERE d.id=p_dispatch AND d.recipient=p_recipient AND d.state IN ('collecting','queued')),
 sources AS MATERIALIZED(
  SELECT s.*,e FROM public.notification_center_email_items i
  JOIN public.notification_center_email_item_sources s USING(recipient,delivery_key)
  JOIN public.notification_center_events e ON e.id=s.event_id AND e.organization=s.organization
  WHERE i.dispatch_id=p_dispatch AND i.recipient=p_recipient),
 scopes AS MATERIALIZED(
  SELECT org.organization,ARRAY(SELECT a.scope FROM public.notification_center_prepared_allowed_scopes(org.organization,NULL,p_recipient) a) allowed
  FROM (SELECT DISTINCT organization FROM sources) org),
 eligible AS MATERIALIZED(
  SELECT s.* FROM sources s JOIN scopes sc USING(organization)
  WHERE public.notification_center_prepared_event_access(s.e,s.organization,sc.allowed)
   AND public.notification_center_in_center_internal(s.e,statement_timestamp())
   AND public.notification_center_email_enabled_internal(s.e,p_recipient,sc.allowed) IS NOT NULL),
 facts AS MATERIALIZED(
  SELECT x.e,public.notification_center_event_facts_internal(x.e) facts
  FROM (SELECT DISTINCT ON ((s.e).id) s.e FROM eligible s ORDER BY (s.e).id) x),
 metadata AS MATERIALIZED(
  SELECT (x.e).organization organization,(x.e).occasion occasion,public.notification_center_event_display_internal(x.e) display
  FROM (SELECT DISTINCT ON ((s.e).organization,(s.e).occasion) s.e FROM eligible s ORDER BY (s.e).organization,(s.e).occasion) x),
 contributions AS MATERIALIZED(
  SELECT s.delivery_key,s.event_id,s.organization,
   m.display||public.notification_center_bank_display_internal(s.e,p_recipient)||
    CASE WHEN (s.e).kind='provider_problem' THEN jsonb_build_object('unitId',(s.e).data->'unitId','provider',(s.e).data->>'title') ELSE '{}'::jsonb END||jsonb_build_object('orderId',(s.e).data->'orderId','key',s.delivery_key,'kind',(s.e).kind,
    'occurredAt',(s.e).occurred_at,'facts',f.facts) value
  FROM eligible s JOIN facts f ON (f.e).id=s.event_id
  JOIN metadata m ON m.organization=s.organization AND m.occasion IS NOT DISTINCT FROM (s.e).occasion),
 content AS MATERIALIZED(
  SELECT delivery_key,min(organization) organization,min(event_id::text) event_id,
   (jsonb_agg(value ORDER BY organization,event_id)->0)||jsonb_build_object('sources',jsonb_agg(value ORDER BY organization,event_id)) value
  FROM contributions GROUP BY delivery_key),
 snapshot AS(
  SELECT en.locale,en.address,en.revision,coalesce(jsonb_agg(c.value ORDER BY c.organization,c.event_id) FILTER(WHERE c.event_id IS NOT NULL),'[]') items
  FROM envelope en LEFT JOIN content c ON true GROUP BY en.locale,en.address,en.revision)
 SELECT jsonb_build_object('locale',locale,'address',address,'items',items,
  'fingerprint',encode(extensions.digest(to_jsonb(snapshot)::text,'sha256'),'hex')) FROM snapshot;
$$;
CREATE OR REPLACE FUNCTION public.get_notification_center_email_context(p_dispatch uuid,p_recipient uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 RETURN public.notification_center_email_context_internal(p_dispatch,p_recipient);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_email_context_internal(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_notification_center_email_context(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_notification_center_email_context(uuid,uuid) TO service_role;


-- SOURCE: notification_center/email_delivery.sql
CREATE OR REPLACE FUNCTION public.collect_notification_center_emails(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE profile record; scope record; entry record; scopes text[]; key text; dispatch uuid; at timestamptz;
 bound bigint; scanned bigint; n integer:=0; rows integer; enabled timestamptz; expired integer:=0; total_scanned integer:=0; required_recipient uuid;
BEGIN
 PERFORM public.notification_center_require_service();
 -- Captured required deliveries enroll a serialization profile, never optional
 -- subscriptions. Recovered/revoked events are then consumed and skipped by the
 -- ordinary live checks, so a missing profile cannot leave endless wake work.
 FOR required_recipient IN
  SELECT DISTINCT u.recipient FROM public.notification_center_user_state u
  JOIN public.notification_center_organizations a USING(organization)
  JOIN public.user_info ui ON ui.id=u.recipient
  JOIN public.notification_center_deliveries d ON d.organization=u.organization AND d.recipient=u.recipient AND d.sequence>u.email_scanned_sequence
  JOIN public.notification_center_events e ON e.id=d.event_id
  WHERE u.email_scanned_sequence<u.last_delivery_sequence AND a.email_collection_started_at IS NOT NULL
   AND e.occurred_at>=a.email_collection_started_at AND public.notification_center_email_required_kind_internal(e.kind)
   AND NOT EXISTS(SELECT 1 FROM public.notification_center_email_profiles p WHERE p.recipient=u.recipient)
  ORDER BY u.recipient LIMIT greatest(1,least(p_limit,100))
 LOOP
  PERFORM public.notification_center_email_ensure_profile_internal(required_recipient,true);
 END LOOP;

 FOR profile IN SELECT p.* FROM public.notification_center_email_profiles p
  WHERE EXISTS(SELECT 1 FROM public.notification_center_user_state u
   JOIN public.notification_center_organizations a USING(organization)
   WHERE u.recipient=p.recipient AND u.email_scanned_sequence<u.last_delivery_sequence AND a.email_collection_started_at IS NOT NULL)
   OR (p.collected_at<clock_timestamp()-interval '1 day' AND EXISTS(SELECT 1 FROM public.notification_center_email_items i WHERE i.recipient=p.recipient AND i.admitted_at<clock_timestamp()-interval '90 days'))
  ORDER BY p.collected_at,p.recipient LIMIT greatest(1,least(p_limit,100)) FOR UPDATE OF p SKIP LOCKED LOOP
  FOR scope IN SELECT u.* FROM public.notification_center_user_state u
   JOIN public.notification_center_organizations a USING(organization)
   WHERE u.recipient=profile.recipient AND u.email_scanned_sequence<u.last_delivery_sequence AND a.email_collection_started_at IS NOT NULL
   ORDER BY u.organization LIMIT 20 FOR UPDATE OF u SKIP LOCKED LOOP
   bound:=scope.last_delivery_sequence; scanned:=scope.email_scanned_sequence; rows:=0;
   SELECT array_agg(a.scope) INTO scopes FROM public.notification_center_prepared_allowed_scopes(scope.organization,NULL,profile.recipient) a;
   FOR entry IN SELECT d.sequence,e FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
    WHERE d.organization=scope.organization AND d.recipient=profile.recipient AND d.sequence>scope.email_scanned_sequence AND d.sequence<=bound
    ORDER BY d.sequence LIMIT 500 LOOP
    scanned:=entry.sequence; rows:=rows+1; total_scanned:=total_scanned+1;
    enabled:=public.notification_center_email_enabled_internal(entry.e,profile.recipient,coalesce(scopes,'{}'));
    IF enabled IS NULL OR NOT public.notification_center_prepared_event_access(entry.e,scope.organization,coalesce(scopes,'{}'))
     OR NOT public.notification_center_in_center_internal(entry.e,statement_timestamp()) THEN CONTINUE; END IF;
    IF (entry.e).kind NOT IN ('bank_problem','email_problem','payment_problem','provider_problem') AND (entry.e).occurred_at<statement_timestamp()-interval '24 hours' THEN
     expired:=expired+1; CONTINUE;
    END IF;
    key:=CASE WHEN (entry.e).kind='bank_problem' THEN
     'bank:'||((entry.e).data->>'bankConnectionId')||':incident:'||((entry.e).data->>'incidentId')
     WHEN (entry.e).kind='provider_problem' THEN 'provider:'||((entry.e).data->>'provider')||':'||((entry.e).data->>'connectionId')||':incident:'||((entry.e).data->>'incidentId') ELSE 'event:'||(entry.e).id END;
    -- Unmapped historical bank episodes cannot start a new external campaign.
    IF key IS NULL THEN CONTINUE; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.notification_center_email_items i WHERE i.recipient=profile.recipient AND i.delivery_key=key) THEN
     SELECT id INTO dispatch FROM public.notification_center_email_dispatches WHERE recipient=profile.recipient AND state='collecting' FOR UPDATE;
     IF dispatch IS NULL THEN
      at:=clock_timestamp();
      INSERT INTO public.notification_center_email_dispatches(recipient,opened_at,due_at) VALUES(profile.recipient,at,at+public.notification_center_email_window_internal()) RETURNING id INTO dispatch;
     END IF;
     INSERT INTO public.notification_center_email_items(recipient,delivery_key,dispatch_id) VALUES(profile.recipient,key,dispatch) ON CONFLICT DO NOTHING;
    END IF;
    INSERT INTO public.notification_center_email_item_sources(event_id,recipient,organization,delivery_key,first_sequence,enabled_from)
    VALUES((entry.e).id,profile.recipient,scope.organization,key,entry.sequence,enabled) ON CONFLICT DO NOTHING;
   END LOOP;
   IF rows<500 THEN scanned:=bound; END IF;
   UPDATE public.notification_center_user_state SET email_scanned_sequence=scanned WHERE organization=scope.organization AND recipient=profile.recipient;
  END LOOP;
  DELETE FROM public.notification_center_email_items i WHERE i.recipient=profile.recipient
   AND i.admitted_at<clock_timestamp()-interval '90 days'
   AND NOT EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d JOIN public.email_messages m ON m.message_id=d.message_id
    WHERE d.id=i.dispatch_id AND m.workflow_state IN ('blocked','pending','preparing','sending','retry_wait','unknown'))
   AND NOT EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d WHERE d.id=i.dispatch_id AND d.state='collecting')
   AND NOT EXISTS(SELECT 1 FROM public.notification_center_email_item_sources s JOIN public.notification_center_events e ON e.id=s.event_id
    WHERE s.recipient=i.recipient AND s.delivery_key=i.delivery_key AND e.kind IN ('bank_problem','email_problem','payment_problem','provider_problem') AND e.status NOT IN ('resolved','recovered'))
   AND NOT EXISTS(SELECT 1 FROM eshop.provider_connection_notification_incidents i2 WHERE i2.active
    AND i.delivery_key='provider:'||i2.provider||':'||i2.connection_id||':incident:'||i2.incident_id)
   AND NOT EXISTS(SELECT 1 FROM eshop.bank_sync_health h WHERE i.delivery_key='bank:'||h.connection_id||':incident:'||h.incident_id AND h.warning_code IS NOT NULL);
  DELETE FROM public.notification_center_email_dispatches d WHERE d.recipient=profile.recipient AND d.state IN ('collecting','omitted')
   AND NOT EXISTS(SELECT 1 FROM public.notification_center_email_items i WHERE i.dispatch_id=d.id);
  UPDATE public.notification_center_email_profiles SET collected_at=clock_timestamp() WHERE recipient=profile.recipient;
  n:=n+1;
 END LOOP;
 UPDATE public.notification_center_maintenance SET last_scanned=total_scanned,last_processed=n,
  last_deferred=expired,last_run_at=clock_timestamp() WHERE name='email-collection' AND n>0
  AND ctid IN(SELECT ctid FROM public.notification_center_maintenance WHERE name='email-collection' FOR UPDATE SKIP LOCKED);
 RETURN n;
END $$;
CREATE OR REPLACE FUNCTION public.enqueue_notification_center_emails(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE profile record; dispatch record; context jsonb; result jsonb; n integer:=0; detail text; retry integer;
BEGIN
 PERFORM public.notification_center_require_service();
 FOR profile IN SELECT p.* FROM public.notification_center_email_profiles p
  WHERE EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d WHERE d.recipient=p.recipient AND d.state='collecting' AND d.due_at<=clock_timestamp() AND d.next_attempt_at<=clock_timestamp())
  ORDER BY p.collected_at,p.recipient LIMIT greatest(1,least(p_limit,100)) FOR UPDATE OF p SKIP LOCKED LOOP
  IF EXISTS(SELECT 1 FROM public.email_messages m WHERE m.recipient_user=profile.recipient AND m.message_kind='admin_notification_digest'
   AND m.workflow_state IN ('blocked','pending','preparing','sending','retry_wait','unknown')) THEN CONTINUE; END IF;
  SELECT * INTO dispatch FROM public.notification_center_email_dispatches WHERE recipient=profile.recipient AND state='collecting' AND due_at<=clock_timestamp() AND next_attempt_at<=clock_timestamp() FOR UPDATE;
  IF NOT FOUND THEN CONTINUE; END IF;
  context:=public.notification_center_email_context_internal(dispatch.id,profile.recipient);
  IF context IS NULL OR jsonb_array_length(context->'items')=0 THEN
   UPDATE public.notification_center_email_dispatches SET state='omitted' WHERE id=dispatch.id;
   CONTINUE;
  END IF;
  IF nullif(context->>'address','') IS NULL THEN
   UPDATE public.notification_center_email_dispatches SET next_attempt_at=clock_timestamp()+interval '5 minutes' WHERE id=dispatch.id;
   CONTINUE;
  END IF;
  BEGIN
  result:=public.enqueue_email('admin_notification_digest',jsonb_build_object('recipient_user',profile.recipient),context->>'address',
   jsonb_build_object('dispatchId',dispatch.id,'templateVersion',1),'notification:'||dispatch.id,'ADMIN_NOTIFICATION_DIGEST');
  UPDATE public.notification_center_email_dispatches SET state='queued',message_id=(result->>'message_id')::uuid WHERE id=dispatch.id;
  n:=n+1;
  EXCEPTION WHEN SQLSTATE 'PT429' THEN
   -- Producer admission rolls back independently; the durable collecting
   -- envelope waits for the original abuse backend's release time.
   GET STACKED DIAGNOSTICS detail=PG_EXCEPTION_DETAIL;
   retry:=greatest(1,least(coalesce((detail::jsonb->>'retryAfterSeconds')::integer,60),86400));
   UPDATE public.notification_center_email_dispatches SET next_attempt_at=clock_timestamp()+make_interval(secs=>retry) WHERE id=dispatch.id;
  END;
 END LOOP;
 RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.collect_notification_center_emails(integer),public.enqueue_notification_center_emails(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.collect_notification_center_emails(integer),public.enqueue_notification_center_emails(integer) TO service_role;
CREATE OR REPLACE FUNCTION public.get_notification_center_email_health()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 RETURN jsonb_build_object(
 'lastCollection',(SELECT jsonb_build_object('scanned',last_scanned,'recipients',last_processed,'expiredCatchup',last_deferred,'at',last_run_at) FROM public.notification_center_maintenance WHERE name='email-collection'),
 'cursorLag',(SELECT coalesce(sum(u.last_delivery_sequence-u.email_scanned_sequence),0) FROM public.notification_center_user_state u JOIN public.notification_center_email_profiles p USING(recipient) JOIN public.notification_center_organizations a USING(organization) WHERE a.email_collection_started_at IS NOT NULL),
 'oldestUnscanned',(SELECT min(d.delivered_at) FROM public.notification_center_user_state u JOIN public.notification_center_email_profiles p USING(recipient) JOIN public.notification_center_organizations a USING(organization) JOIN public.notification_center_deliveries d ON d.organization=u.organization AND d.recipient=u.recipient AND d.sequence>u.email_scanned_sequence WHERE a.email_collection_started_at IS NOT NULL),
 'oldestDue',(SELECT min(due_at) FROM public.notification_center_email_dispatches WHERE state='collecting' AND due_at<=clock_timestamp()),
 'deferredEnqueue',(SELECT count(*) FROM public.notification_center_email_dispatches WHERE state='collecting' AND next_attempt_at>clock_timestamp()),
 'activeQueue',(SELECT count(*) FROM public.email_messages WHERE message_kind='admin_notification_digest' AND workflow_state IN ('blocked','pending','preparing','sending','retry_wait','unknown')),
 'unknown',(SELECT count(*) FROM public.email_messages WHERE message_kind='admin_notification_digest' AND workflow_state='unknown'),
 'noAddress',(SELECT count(*) FROM public.notification_center_email_dispatches d JOIN public.notification_center_email_profiles p USING(recipient) WHERE d.state='collecting' AND public.get_user_delivery_email(p.recipient) IS NULL));
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_email_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_notification_center_email_health() TO service_role;


-- SOURCE: abuse/policy.sql
-- One statement snapshot per domain admission. Scoped overrides cannot alter an actor rule.
CREATE OR REPLACE FUNCTION public.abuse_effective_rules_v1(p_budget text,p_unit bigint,p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('revision',v.revision,'rules',coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object(
 'base_limit',coalesce(u.base_limit,o.base_limit,r.base_limit)) ORDER BY r.rule_key),'[]'::jsonb))
 FROM public.abuse_policy_revision v CROSS JOIN public.abuse_policy_rules r
 LEFT JOIN public.abuse_policy_overrides o ON o.rule_key=r.rule_key AND o.target_kind='organization'
  AND o.target_id=p_org AND r.scope_kind IN ('unit','organization') AND o.expires_at>statement_timestamp()
 LEFT JOIN public.abuse_policy_overrides u ON u.rule_key=r.rule_key AND u.target_kind='unit'
  AND u.target_id=p_unit AND r.scope_kind='unit' AND u.expires_at>statement_timestamp()
 WHERE r.budget_key=p_budget GROUP BY v.revision
 HAVING count(*)=CASE p_budget WHEN 'occasion.creation' THEN 8 WHEN 'occasion.copy' THEN 2 WHEN 'occasion.draft' THEN 7
  WHEN 'unit.creation' THEN 3 WHEN 'email.ordinary' THEN 4 WHEN 'email.auth' THEN 4
  WHEN 'email.backlog' THEN 4 WHEN 'email.auth.backlog' THEN 1 WHEN 'email.payload' THEN 1
  WHEN 'email.prepare' THEN 2 WHEN 'email.actor' THEN 1 WHEN 'email.dispatch' THEN 1 WHEN 'ticket.document' THEN 4 WHEN 'ticket.preview' THEN 4 WHEN 'bank.operation' THEN 3 WHEN 'stripe.connect' THEN 3 WHEN 'stripe.checkout' THEN 3 WHEN 'barion.checkout' THEN 3 WHEN 'order.creation' THEN 4 WHEN 'qr.global' THEN 1 WHEN 'qr.proof' THEN 1 WHEN 'qr.payload' THEN 1 WHEN 'spot.hold' THEN 3 WHEN 'image.upload' THEN 5 WHEN 'image.fetch' THEN 5 WHEN 'sync.snapshot' THEN 2 WHEN 'sync.work' THEN 1 WHEN 'hold.duration' THEN 1 WHEN 'auth.reset.source' THEN 2 WHEN 'organization.creation' THEN 1 WHEN 'auth.reset.account' THEN 1
  WHEN 'auth.google.source' THEN 1 WHEN 'auth.google.client' THEN 1 WHEN 'auth.google.global' THEN 1 WHEN 'auth.google.attempt' THEN 1 WHEN 'auth.google.proof' THEN 1
  WHEN 'scan.operation' THEN 2 WHEN 'scan.invalid.global' THEN 1 WHEN 'scan.invalid.source' THEN 1 WHEN 'scan.password' THEN 2 WHEN 'scan.export' THEN 2
  WHEN 'reception.create' THEN 1 WHEN 'reception.issue' THEN 1 WHEN 'reception.revoke' THEN 1 WHEN 'reception.cancel' THEN 1
  WHEN 'order.mutation' THEN 4 WHEN 'batch-create' THEN 1 WHEN 'batch-document' THEN 2
  WHEN 'push.delivery' THEN 10
  WHEN 'cleaning.report' THEN 3
  WHEN 'push.dispatch' THEN 2
  WHEN 'image.records' THEN 9 WHEN 'auth.password' THEN 2 WHEN 'document.output' THEN 4 WHEN 'image.storage' THEN 3 WHEN 'monitor.thresholds' THEN 6 WHEN 'auth.password.change' THEN 3
  WHEN 'email.notification' THEN 3 WHEN 'email.notification.backlog' THEN 4 WHEN 'email.notification.prepare' THEN 2 WHEN 'email.send.notification' THEN 3
  WHEN 'email.send.ordinary' THEN 2 WHEN 'email.send.auth' THEN 2 WHEN 'email.send.commitment' THEN 2
  ELSE -1 END;
$$;

-- All families in one admission phase share a PostgreSQL STABLE statement
-- snapshot, including overrides and revision; no config lock or HTTP hop.
CREATE OR REPLACE FUNCTION public.abuse_policy_bundle_v1(p_budgets text[],p_unit bigint,p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_object_agg(b,public.abuse_effective_rules_v1(b,p_unit,p_org)) FROM unnest(p_budgets) b;
$$;
REVOKE ALL ON FUNCTION public.abuse_policy_bundle_v1(text[],bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Only numeric limits may be changed here. Algorithm/window/identity changes need a migration.
-- A batch is one audited optimistic revision; no writes to usage.
CREATE OR REPLACE FUNCTION public.set_abuse_policy_v1(p_expected_revision bigint,p_reason text,p_changes jsonb)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_revision bigint; c jsonb; r public.abuse_policy_rules; v_old jsonb; v_author text;
BEGIN
 PERFORM public.require_service_role();
 IF length(btrim(p_reason)) NOT BETWEEN 8 AND 1000 OR p_reason IS NULL OR jsonb_typeof(p_changes) IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_changes) NOT BETWEEN 1 AND 100 THEN RAISE invalid_parameter_value USING MESSAGE='invalid abuse policy batch'; END IF;
 SELECT revision INTO v_revision FROM public.abuse_policy_revision FOR UPDATE;
 IF p_expected_revision IS DISTINCT FROM v_revision THEN RAISE serialization_failure USING MESSAGE='abuse policy revision conflict'; END IF;
 v_author:=coalesce(auth.uid()::text,session_user::text);
 SELECT jsonb_build_object('rules',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_rules x),
 'overrides',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_overrides x)) INTO v_old;
 FOR c IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(c) k WHERE k NOT IN ('rule_key','base_limit','target_kind','target_id','expires_at')) THEN
   RAISE invalid_parameter_value USING MESSAGE='unsupported abuse policy parameter'; END IF;
  SELECT * INTO r FROM public.abuse_policy_rules WHERE rule_key=c->>'rule_key';
  IF NOT FOUND OR (c->>'base_limit')::bigint IS NULL OR (c->>'base_limit')::bigint NOT BETWEEN 1 AND r.hard_cap THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid abuse policy limit'; END IF;
  IF c ? 'target_kind' THEN
   IF (c->>'target_kind'='unit' AND r.scope_kind<>'unit') OR
    (c->>'target_kind'='organization' AND r.scope_kind NOT IN ('unit','organization')) OR
    c->>'target_kind' NOT IN ('unit','organization') OR (c->>'target_id')::bigint IS NULL OR
    (c->>'expires_at')::timestamptz IS NULL OR (c->>'expires_at')::timestamptz<=statement_timestamp() OR
    (c->>'expires_at')::timestamptz>statement_timestamp()+interval '90 days' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid abuse override scope or expiry'; END IF;
   IF NOT (CASE WHEN c->>'target_kind'='unit' THEN EXISTS(SELECT 1 FROM public.units WHERE id=(c->>'target_id')::bigint)
    ELSE EXISTS(SELECT 1 FROM public.organizations WHERE id=(c->>'target_id')::bigint) END) THEN
    RAISE invalid_parameter_value USING MESSAGE='unknown abuse override target'; END IF;
   INSERT INTO public.abuse_policy_overrides VALUES(r.rule_key,c->>'target_kind',(c->>'target_id')::bigint,
    (c->>'base_limit')::bigint,(c->>'expires_at')::timestamptz,p_reason,v_author)
   ON CONFLICT(rule_key,target_kind,target_id) DO UPDATE SET base_limit=excluded.base_limit,expires_at=excluded.expires_at,reason=excluded.reason,author=excluded.author;
  ELSE
   IF c ? 'target_id' OR c ? 'expires_at' THEN RAISE invalid_parameter_value USING MESSAGE='override target required'; END IF;
   UPDATE public.abuse_policy_rules SET base_limit=(c->>'base_limit')::bigint WHERE rule_key=r.rule_key;
  END IF;
 END LOOP;
 UPDATE public.abuse_policy_revision SET revision=revision+1 RETURNING revision INTO v_revision;
 INSERT INTO public.abuse_policy_audit SELECT v_revision,clock_timestamp(),v_author,p_reason,v_old,
  jsonb_build_object('rules',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_rules x),
   'overrides',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_overrides x));
 RETURN v_revision;
END $$;
REVOKE ALL ON FUNCTION public.set_abuse_policy_v1(bigint,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_abuse_policy_v1(bigint,text,jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.abuse_effective_rules_v1(text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_unit_abuse_policy_v1(p_unit bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_org bigint;
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_read_unit_abuse_policy(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
 SELECT organization INTO v_org FROM public.units WHERE id=p_unit;
 RETURN jsonb_build_object('creation',public.abuse_effective_rules_v1('occasion.creation',p_unit,v_org),
 'draft',public.abuse_effective_rules_v1('occasion.draft',p_unit,v_org),
 'usage',coalesce((SELECT jsonb_agg(jsonb_build_object('rule',u.rule_key,'amount',u.amount,'bucketAt',u.bucket_at,'expiresAt',u.expires_at))
 FROM public.abuse_budget_usage u JOIN public.abuse_policy_rules r USING(rule_key)
 WHERE u.expires_at>statement_timestamp() AND ((r.scope_kind='unit' AND u.scope_id=p_unit::text)
 OR (r.scope_kind='actor' AND u.scope_id=auth.uid()::text))),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.get_unit_abuse_policy_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_unit_abuse_policy_v1(bigint) TO authenticated;


-- SOURCE: abuse/email.sql
CREATE OR REPLACE FUNCTION public.abuse_recipient_key_v1(p_recipient text) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT encode(extensions.hmac(lower(btrim(p_recipient)),encode(secret,'hex'),'sha256'),'hex')
 FROM public.abuse_identity_key WHERE singleton;
$$;
REVOKE ALL ON FUNCTION public.abuse_recipient_key_v1(text) FROM PUBLIC,anon,authenticated,service_role;

-- Shared classification also adopts pending pre-cutover intents without recharging them.
CREATE OR REPLACE FUNCTION public.email_admission_class_v1(m public.email_messages) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; commitment boolean:=false;
BEGIN
 IF m.message_kind='admin_notification_digest' AND m.organization IS NULL AND m.recipient_user IS NOT NULL
  AND EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d WHERE d.id=m.notification_dispatch_id AND d.recipient=m.recipient_user) THEN RETURN 'notification'; END IF;

 IF m.message_kind IN ('order_tickets','order_payment_notice','order_storno') AND m.order_id IS NOT NULL THEN
  SELECT * INTO o FROM eshop.orders WHERE id=m.order_id;
  commitment:=((m.message_kind IN ('order_tickets','order_payment_notice') AND o.state IN ('paid','sent')) OR (m.message_kind='order_storno' AND o.state='storno')) AND o.occasion=m.occasion AND o.email_payment_version=m.source_version
   AND m.recipient IS NOT DISTINCT FROM o.data->>'email'
   AND m.dedupe_key=o.id||':'||o.email_payment_version||':'||coalesce(m.recipient,'')||CASE WHEN m.message_kind='order_storno' THEN ':storno' ELSE ':false' END
   AND NOT m.data ? 'requested_by';
 END IF;
 IF commitment THEN RETURN 'commitment'; END IF;
 RETURN CASE WHEN m.message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 'auth' ELSE 'ordinary' END;
END $$;
REVOKE ALL ON FUNCTION public.email_admission_class_v1(public.email_messages) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_email_intent_v1(p_message bigint,p_recheck boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; policy jsonb; scopes jsonb; costs jsonb; r jsonb;
 is_auth boolean; unit_count bigint; org_count bigint; unit_bytes bigint; org_bytes bigint; growth bigint:=0; policies jsonb;
BEGIN
 SELECT * INTO STRICT m FROM public.email_messages WHERE id=p_message;

 IF public.email_admission_class_v1(m)='notification' THEN
  scopes:=jsonb_build_object('global','all','recipient',m.recipient_user::text);
  PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.payload',NULL,NULL),scopes,
   jsonb_build_object('email.payload.bytes',octet_length(m.data::text)+coalesce(octet_length(m.prepared::text),0)));
  policy:=public.abuse_effective_rules_v1('email.notification.backlog',NULL,NULL);
  FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
   PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
  END LOOP;
  SELECT count(*) FILTER(WHERE recipient_user=m.recipient_user),count(*),
   coalesce(sum(octet_length(data::text)+coalesce(octet_length(prepared::text),0)) FILTER(WHERE recipient_user=m.recipient_user),0),
   coalesce(sum(octet_length(data::text)+coalesce(octet_length(prepared::text),0)),0)
  INTO unit_count,org_count,unit_bytes,org_bytes FROM public.email_messages
  WHERE message_kind='admin_notification_digest' AND workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown');
  PERFORM public.abuse_charge_v1(policy,scopes,jsonb_build_object(
   'email.notification.backlog.recipient',unit_count,'email.notification.backlog.global',org_count,
   'email.notification.backlog.recipient.bytes',unit_bytes,'email.notification.backlog.global.bytes',org_bytes));
  IF NOT p_recheck THEN
   PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.notification',NULL,NULL),scopes);

  END IF;
  UPDATE public.email_messages SET admission_class='notification',priority=80 WHERE id=m.id;
  RETURN;
 END IF;
 policies:=public.abuse_policy_bundle_v1(ARRAY['email.payload','email.actor','email.backlog','email.auth.backlog','email.auth','email.ordinary'],m.unit,m.organization);
 IF m.unit IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.units WHERE id=m.unit AND organization=m.organization) THEN
  RAISE invalid_parameter_value USING MESSAGE='email_scope_mismatch'; END IF;
 scopes:=jsonb_build_object('unit',m.unit,'organization',m.organization,'global','all',
  'actor',m.producer_actor,'recipient',public.abuse_recipient_key_v1(coalesce(m.recipient,(SELECT email_readonly FROM public.user_info WHERE id=m.recipient_user))));
 PERFORM public.abuse_charge_v1(policies->'email.payload',scopes,
  jsonb_build_object('email.payload.bytes',octet_length(m.data::text)+coalesce(octet_length(m.prepared::text),0)));
 -- Neither caller priority nor request data can claim the reserved class.
 IF public.email_admission_class_v1(m)='commitment' THEN
  UPDATE public.email_messages SET admission_class='commitment',priority=5 WHERE id=m.id;
  RETURN;
 END IF;
 IF NOT p_recheck AND m.producer_actor IS NOT NULL THEN
  PERFORM public.abuse_charge_v1(policies->'email.actor',scopes);
 END IF;
 is_auth:=public.email_admission_class_v1(m)='auth';
 UPDATE public.email_messages SET admission_class=CASE WHEN is_auth THEN 'auth' ELSE 'ordinary' END WHERE id=m.id;
 policy:=policies->(CASE WHEN is_auth THEN 'email.auth.backlog' ELSE 'email.backlog' END);
 -- Null Unit auth has an explicit tenant/global class, never a synthetic Unit.
 IF m.unit IS NULL THEN policy:=jsonb_set(policy,'{rules}',(SELECT jsonb_agg(value) FROM jsonb_array_elements(policy->'rules') WHERE value->>'scope_kind'<>'unit')); END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  IF r->>'kind' IN ('bytes','duration') THEN CONTINUE; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 -- Pending partial indexes exclude delivery history. Include blocked/future/unknown.
 SELECT count(*) FILTER(WHERE unit=m.unit),count(*),
  coalesce(sum(octet_length(data::text)+coalesce(octet_length(prepared::text),0)) FILTER(WHERE unit=m.unit),0),
  coalesce(sum(octet_length(data::text)+coalesce(octet_length(prepared::text),0)),0)
 INTO unit_count,org_count,unit_bytes,org_bytes FROM public.email_messages
 WHERE organization=m.organization AND admission_class=CASE WHEN is_auth THEN 'auth' ELSE 'ordinary' END AND workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown');
 costs:=jsonb_build_object('email.auth.backlog.organization',org_count,'email.backlog.unit',unit_count,'email.backlog.organization',org_count,
  'email.backlog.unit.bytes',unit_bytes,'email.backlog.organization.bytes',org_bytes);
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
 IF p_recheck THEN RETURN; END IF;
 policy:=policies->(CASE WHEN is_auth THEN 'email.auth' ELSE 'email.ordinary' END);
 IF NOT is_auth AND m.unit IS NULL THEN
  -- System producers without a Unit retain tenant and recipient bounds.
  policy:=jsonb_set(policy,'{rules}',(SELECT jsonb_agg(value) FROM jsonb_array_elements(policy->'rules') WHERE value->>'scope_kind'<>'unit'));
 END IF;
 IF NOT is_auth AND m.unit IS NOT NULL THEN
  SELECT coalesce(verified_orders,0) INTO growth FROM public.abuse_unit_evidence
   WHERE unit=m.unit AND measured_at>statement_timestamp()-interval '15 minutes';
  growth:=coalesce(growth,0);
 END IF;
 PERFORM public.abuse_charge_v1(policy,scopes,jsonb_build_object('growth',growth));
END $$;
REVOKE ALL ON FUNCTION public.admit_email_intent_v1(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Separate committed preparation budget limits rendering before final enqueue.
CREATE OR REPLACE FUNCTION public.admit_email_preparation_v1(p_organization bigint,p_occasion bigint,p_unit bigint,p_recipient text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_organization)
 OR (p_unit IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.units WHERE id=p_unit AND organization=p_organization))
 OR (p_occasion IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion AND organization=p_organization AND (p_unit IS NULL OR unit=p_unit)))
 OR p_recipient IS NULL OR length(p_recipient)>320 THEN RAISE invalid_parameter_value USING MESSAGE='email_preparation_scope'; END IF;
 RETURN public.abuse_charge_v1(public.abuse_effective_rules_v1('email.prepare',p_unit,p_organization),
  jsonb_build_object('organization',p_organization,'recipient',public.abuse_recipient_key_v1(p_recipient)), '{}',true);
END $$;
REVOKE ALL ON FUNCTION public.admit_email_preparation_v1(bigint,bigint,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admit_email_preparation_v1(bigint,bigint,bigint,text) TO service_role;

CREATE OR REPLACE FUNCTION public.admit_order_creation_v1(p_occasion bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occ public.occasions; policy jsonb; scopes jsonb; costs jsonb; r jsonb;
BEGIN
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=p_occasion;
 policy:=public.abuse_effective_rules_v1('order.creation',occ.unit,occ.organization);
 scopes:=jsonb_build_object('unit',occ.unit,'organization',occ.organization);
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 SELECT jsonb_build_object('order.outstanding.unit',count(*) FILTER(WHERE oc.unit=occ.unit)+1,
  'order.outstanding.organization',count(*)+1) INTO costs
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
 WHERE oc.organization=occ.organization AND o.state IN ('ordered','created','expired','waitlisted','paid');
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
END $$;
REVOKE ALL ON FUNCTION public.admit_order_creation_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Periodic local maintenance, not a query per mail/request. The source is
-- positive signed-bank evidence, distinct orders, and a capped sample/count.
CREATE OR REPLACE FUNCTION public.refresh_abuse_unit_evidence_v1() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE u record; cap bigint; n integer:=0; verified bigint;
BEGIN
 PERFORM public.require_service_role();
 SELECT hard_cap/greatest(growth_increment,1)+1 INTO cap FROM public.abuse_policy_rules WHERE rule_key='email.ordinary.unit.day';
 IF cap IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 FOR u IN SELECT units.id FROM public.units LEFT JOIN public.abuse_unit_evidence e ON e.unit=units.id
  WHERE e.measured_at IS NULL OR e.measured_at<statement_timestamp()-interval '5 minutes'
  ORDER BY e.measured_at NULLS FIRST,units.id LIMIT 20 LOOP
  IF NOT pg_try_advisory_xact_lock(hashtextextended('abuse-growth:'||u.id,0)) THEN CONTINUE; END IF;
  SELECT count(*) INTO verified FROM (
   SELECT ord.id FROM eshop.orders ord JOIN public.occasions occ ON occ.id=ord.occasion
   WHERE occ.unit=u.id AND ord.state IN ('paid','sent') AND ord.price>0
   AND (SELECT coalesce(sum(t.amount),0) FROM eshop.transactions t
    WHERE t.payment_info=ord.payment_info AND t.currency=ord.currency_code
     AND EXISTS(SELECT 1 FROM eshop.bank_transaction_identities i WHERE i.transaction_id=t.id))>=ord.price LIMIT cap
  ) proof;
  INSERT INTO public.abuse_unit_evidence VALUES(u.id,verified,statement_timestamp())
   ON CONFLICT(unit) DO UPDATE SET verified_orders=excluded.verified_orders,measured_at=excluded.measured_at;
  n:=n+1;
 END LOOP;
 RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.refresh_abuse_unit_evidence_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_abuse_unit_evidence_v1() TO service_role;


-- SOURCE: emails/email_queue.sql
CREATE OR REPLACE FUNCTION public.wake_email_worker() RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path=public,extensions AS $$
DECLARE v_url text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF current_setting('festapp.email_wake',true)='scheduled' THEN RETURN; END IF;
 SELECT worker_url INTO v_url FROM public.email_capacity WHERE NOT paused;
 IF v_url IS NULL OR NOT (EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now())
  OR EXISTS(SELECT 1 FROM public.email_capacity WHERE quota_at IS NULL OR quota_at<now()-interval '5 minutes')) THEN RETURN; END IF;
 PERFORM set_config('festapp.email_wake','scheduled',true);
 BEGIN
  PERFORM net.http_post(url:=v_url,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
 EXCEPTION WHEN OTHERS THEN
  -- Do not invert producer order/message locks against gateway capacity/order locks.
  UPDATE public.email_capacity SET wake_error='wake_failed' WHERE ctid IN (SELECT ctid FROM public.email_capacity FOR UPDATE SKIP LOCKED);
 END;
END $$;

-- Internal service boundary. Domain functions are the only caller for public commands.
CREATE OR REPLACE FUNCTION public.enqueue_email(p_kind text,p_context jsonb,p_recipient text,p_data jsonb,p_dedupe text,
 p_code text DEFAULT '',p_not_before timestamptz DEFAULT now(),p_expires timestamptz DEFAULT NULL,
 p_order bigint DEFAULT NULL,p_version bigint DEFAULT NULL,p_post_action jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_hash text; v_row public.email_messages; v_org bigint:=(p_context->>'organization')::bigint; v_occ bigint:=(p_context->>'occasion')::bigint; v_unit bigint:=(p_context->>'unit')::bigint;
BEGIN
 IF p_code='BANK_SYNC_WARNING' THEN RAISE EXCEPTION 'bank_warning_producer_retired'; END IF;
 p_recipient:=public.normalize_order_email_contact(p_recipient);
 PERFORM public.check_occasion_writable(v_occ);
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF (v_org IS NULL AND p_kind<>'admin_notification_digest') OR p_kind NOT IN ('admin_notification_digest','order_confirmation','order_payment_notice','order_tickets','order_reminder','order_update','order_storno','custom','registration','sign_in','reset_password','app_links','deletion_confirm','deletion_complete','google_mailbox','gotrue','waitlist_confirmation','waitlist_offer','sale_opening_opened')
 OR p_dedupe IS NULL OR length(p_dedupe)>512 OR (p_recipient IS NOT NULL AND (length(p_recipient)>320 OR position('@' in p_recipient)=0)) THEN RAISE EXCEPTION 'invalid_email_intent'; END IF;
 IF (v_org IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org)) OR
 (v_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=v_occ AND organization=v_org AND (NOT p_context ? 'unit' OR unit IS NOT DISTINCT FROM v_unit))) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 IF p_kind='admin_notification_digest' THEN
  IF v_org IS NOT NULL OR v_occ IS NOT NULL OR v_unit IS NOT NULL OR p_order IS NOT NULL OR
   p_recipient IS DISTINCT FROM public.get_user_delivery_email((p_context->>'recipient_user')::uuid) OR
   NOT EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d
    WHERE d.id=(p_data->>'dispatchId')::uuid AND d.recipient=(p_context->>'recipient_user')::uuid AND d.state IN ('collecting','queued')) THEN
   RAISE EXCEPTION 'email_recipient_scope_mismatch';
  END IF;
 END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=v_occ) THEN RAISE EXCEPTION 'email_order_scope_mismatch'; END IF;
 IF v_occ IS NOT NULL THEN SELECT unit INTO v_unit FROM public.occasions WHERE id=v_occ; END IF;
 IF p_order IS NOT NULL AND p_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice') THEN
  p_data:=coalesce(p_data,'{}')||jsonb_build_object('collectionAction',public.payment_collection_action_internal(p_order));
 END IF;
 IF p_order IS NOT NULL AND p_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice','order_storno','order_tickets') THEN
  p_data:=coalesce(p_data,'{}')||jsonb_build_object('paymentTemplateEpoch',coalesce((SELECT revision FROM eshop.payment_template_epochs WHERE occasion_id=v_occ),0));
 END IF;
 -- Snapshot the tenant default only for new unlocalized domain intents. Existing
 -- messages, explicit locales and prepared/encrypted Auth content are untouched.
 IF NOT coalesce(p_data,'{}'::jsonb) ? 'lang' AND
    (p_kind LIKE 'order_%' OR p_kind IN ('waitlist_confirmation','waitlist_offer','sale_opening_opened')) AND
    (SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=v_org)='en' THEN
   p_data:=coalesce(p_data,'{}'::jsonb)||'{"lang":"en"}'::jsonb;
 END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('context',p_context-'tracking_policy','recipient',p_recipient,'data',CASE WHEN p_order IS NOT NULL AND p_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice','order_storno','order_tickets') THEN p_data-'requested_by'-'collectionAction'-'paymentTemplateEpoch' ELSE p_data-'requested_by' END,'code',p_code,'version',p_version,'post',p_post_action)::text,'sha256'),'hex');
 IF p_kind='admin_notification_digest' THEN
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,producer_actor,priority,workflow_state,post_action,tracking_policy,notification_dispatch_id)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,coalesce((p_context->>'actor_id')::uuid,auth.uid()),
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,CASE WHEN p_kind LIKE 'order_%' OR p_kind IN ('app_links','custom') THEN CASE WHEN p_context->>'tracking_policy'='engagement' THEN 'engagement' ELSE 'open' END ELSE 'disabled' END,CASE WHEN p_kind='admin_notification_digest' THEN (p_data->>'dispatchId')::uuid END)
 ON CONFLICT(recipient_user,message_kind,dedupe_key) WHERE message_kind='admin_notification_digest' DO NOTHING RETURNING * INTO v_row;
 ELSE
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,producer_actor,priority,workflow_state,post_action,tracking_policy,notification_dispatch_id)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,coalesce((p_context->>'actor_id')::uuid,auth.uid()),
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,CASE WHEN p_kind LIKE 'order_%' OR p_kind IN ('app_links','custom') THEN CASE WHEN p_context->>'tracking_policy'='engagement' THEN 'engagement' ELSE 'open' END ELSE 'disabled' END,CASE WHEN p_kind='admin_notification_digest' THEN (p_data->>'dispatchId')::uuid END)
 ON CONFLICT(organization,message_kind,dedupe_key) DO NOTHING RETURNING * INTO v_row;
 END IF;
 IF v_row.id IS NULL THEN
  SELECT * INTO v_row FROM public.email_messages WHERE (organization=v_org OR (p_kind='admin_notification_digest' AND recipient_user=(p_context->>'recipient_user')::uuid)) AND message_kind=p_kind AND dedupe_key=p_dedupe;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'email_active_notification_conflict'; END IF;
  IF v_row.input_hash<>v_hash THEN RAISE EXCEPTION 'email_dedupe_conflict'; END IF;
  RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',true);
 END IF;
 PERFORM public.admit_email_intent_v1(v_row.id);
 PERFORM public.notification_center_email_internal(v_row.message_id);
 IF p_not_before<=now() THEN PERFORM public.wake_email_worker(); END IF;
 RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',false);
END $$;

CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb; v_template_epoch bigint; template_audit jsonb; bank_enabled boolean;
BEGIN
 IF p_message.message_kind='custom' AND p_message.code='MEASUREMENT_APPROVAL_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM analytics.unit_measurement_request q JOIN public.units u ON u.id=q.unit
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE q.unit=p_message.unit AND u.organization=p_message.organization AND NOT public.is_demo_unit(u.id)
    AND q.revision=coalesce((p_message.data->>'request_revision')::integer,1)
    AND (public.unit_measurement_approval_internal(u.id)->'approved'='false'::jsonb
     OR EXISTS(SELECT FROM jsonb_array_elements(q.requested_origins) x
      WHERE coalesce(u.data->'measurement_websites','[]'::jsonb) @> jsonb_build_array(x.value)
       AND NOT (public.unit_measurement_approval_internal(u.id)->'approved_origins' @> jsonb_build_array(x.value))))
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 IF p_message.message_kind='admin_notification_digest' THEN
  RETURN p_message.recipient IS NOT DISTINCT FROM public.get_user_delivery_email(p_message.recipient_user)
   AND coalesce(jsonb_array_length(public.notification_center_email_context_internal(p_message.notification_dispatch_id,p_message.recipient_user)->'items'),0)>0;
 END IF;

 PERFORM public.require_service_role();
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.message_kind='sign_in' AND EXISTS(SELECT 1 FROM public.occasion_users ou
   WHERE ou.occasion=p_message.occasion AND ou."user"=p_message.recipient_user AND (ou.is_editor OR ou.is_editor_view OR ou.is_manager)) THEN
  RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_INVITATION' THEN
  RETURN EXISTS(SELECT 1 FROM public.access_invitations i WHERE i.message_id=p_message.message_id
   AND i.accepted_at IS NULL AND public.access_invitation_valid_internal_v1(i)
   AND i.email=p_message.recipient AND i.occasion IS NOT DISTINCT FROM p_message.occasion AND i.unit=p_message.unit AND i.organization=p_message.organization);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_ACCESS_NOTICE' THEN
  RETURN public.can_manage_member_access_as_actor_internal_v1(p_message.producer_actor,
   CASE WHEN p_message.occasion IS NULL THEN 'unit' ELSE 'occasion' END,coalesce(p_message.occasion,p_message.unit))
   AND public.get_user_delivery_email(p_message.recipient_user)=p_message.recipient
   AND CASE WHEN p_message.occasion IS NULL THEN EXISTS(SELECT 1 FROM public.unit_users WHERE unit=p_message.unit AND "user"=p_message.recipient_user)
    ELSE EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_message.occasion AND "user"=p_message.recipient_user) END;
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='UNIT_VERIFICATION_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM public.unit_legal_profiles p JOIN public.units u ON u.id=p.unit_id
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE p.unit_id=p_message.unit AND u.organization=p_message.organization AND p.status='pending'
    AND p.revision=p_message.source_version
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN RETURN false; END IF;
 IF p_message.message_kind='sale_opening_confirmation' THEN RETURN false; END IF;
 IF p_message.message_kind='sale_opening_opened' THEN
  RETURN public.sale_opening_intent_valid_internal(p_message);
 END IF;
 IF p_message.order_id IS NULL THEN
  IF p_message.recipient_user IS NOT NULL AND p_message.message_kind<>'deletion_complete' THEN
   IF p_message.message_kind<>'gotrue' AND public.get_user_delivery_email(p_message.recipient_user) IS DISTINCT FROM p_message.recipient THEN RETURN false; END IF;
   IF p_message.data ? 'sign_in_code_version' AND NOT EXISTS(SELECT 1 FROM public.sign_in_codes WHERE user_id=p_message.recipient_user AND version::text=p_message.data->>'sign_in_code_version' AND expires_at>now() AND consumed_at IS NULL AND attempts<5) THEN RETURN false; END IF;
   IF p_message.data ? 'password_version' AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_message.recipient_user AND encode(extensions.digest(encrypted_password,'sha256'),'hex')=p_message.data->>'password_version') THEN RETURN false; END IF;
   IF p_message.data ? 'reset_hash' AND NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=p_message.recipient_user AND encode(extensions.digest(token::text,'sha256'),'hex')=p_message.data->>'reset_hash') THEN RETURN false; END IF;
  END IF;
  IF p_message.data ? 'deletion_request' AND NOT EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE id=(p_message.data->>'deletion_request')::uuid AND status IN ('email_pending','email_sent') AND expires_at>now()) THEN RETURN false; END IF;
  IF p_message.data ? 'google_attempt' AND NOT EXISTS(SELECT 1 FROM public.external_login_attempts WHERE id=(p_message.data->>'google_attempt')::uuid AND mailbox_hash=p_message.data->>'mailbox_hash' AND expires_at>now() AND NOT mailbox_verified) THEN RETURN false; END IF;
  RETURN true;
 END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_message.order_id;
 IF v_order.id IS NULL OR v_order.occasion<>p_message.occasion THEN RETURN false; END IF;
 IF p_message.data->>'repair_payment_fingerprint' IS NOT NULL AND p_message.data->>'repair_payment_fingerprint' IS DISTINCT FROM public.order_email_payment_fingerprint(v_order.id) THEN RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN
  RETURN v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash)
   WHERE s.command_id=(p_message.data->>'order_overview_command')::uuid AND c.kind='order_view'
   AND c.order_id=v_order.id AND c.form_id=v_order.form AND c.organization_id=p_message.organization
   AND c.revoked_at IS NULL AND c.expires_at>now() AND s.expires_at=c.expires_at);
 END IF;
 IF p_message.message_kind='waitlist_confirmation' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='waitlist_offer' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots s ON s.offer_id=w.id
   WHERE w.id=(p_message.data->>'offer_id')::uuid AND w.order_id=v_order.id AND w.expires_at>clock_timestamp() AND s.outcome='pending');
 END IF;
 IF p_message.message_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice','order_storno','order_tickets') THEN
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  v_template_epoch:=coalesce((SELECT e.revision FROM eshop.payment_template_epochs e WHERE e.occasion_id=v_order.occasion),0);
  bank_enabled:=coalesce(public.payment_method_policy_enabled_internal(v_occ.unit,'bank'),false);
  IF p_message.data ? 'paymentTemplateEpoch' THEN
   IF (p_message.data->>'paymentTemplateEpoch')::bigint IS DISTINCT FROM v_template_epoch THEN RETURN false; END IF;
  ELSIF p_message.prepared IS NOT NULL AND (NOT bank_enabled OR public.payment_method_is_online_internal(v_pi.payment_method)) THEN
   -- An encrypted legacy snapshot has no attestation for the current template.
   -- Preserve it as audit; a new authorized preparation must replace the intent.
   RETURN false;
  END IF;
  IF NOT bank_enabled OR public.payment_method_is_online_internal(v_pi.payment_method) THEN
   template_audit:=public.payment_template_audit_internal(v_order.occasion);
   IF template_audit->'compatible' IS DISTINCT FROM 'true'::jsonb THEN RETURN false; END IF;
  END IF;
 END IF;
 IF p_message.message_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice') THEN
  IF p_message.data#>>'{collectionAction,policyRevision}' IS NULL THEN RETURN false; END IF;
  IF public.payment_collection_action_internal(v_order.id)->'policyRevision' IS DISTINCT FROM p_message.data#>'{collectionAction,policyRevision}' THEN RETURN false; END IF;
 END IF;
 IF p_message.data#>'{collectionAction,allowed}'='true'::jsonb THEN
 IF (
  public.payment_collection_action_internal(v_order.id)->'allowed' IS DISTINCT FROM 'true'::jsonb OR
  public.payment_collection_action_internal(v_order.id)->'policyRevision' IS DISTINCT FROM p_message.data#>'{collectionAction,policyRevision}') THEN RETURN false; END IF;
 END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_order.payment_info AND public.payment_method_is_online_internal(payment_method))
   AND public.provider_order_payment_projection_internal(v_order.id)->>'admissionState' IS DISTINCT FROM 'valid' THEN RETURN false; END IF;
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_confirmation' THEN
  RETURN public.order_checkout_email_kind_internal(v_order.id)='order_confirmation'
   AND v_order.state IN ('ordered','paid') AND v_order.email_payment_version=p_message.source_version
   AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  IF public.payment_collection_action_internal(v_order.id)->'allowed' IS DISTINCT FROM 'true'::jsonb THEN RETURN false; END IF;
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  IF v_pi.payment_method<>'bank' OR v_pi.data#>>'{payment_policy,mode}'='none' THEN RETURN false; END IF;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND coalesce(v_pi.paid,0)-coalesce(v_pi.returned,0)<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.recover_email_leases() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 -- Sending expiry is ambiguous, preparation expiry is safe to recover.
 UPDATE public.email_attempts a SET state='unknown',finished_at=now(),error_code='lease_expired'
 FROM public.email_messages m WHERE m.message_id=a.message_id AND m.workflow_state='sending' AND m.lease_until<now() AND a.state='sending';
 UPDATE public.email_messages SET workflow_state='unknown',last_error='lease_expired' WHERE workflow_state='sending' AND lease_until<now();
 UPDATE public.email_attempts a SET state='cancelled',finished_at=now() FROM public.email_messages m
 WHERE a.message_id=m.message_id AND a.lease_token=m.lease_token AND a.state='preparing' AND m.lease_until<now();
 UPDATE public.email_messages SET workflow_state='pending',lease_token=NULL,lease_until=NULL WHERE workflow_state='preparing' AND lease_until<now();

END $$;
REVOKE ALL ON FUNCTION public.recover_email_leases() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_leases() TO service_role;

CREATE OR REPLACE FUNCTION public.claim_email() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_row public.email_messages; v_cap public.email_capacity; v_attempt uuid; v_token uuid:=extensions.gen_random_uuid(); v_wait integer;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_capacity SET heartbeat_at=now() WHERE singleton;
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_cap.circuit_until>now()
  OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='preparing' AND lease_until>now())>=v_cap.max_preparing THEN RETURN NULL; END IF;
 SELECT (x->>'base_limit')::integer INTO v_wait FROM jsonb_array_elements(public.abuse_effective_rules_v1('email.dispatch',NULL,NULL)->'rules') x;
 IF v_wait IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 SELECT * INTO v_row FROM public.email_messages m
 WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now()
 AND (m.prepared IS NOT NULL OR m.message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation')
  OR (SELECT count(*) FROM public.email_messages heavy WHERE heavy.workflow_state='preparing' AND heavy.lease_until>now() AND heavy.prepared IS NULL
   AND heavy.message_kind NOT IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation'))<greatest(1,v_cap.max_preparing-1))
 AND NOT EXISTS(SELECT 1 FROM public.email_messages prior WHERE prior.order_id=m.order_id AND prior.message_kind='order_confirmation'
  AND m.message_kind<>'order_confirmation' AND prior.workflow_state NOT IN ('accepted','cancelled','expired'))
 ORDER BY CASE WHEN m.message_kind='admin_notification_digest' THEN 80 WHEN m.created_at<=now()-make_interval(secs=>v_wait) THEN 0 ELSE priority END,
 (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.organization=m.organization AND served.last_claimed_at IS NOT NULL) NULLS FIRST,
 CASE WHEN m.unit IS NULL THEN (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.organization=m.organization AND served.unit IS NULL AND served.last_claimed_at IS NOT NULL)
 ELSE (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.unit=m.unit AND served.last_claimed_at IS NOT NULL) END NULLS FIRST,target_time,id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF v_row.id IS NULL THEN RETURN NULL; END IF;
 IF NOT public.email_intent_valid(v_row) THEN
  UPDATE public.email_messages SET workflow_state=CASE WHEN expires_at<=now() THEN 'expired' ELSE 'cancelled' END,last_error=CASE WHEN v_row.message_kind='admin_notification_digest' AND v_row.recipient IS DISTINCT FROM public.get_user_delivery_email(v_row.recipient_user) THEN 'destination_changed' ELSE 'intent_invalid' END WHERE id=v_row.id;
  RETURN jsonb_build_object('skipped',true);
 END IF;
 IF v_row.message_kind='admin_notification_digest' AND v_row.prepared IS NULL THEN
  PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.notification.prepare',NULL,NULL),
   jsonb_build_object('global','all','recipient',v_row.recipient_user::text));
 END IF;
 UPDATE public.email_messages SET workflow_state='preparing',last_claimed_at=now(),lease_token=v_token,lease_until=now()+interval '90 seconds' WHERE id=v_row.id RETURNING * INTO v_row;
 INSERT INTO public.email_attempts(message_id,lease_token,state) VALUES(v_row.message_id,v_token,'preparing') RETURNING attempt_id INTO v_attempt;
 RETURN to_jsonb(v_row)||jsonb_build_object('attempt_id',v_attempt);
END $$;

-- Keep the global preparation permit while rendering still runs; expired workers cannot renew.
CREATE OR REPLACE FUNCTION public.renew_email_preparation(p_message uuid,p_token uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_messages SET lease_until=now()+interval '90 seconds'
 WHERE message_id=p_message AND lease_token=p_token AND workflow_state='preparing' AND lease_until>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.renew_email_preparation(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.renew_email_preparation(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.prepare_email(p_message uuid,p_token uuid,p_prepared jsonb,p_post_action jsonb DEFAULT '{}') RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.notification_center_email_profiles p JOIN public.email_messages m ON m.recipient_user=p.recipient
 WHERE m.message_id=p_message AND m.message_kind='admin_notification_digest' FOR UPDATE OF p;

 IF octet_length(p_prepared::text)>(SELECT (x->>'base_limit')::bigint
  FROM jsonb_array_elements(public.abuse_effective_rules_v1('email.payload',NULL,NULL)->'rules') x LIMIT 1) THEN
  RAISE configuration_limit_exceeded USING MESSAGE='email_payload_too_large'; END IF;
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_prepared),
 prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_prepared::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now()),
 tracking_policy=CASE WHEN prepared IS NULL AND message_kind LIKE 'order_%' AND p_post_action->>'tracking_policy'='engagement' THEN 'engagement' ELSE tracking_policy END,
 post_action=CASE WHEN prepared IS NULL THEN post_action||p_post_action ELSE post_action END
 WHERE message_id=p_message AND lease_token=p_token AND lease_until>now() AND workflow_state='preparing'
 AND (prepared IS NULL OR prepared=p_prepared);
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=p_message),true);
END $$;

CREATE OR REPLACE FUNCTION public.begin_email_send(p_attempt uuid,p_token uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_attempt public.email_attempts; v_row public.email_messages; v_cap public.email_capacity; v_rate numeric; v_daily numeric; v_used numeric; v_detail text; v_retry integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.notification_center_email_profiles p JOIN public.email_messages m ON m.recipient_user=p.recipient
 JOIN public.email_attempts a ON a.message_id=m.message_id WHERE a.attempt_id=p_attempt AND m.message_kind='admin_notification_digest' FOR UPDATE OF p;

 PERFORM public.payment_policy_fence_internal(m.organization) FROM public.email_messages m
 JOIN public.email_attempts a ON a.message_id=m.message_id WHERE a.attempt_id=p_attempt AND m.order_id IS NOT NULL;
 PERFORM 1 FROM public.forms f JOIN public.sale_opening_campaigns c ON c.form_id=f.id
  JOIN public.email_messages m ON m.data->>'campaign_id'=c.id::text
  JOIN public.email_attempts a ON a.message_id=m.message_id
  WHERE a.attempt_id=p_attempt AND m.message_kind IN ('sale_opening_opened') FOR UPDATE OF f;
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id;
 IF v_row.order_id IS NOT NULL THEN PERFORM 1 FROM eshop.orders WHERE id=v_row.order_id FOR UPDATE; END IF;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id FOR UPDATE;
 IF v_attempt.lease_token IS DISTINCT FROM p_token OR v_row.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF v_attempt.state<>'preparing' THEN RETURN jsonb_build_object('disposition','replay','state',v_attempt.state); END IF;
 IF v_row.workflow_state<>'preparing' OR v_row.lease_until<=now() OR v_row.prepared IS NULL THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF NOT public.email_intent_valid(v_row) OR EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN
  UPDATE public.email_messages SET last_error=CASE WHEN v_row.message_kind='admin_notification_digest' AND v_row.recipient IS DISTINCT FROM public.get_user_delivery_email(v_row.recipient_user) THEN 'destination_changed' ELSE 'intent_invalid' END,workflow_state=CASE WHEN EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN 'suppressed' ELSE 'cancelled' END WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now() WHERE attempt_id=p_attempt;
  PERFORM public.notification_center_email_internal(v_row.message_id);
  RETURN jsonb_build_object('disposition','cancelled');
 END IF;
 -- A partial acceptance can change a queued offer after its rendered snapshot
 -- was cached. Re-render within this same queue before granting a send permit.
 IF v_row.message_kind='waitlist_offer' AND
  (v_row.post_action->>'waitlist_pending_count')::bigint IS DISTINCT FROM
  (SELECT count(*) FROM eshop.waitlist_offer_slots
   WHERE offer_id=(v_row.data->>'offer_id')::uuid AND outcome='pending') THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=now(),
   prepared=NULL,prepared_hash=NULL,prepared_at=NULL,
   post_action=post_action-'waitlist_pending_count',lease_token=NULL,lease_until=NULL,
   last_error='offer_snapshot_changed' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),
   error_code='offer_snapshot_changed' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 -- Only unstarted provider attempts can discard a stale Wallet snapshot.
 IF v_row.message_kind='order_tickets' AND v_row.post_action->>'wallet_fingerprint'
  IS DISTINCT FROM public.ticket_wallet_fingerprint(v_row.occasion) THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=now(),prepared=NULL,prepared_hash=NULL,prepared_at=NULL,
   post_action=post_action-'wallet_fingerprint',lease_token=NULL,lease_until=NULL,last_error='wallet_snapshot_changed' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='wallet_snapshot_changed' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 BEGIN
 v_rate:=CASE WHEN v_cap.shared_account THEN least(v_cap.max_rate*0.8,v_cap.allocated_rate) ELSE v_cap.max_rate*0.8 END*v_cap.rate_factor;
 v_daily:=CASE WHEN v_cap.shared_account THEN least(v_cap.daily_quota,v_cap.allocated_daily) ELSE v_cap.daily_quota END*0.9;
 -- Count all local starts since snapshot plus provider's rolling usage; conservative during drift.
 SELECT count(*) INTO v_used FROM public.email_attempts WHERE began_at>now()-interval '24 hours' AND (began_at>v_cap.quota_at OR state IN ('sending','unknown')) AND state IN ('sending','accepted','unknown');
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_rate IS NULL OR v_rate<=0 OR v_daily IS NULL
 OR (v_cap.shared_account AND (v_cap.allocated_rate IS NULL OR v_cap.allocated_daily IS NULL)) OR v_cap.provider_sent_24h+v_used>=v_daily
 OR v_cap.next_send_at>now() OR v_cap.circuit_until>now()
 OR (v_cap.provider_outage_streak>0 AND v_cap.probe_until>now())
 OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='sending' AND lease_until>now())>=v_cap.max_sending THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=greatest(now()+interval '1 second',coalesce(v_cap.next_send_at,now()),coalesce(v_cap.circuit_until,now()),coalesce(v_cap.probe_until,now())),lease_token=NULL,lease_until=NULL,last_error='capacity_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='capacity_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 -- Recipient admission at enqueue does not protect against many future intents
 -- converging on one date. Meter the actual fenced send, with separate essential
 -- classes so ordinary bulk cannot consume Auth or accepted-order capacity.
 BEGIN
  PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.send.'||v_row.admission_class,v_row.unit,v_row.organization),
   jsonb_build_object('recipient',CASE WHEN v_row.admission_class='notification' THEN v_row.recipient_user::text ELSE public.abuse_recipient_key_v1(v_row.recipient) END,'global','all'));
 EXCEPTION WHEN SQLSTATE 'PT429' THEN
  GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
  v_retry:=greatest(coalesce((v_detail::jsonb->>'retryAfterSeconds')::integer,60),1);
  UPDATE public.email_messages SET workflow_state='pending',target_time=now()+make_interval(secs=>v_retry),lease_token=NULL,lease_until=NULL,last_error='recipient_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='recipient_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END;
 UPDATE public.email_capacity SET next_send_at=clock_timestamp()+make_interval(secs=>(1/v_rate)::double precision),
 probe_until=CASE WHEN provider_outage_streak>0 THEN now()+interval '90 seconds' ELSE NULL END,
 probe_attempt=CASE WHEN provider_outage_streak>0 THEN p_attempt ELSE NULL END WHERE singleton;
 IF v_row.message_kind='admin_notification_digest' THEN
  WITH context AS MATERIALIZED(SELECT public.notification_center_email_context_internal(v_row.notification_dispatch_id,v_row.recipient_user) value),
  decision AS MATERIALIZED(SELECT CASE
   WHEN value IS NULL OR jsonb_array_length(value->'items')=0 THEN 'cancelled'
   WHEN value->>'address' IS DISTINCT FROM v_row.recipient THEN 'destination_changed'
   WHEN value->>'fingerprint' IS DISTINCT FROM v_row.post_action->>'notification_fingerprint' THEN 'snapshot_changed'
   ELSE 'send' END action FROM context),
  attempt AS(UPDATE public.email_attempts SET state=CASE WHEN decision.action='send' THEN 'sending' ELSE 'cancelled' END,
   began_at=CASE WHEN decision.action='send' THEN now() END,
   error_code=CASE WHEN decision.action<>'send' THEN decision.action END FROM decision WHERE attempt_id=p_attempt)
  UPDATE public.email_messages SET workflow_state=CASE WHEN decision.action='send' THEN 'sending' WHEN decision.action='snapshot_changed' THEN 'pending' ELSE 'cancelled' END,
   prepared=CASE WHEN decision.action='snapshot_changed' THEN NULL ELSE prepared END,
   prepared_hash=CASE WHEN decision.action='snapshot_changed' THEN NULL ELSE prepared_hash END,
   prepared_at=CASE WHEN decision.action='snapshot_changed' THEN NULL ELSE prepared_at END,
   post_action=CASE WHEN decision.action='snapshot_changed' THEN post_action-'notification_fingerprint' ELSE post_action END,
   attempt_count=attempt_count+(decision.action='send')::integer,
   last_error=CASE WHEN decision.action<>'send' THEN decision.action END,
   lease_token=CASE WHEN decision.action='send' THEN lease_token END,
   lease_until=CASE WHEN decision.action='send' THEN lease_until END
   FROM decision WHERE id=v_row.id RETURNING last_error INTO v_detail;
  IF v_detail IS NOT NULL THEN
   RAISE SQLSTATE 'PN001' USING MESSAGE=v_detail;
  END IF;
 ELSE
  UPDATE public.email_attempts SET state='sending',began_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state='sending',attempt_count=attempt_count+1 WHERE id=v_row.id;
 END IF;
 RETURN jsonb_build_object('disposition','send','message',to_jsonb(v_row));
 EXCEPTION WHEN SQLSTATE 'PN001' THEN
  -- Metering, capacity reservation and final state changes roll back together.
  GET STACKED DIAGNOSTICS v_detail=MESSAGE_TEXT;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code=v_detail WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state=CASE WHEN v_detail='snapshot_changed' THEN 'pending' ELSE 'cancelled' END,
   target_time=now(),prepared=CASE WHEN v_detail='snapshot_changed' THEN NULL ELSE prepared END,
   prepared_hash=CASE WHEN v_detail='snapshot_changed' THEN NULL ELSE prepared_hash END,
   prepared_at=CASE WHEN v_detail='snapshot_changed' THEN NULL ELSE prepared_at END,
   post_action=post_action-'notification_fingerprint',lease_token=NULL,lease_until=NULL,last_error=v_detail WHERE id=v_row.id;
  RETURN jsonb_build_object('disposition',CASE WHEN v_detail='snapshot_changed' THEN 'deferred' ELSE 'cancelled' END);
 END;

END $$;

CREATE OR REPLACE FUNCTION public.finish_email_attempt(p_attempt uuid,p_token uuid,p_outcome text,p_provider_id text DEFAULT NULL,p_error text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_a public.email_attempts; v_m public.email_messages; v_delay integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_a FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_m FROM public.email_messages WHERE message_id=v_a.message_id FOR UPDATE;
 IF v_a.lease_token IS DISTINCT FROM p_token OR v_m.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_completion'; END IF;
 IF v_a.state='accepted' THEN RETURN; END IF;
 IF p_outcome NOT IN ('accepted','retry','dead','unknown','preparation_failed') THEN RAISE EXCEPTION 'invalid_email_outcome'; END IF;
 IF p_outcome='accepted' AND (p_provider_id IS NULL OR v_a.state NOT IN ('sending','unknown')) THEN RAISE EXCEPTION 'invalid_email_acceptance'; END IF;
 IF p_outcome IN ('retry','dead','unknown') AND v_a.state<>'sending' THEN RAISE EXCEPTION 'invalid_email_failure'; END IF;
 IF p_outcome='preparation_failed' AND v_a.state<>'preparing' THEN RAISE EXCEPTION 'invalid_email_preparation_failure'; END IF;
 IF p_outcome='accepted' THEN
  UPDATE public.email_capacity SET provider_outage_streak=0,probe_until=NULL,probe_attempt=NULL,circuit_until=NULL WHERE probe_attempt=p_attempt;
  UPDATE public.email_attempts SET state='accepted',provider_message_id=p_provider_id,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state='accepted',provider_message_id=p_provider_id,accepted_at=coalesce(accepted_at,now()),last_error=NULL WHERE id=v_m.id;
 ELSE
  v_delay:=(ARRAY[15,60,300,1800,7200])[least(greatest(v_m.attempt_count,1),5)];
  UPDATE public.email_attempts SET state=CASE WHEN p_outcome='unknown' THEN 'unknown' ELSE 'not_accepted' END,error_code=p_error,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state=CASE WHEN p_outcome='unknown' THEN 'unknown' WHEN p_outcome='dead' OR attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END>=8 THEN 'dead' ELSE 'retry_wait' END,
   attempt_count=attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END,
   target_time=now()+make_interval(secs=>v_delay*(0.8+random()*0.4)),last_error=left(p_error,100),lease_until=NULL WHERE id=v_m.id;
  IF p_outcome='unknown' THEN UPDATE public.email_capacity SET provider_outage_streak=least(provider_outage_streak+1,10),
   probe_until=NULL,probe_attempt=NULL,circuit_until=now()+make_interval(secs=>least(300,30*power(2,least(provider_outage_streak,4)))::double precision) WHERE singleton; END IF;
  PERFORM public.notification_center_email_internal(v_m.message_id);
  IF p_error='throttled' THEN UPDATE public.email_capacity SET rate_factor=greatest(rate_factor/2,0.01),probe_until=NULL,probe_attempt=NULL,circuit_until=now()+interval '15 seconds' WHERE singleton; END IF;
 END IF;
 PERFORM public.reconcile_email_events();
 PERFORM public.notification_center_email_internal(v_m.message_id);
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_email_events() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_event record;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 WITH matched AS (UPDATE public.email_delivery_events e SET message_id=m.message_id FROM public.email_messages m
 WHERE e.message_id IS NULL AND lower(e.recipient)=lower(m.recipient)
 AND (m.provider_message_id=e.provider_message_id OR EXISTS(SELECT 1 FROM public.email_attempts a WHERE a.message_id=m.message_id AND a.attempt_id=e.attempt_id AND a.state IN ('sending','unknown','accepted'))) RETURNING e.message_id)
 UPDATE public.email_messages m SET feedback_pending=true WHERE m.message_id IN (SELECT message_id FROM matched);
 FOR v_event IN SELECT message_id,min(provider_time) FILTER(WHERE event_type='delivery') delivery,
 min(provider_time) FILTER(WHERE event_type='bounce') bounce,min(provider_time) FILTER(WHERE event_type='complaint') complaint,
 min(provider_time) FILTER(WHERE event_type='open') opened,min(provider_time) FILTER(WHERE event_type='click') clicked,
 min(provider_time) FILTER(WHERE event_type IN ('send','delivery','open','click','bounce','complaint','delay')) accepted,
 min(provider_message_id) provider_id,max(event_type) FILTER(WHERE event_type IN ('reject','rendering_failure','delay')) failure
 FROM public.email_delivery_events WHERE message_id IN (SELECT message_id FROM public.email_messages WHERE workflow_state IN ('sending','unknown') OR feedback_pending) GROUP BY message_id LOOP
  UPDATE public.email_messages SET delivered_at=least(delivered_at,v_event.delivery),bounced_at=least(bounced_at,v_event.bounce),complained_at=least(complained_at,v_event.complaint),
   opened_at=CASE WHEN tracking_policy<>'disabled' THEN least(opened_at,v_event.opened) ELSE NULL END,
   clicked_at=CASE WHEN tracking_policy='engagement' THEN least(clicked_at,v_event.clicked) ELSE NULL END,provider_failure=v_event.failure,
   accepted_at=coalesce(accepted_at,v_event.accepted),provider_message_id=coalesce(provider_message_id,v_event.provider_id),
   workflow_state=CASE WHEN v_event.accepted IS NOT NULL AND workflow_state IN ('sending','unknown') THEN 'accepted' ELSE workflow_state END,feedback_pending=false
  WHERE message_id=v_event.message_id;
  PERFORM public.notification_center_email_internal(v_event.message_id);
  UPDATE public.email_attempts SET state='accepted',provider_message_id=v_event.provider_id,finished_at=coalesce(finished_at,now())
  WHERE message_id=v_event.message_id AND state IN ('sending','unknown') AND v_event.accepted IS NOT NULL;
 INSERT INTO public.email_suppressions(recipient,reason)
 SELECT lower(recipient),CASE WHEN bool_or(event_type='complaint') THEN 'complaint' ELSE 'hard_bounce' END
 FROM public.email_delivery_events WHERE message_id=v_event.message_id AND (event_type='complaint' OR (event_type='bounce' AND hard_bounce))
 GROUP BY lower(recipient)
 ON CONFLICT(recipient) DO UPDATE SET reason=CASE WHEN email_suppressions.reason='complaint' THEN 'complaint' ELSE excluded.reason END;
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.record_email_events(p_events jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF jsonb_typeof(p_events)<>'array' OR jsonb_array_length(p_events)>100 THEN RAISE EXCEPTION 'invalid_event_batch'; END IF;
 INSERT INTO public.email_delivery_events(event_key,provider_message_id,attempt_id,recipient,event_type,provider_time,hard_bounce,invalid_recipient)
 SELECT e->>'key',e->>'provider_id',(e->>'attempt_id')::uuid,e->>'recipient',e->>'type',(e->>'time')::timestamptz,coalesce((e->>'hard_bounce')::boolean,false),coalesce((e->>'invalid_recipient')::boolean,false)
 FROM jsonb_array_elements(p_events) e ON CONFLICT(event_key) DO NOTHING;
 PERFORM public.reconcile_email_events();
END $$;
REVOKE ALL ON FUNCTION public.record_email_events(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_email_events(jsonb) TO service_role;
CREATE OR REPLACE FUNCTION public.record_email_event(p_event jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.record_email_events(jsonb_build_array(p_event));
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_prepared_email(p_kind text,p_context jsonb,p_recipient text,p_sealed jsonb,p_dedupe text,p_content_hash text,p_code text,p_expires timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb; v_m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 -- Use stable digest as canonical data; nonce/ciphertext is not part of dedupe equality.
 v_result:=public.enqueue_email(p_kind,p_context,p_recipient,jsonb_build_object('content_hash',p_content_hash),p_dedupe,p_code,now(),p_expires);
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_sealed),prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_sealed::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now())
 WHERE message_id=(v_result->>'message_id')::uuid AND workflow_state IN ('pending','blocked','preparing','retry_wait');
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid),true);
 RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.get_internal_email_state(p_message uuid) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT workflow_state FROM public.email_messages WHERE message_id=p_message);
END $$;

CREATE OR REPLACE FUNCTION public.refresh_email_quota(p_account text,p_region text,p_rate numeric,p_daily numeric,p_used numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM public.email_capacity FOR UPDATE;
 IF c.account_id IS DISTINCT FROM p_account OR c.region IS DISTINCT FROM p_region OR p_rate IS NULL OR p_daily IS NULL OR p_used IS NULL OR p_rate<=0 OR p_daily<=0 OR p_used<0 THEN RAISE EXCEPTION 'email_quota_identity_mismatch'; END IF;
 UPDATE public.email_capacity SET max_rate=p_rate,daily_quota=p_daily,provider_sent_24h=p_used,quota_at=now(),wake_error=NULL,rate_factor=least(1,rate_factor+0.05) WHERE singleton;
END $$;

CREATE OR REPLACE FUNCTION public.invalidate_email_quota(p_reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();UPDATE public.email_capacity SET quota_at=NULL,wake_error=left(p_reason,100) WHERE singleton;END $$;
REVOKE ALL ON FUNCTION public.invalidate_email_quota(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_email_quota(text) TO service_role;

-- Explicit internal ACLs, including the invoker-only domain helpers.
DO $$ DECLARE p record; BEGIN
 FOR p IN SELECT oid::regprocedure signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('wake_email_worker','enqueue_email','email_intent_valid','claim_email','prepare_email','begin_email_send','finish_email_attempt','reconcile_email_events','record_email_event',
  'enqueue_prepared_email','get_internal_email_state','refresh_email_quota','enqueue_order_email','enqueue_paid_order_tickets','cancel_order_email_intents','apply_email_post_actions') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',p.signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',p.signature);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.get_next_email_due() RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();RETURN (SELECT min(target_time) FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait'));END $$;
REVOKE ALL ON FUNCTION public.get_next_email_due() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_next_email_due() TO service_role;

CREATE OR REPLACE FUNCTION public.reserve_email_quota_refresh() RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_capacity SET quota_refresh_until=now()+interval '30 seconds' WHERE (quota_at IS NULL OR quota_at<now()-interval '5 minutes') AND (quota_refresh_until IS NULL OR quota_refresh_until<now());
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.reserve_email_quota_refresh() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_email_quota_refresh() TO service_role;
CREATE OR REPLACE FUNCTION public.recover_email_delivery() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_messages SET workflow_state='expired',lease_token=NULL,lease_until=NULL
 WHERE expires_at<now() AND workflow_state IN ('pending','retry_wait','blocked','preparing');
 -- Erase sensitive body after terminal state/expiry; retain correlation and dedupe tombstones.
 UPDATE public.email_messages SET prepared=NULL,data=data-'ciphertext'
 WHERE message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','deletion_confirm','deletion_complete','sale_opening_opened')
 AND (workflow_state IN ('accepted','dead','cancelled','suppressed','expired') OR expires_at<now()) AND prepared IS NOT NULL;
 UPDATE public.email_messages SET prepared=NULL,data=jsonb_build_object('command_id',data->'command_id')
 WHERE created_at<now()-interval '30 days' AND workflow_state IN ('accepted','dead','cancelled','suppressed','expired') AND prepared IS NOT NULL;
 PERFORM public.notification_center_prepared_invalidate(e.id) FROM public.email_messages m JOIN public.notification_center_events e
  ON e.organization=m.organization AND e.kind='email_problem' AND e.data->>'messageId'=m.message_id::text
  WHERE m.message_kind='sale_opening_opened' AND m.expires_at<now()-interval '30 days' AND m.workflow_state NOT IN ('sending','unknown') AND m.recipient IS NOT NULL;
 UPDATE public.email_messages SET recipient=NULL,prepared=NULL,data='{}'
 WHERE message_kind IN ('sale_opening_opened') AND expires_at<now()-interval '30 days'
 AND workflow_state NOT IN ('sending','unknown');
 DELETE FROM public.email_confirmation_receipts WHERE expires_at<now();
 DELETE FROM public.email_delivery_events WHERE received_at<now()-interval '90 days';
 PERFORM public.apply_email_post_actions();
 PERFORM public.reconcile_email_events();
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.recover_email_delivery() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_delivery() TO service_role;

CREATE OR REPLACE FUNCTION public.reconcile_unknown_email(p_message uuid,p_decision text,p_evidence text,p_provider_id text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF p_evidence IS NULL OR length(p_evidence)<10 OR p_decision NOT IN ('accepted','known_not_accepted','cancelled') THEN RAISE EXCEPTION 'reconciliation_evidence_required'; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message FOR UPDATE;
 IF m.workflow_state<>'unknown' THEN RAISE EXCEPTION 'email_not_unknown'; END IF;
 IF p_decision='accepted' AND p_provider_id IS NULL THEN RAISE EXCEPTION 'provider_receipt_required'; END IF;
 UPDATE public.email_messages SET workflow_state=CASE p_decision WHEN 'accepted' THEN 'accepted' WHEN 'known_not_accepted' THEN 'pending' ELSE 'cancelled' END,
 accepted_at=CASE WHEN p_decision='accepted' THEN now() ELSE accepted_at END,provider_message_id=coalesce(p_provider_id,provider_message_id),
 target_time=now(),lease_token=NULL,lease_until=NULL,post_action=post_action||jsonb_build_object('reconciliation',jsonb_build_object('decision',p_decision,'evidence',left(p_evidence,256),'at',now()))
 WHERE message_id=p_message;
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) TO service_role;


-- SOURCE: emails/email_reporting.sql
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

-- Current issues are explicit provenance chains, independent of historical counts.
-- This invoker helper is only reachable through authorized reporting functions.
-- Batched provenance chains retain order and message-kind boundaries. Events
-- are aggregated once, including failures needed to judge superseding delivery.
CREATE OR REPLACE FUNCTION public.order_email_current_issues_bulk(p_orders bigint[])
RETURNS TABLE(order_id bigint,issues jsonb)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN QUERY

 WITH RECURSIVE selected_orders AS MATERIALIZED (
  SELECT o.* FROM eshop.orders o WHERE o.id=ANY(p_orders) AND o.state<>'storno'
 ), scoped_messages AS MATERIALIZED (
  SELECT m.* FROM public.email_messages m JOIN selected_orders o ON o.id=m.order_id AND o.occasion=m.occasion
  JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=m.organization
 ), event_times AS MATERIALIZED (
  SELECT e.message_id,max(e.provider_time) FILTER(WHERE e.event_type='bounce') bounce,
   max(e.provider_time) FILTER(WHERE e.event_type='delivery') delivery,
   max(e.provider_time) FILTER(WHERE e.event_type IN ('bounce','complaint','reject','rendering_failure')) failure
  FROM public.email_delivery_events e JOIN scoped_messages m ON m.message_id=e.message_id GROUP BY e.message_id
 ), messages AS MATERIALIZED (
  SELECT m.*,CASE WHEN m.complained_at IS NULL AND m.last_error IS DISTINCT FROM 'post_action_failed'
   AND coalesce(m.provider_failure,'') NOT IN ('reject','rendering_failure')
   AND greatest(m.bounced_at,events.bounce) IS NOT NULL
   AND greatest(m.delivered_at,events.delivery)>greatest(m.bounced_at,events.bounce)
   THEN 'delivery' ELSE public.email_reporting_state(m::public.email_messages) END rs,events.failure FROM scoped_messages m
  LEFT JOIN event_times events ON events.message_id=m.message_id),
 problem_orders AS MATERIALIZED (
  SELECT DISTINCT m.order_id FROM messages m
  WHERE m.rs IN ('bounce','complaint','reject','rendering_failure','dead','suppressed','unknown','retry_wait','delay','blocked','sending','post_action_failed')
   OR (m.message_kind IN ('order_confirmation','order_tickets') AND m.workflow_state IN ('pending','preparing') AND m.target_time<=now())
 ), chain AS (
  SELECT m.order_id,m.message_id root,m.message_id leaf,ARRAY[m.message_id] path FROM messages m JOIN problem_orders problem ON problem.order_id=m.order_id
  WHERE NOT EXISTS(SELECT 1 FROM messages parent WHERE parent.message_id::text=m.data->>'repair_source_message_id' AND parent.message_kind=m.message_kind AND parent.order_id=m.order_id)
  UNION ALL
  SELECT c.order_id,c.root,m.message_id,c.path||m.message_id FROM chain c JOIN messages parent ON parent.message_id=c.leaf
  JOIN messages m ON m.data->>'repair_source_message_id'=c.leaf::text AND m.message_kind=parent.message_kind AND m.order_id=c.order_id
  WHERE NOT m.message_id=ANY(c.path)),
 leaves AS (SELECT DISTINCT ON (c.order_id,c.root) * FROM chain c ORDER BY c.order_id,c.root,cardinality(c.path) DESC,c.leaf),
 issues AS (
  SELECT c.order_id,root.message_id source_message_id,leaf.message_id,root.message_kind kind,root.recipient original_recipient,
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
   (root.message_kind<>public.order_checkout_email_kind_internal(o.id)) obsolete
  FROM leaves c JOIN messages root ON root.message_id=c.root JOIN messages leaf ON leaf.message_id=c.leaf
  JOIN selected_orders o ON o.id=c.order_id
  WHERE (EXISTS(SELECT 1 FROM messages m WHERE m.message_id=ANY(c.path)
    AND (m.rs IN ('bounce','complaint','reject','rendering_failure','dead','suppressed','unknown','retry_wait','delay','blocked','sending','post_action_failed')
     OR (m.message_kind IN ('order_confirmation','order_tickets') AND m.workflow_state IN ('pending','preparing') AND m.target_time<=now()))))
   -- Delivered current tickets supersede the obsolete checkout confirmation,
   -- even though confirmation and ticket repairs intentionally have separate chains.
   -- Acceptance/open tracking alone, stale snapshots and unrelated message kinds
   -- must never clear an actionable delivery failure.
   AND NOT (root.message_kind='order_confirmation' AND o.state IN ('paid','sent')
    AND EXISTS(SELECT 1 FROM messages tickets WHERE tickets.order_id=c.order_id AND tickets.message_kind='order_tickets'
     AND tickets.rs IN ('delivery','open','click') AND tickets.delivered_at IS NOT NULL
     AND tickets.recipient=o.data->>'email' AND tickets.source_version=o.email_payment_version
     AND (tickets.data->>'repair_payment_fingerprint' IS NULL
      OR tickets.data->>'repair_payment_fingerprint'=public.order_email_payment_fingerprint(o.id))
     AND tickets.delivered_at>greatest(leaf.created_at,leaf.bounced_at,leaf.complained_at,
      leaf.failure)))
   AND NOT (leaf.delivered_at IS NOT NULL AND leaf.rs IN ('delivery','open','click')
    AND leaf.recipient=o.data->>'email' AND leaf.source_version=o.email_payment_version
    AND (leaf.data->>'repair_payment_fingerprint' IS NULL OR leaf.data->>'repair_payment_fingerprint'=public.order_email_payment_fingerprint(o.id))))
 SELECT o.id::bigint,coalesce(jsonb_agg(to_jsonb(i)-'order_id' ORDER BY i.source_message_id)
  FILTER(WHERE i.source_message_id IS NOT NULL),'[]'::jsonb)
 FROM eshop.orders o LEFT JOIN issues i ON i.order_id=o.id WHERE o.id=ANY(p_orders) GROUP BY o.id;

END;
$$;
REVOKE ALL ON FUNCTION public.order_email_current_issues_bulk(bigint[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_email_current_issues_bulk(bigint[]) TO service_role;

CREATE OR REPLACE FUNCTION public.order_email_current_issues(p_order bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN coalesce((SELECT b.issues FROM public.order_email_current_issues_bulk(ARRAY[p_order]) b),'[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.order_email_current_issues(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_email_current_issues(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.get_order_email_summaries(p_occasion bigint,p_orders bigint[]) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_summary jsonb;
BEGIN
 IF NOT coalesce(public.can_read_orders(p_occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=ANY(p_orders) AND occasion<>p_occasion) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 WITH selected_orders AS MATERIALIZED (
  SELECT o.id FROM eshop.orders o WHERE o.id=ANY(p_orders) AND o.occasion=p_occasion
 ), messages AS MATERIALIZED (
  SELECT m.*,public.email_reporting_state(m) reporting_state FROM public.email_messages m
  WHERE m.order_id=ANY(p_orders) AND m.occasion=p_occasion AND m.workflow_state NOT IN ('cancelled','expired')
 ), current_issues AS MATERIALIZED (
  SELECT b.order_id,b.issues FROM public.order_email_current_issues_bulk(p_orders) b
 ), ranked AS MATERIALIZED (
  SELECT m.*,i.issues,CASE WHEN m.reporting_state IN ('complaint','bounce','reject','rendering_failure','unknown','dead','suppressed','retry_wait','post_action_failed')
   AND EXISTS(SELECT 1 FROM jsonb_array_elements(i.issues) issue WHERE issue->>'message_id'=m.message_id::text) THEN 0
   WHEN m.workflow_state IN ('pending','preparing','sending','blocked') AND m.target_time<=now() THEN 1
   WHEN m.workflow_state='accepted' AND m.reporting_state NOT IN ('complaint','bounce','reject','rendering_failure') THEN 2 ELSE 3 END rank
  FROM messages m JOIN current_issues i USING(order_id)
 ), histories AS MATERIALIZED (
  SELECT n.order_id,count(*) FILTER(WHERE n.rank=0) attention_count,
   jsonb_agg(jsonb_build_object('kind',n.message_kind,'state',n.reporting_state,'at',coalesce(n.delivered_at,n.accepted_at,n.created_at)) ORDER BY n.created_at DESC) messages
  FROM ranked n GROUP BY n.order_id
 ), latest AS (
  SELECT DISTINCT ON (r.order_id) * FROM ranked r ORDER BY r.order_id,r.rank,r.created_at DESC,r.id DESC
 )
 SELECT coalesce(jsonb_object_agg(o.id,CASE WHEN r.order_id IS NULL
  THEN jsonb_build_object('state','unavailable','messages','[]'::jsonb,'current_issues',i.issues,'loaded_at',now())
  ELSE jsonb_build_object('state',r.reporting_state,'kind',r.message_kind,'recipient',r.recipient,'message_id',r.message_id,
   'at',coalesce(r.clicked_at,r.opened_at,r.delivered_at,r.accepted_at,r.created_at),'current_issues',i.issues,
   'scheduled_at',r.target_time,'attention_count',h.attention_count,'loaded_at',now(),'messages',h.messages) END),'{}')
 INTO v_summary FROM selected_orders o JOIN current_issues i ON i.order_id=o.id
 LEFT JOIN latest r ON r.order_id=o.id LEFT JOIN histories h ON h.order_id=o.id;
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
 AND coalesce(public.can_read_orders(p_occasion),false)
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
 SELECT id,message_id,message_kind,recipient,order_id,(SELECT o.order_symbol FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=m.order_id AND oc.organization=m.organization AND o.occasion=m.occasion) order_symbol,created_at,accepted_at,delivered_at,bounced_at,complained_at,opened_at,clicked_at,
 public.email_reporting_state(m) state,tracking_policy,post_action_state,last_error FROM public.email_messages m
 WHERE organization=v_org AND message_kind<>'admin_notification_digest' AND (p_occasion IS NULL OR occasion=p_occasion OR (p_user IS NOT NULL AND occasion IS NULL))
 AND (p_user IS NULL OR recipient_user=p_user) AND (p_since IS NULL OR created_at>=p_since) AND (p_before IS NULL OR id<p_before) AND (p_order IS NULL OR order_id=p_order)
 AND (m.message_kind NOT IN ('sale_opening_confirmation','sale_opening_opened') OR public.can_read_sale_opening_subscribers(m.occasion))
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
 IF m.message_kind='admin_notification_digest' THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 IF m.message_id IS NULL THEN RAISE EXCEPTION 'email_detail_not_available'; END IF;
 IF NOT (CASE WHEN m.message_kind IN ('sale_opening_confirmation','sale_opening_opened') THEN public.can_read_sale_opening_subscribers(m.occasion) ELSE coalesce(public.email_report_allowed(m.organization,m.occasion),false) END) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 RETURN jsonb_build_object('message',jsonb_build_object('id',m.message_id,'kind',m.message_kind,'recipient',m.recipient,'created_at',m.created_at,'state',public.email_reporting_state(m),'tracking_policy',m.tracking_policy,'opened_at',m.opened_at,'clicked_at',m.clicked_at,'post_action',m.post_action_state,'last_error',m.last_error,'provider_id',m.provider_message_id,'requested_by',m.data->>'requested_by'),
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
 'feedback_overdue',count(*) FILTER(WHERE accepted_at BETWEEN now()-interval '1 day' AND now()-interval '30 minutes' AND NOT EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=email_messages.message_id))) FROM public.email_messages WHERE organization=v_org AND message_kind<>'admin_notification_digest' AND (p_occasion IS NULL OR occasion=p_occasion));
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_overview(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_overview(bigint,bigint) TO authenticated,service_role;


-- SOURCE: notification_center/email.sql
-- Reuse the order reporting authority: successful repair chains and delivered
-- current tickets can resolve a different, older message's incident.
CREATE OR REPLACE FUNCTION public.notification_center_reconcile_order_email_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE issues jsonb; event_id uuid;
BEGIN
 IF p_order IS NULL THEN RETURN; END IF;
 issues:=public.order_email_current_issues(p_order);
 FOR event_id IN
  SELECT e.id FROM public.email_messages m
  JOIN eshop.orders o ON o.id=m.order_id AND o.occasion=m.occasion AND o.state<>'storno'
  JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=m.organization
  JOIN public.notification_center_events e ON e.organization=m.organization AND e.source_key='email:'||m.message_id
  WHERE m.order_id=p_order AND m.message_kind IN ('order_confirmation','order_tickets')
   AND e.kind='email_problem' AND e.status='active'
   AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(issues) issue
    WHERE issue->>'source_message_id'=m.message_id::text OR issue->>'message_id'=m.message_id::text)
 LOOP
  PERFORM public.notification_center_prepared_invalidate(event_id);
  UPDATE public.notification_center_events SET status='recovered' WHERE id=event_id;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_reconcile_order_email_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.notification_center_email_internal(p_message uuid,p_at timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; a public.notification_center_organizations; old public.notification_center_source_state;
 reason text; fact_at timestamptz; ev uuid; seen jsonb; key text:='email:'||p_message; due_at timestamptz;
BEGIN
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF m.message_kind='admin_notification_digest' THEN RETURN; END IF;
 IF NOT FOUND THEN RETURN; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-organization:'||m.organization,0));
 p_at:=coalesce(p_at,clock_timestamp());
 SELECT * INTO a FROM public.notification_center_organizations WHERE organization=m.organization FOR SHARE;
 IF NOT FOUND THEN RETURN; END IF;
 -- Cancellation retires recovery of the original order messages. Provider
 -- callbacks can arrive later; preserve their audit facts without re-alerting.
 -- A failed cancellation notice is a separate, still relevant incident.
 IF m.order_id IS NOT NULL AND m.message_kind<>'order_storno' AND EXISTS(
  SELECT 1 FROM eshop.orders o WHERE o.id=m.order_id AND o.occasion=m.occasion AND o.state='storno') THEN
  PERFORM public.notification_center_prepared_invalidate(ev.id) FROM public.notification_center_events ev WHERE ev.organization=m.organization AND ev.source_key=key AND ev.status<>'recovered';
  UPDATE public.notification_center_events SET status='recovered'
   WHERE organization=m.organization AND source_key=key AND kind='email_problem';
  RETURN;
 END IF;
 reason:=public.email_reporting_state(m);
 -- A failed preparation/send is an incident now, even while the queue retries.
 -- Reserve the grace period for ordinary waiting and brief rate limiting.
 IF reason IN ('retry_wait','unknown') AND nullif(m.last_error,'') IS NOT NULL
    AND m.last_error<>'throttled' AND (m.expires_at IS NULL OR m.expires_at>p_at) THEN
  reason:=CASE WHEN m.last_error='preparation_failed' THEN 'rendering_failure' ELSE 'delayed' END;
 END IF;
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
 IF reason IS NOT NULL AND coalesce(fact_at,p_at)>=a.initialized_at AND NOT seen ? reason THEN
  ev:=public.notification_center_publish_internal(m.organization,m.occasion,'email_problem',key,
    jsonb_build_object('messageId',m.message_id,'messageKind',m.message_kind,'reason',reason),NULL,coalesce(fact_at,p_at));
  IF ev IS NOT NULL AND old.state->>'eventId'=ev::text THEN
   PERFORM public.notification_center_prepared_invalidate((old.state->>'eventId')::uuid);
   UPDATE public.notification_center_events SET attention_revision=attention_revision+1,status='active',
    data=data||jsonb_build_object('reason',reason) WHERE id=(old.state->>'eventId')::uuid;
   PERFORM public.notification_center_capture_recipients_internal((old.state->>'eventId')::uuid,NULL);
  END IF;
  seen:=seen||jsonb_build_array(reason);
 ELSIF reason IS NULL AND old.state->>'eventId' IS NOT NULL
  AND (m.order_id IS NULL OR m.message_kind NOT IN ('order_confirmation','order_tickets'))
  AND public.email_reporting_state(m) IN ('delivery','open','click','accepted') THEN
  PERFORM public.notification_center_prepared_invalidate((old.state->>'eventId')::uuid);
  UPDATE public.notification_center_events SET status='recovered' WHERE id=(old.state->>'eventId')::uuid;
 END IF;
 INSERT INTO public.notification_center_source_state(organization,source_key,state)
 VALUES(m.organization,key,jsonb_build_object('reason',reason,'seen',seen,'dueAt',due_at,'eventId',coalesce(ev::text,old.state->>'eventId')))
 ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,observed_at=p_at;
 PERFORM public.notification_center_reconcile_order_email_internal(m.order_id);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_email_internal(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/prepared_wake.sql
-- pg_net publishes only after the surrounding domain transaction commits.
-- This is a coalesced synchronization hint, never a second business queue.
CREATE OR REPLACE FUNCTION public.notification_center_prepared_wake()
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE url text;
BEGIN
 IF current_setting('festapp.notification_wake',true)='scheduled' THEN RETURN; END IF;
 UPDATE public.notification_center_maintenance SET next_at=clock_timestamp()+interval '1 second',wake_error=NULL
 WHERE name='delivery-wake' AND worker_url IS NOT NULL AND next_at<=clock_timestamp()
  AND ctid IN(SELECT ctid FROM public.notification_center_maintenance WHERE name='delivery-wake' FOR UPDATE SKIP LOCKED)
 RETURNING worker_url INTO url;
 IF url IS NULL THEN RETURN; END IF;
 PERFORM set_config('festapp.notification_wake','scheduled',true);
 BEGIN
  PERFORM net.http_post(url:=url,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
 EXCEPTION WHEN OTHERS THEN
  UPDATE public.notification_center_maintenance SET wake_error='wake_failed' WHERE name='delivery-wake'
   AND ctid IN(SELECT ctid FROM public.notification_center_maintenance WHERE name='delivery-wake' FOR UPDATE SKIP LOCKED);
 END;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_prepared_wake() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.wake_notification_center()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 -- The one-second safety tick discovers durable work; it must not create an
 -- HTTP request when idle. Domain commits retain their unconditional fast wake.
 -- Keep existing views eligible so live privacy/read repair and expiry cleanup
 -- are never delayed by this scheduler optimization.
 IF EXISTS(SELECT 1 FROM public.notification_center_events WHERE projected_revision<attention_revision)
  OR EXISTS(SELECT 1 FROM public.notification_center_projection_scopes WHERE next_check_at<=clock_timestamp() AND NOT quarantined)
  OR EXISTS(SELECT 1 FROM public.notification_center_views)
  OR EXISTS(SELECT 1 FROM public.notification_center_user_state u
   JOIN public.notification_center_email_profiles p USING(recipient)
   JOIN public.notification_center_organizations a USING(organization)
   WHERE u.email_scanned_sequence<u.last_delivery_sequence AND a.email_collection_started_at IS NOT NULL)
  OR EXISTS(SELECT 1 FROM public.notification_center_user_state u
   JOIN public.notification_center_organizations a USING(organization)
   JOIN public.user_info ui ON ui.id=u.recipient
   JOIN public.notification_center_deliveries d ON d.organization=u.organization AND d.recipient=u.recipient AND d.sequence>u.email_scanned_sequence
   JOIN public.notification_center_events e ON e.id=d.event_id
   WHERE u.email_scanned_sequence<u.last_delivery_sequence AND a.email_collection_started_at IS NOT NULL
    AND e.occurred_at>=a.email_collection_started_at AND public.notification_center_email_required_kind_internal(e.kind)
    AND NOT EXISTS(SELECT 1 FROM public.notification_center_email_profiles p WHERE p.recipient=u.recipient))
  OR EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d
   WHERE d.state='collecting' AND d.due_at<=clock_timestamp() AND d.next_attempt_at<=clock_timestamp()
    AND EXISTS(SELECT 1 FROM public.notification_center_email_profiles p WHERE p.recipient=d.recipient)
    AND NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.recipient_user=d.recipient AND m.message_kind='admin_notification_digest'
      AND m.workflow_state IN ('blocked','pending','preparing','sending','retry_wait','unknown'))) THEN
  PERFORM public.notification_center_prepared_wake();
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.wake_notification_center() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.wake_notification_center() TO service_role;
CREATE OR REPLACE FUNCTION public.configure_notification_center_worker(p_project_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 IF p_project_url IS NULL OR p_project_url !~ '^https?://[^/?#[:space:]]+/?$' THEN RAISE invalid_parameter_value USING MESSAGE='notification_worker_origin_required'; END IF;
 INSERT INTO public.notification_center_maintenance(name,worker_url) VALUES('delivery-wake',rtrim(p_project_url,'/')||'/functions/v1/process-notification-center')
 ON CONFLICT(name) DO UPDATE SET worker_url=excluded.worker_url,next_at='-infinity',wake_error=NULL;
END $$;
REVOKE ALL ON FUNCTION public.configure_notification_center_worker(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configure_notification_center_worker(text) TO service_role;


-- SOURCE: notification_center/orders.sql
CREATE OR REPLACE FUNCTION public.notification_center_order_internal(p_order bigint,p_kind text,p_transition text,p_actor uuid DEFAULT auth.uid(),p_extra jsonb DEFAULT '{}')
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; org bigint; event uuid; ticket_count bigint; form_context jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF NOT FOUND OR o.state='stock' THEN RETURN; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=o.occasion;
 IF NOT EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=org) THEN RETURN; END IF;
 -- Financial facts carry no ticket/person contribution. NULL means not
 -- applicable here; the shared facts owner never invokes legacy hydration.
 IF p_kind NOT IN ('order_payment_received','payment_problem') THEN
  SELECT count(DISTINCT ticket) INTO ticket_count FROM eshop.order_product_ticket WHERE "order"=o.id;
  form_context:=public.notification_center_order_form_context_internal(o.form);
 END IF;
 event:=public.notification_center_publish_internal(org,o.occasion,p_kind,p_kind||':'||p_order||':'||p_transition,
 jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,'state',o.state,'formContext',form_context,'count',ticket_count)||p_extra,p_actor);
 UPDATE public.notification_center_events SET status=o.state WHERE id=event;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_order_state_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.notification_center_events e JOIN eshop.orders o ON o.occasion=e.occasion
  WHERE o.id=p_order AND e.data->>'orderId'=p_order::text AND e.kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted') AND (e.status='storno') IS DISTINCT FROM (o.state='storno')) OR EXISTS(SELECT 1 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
 JOIN public.email_messages m ON m.order_id=o.id AND m.occasion=o.occasion AND m.organization=oc.organization
 JOIN public.notification_center_events e ON e.organization=m.organization AND e.source_key='email:'||m.message_id AND e.kind='email_problem'
 WHERE o.id=p_order AND o.state='storno' AND m.message_kind<>'order_storno' AND e.status NOT IN ('recovered','resolved')) THEN
  PERFORM public.notification_center_prepared_invalidate_order(p_order);
 END IF;
 UPDATE public.notification_center_events e SET status=o.state,data=e.data||jsonb_build_object('state',o.state)
 FROM eshop.orders o WHERE o.id=p_order AND e.data->>'orderId'=p_order::text
 AND e.occasion=o.occasion AND e.kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted');
END $$;
REVOKE ALL ON FUNCTION public.notification_center_order_internal(bigint,text,text,uuid,jsonb),public.notification_center_order_state_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/subject_visibility.sql
-- Order operations are visible to their already-authorized order readers.
-- Hidden membership protects participant identity/enrollment, not purchases.
CREATE OR REPLACE FUNCTION public.notification_center_order_activity_internal(p_org bigint,p_kind text,p_data jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
BEGIN
 IF p_kind IN ('order_created','order_cancelled','order_payment_received','payment_problem','waitlist_registered','offer_accepted','offer_declined','offer_expired') THEN RETURN true; END IF;
 IF p_kind='email_problem' THEN
  RETURN EXISTS(SELECT 1 FROM public.email_messages m JOIN eshop.orders o ON o.id=m.order_id
   JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=m.organization
   WHERE m.organization=p_org AND m.message_id=CASE WHEN p_data->>'messageId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (p_data->>'messageId')::uuid END);
 END IF;
 RETURN false;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_order_activity_internal(bigint,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Keep hidden membership subjects out of notification projections.
CREATE OR REPLACE FUNCTION public.notification_center_subject_visible_internal(p_org bigint, p_kind text, p_data jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
 IF public.notification_center_order_activity_internal(p_org,p_kind,p_data) THEN RETURN true; END IF;
 -- Avoid initializing identity, order and email subplans for every event when
 -- this organization has no hidden members.
 IF NOT EXISTS(SELECT 1 FROM public.organization_users hidden
  WHERE hidden.organization=p_org AND hidden.is_hidden) THEN
  RETURN true;
 END IF;
 -- Plan only the lookup relevant to this payload. A single OR over all three
 -- families initialized every subplan for every delivered event.
 IF p_data ? 'userId' AND EXISTS(
  SELECT 1 FROM public.organization_users hidden
  JOIN public.user_info u ON u.id=hidden."user" AND u.organization=hidden.organization
  WHERE hidden.organization=p_org AND hidden.is_hidden AND p_data->>'userId'=hidden."user"::text) THEN
  RETURN false;
 END IF;
 IF p_data ? 'orderId' AND EXISTS(
  SELECT 1 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
  JOIN public.organization_users hidden ON hidden.organization=oc.organization AND hidden.is_hidden
  JOIN public.user_info u ON u.id=hidden."user" AND u.organization=hidden.organization
  WHERE o.id=CASE WHEN p_data->>'orderId' ~ '^[0-9]{1,18}$' THEN (p_data->>'orderId')::bigint END
   AND oc.organization=p_org AND nullif(btrim(u.email_readonly),'') IS NOT NULL
   AND lower(btrim(o.data->>'email'))=lower(btrim(u.email_readonly))) THEN
  RETURN false;
 END IF;
 IF p_kind='email_problem' AND EXISTS(
  SELECT 1 FROM public.email_messages m
  JOIN public.organization_users hidden ON hidden.organization=m.organization AND hidden.is_hidden
  JOIN public.user_info u ON u.id=hidden."user" AND u.organization=hidden.organization
  WHERE m.message_id=CASE WHEN p_data->>'messageId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (p_data->>'messageId')::uuid END
   AND m.organization=p_org AND (m.recipient_user=hidden."user"
    OR (nullif(btrim(u.email_readonly),'') IS NOT NULL AND lower(btrim(m.recipient))=lower(btrim(u.email_readonly)))
    OR EXISTS(SELECT 1 FROM eshop.orders email_order JOIN public.occasions email_oc ON email_oc.id=email_order.occasion
     WHERE email_order.id=m.order_id AND email_oc.organization=p_org
      AND nullif(btrim(u.email_readonly),'') IS NOT NULL
      AND lower(btrim(email_order.data->>'email'))=lower(btrim(u.email_readonly))))) THEN
  RETURN false;
 END IF;
 RETURN true;
END;
$function$;
REVOKE ALL ON FUNCTION public.notification_center_subject_visible_internal(bigint,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: eshop_transactions/apply_transaction_pairing.sql
CREATE OR REPLACE FUNCTION public.apply_transaction_pairing(
  p_transaction_id bigint,
  p_payment_info_id bigint,
  p_method text,
  p_actor_kind text DEFAULT 'system',
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_transaction eshop.transactions%ROWTYPE;
  v_target eshop.payment_info%ROWTYPE;
  v_old_payment_info_id bigint;
  v_order_id bigint;
  v_order_ids bigint[];
  v_order_bindings jsonb;
  v_locked_order_bindings jsonb;
BEGIN
  PERFORM public.check_bank_account_writable((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id));
  PERFORM public.check_bank_account_writable((SELECT bank_account FROM eshop.payment_info WHERE id=p_payment_info_id));
  IF p_method IS NULL OR p_method !~ '^[a-z0-9_]{1,64}$' THEN
    RAISE EXCEPTION 'PAIRING_INVALID_METHOD';
  END IF;
  IF p_actor_kind NOT IN ('service', 'user', 'system') THEN
    RAISE EXCEPTION 'PAIRING_INVALID_ACTOR_KIND';
  END IF;

  SELECT * INTO v_transaction
  FROM eshop.transactions
  WHERE id = p_transaction_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_TRANSACTION_NOT_FOUND'; END IF;
  v_old_payment_info_id := v_transaction.payment_info;

  -- The transaction row stabilizes the old target (also held by ingest/matcher).
  -- Acquire every stored old/new form and order before either payment row,
  -- matching product edit and cancellation. Never trust a caller's scope list.
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]),
    coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_order_ids,v_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  PERFORM public.lock_order_capacity_scope_internal(v_order_ids);
  SELECT coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_locked_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  IF v_order_bindings IS DISTINCT FROM v_locked_order_bindings THEN
    RAISE EXCEPTION 'PAIRING_ORDER_SCOPE_CHANGED' USING ERRCODE='40001';
  END IF;
  PERFORM 1 FROM eshop.payment_info WHERE id IN (v_old_payment_info_id,p_payment_info_id)
  ORDER BY id FOR UPDATE;

  -- A settled movement is immutable through the generic attach/unlink API.
  -- Cash voids and evidenced bank reclassification have their explicit owner.
  IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=p_transaction_id)
     AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    RAISE EXCEPTION 'REFUND_SETTLEMENT_REQUIRES_EXPLICIT_CORRECTION';
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0
     AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b WHERE b.id=v_transaction.bank_account_id
       AND upper(b.type)='CASH' AND v_transaction.transaction_type='manual'
       AND v_transaction.ingest_source='manual') THEN
    RAISE EXCEPTION 'OUTGOING_REQUIRES_REFUND_CLASSIFICATION';
  END IF;
  IF v_old_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    PERFORM public.assert_payment_refund_reservations_internal(v_old_payment_info_id,greatest(v_transaction.amount,0));
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0 THEN
    PERFORM public.assert_payment_refund_reservations_internal(p_payment_info_id,-v_transaction.amount);
  END IF;

  IF p_actor_kind='user' THEN
    FOR v_order_id IN SELECT id FROM eshop.orders
      WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id) ORDER BY id LOOP
      PERFORM public.check_order_is_mutable(v_order_id);
    END LOOP;
  END IF;

  IF v_old_payment_info_id IS NOT DISTINCT FROM p_payment_info_id THEN
    RETURN jsonb_build_object('status', 'unchanged', 'transaction_id', p_transaction_id,
      'payment_info_id', p_payment_info_id);
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    SELECT * INTO v_target FROM eshop.payment_info WHERE id = p_payment_info_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_PAYMENT_INFO_NOT_FOUND'; END IF;
    IF public.payment_method_is_online_internal(v_target.payment_method) THEN RAISE EXCEPTION 'STRIPE_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_target.payment_method='cash' AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b
      WHERE b.id=v_transaction.bank_account_id AND b.type='CASH' AND v_transaction.transaction_type='manual') THEN
      RAISE EXCEPTION 'CASH_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_transaction.transaction_type='manual' THEN
      IF NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link JOIN public.occasions oc ON oc.unit=link.unit
        JOIN eshop.orders o ON o.occasion=oc.id JOIN eshop.bank_accounts b ON b.id=link.bank_account
        WHERE o.payment_info=v_target.id AND b.id=v_transaction.bank_account_id ) THEN
        RAISE EXCEPTION 'CASH_ORDER_SCOPE_MISMATCH'; END IF;
    END IF;
    IF upper(trim(v_transaction.currency::text)) <> upper(trim(v_target.currency_code::text)) THEN
      RAISE EXCEPTION 'PAIRING_CURRENCY_MISMATCH';
    END IF;
    IF v_transaction.transaction_type IS DISTINCT FROM 'manual'
       AND v_transaction.bank_account_id <> v_target.bank_account
       AND NOT public.bank_sync_accounts_match(p_transaction_id,v_target.bank_account) THEN
      RAISE EXCEPTION 'PAIRING_BANK_ACCOUNT_MISMATCH';
    END IF;
  END IF;

  UPDATE eshop.transactions SET payment_info = p_payment_info_id WHERE id = p_transaction_id;

  IF v_old_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(v_old_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = v_old_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(p_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = p_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;


  IF v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    PERFORM public.notification_center_prepared_invalidate(e.id) FROM public.notification_center_events e
     JOIN eshop.orders o ON o.occasion=e.occasion AND o.id=(e.data->>'orderId')::bigint
     WHERE e.kind='order_payment_received' AND e.data->>'paymentFact'='transaction:'||p_transaction_id AND o.payment_info=v_old_payment_info_id;
    UPDATE public.notification_center_events e SET status='resolved' FROM eshop.orders o
     WHERE e.kind='order_payment_received' AND e.data->>'paymentFact'='transaction:'||p_transaction_id
      AND o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion AND o.payment_info=v_old_payment_info_id;
    IF p_payment_info_id IS NOT NULL AND v_transaction.amount>0 THEN
      FOR v_order_id IN SELECT id FROM eshop.orders WHERE payment_info=p_payment_info_id LOOP
       PERFORM public.notification_center_payment_fact_internal(v_order_id,'transaction',p_transaction_id::text,
        v_transaction.amount,v_transaction.currency::text,coalesce(v_transaction.date,now()),
        EXISTS(SELECT 1 FROM eshop.transaction_pairing_events WHERE transaction_id=p_transaction_id AND new_payment_info_id IS NOT NULL));
      END LOOP;
    END IF;
  END IF;
  INSERT INTO eshop.transaction_pairing_events (
    transaction_snapshot_id, transaction_id, old_payment_info_id,
    new_payment_info_id, action, method, actor_id, actor_kind, details
  ) VALUES (
    p_transaction_id, p_transaction_id, v_old_payment_info_id,
    p_payment_info_id, CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    p_method, auth.uid(), p_actor_kind, COALESCE(p_details, '{}'::jsonb)
  );

  RETURN jsonb_build_object('status', CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    'transaction_id', p_transaction_id, 'payment_info_id', p_payment_info_id);
END;
$$;

REVOKE ALL ON FUNCTION public.apply_transaction_pairing(bigint,bigint,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;


-- SOURCE: eshop_stripe/provider.sql
-- Stripe is one connector. All Stripe storage/identity and price restrictions
-- remain here; the order lifecycle dispatches through the common registry.
CREATE OR REPLACE FUNCTION public.stripe_payment_provider_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE input jsonb; connection uuid; payment_id bigint; attempt uuid; expires timestamptz;
 amount numeric; currency text; target bigint; result jsonb;
BEGIN
 target:=(p_args->>'orderId')::bigint;
 IF p_operation='notification_connection_health' THEN
  SELECT jsonb_build_object('organizationId',c.organization_id,'unitId',c.unit_id,'title','Stripe',
   'reason',CASE WHEN c.state='retired' OR (c.state='revoked' AND (SELECT a.action FROM eshop.stripe_connection_audit a
    WHERE a.connection_id=c.id AND a.actor IS NOT NULL AND a.action IN ('connected','reconnected','replaced','revoked') ORDER BY a.id DESC LIMIT 1)='revoked') THEN NULL WHEN c.state='revoked' THEN 'provider_access_revoked'
    WHEN c.state='restricted' THEN 'provider_restricted' WHEN c.status_failures>=public.payment_provider_connection_failure_threshold_internal() THEN 'provider_unavailable' END)
  INTO result FROM eshop.stripe_connections c WHERE c.id=(p_args->>'connectionId')::uuid;
  RETURN result;
 ELSIF p_operation='operation_capabilities' THEN
  result:=public.stripe_payment_provider_internal('refund_binding',p_args);
  RETURN jsonb_build_object('id','stripe','displayName','Stripe','record',false,'refund',result IS NOT NULL,
   'verification','verified_provider_observation','reason',CASE WHEN result IS NULL THEN 'original_payment_unavailable' ELSE NULL END);
 ELSIF p_operation='refund_binding' THEN
  -- Refunds bind to one evidenced original payment, never a checkout URL or client identity.
  SELECT jsonb_build_object('attemptId',a.id,'accountId',c.account_id,'livemode',a.livemode,
   'paymentId',a.payment_intent_id,'currency',a.currency,'amountMinor',a.amount_minor) INTO result
  FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_connections c ON c.id=a.connection_id
  JOIN eshop.orders o ON o.id=a.order_id AND o.payment_info=a.payment_info_id
  JOIN eshop.payment_info pi ON pi.id=a.payment_info_id AND pi.stripe_connection_id=c.id
  WHERE a.order_id=target AND a.payment_intent_id IS NOT NULL AND c.livemode=a.livemode
   AND c.organization_id=a.organization_id AND c.unit_id=a.unit_id AND pi.payment_method='stripe' AND pi.currency_code::text=a.currency AND pi.amount*100=a.amount_minor
   AND c.state IN ('connected','restricted') AND c.model_verified
   AND a.currency IN ('CZK','EUR','PLN','USD','GBP')
   AND EXISTS(SELECT 1 FROM eshop.stripe_payment_movements m WHERE m.attempt_id=a.id AND m.kind='payment' AND m.provider_id=a.payment_intent_id AND m.currency=a.currency AND m.amount_minor=a.amount_minor)
   AND 1=(SELECT count(*) FROM eshop.stripe_checkout_attempts x WHERE x.order_id=target AND EXISTS(
    SELECT 1 FROM eshop.stripe_payment_movements m WHERE m.attempt_id=x.id AND m.kind='payment'));
  RETURN result;
 ELSIF p_operation='refund_observed' THEN
  RETURN to_jsonb(EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts a
   JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id AND m.connection_id=a.connection_id
   WHERE a.order_id=target AND m.kind='refund' AND m.provider_id=p_args->>'refundId'
    AND EXISTS(SELECT 1 FROM eshop.refund_requests r WHERE r.id=(p_args->>'requestId')::uuid
      AND r.order_id=a.order_id AND r.payment_info=a.payment_info_id AND r.method='stripe'
      AND r.currency=m.currency AND r.amount*100=m.amount_minor)));
 ELSIF p_operation='projection' THEN RETURN public.stripe_order_payment_projection_internal(target);
 ELSIF p_operation='attach_source' THEN
  PERFORM public.attach_stripe_order_pay_source_internal(target,(p_args->>'commandId')::uuid,p_args->'source'); RETURN NULL;
 ELSIF p_operation='initialize_payment' THEN
  input:=p_args->'input';amount:=(p_args->>'amount')::numeric;currency:=p_args->>'currency';
  IF coalesce(input->>'payment_type','full')<>'full' OR (p_args->>'deposit')::numeric>0 THEN RAISE EXCEPTION 'STRIPE_DEPOSIT_UNSUPPORTED'; END IF;
  connection:=public.assert_stripe_form_payable_internal((p_args->>'formId')::bigint,(input->>'stripe_connection_id')::uuid,input->>'payment_surface');
  IF (input->>'expected_payment_amount_minor')::numeric IS DISTINCT FROM amount*100 OR input->>'expected_payment_currency' IS DISTINCT FROM currency THEN
   RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','STRIPE_PRICE_CHANGED','message','Order price changed. Review the order before paying.')::text; END IF;
  IF currency NOT IN ('CZK','EUR','PLN','USD','GBP') OR amount*100<>trunc(amount*100) THEN RAISE EXCEPTION 'STRIPE_AMOUNT_UNSUPPORTED'; END IF;
  INSERT INTO eshop.payment_info(amount,currency_code,created_at,payment_method,stripe_connection_id)
   VALUES(amount,currency,(p_args->>'createdAt')::timestamptz,'stripe',connection) RETURNING id INTO payment_id;
  RETURN jsonb_build_object('paymentInfoId',payment_id);
 ELSIF p_operation='create_attempt' THEN
  attempt:=public.create_stripe_order_attempt_internal(target);
  SELECT reservation_expires_at INTO STRICT expires FROM eshop.stripe_checkout_attempts WHERE id=attempt;
  RETURN jsonb_build_object('expiresAt',expires);
 ELSIF p_operation='paid_guard' THEN
  IF NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
   JOIN eshop.stripe_checkout_attempts a ON a.order_id=o.id JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id
   WHERE o.id=target AND m.kind='payment' AND m.amount_minor=a.amount_minor
    AND m.connection_id=pi.stripe_connection_id AND m.occurred_at<=a.reservation_expires_at) THEN
   RETURN jsonb_build_object('code',409,'message','STRIPE_PROVIDER_PAYMENT_REQUIRED'); END IF;
  IF (SELECT state FROM eshop.orders WHERE id=target)='expired' THEN RETURN jsonb_build_object('code',409,'message','Stripe reservation was released'); END IF;
  RETURN NULL;
 ELSIF p_operation='totals' THEN
  payment_id:=(p_args->>'paymentId')::bigint;
  WITH p AS (SELECT * FROM eshop.payment_info WHERE id=payment_id), money AS (
   SELECT coalesce(sum(m.amount_minor) FILTER(WHERE m.kind='payment'),0)/100 received,
    coalesce(sum(m.amount_minor) FILTER(WHERE m.kind='refund'),0)/100 returned,
    coalesce(bool_or(m.connection_id IS DISTINCT FROM p.stripe_connection_id OR m.currency IS DISTINCT FROM p.currency_code::text
     OR a.order_id NOT IN(SELECT id FROM eshop.orders WHERE payment_info=p.id)),false) invalid
   FROM p JOIN eshop.stripe_checkout_attempts a ON a.payment_info_id=p.id JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id),
  holds AS (SELECT coalesce(sum(d.amount_minor) FILTER(WHERE d.status IN ('needs_response','under_review','lost')),0)/100 held
   FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_disputes d ON d.attempt_id=a.id WHERE a.payment_info_id=payment_id)
  SELECT jsonb_build_object('received',received,'returned',returned,'invalid',invalid,'held',held) INTO result FROM money CROSS JOIN holds;
  RETURN result;
 ELSIF p_operation='notification_facts' THEN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('identity',m.connection_id::text||':'||m.provider_id||':'||m.kind,
   'amount',m.amount_minor::numeric/100,'currency',m.currency,'occurredAt',m.occurred_at)),'[]')
   FROM eshop.stripe_payment_movements m WHERE m.attempt_id=(p_args->>'attemptId')::uuid AND m.kind='payment');
 ELSIF p_operation='effect_context' THEN
  SELECT jsonb_build_object('attemptId',a.id,'orderId',a.order_id,'paymentId',a.payment_info_id,'connectionId',a.connection_id,
   'organizationId',a.organization_id,'unitId',a.unit_id,'accountId',c.account_id,'livemode',a.livemode,
   'amountMinor',a.amount_minor,'currency',a.currency,'reservationExpiresAt',a.reservation_expires_at,
   'state',a.state,'incomplete',a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL,
   'receivedMinor',(SELECT coalesce(sum(amount_minor),0) FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='payment'),
   'refundedMinor',(SELECT coalesce(sum(amount_minor),0) FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund'),
   'paymentTime',(SELECT min(occurred_at) FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='payment'),
   'decisions',coalesce((SELECT jsonb_agg(reason) FROM eshop.stripe_admission_decisions WHERE attempt_id=a.id),'[]'))
  INTO result FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_connections c ON c.id=a.connection_id
   JOIN eshop.payment_info pi ON pi.id=a.payment_info_id AND pi.stripe_connection_id=c.id
   WHERE a.id=(p_args->>'attemptId')::uuid AND c.organization_id=a.organization_id AND c.unit_id=a.unit_id AND c.livemode=a.livemode;
  RETURN result;
 ELSIF p_operation='effect_lock' THEN
  PERFORM 1 FROM eshop.stripe_checkout_attempts WHERE id=(p_args->>'attemptId')::uuid FOR UPDATE; RETURN NULL;
 ELSIF p_operation='effect_state' THEN
  IF p_args->>'state' NOT IN ('paid','expired','action_required') THEN RAISE EXCEPTION 'PAYMENT_EFFECT_STATE_INVALID'; END IF;
  UPDATE eshop.stripe_checkout_attempts SET state=p_args->>'state'
   WHERE id=(p_args->>'attemptId')::uuid; RETURN NULL;
 ELSIF p_operation='effect_decision' THEN
  INSERT INTO eshop.stripe_admission_decisions(attempt_id,reason,provider_revision,ticket_ids,actor)
   VALUES((p_args->>'attemptId')::uuid,p_args->>'reason',p_args->>'revision',
    ARRAY(SELECT jsonb_array_elements_text(coalesce(p_args->'tickets','[]'))::bigint),auth.uid()) RETURNING id INTO attempt;
  RETURN to_jsonb(attempt);
 ELSIF p_operation='setup_recipients' THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('connectionId',id,'name',business_name,'livemode',livemode) ORDER BY livemode,id),'[]') INTO result
   FROM eshop.stripe_connections WHERE unit_id=(p_args->>'unitId')::bigint AND model_verified AND state IN ('connected','restricted');
  RETURN result;
 ELSIF p_operation='unit_fields' THEN RETURN jsonb_build_object('stripe_preview_enabled',public.stripe_unit_feature_enabled_internal((p_args->>'unitId')::bigint));
 ELSIF p_operation='unit_feature' THEN RETURN to_jsonb(public.stripe_unit_feature_enabled_internal((p_args->>'unitId')::bigint));
 ELSIF p_operation='form_availability' THEN
  result:=public.stripe_form_payment_availability_internal((p_args->>'formId')::bigint);
  RETURN jsonb_build_object('providerId','stripe','configured',result#>'{configured,stripe}',
   'available',result->'available' ? 'stripe','recipient',result->'recipient','supportedSurfaces',result->'supportedSurfaces',
   'reason',jsonb_build_object('code',result->'stripeUnavailableReason'));
 ELSIF p_operation='validate_form' THEN
  PERFORM public.validate_stripe_form_payment_configuration_internal((p_args->>'formId')::bigint); RETURN NULL;
 ELSIF p_operation='form_editor_fields' THEN
  RETURN jsonb_build_object('stripeRecipient',public.get_form_stripe_recipient((p_args->>'unitId')::bigint,(p_args->>'occasionId')::bigint,(p_args->>'livemode')::boolean));
 ELSIF p_operation='movements' THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('sourceId',m.source_id,'kind',m.kind,'amount_minor',m.amount_minor,'currency',m.currency,'occurred_at',m.occurred_at,'status',m.status)),'[]') INTO result
   FROM (
    SELECT m.connection_id::text||':'||m.provider_id source_id,m.kind,m.amount_minor,m.currency,m.occurred_at,NULL::text status
    FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id WHERE a.payment_info_id=(p_args->>'paymentId')::bigint
    UNION ALL
    SELECT d.connection_id::text||':dispute:'||d.provider_id,'dispute',d.amount_minor,a.currency,d.observed_at,d.status
    FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_disputes d ON d.attempt_id=a.id WHERE a.payment_info_id=(p_args->>'paymentId')::bigint
   ) m;
  RETURN result;
 END IF;
 RAISE EXCEPTION 'PAYMENT_PROVIDER_OPERATION_UNSUPPORTED';
END $$;
REVOKE ALL ON FUNCTION public.stripe_payment_provider_internal(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='eshop.payment_info'::regclass AND conname='payment_info_stripe_connection_identity') THEN
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_stripe_connection_identity CHECK(
 (payment_method='stripe')=(stripe_connection_id IS NOT NULL)); END IF; END $$;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field,legacy_connection_field,hosted_checkout,operation_mode,verification)
 VALUES('stripe','public.stripe_payment_provider_internal(text,jsonb)'::regprocedure,'stripePaymentSource','stripeConnectionId',true,'remote','verified_provider_observation') ON CONFLICT(provider_key) DO UPDATE SET handler=excluded.handler,source_field=excluded.source_field,legacy_connection_field=excluded.legacy_connection_field,hosted_checkout=excluded.hosted_checkout,operation_mode=excluded.operation_mode,verification=excluded.verification;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='eshop.payment_info'::regclass AND conname='payment_info_registered_method') THEN
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_registered_method
 FOREIGN KEY(payment_method) REFERENCES eshop.payment_providers(provider_key); END IF; END $$;


-- SOURCE: eshop_barion/provider.sql
-- Protocol persistence and projections only. Order/ticket/email decisions are
-- exclusively owned by apply_provider_payment_effects_internal.
CREATE OR REPLACE FUNCTION public.barion_payment_provider_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a eshop.barion_attempts; c eshop.barion_connections; o eshop.orders; pi eshop.payment_info;
 result jsonb; input jsonb; binding uuid; amount numeric; stamp timestamptz:=date_trunc('second',clock_timestamp());
 received bigint; refunded bigint; status text; admission text; expiry timestamptz;
BEGIN
 IF p_operation='notification_connection_health' THEN
  SELECT jsonb_build_object('organizationId',connection_row.organization_id,'unitId',connection_row.unit_id,'title','Barion',
   'reason',CASE WHEN connection_row.enabled AND EXISTS(SELECT 1 FROM eshop.barion_attempts attempt_row WHERE attempt_row.connection_id=connection_row.id AND attempt_row.reconcile_failures>=public.payment_provider_connection_failure_threshold_internal()) THEN 'provider_unavailable' END)
  INTO result FROM eshop.barion_connections connection_row WHERE connection_row.id=(p_args->>'connectionId')::uuid;
  RETURN result;
 ELSIF p_operation='operation_capabilities' THEN
  RETURN jsonb_build_object('id','barion','displayName','Barion sandbox','record',false,'refund',false,
   'verification','verified_provider_observation','reason','refund_write_unavailable');
 ELSIF p_operation='refund_binding' THEN RETURN NULL;
 ELSIF p_operation='refund_observed' THEN
  RETURN to_jsonb(EXISTS(SELECT 1 FROM eshop.barion_attempts a JOIN eshop.barion_movements m ON m.attempt_id=a.id
   WHERE a.order_id=(p_args->>'orderId')::bigint AND m.kind='refund' AND m.provider_id=p_args->>'refundId'
    AND EXISTS(SELECT 1 FROM eshop.refund_requests r WHERE r.id=(p_args->>'requestId')::uuid
      AND r.order_id=a.order_id AND r.payment_info=a.payment_info_id AND r.method='barion'
      AND r.currency=m.currency AND r.amount*100=m.amount_minor)));
 ELSIF p_operation IN ('unit_feature','unit_fields') THEN RETURN CASE WHEN p_operation='unit_feature' THEN 'false'::jsonb ELSE '{}'::jsonb END;
 ELSIF p_operation='setup_recipients' THEN RETURN '[]'::jsonb;
 ELSIF p_operation='form_editor_fields' THEN RETURN '{}'::jsonb;
 ELSIF p_operation IN ('form_availability','validate_form') THEN
  binding:=public.payment_provider_connection_internal((SELECT data->'payments' FROM public.forms WHERE id=(p_args->>'formId')::bigint),'barion');
  IF p_operation='validate_form' THEN
   IF binding IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.barion_connections b JOIN public.forms f ON f.id=(p_args->>'formId')::bigint JOIN public.occasions oc ON oc.id=f.occasion
    WHERE b.id=binding AND b.unit_id=oc.unit AND b.organization_id=oc.organization AND f.id=ANY(b.sandbox_form_ids)) THEN RAISE EXCEPTION 'BARION_SANDBOX_FORM_REQUIRED'; END IF;
   RETURN NULL;
  END IF;
  SELECT * INTO c FROM eshop.barion_connections WHERE id=binding;
  RETURN jsonb_build_object('providerId','barion','configured',binding IS NOT NULL,'available',false,'collectionAvailable',c.enabled AND EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE f.id=(p_args->>'formId')::bigint AND f.id=ANY(c.sandbox_form_ids) AND oc.unit=c.unit_id AND oc.organization=c.organization_id),
   'recipient',CASE WHEN c.id IS NOT NULL THEN jsonb_build_object('connectionId',c.id,'name',c.business_name,'livemode',false) ELSE NULL END,
   'supportedSurfaces','[]'::jsonb,'reason',jsonb_build_object('code','sandbox_only'));
 ELSIF p_operation='initialize_payment' THEN
  input:=p_args->'input';amount:=(p_args->>'amount')::numeric;
  binding:=public.payment_provider_connection_internal((SELECT data->'payments' FROM public.forms WHERE id=(p_args->>'formId')::bigint),'barion');
  SELECT b.* INTO c FROM eshop.barion_connections b JOIN public.forms f ON f.id=(p_args->>'formId')::bigint JOIN public.occasions oc ON oc.id=f.occasion
   WHERE b.id=binding AND b.enabled AND b.organization_id=oc.organization AND b.unit_id=oc.unit AND f.id=ANY(b.sandbox_form_ids);
  IF c.id IS NULL OR input->>'payment_connection_id' IS DISTINCT FROM binding::text THEN RAISE EXCEPTION 'BARION_SANDBOX_FORM_REQUIRED'; END IF;
  IF amount<=0 OR amount*100<>trunc(amount*100) OR amount*100>1000000000 OR p_args->>'currency' NOT IN ('CZK','EUR','USD')
   OR (input->>'expected_payment_amount_minor')::numeric IS DISTINCT FROM amount*100 OR input->>'expected_payment_currency' IS DISTINCT FROM p_args->>'currency'
   OR coalesce(input->>'payment_type','full')<>'full' OR coalesce((p_args->>'deposit')::numeric,0)<>0 THEN RAISE EXCEPTION 'BARION_PRICE_INVALID'; END IF;
  INSERT INTO eshop.payment_info(amount,currency_code,payment_method,created_at,barion_connection_id) VALUES(amount,p_args->>'currency','barion',stamp,binding) RETURNING id INTO amount;
  RETURN jsonb_build_object('paymentInfoId',amount);
 END IF;
 IF p_args ? 'attemptId' THEN SELECT * INTO a FROM eshop.barion_attempts WHERE id=(p_args->>'attemptId')::uuid;
 ELSIF p_args ? 'orderId' THEN SELECT * INTO a FROM eshop.barion_attempts WHERE order_id=(p_args->>'orderId')::bigint;
 ELSE SELECT * INTO a FROM eshop.barion_attempts WHERE payment_info_id=(p_args->>'paymentId')::bigint; END IF;
 IF p_operation='create_attempt' THEN
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=(p_args->>'orderId')::bigint FOR UPDATE;
  SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
  binding:=pi.barion_connection_id;
  SELECT * INTO STRICT c FROM eshop.barion_connections WHERE id=binding AND enabled AND o.form=ANY(sandbox_form_ids);
  IF pi.payment_method<>'barion' OR pi.amount<>o.price OR pi.currency_code<>o.currency_code OR o.state<>'ordered'
    OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=o.occasion AND unit=c.unit_id AND organization=c.organization_id) THEN RAISE EXCEPTION 'BARION_SCOPE_INVALID'; END IF;
  expiry:=stamp+make_interval(secs=>(public.payment_sale_policy_internal()->>'reservationSeconds')::integer);
  INSERT INTO eshop.barion_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,amount_minor,currency,reservation_expires_at,return_base_url,locale)
   SELECT o.id,pi.id,c.organization_id,c.unit_id,c.id,(pi.amount*100)::bigint,pi.currency_code,expiry,
    rtrim(data->>'DEFAULT_URL','/')||'/payments/barion/return',CASE WHEN data->>'DEFAULT_LANGUAGE' IN ('cs','en','de','pl','sk') THEN data->>'DEFAULT_LANGUAGE' ELSE 'en' END
   FROM public.organizations WHERE id=c.organization_id RETURNING * INTO a;
  UPDATE eshop.payment_info SET deadline=expiry WHERE id=pi.id;
  RETURN jsonb_build_object('expiresAt',expiry);
 END IF;
 IF a.id IS NULL THEN
  IF p_operation='projection' THEN RETURN NULL; END IF;
  IF p_operation='paid_guard' THEN RETURN jsonb_build_object('code',409,'message','BARION_VERIFIED_PAYMENT_REQUIRED'); END IF;
  RAISE EXCEPTION 'BARION_ATTEMPT_REQUIRED';
 END IF;
 SELECT * INTO STRICT c FROM eshop.barion_connections WHERE id=a.connection_id;
 SELECT coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0),coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0) INTO received,refunded FROM eshop.barion_movements WHERE attempt_id=a.id;
 IF p_operation='totals' THEN RETURN jsonb_build_object('received',received/100.0,'returned',refunded/100.0,'held',CASE WHEN a.financial_hold THEN a.amount_minor/100.0 ELSE 0 END,'invalid',false);
 ELSIF p_operation='movements' THEN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('sourceId',m.connection_id::text||':'||m.provider_id,'kind',m.kind,'amount_minor',m.amount_minor,'currency',m.currency,'occurred_at',m.occurred_at)),'[]') FROM eshop.barion_movements m WHERE attempt_id=a.id);
 ELSIF p_operation='notification_facts' THEN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('identity',m.connection_id::text||':'||m.provider_id||':'||m.kind,
   'amount',m.amount_minor::numeric/100,'currency',m.currency,'occurredAt',m.occurred_at)),'[]')
   FROM eshop.barion_movements m WHERE m.attempt_id=(p_args->>'attemptId')::uuid AND m.kind='payment');
 ELSIF p_operation='effect_context' THEN
  RETURN jsonb_build_object('attemptId',a.id,'orderId',a.order_id,'paymentId',a.payment_info_id,'connectionId',c.id,'organizationId',a.organization_id,'unitId',a.unit_id,
   'accountId',c.account_id,'livemode',false,'amountMinor',a.amount_minor,'currency',a.currency,'reservationExpiresAt',a.reservation_expires_at,
   'state',a.state,'incomplete',a.financial_hold,'receivedMinor',received,'refundedMinor',refunded,
   'paymentTime',(SELECT min(occurred_at) FROM eshop.barion_movements WHERE attempt_id=a.id AND kind='payment'),'decisions',a.decisions);
 ELSIF p_operation='effect_lock' THEN PERFORM 1 FROM eshop.barion_attempts WHERE id=a.id FOR UPDATE;RETURN NULL;
 ELSIF p_operation='effect_state' THEN
  IF p_args->>'state' NOT IN ('paid','expired','action_required') THEN RAISE EXCEPTION 'PAYMENT_EFFECT_STATE_INVALID'; END IF;
  UPDATE eshop.barion_attempts SET state=p_args->>'state' WHERE id=a.id;RETURN NULL;
 ELSIF p_operation='effect_decision' THEN
  UPDATE eshop.barion_attempts SET decisions=decisions||jsonb_build_array(p_args->>'reason') WHERE id=a.id;RETURN to_jsonb(extensions.gen_random_uuid());
 ELSIF p_operation IN ('projection','paid_guard') THEN
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id;SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=a.payment_info_id;
  IF p_operation='paid_guard' THEN
   IF a.financial_hold OR received<>a.amount_minor OR refunded>=a.amount_minor OR o.state='expired' OR NOT EXISTS(
    SELECT 1 FROM eshop.barion_movements WHERE attempt_id=a.id AND kind='payment' AND occurred_at<=a.reservation_expires_at) THEN
    RETURN jsonb_build_object('code',409,'message','BARION_VERIFIED_PAYMENT_REQUIRED'); END IF; RETURN NULL;
  END IF;
  status:=CASE WHEN a.financial_hold THEN 'disputed' WHEN refunded>=a.amount_minor THEN 'refunded' WHEN a.state='action_required' THEN 'action_required'
   WHEN refunded>0 THEN 'partially_refunded' WHEN received>=a.amount_minor AND o.state IN ('paid','sent') THEN 'paid'
   WHEN a.state='uncertain' AND a.remote_id IS NULL THEN 'pending'
   WHEN a.state='expired' OR a.reservation_expires_at<=clock_timestamp() OR o.state IN ('expired','storno') THEN 'expired'
   WHEN a.state='preparing' THEN 'preparing' ELSE 'open' END;
  admission:=CASE WHEN status IN ('disputed','refunded','action_required') THEN 'hold' WHEN status IN ('paid','partially_refunded') AND o.state IN ('paid','sent') THEN 'valid' ELSE 'pending' END;
  RETURN jsonb_build_object('method','barion','status',status,'amount',pi.amount::text,'received',(received/100.0)::numeric(30,2)::text,'returned',(refunded/100.0)::numeric(30,2)::text,
   'currency',a.currency,'admissionState',admission,'orderState',o.state,'reservationExpiresAt',a.reservation_expires_at,'serverNow',clock_timestamp(),
   'reconciliationPending',a.financial_hold OR (a.state='uncertain' AND a.remote_id IS NULL),'reconciliationFailures',a.reconcile_failures,'lastSyncedAt',a.last_synced_at,
   'deliveryState',coalesce((SELECT CASE workflow_state WHEN 'accepted' THEN 'accepted' WHEN 'failed' THEN 'failed' ELSE 'pending' END FROM public.email_messages WHERE order_id=o.id AND message_kind='order_tickets' ORDER BY created_at DESC,id DESC LIMIT 1),'not_requested'),
   'allowedActions',CASE WHEN status IN ('preparing','open') THEN '["refresh","pay"]'::jsonb ELSE '["refresh"]'::jsonb END);
 ELSIF p_operation='attach_source' THEN
  input:=p_args->'source';
  IF input->>'tokenHash' IS NULL OR input->>'tokenHash' !~ '^[a-f0-9]{64}$' OR input->>'returnHash' IS NULL OR input->>'returnHash' !~ '^[a-f0-9]{64}$'
   OR input->>'tokenHash'=input->>'returnHash' OR input->>'contentHash' IS NULL OR input->>'contentHash' !~ '^[a-f0-9]{64}$'
   OR jsonb_typeof(input->'sealed') IS DISTINCT FROM 'object' OR input#>>'{sealed,v}' IS DISTINCT FROM '1'
   OR nullif(input#>>'{sealed,iv}','') IS NULL OR nullif(input#>>'{sealed,ciphertext}','') IS NULL THEN RAISE EXCEPTION 'BARION_SOURCE_INVALID'; END IF;
  INSERT INTO eshop.barion_capabilities(token_hash,attempt_id,scope,expires_at) VALUES(input->>'tokenHash',a.id,'order_pay',stamp+interval '30 days'),(input->>'returnHash',a.id,'return_read',a.reservation_expires_at+interval '1 day');
  INSERT INTO eshop.barion_sources VALUES(a.id,(p_args->>'commandId')::uuid,input->>'tokenHash',input->'sealed',input->>'contentHash');RETURN NULL;
 END IF;
 RAISE EXCEPTION 'BARION_OPERATION_UNSUPPORTED';
END $$;
REVOKE ALL ON FUNCTION public.barion_payment_provider_internal(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field,hosted_checkout,operation_mode,verification) VALUES('barion','public.barion_payment_provider_internal(text,jsonb)'::regprocedure,'barionPaymentSource',true,'remote','verified_provider_observation') ON CONFLICT(provider_key) DO UPDATE SET handler=excluded.handler,source_field=excluded.source_field,hosted_checkout=true,operation_mode=excluded.operation_mode,verification=excluded.verification;


-- SOURCE: payment_providers/effects.sql
-- Lock order: capacity/form scope -> order -> payment -> provider attempt -> tickets.
-- All facts are read back from connector storage. No caller-supplied markPaid/amount.
CREATE OR REPLACE FUNCTION public.apply_provider_payment_effects_internal(
 p_provider text,p_attempt uuid,p_revision text,p_before jsonb,p_expired boolean DEFAULT false,
 p_unresolved boolean DEFAULT false,p_action text DEFAULT 'observe',p_tickets bigint[] DEFAULT '{}'
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE context jsonb; prior jsonb; o eshop.orders; pi eshop.payment_info; totals record; projection jsonb; transition jsonb;
 received numeric; refunded numeric; payment_time timestamptz; deadline timestamptz; cancelled bigint[];
 conflict boolean; action_required boolean; changed boolean:=false; args jsonb:=jsonb_build_object('attemptId',p_attempt); decision jsonb; fact jsonb;
BEGIN
 IF p_provider IS NULL OR p_provider='bank' OR p_attempt IS NULL OR nullif(p_revision,'') IS NULL
  OR p_action IS NULL OR p_action NOT IN ('observe','keep','cancel_selected') THEN RAISE EXCEPTION 'PAYMENT_EFFECT_INPUT_INVALID'; END IF;
 context:=public.payment_provider_call_internal(p_provider,'effect_context',args);
 IF context IS NULL OR jsonb_typeof(context)<>'object' OR NOT context ?& ARRAY['attemptId','orderId','paymentId','connectionId','organizationId','unitId','accountId','livemode','amountMinor','currency','reservationExpiresAt','state','incomplete','receivedMinor','refundedMinor','paymentTime','decisions']
  OR context->>'attemptId' IS DISTINCT FROM p_attempt::text OR nullif(context->>'accountId','') IS NULL
  OR nullif(context->>'connectionId','') IS NULL OR (context->>'connectionId')::uuid IS NULL
  OR context->>'state' IS NULL OR context->>'state' NOT IN ('preparing','open','uncertain','paid','expired','action_required')
  OR jsonb_typeof(context->'livemode') IS DISTINCT FROM 'boolean' OR jsonb_typeof(context->'incomplete') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(context->'decisions') IS DISTINCT FROM 'array'
  OR jsonb_typeof(context->'amountMinor') IS DISTINCT FROM 'number' OR jsonb_typeof(context->'receivedMinor') IS DISTINCT FROM 'number'
  OR jsonb_typeof(context->'refundedMinor') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'PAYMENT_EFFECT_CONTEXT_INVALID'; END IF;
 prior:=context;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[(context->>'orderId')::bigint]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=(context->>'orderId')::bigint FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 PERFORM public.payment_provider_call_internal(p_provider,'effect_lock',args);
 context:=public.payment_provider_call_internal(p_provider,'effect_context',args);
 IF context IS DISTINCT FROM prior OR pi.id IS DISTINCT FROM (context->>'paymentId')::bigint
  OR pi.payment_method IS DISTINCT FROM p_provider OR pi.amount*100 IS DISTINCT FROM (context->>'amountMinor')::numeric
  OR pi.currency_code::text IS DISTINCT FROM context->>'currency'
  OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=o.occasion AND organization=(context->>'organizationId')::bigint AND unit=(context->>'unitId')::bigint)
  OR (p_before IS NOT NULL AND p_before->>'method' IS DISTINCT FROM p_provider) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_SCOPE_INVALID'; END IF;
 IF (context->>'amountMinor')::numeric<=0 OR (context->>'amountMinor')::numeric<>trunc((context->>'amountMinor')::numeric) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_TOTALS_INVALID'; END IF;
 received:=(context->>'receivedMinor')::numeric/100;refunded:=(context->>'refundedMinor')::numeric/100;
 deadline:=(context->>'reservationExpiresAt')::timestamptz;payment_time:=(context->>'paymentTime')::timestamptz;
 IF received<0 OR refunded<0 OR received>pi.amount OR refunded>received OR deadline IS NULL
  OR received*100<>trunc(received*100) OR refunded*100<>trunc(refunded*100)
  OR (received>0 AND payment_time IS NULL) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_TOTALS_INVALID'; END IF;
 PERFORM public.refresh_payment_info_totals_internal(pi.id);
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(pi.id);
 conflict:=totals.gross_received>pi.amount OR totals.external_received<>0;
 action_required:=context->>'state'='action_required';
 IF p_action<>'observe' THEN
  IF auth.uid() IS NULL OR NOT public.can_write_orders(o.occasion) OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid() AND organization=(context->>'organizationId')::bigint)
   THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  IF refunded<=0 OR refunded>=pi.amount OR context->>'state'<>'paid' OR o.state NOT IN ('paid','sent') OR totals.invalid_identity
   OR context->'incomplete'='true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_PARTIAL_REFUND_REQUIRED'; END IF;
  IF (p_action='keep' AND cardinality(p_tickets)<>0) OR (p_action='cancel_selected' AND cardinality(p_tickets) NOT BETWEEN 1 AND 1000)
   OR EXISTS(SELECT 1 FROM unnest(p_tickets) selected(id) WHERE selected.id IS NULL OR NOT EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) t WHERE t.id=selected.id AND t.state IN ('paid','sent','ordered'))) THEN RAISE EXCEPTION 'PAYMENT_REFUND_TICKET_UNAVAILABLE'; END IF;
  PERFORM 1 FROM eshop.tickets WHERE id=ANY(p_tickets) ORDER BY id FOR UPDATE;
  IF p_action='cancel_selected' THEN
   PERFORM public.internal_storno_tickets_221(p_tickets);
   UPDATE eshop.orders SET email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
   IF EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state<>'storno') THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  END IF;
  decision:=public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason',CASE WHEN p_action='keep' THEN 'partial_refund_keep' ELSE 'partial_refund_cancel' END,'revision',p_revision,'tickets',to_jsonb(p_tickets)));
  RETURN jsonb_build_object('changed',true,'decisionId',decision,'payment',public.provider_order_payment_projection_internal(o.id));
 END IF;
 IF conflict AND NOT context->'decisions' ? 'financial_conflict' THEN
  action_required:=true;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"action_required"}');
  PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','financial_conflict','revision',p_revision));
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.cancel_order_email_intents(o.id);changed:=true;
 END IF;
 IF received>=pi.amount AND refunded<pi.amount AND NOT conflict AND context->'incomplete'='false'::jsonb THEN
  IF o.state IN ('ordered','created') AND payment_time<=deadline THEN
   transition:=public.update_order_and_tickets_to_paid(o.id);
   IF transition->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'PAYMENT_PAID_TRANSITION_FAILED'; END IF;
   changed:=true;
  ELSIF o.state NOT IN ('paid','sent') THEN
   action_required:=true;
   PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"action_required"}');
   IF NOT context->'decisions' ? 'late_payment' THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','late_payment','revision',p_revision)); END IF;
  END IF;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||jsonb_build_object('state',CASE WHEN action_required THEN 'action_required' ELSE 'paid' END));
 END IF;
 IF refunded>=pi.amount AND received>0 THEN
  IF NOT context->'decisions' ? 'full_refund' THEN
   SELECT array_agg(t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) t WHERE coalesce(t.state,'') NOT IN ('used','storno');
   PERFORM public.internal_storno_tickets_221(cancelled);
   PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','full_refund','revision',p_revision,'tickets',to_jsonb(coalesce(cancelled,'{}'))));
   UPDATE eshop.orders SET state='storno',email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
   PERFORM public.cancel_order_email_intents(o.id);changed:=true;
  END IF;
 ELSIF totals.gross_received=0 AND (p_expired OR (p_unresolved AND deadline<=clock_timestamp())) AND o.state='ordered' THEN
  SELECT array_agg(t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) t WHERE coalesce(t.state,'') NOT IN ('used','storno');
  PERFORM public.internal_storno_tickets_221(cancelled);
  UPDATE eshop.orders SET state='expired',email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
  -- Releasing inventory does not prove financial absence. Keep uncertain recovery alive.
  IF NOT p_unresolved THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"expired"}'); END IF;
  PERFORM public.cancel_order_email_intents(o.id);changed:=true;
 END IF;
 projection:=public.provider_order_payment_projection_internal(o.id);
 IF projection->>'admissionState' IS DISTINCT FROM p_before->>'admissionState' AND
  (projection->>'status'='disputed' OR p_before->>'status'='disputed' OR projection->'reconciliationPending'='true'::jsonb OR p_before->'reconciliationPending'='true'::jsonb) THEN
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('revision',p_revision,'reason',
   CASE WHEN projection->>'status'='disputed' THEN 'dispute_hold' WHEN p_before->>'status'='disputed' THEN 'dispute_release'
   WHEN projection->'reconciliationPending'='true'::jsonb THEN 'reconciliation_hold' ELSE 'reconciliation_release' END));
  IF projection->>'admissionState'='valid' THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  changed:=true;
 END IF;

 FOR fact IN SELECT value FROM jsonb_array_elements(public.payment_provider_call_internal(p_provider,'notification_facts',args)) LOOP
  PERFORM public.notification_center_payment_fact_internal(o.id,p_provider,fact->>'identity',(fact->>'amount')::numeric,fact->>'currency',(fact->>'occurredAt')::timestamptz);
 END LOOP;
 PERFORM public.notification_center_payment_problem_internal(o.id,action_required OR conflict,
  CASE WHEN conflict THEN 'financial_conflict' ELSE 'action_required' END);
 RETURN jsonb_build_object('changed',changed,'payment',projection);
END $$;
REVOKE ALL ON FUNCTION public.apply_provider_payment_effects_internal(text,uuid,text,jsonb,boolean,boolean,text,bigint[]) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/bank.sql
-- Projection only: BankSync owns readiness, warning clocks and incident UUIDs.
CREATE OR REPLACE FUNCTION public.notification_center_bank_incident_internal(p_connection bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE c eshop.bank_sync_connections; h eshop.bank_sync_health; scope record; affected bigint[]; ev uuid; ready boolean; reason text;
BEGIN
 SELECT * INTO c FROM eshop.bank_sync_connections WHERE id=p_connection;
 SELECT * INTO h FROM eshop.bank_sync_health WHERE connection_id=p_connection;
 ready:=coalesce(public.bank_sync_alert_ready(p_connection),false);
 reason:=CASE h.warning_code WHEN 'token_invalid' THEN 'fio_token_invalid_or_inactive'
 WHEN 'account_mismatch' THEN 'fio_receiving_account_mismatch' WHEN 'unavailable' THEN 'transport_unavailable'
 ELSE 'bank_sync_retry_required' END;
 FOR scope IN SELECT a.organization,a.initialized_at FROM public.notification_center_organizations a
 WHERE EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit
  WHERE u.organization=a.organization AND (uba.bank_account=c.bank_account_id OR uba.bank_account IN(
   SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection))) LOOP
  FOR ev IN SELECT id FROM public.notification_center_events WHERE organization=scope.organization AND kind='bank_problem'
   AND data->>'bankConnectionId'=p_connection::text AND status NOT IN ('recovered','resolved')
   AND (h.incident_id IS NULL OR c.state NOT IN ('connected','degraded') OR data->>'incidentId' IS DISTINCT FROM h.incident_id::text) LOOP
   PERFORM public.notification_center_prepared_invalidate(ev);
   UPDATE public.notification_center_events SET status='recovered' WHERE id=ev;
  END LOOP;
  IF NOT ready OR h.incident_id IS NULL OR h.warning_since<scope.initialized_at THEN CONTINUE; END IF;
  SELECT array_agg(DISTINCT oc.id) INTO affected FROM public.occasions oc
  WHERE oc.organization=scope.organization AND (
   EXISTS(SELECT 1 FROM public.forms f WHERE f.occasion=oc.id AND (f.bank_account=c.bank_account_id OR f.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection)))
   OR EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE o.occasion=oc.id AND (pi.bank_account=c.bank_account_id OR pi.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection))));
  ev:=public.notification_center_publish_internal(scope.organization,NULL,'bank_problem',
   'bank:'||p_connection||':incident:'||h.incident_id,
   jsonb_build_object('bankConnectionId',p_connection,'incidentId',h.incident_id,'reason',reason),NULL,h.warning_since,coalesce(affected,'{}'));
  IF ev IS NOT NULL AND EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=ev
   AND (data->>'reason' IS DISTINCT FROM reason OR affected_occasions IS DISTINCT FROM coalesce(affected,'{}'))) THEN
   PERFORM public.notification_center_prepared_invalidate(ev);
   UPDATE public.notification_center_events SET data=data||jsonb_build_object('reason',reason),affected_occasions=coalesce(affected,'{}') WHERE id=ev;
   PERFORM public.notification_center_capture_recipients_internal(ev,NULL);
  END IF;
 END LOOP;
 -- Disconnection/deletion of the final alias still closes already projected sources.
 FOR ev IN SELECT e.id FROM public.notification_center_events e WHERE e.kind='bank_problem'
  AND e.data->>'bankConnectionId'=p_connection::text AND e.status NOT IN ('recovered','resolved')
  AND NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit
   WHERE u.organization=e.organization AND (uba.bank_account=c.bank_account_id OR uba.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection))) LOOP
  PERFORM public.notification_center_prepared_invalidate(ev);
  UPDATE public.notification_center_events SET status='recovered' WHERE id=ev;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_bank_incident_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: eshop_bank_sync/bank_sync_manage.sql
-- Prevent intentional suspension while issued bank instructions still reserve
-- funds. Connection -> canonical order locks match ingest; prepare holds the
-- order lock and checks connection state before issuing its immutable snapshot.
CREATE OR REPLACE FUNCTION public.check_bank_refund_source_operation_internal(p_account bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE accounts bigint[];
BEGIN
 PERFORM 1 FROM eshop.bank_sync_connections c WHERE c.bank_account_id=p_account
  OR c.id IN(SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_account)
  ORDER BY c.id FOR UPDATE;
 SELECT array_agg(DISTINCT id) INTO accounts FROM (
  SELECT p_account id UNION ALL SELECT c.bank_account_id FROM eshop.bank_sync_connections c
   WHERE c.id IN(SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_account)
  UNION ALL SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a
   JOIN eshop.bank_sync_connections c ON c.id=a.connection_id WHERE c.bank_account_id=p_account
 ) scope;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(
  SELECT o.id FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE p.bank_account=ANY(accounts) ORDER BY o.id));
 IF EXISTS(SELECT 1 FROM eshop.refund_requests r JOIN eshop.payment_info p ON p.id=r.payment_info
  WHERE p.bank_account=ANY(accounts) AND r.status IN ('pending','processing','unknown')) THEN
  RAISE EXCEPTION 'BANK_ACCOUNT_HAS_PENDING_REFUND';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_bank_refund_source_operation_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_bank_sync_connection(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM public.check_is_admin_for_bank_account(p_bank_account_id);
  SELECT jsonb_build_object('id',c.id,'remote_bank_account_id',c.remote_bank_account_id,'state',c.state,'mode',c.mode,
    'receiving_address',CASE WHEN c.pairing_code IS NOT NULL THEN c.pairing_code||'@banksync.festapp.net' END,
    'bank_pull_at',c.bank_pull_at,'receiver_commit_at',c.receiver_commit_at,'last_error',c.last_error,
    'observation_id',c.observation_id::text,'warning_pending',public.bank_sync_warning_pending(c.id),'token_expiry_at',c.token_expiry_at) INTO v_result FROM eshop.bank_sync_connections c
    WHERE c.bank_account_id=p_bank_account_id OR c.id IN
      (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_bank_account_id);
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_connection(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_connection(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.begin_bank_sync_operation(p_id uuid,p_account_id bigint,p_operation text,p_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_operation eshop.bank_sync_operations%ROWTYPE; v_inserted integer;
BEGIN
  PERFORM public.require_bank_authoring_scope_internal(p_account_id,NULL);
  PERFORM public.check_is_admin_for_bank_account(p_account_id);
  IF p_operation='suspend' THEN PERFORM public.check_bank_refund_source_operation_internal(p_account_id); END IF;
  INSERT INTO eshop.bank_sync_operations(id,bank_account_id,actor,operation,payload_sha256,state)
    VALUES(p_id,p_account_id,auth.uid(),p_operation,p_hash,'pending') ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  IF v_inserted>0 THEN
    PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('bank.operation',NULL,NULL),
      jsonb_build_object('actor',auth.uid(),'recipient','bank:'||p_account_id,'global','all'));
  END IF;
  SELECT * INTO STRICT v_operation FROM eshop.bank_sync_operations WHERE id=p_id OR (bank_account_id=p_account_id AND actor=auth.uid() AND operation=p_operation
      AND payload_sha256=p_hash AND state IN ('pending','running','uncertain')) ORDER BY (id=p_id) DESC LIMIT 1 FOR UPDATE;
  IF v_operation.actor IS DISTINCT FROM auth.uid() OR v_operation.bank_account_id<>p_account_id
    OR v_operation.operation<>p_operation OR v_operation.payload_sha256<>p_hash THEN
    RAISE EXCEPTION 'BANK_SYNC_OPERATION_CONFLICT';
  END IF;
  RETURN jsonb_build_object('id',v_operation.id,'state',v_operation.state,'result',v_operation.result);
END;
$$;
REVOKE ALL ON FUNCTION public.begin_bank_sync_operation(uuid,bigint,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.begin_bank_sync_operation(uuid,bigint,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_bank_sync_operation(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_op eshop.bank_sync_operations%ROWTYPE; v_account eshop.bank_accounts%ROWTYPE; v_conn eshop.bank_sync_connections%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_op FROM eshop.bank_sync_operations WHERE id=p_id;
  IF v_op.operation='suspend' THEN PERFORM public.check_bank_refund_source_operation_internal(v_op.bank_account_id); END IF;
  UPDATE eshop.bank_sync_operations SET state='running',lease_token=gen_random_uuid(),updated_at=now() WHERE id=p_id
    AND (state IN ('pending','uncertain','failed') OR (state='running' AND updated_at<now()-interval '5 minutes'))
    RETURNING * INTO v_op;
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_OPERATION_BUSY'; END IF;
  SELECT * INTO STRICT v_account FROM eshop.bank_accounts WHERE id=v_op.bank_account_id;
  SELECT * INTO v_conn FROM eshop.bank_sync_connections WHERE bank_account_id=v_op.bank_account_id;
  RETURN jsonb_build_object('lease_token',v_op.lease_token,'account_number',v_account.account_number,'provider',COALESCE(v_conn.provider,public.bank_sync_provider_for_account(v_account.account_number)),'title',v_account.title,
    'connection_id',v_conn.id,'remote_id',v_conn.remote_bank_account_id,'pairing_code',v_conn.pairing_code,
    'state',v_conn.state,'mode',v_conn.mode,'barrier',v_conn.legacy_blocked_at,'manifest_sha256',v_conn.manifest_sha256,'request',v_op.request,'token_cipher',v_op.token_cipher);
END;
$$;
REVOKE ALL ON FUNCTION public.claim_bank_sync_operation(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_bank_sync_operation(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_bank_sync_operation(p_id uuid,p_state text,p_result jsonb,p_lease_token uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF p_state NOT IN ('uncertain','completed','failed') THEN RAISE EXCEPTION 'BANK_SYNC_OPERATION_STATE_INVALID'; END IF;
  UPDATE eshop.bank_sync_operations SET state=p_state,result=p_result,token_cipher=CASE WHEN p_state='completed' THEN NULL ELSE token_cipher END,updated_at=now() WHERE id=p_id AND state='running' AND lease_token=p_lease_token;
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_OPERATION_NOT_CLAIMED'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_bank_sync_operation(uuid,text,jsonb,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_bank_sync_operation(uuid,text,jsonb,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.save_bank_sync_connection(p_operation_id uuid,p_instance_id text,p_remote_id text,p_pairing_code text,p_mode text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_op eshop.bank_sync_operations%ROWTYPE; v_account eshop.bank_accounts%ROWTYPE; v_id bigint;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO STRICT v_op FROM eshop.bank_sync_operations WHERE id=p_operation_id AND state='running';
  PERFORM public.check_bank_account_writable(v_op.bank_account_id);
  IF v_op.operation<>'create' THEN RAISE EXCEPTION 'BANK_SYNC_PROVISION_OPERATION_REQUIRED'; END IF;
  SELECT * INTO STRICT v_account FROM eshop.bank_accounts WHERE id=v_op.bank_account_id FOR UPDATE;
  -- Activation adopts historical movement identities under the account lock.
  -- Existing accounts use the same canonical provisioning path as new accounts.
  INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
    provider,mode,state,pairing_code,manifest_sha256)
    VALUES(p_instance_id,'festapp',p_remote_id,v_account.id,upper(regexp_replace(v_account.account_number,'\s','','g')),
      public.bank_sync_provider_for_account(v_account.account_number),p_mode,'provisioning',p_pairing_code,v_op.payload_sha256)
    ON CONFLICT(bank_account_id) DO UPDATE SET pairing_code=EXCLUDED.pairing_code
    WHERE eshop.bank_sync_connections.remote_bank_account_id=EXCLUDED.remote_bank_account_id
      AND eshop.bank_sync_connections.instance_id=EXCLUDED.instance_id RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_CONNECTION_MAPPING_CONFLICT'; END IF;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.save_bank_sync_connection(uuid,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_bank_sync_connection(uuid,text,text,text,text) TO service_role;

DROP FUNCTION IF EXISTS public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text);
DROP FUNCTION IF EXISTS public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text,text);
CREATE OR REPLACE FUNCTION public.update_bank_sync_connection_metadata(p_id bigint,p_pairing_code text,p_expiry timestamptz,p_state text,p_observation_id bigint,p_mode text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF p_observation_id IS NULL OR p_observation_id<=0 THEN RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_REQUIRED'; END IF;
  UPDATE eshop.bank_sync_connections SET pairing_history=CASE WHEN p_pairing_code IS NOT NULL AND pairing_code IS DISTINCT FROM p_pairing_code
      THEN pairing_history||jsonb_build_array(jsonb_build_object('code',pairing_code,'retired_at',now())) ELSE pairing_history END,
    pairing_code=COALESCE(p_pairing_code,pairing_code),
    token_expiry_at=CASE WHEN p_mode='api' THEN p_expiry ELSE COALESCE(p_expiry,token_expiry_at) END,
    mode=COALESCE(p_mode,mode),observation_id=GREATEST(observation_id,p_observation_id),
    state=CASE WHEN p_state IN ('connected','degraded') AND observation_id>p_observation_id THEN state ELSE p_state END
    WHERE id=p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_CONNECTION_NOT_FOUND'; END IF;
  PERFORM public.notification_center_bank_incident_internal(p_id);
END;
$$;
REVOKE ALL ON FUNCTION public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.update_bank_sync_connection_metadata(bigint,text,timestamptz,text,bigint,text) TO service_role;

CREATE OR REPLACE FUNCTION public.begin_bank_sync_observation(p_connection_id bigint)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF NOT EXISTS(SELECT 1 FROM eshop.bank_sync_connections WHERE id=p_connection_id) THEN
    RAISE EXCEPTION 'BANK_SYNC_CONNECTION_NOT_FOUND';
  END IF;
  RETURN nextval('eshop.bank_sync_observation_ids')::text;
END;
$$;
REVOKE ALL ON FUNCTION public.begin_bank_sync_observation(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.begin_bank_sync_observation(bigint) TO service_role;

DROP FUNCTION IF EXISTS public.record_bank_sync_pull(bigint,timestamptz,text);
CREATE OR REPLACE FUNCTION public.record_bank_sync_pull(p_id bigint,p_success_at timestamptz,p_error text,p_observation_id bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF p_observation_id IS NULL OR p_observation_id<=0 THEN RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_REQUIRED'; END IF;
  UPDATE eshop.bank_sync_connections SET observation_id=p_observation_id,
    bank_pull_at=GREATEST(p_success_at,bank_pull_at),last_error=left(p_error,256),
    failure_since=CASE WHEN p_error IS NULL THEN NULL
      WHEN last_error IS NULL OR (p_success_at IS NOT NULL AND (bank_pull_at IS NULL OR p_success_at>bank_pull_at)) THEN now()
      ELSE COALESCE(failure_since,now()) END,
    failure_observed_at=CASE WHEN p_error IS NOT NULL THEN now() END,
    state=CASE WHEN state IN ('connected','degraded') THEN
      CASE WHEN p_error IS NOT NULL THEN 'degraded' WHEN p_success_at IS NOT NULL THEN 'connected' ELSE state END
      ELSE state END WHERE id=p_id AND observation_id<p_observation_id;
  IF NOT FOUND THEN RETURN false; END IF;
  -- Successful pull recovery invalidates the projected incident immediately.
  IF p_error IS NULL AND p_success_at IS NOT NULL THEN
   UPDATE eshop.bank_sync_health SET warning_code=NULL,warning_since=NULL,incident_id=NULL WHERE connection_id=p_id;
  END IF;
  PERFORM public.notification_center_bank_incident_internal(p_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.record_bank_sync_pull(bigint,timestamptz,text,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_bank_sync_pull(bigint,timestamptz,text,bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.get_bank_sync_observations(p_bank_account_id bigint,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM public.check_is_admin_for_bank_account(p_bank_account_id);
  SELECT COALESCE(jsonb_agg(row_to_json(q)),'[]'::jsonb) INTO v_result FROM (
    SELECT i.delivery_id,i.received_at,i.outcome,i.payload->'data' AS bank_data
      FROM eshop.bank_sync_inbox i JOIN eshop.bank_sync_connections c ON c.id=i.connection_id
      WHERE (c.bank_account_id=p_bank_account_id OR c.id IN
        (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_bank_account_id))
        AND i.outcome LIKE 'quarantined_%' AND i.resolution IS NULL ORDER BY i.received_at DESC,i.delivery_id LIMIT LEAST(GREATEST(p_limit,1),100)
  ) q;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_observations(bigint,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_observations(bigint,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.stage_bank_sync_operation(p_id uuid,p_hash text,p_request jsonb,p_token_cipher jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF p_request ? 'token' OR p_request->>'operation_id' IS DISTINCT FROM p_id::text THEN
    RAISE EXCEPTION 'BANK_SYNC_REQUEST_INVALID';
  END IF;
  UPDATE eshop.bank_sync_operations SET request=COALESCE(request,p_request||jsonb_build_object('expected_pairing',
      (SELECT c.pairing_code FROM eshop.bank_sync_connections c WHERE c.bank_account_id=bank_sync_operations.bank_account_id))),
      token_cipher=COALESCE(token_cipher,p_token_cipher)
    WHERE id=p_id AND payload_sha256=p_hash AND state IN ('pending','uncertain');
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_OPERATION_NOT_STAGEABLE'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.stage_bank_sync_operation(uuid,text,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.stage_bank_sync_operation(uuid,text,jsonb,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.get_recoverable_bank_sync_operations()
RETURNS TABLE(id uuid,request jsonb,token_cipher jsonb,payload_sha256 text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  RETURN QUERY SELECT o.id,o.request,o.token_cipher,o.payload_sha256 FROM eshop.bank_sync_operations o
    WHERE o.request IS NOT NULL AND o.state IN ('pending','uncertain','running')
      AND o.updated_at<now()-interval '5 minutes' ORDER BY o.updated_at,o.id LIMIT 10;
END;
$$;
REVOKE ALL ON FUNCTION public.get_recoverable_bank_sync_operations() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_recoverable_bank_sync_operations() TO service_role;

-- Only the authenticated management handler calls this after checking bank-admin rights.
CREATE OR REPLACE FUNCTION public.get_pending_bank_sync_details(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  RETURN (SELECT jsonb_build_object('id',id,'request',request,'payload_sha256',payload_sha256)
    FROM eshop.bank_sync_operations WHERE bank_account_id=p_bank_account_id AND operation='update_details'
    AND state IN ('pending','running','uncertain') ORDER BY created_at LIMIT 1);
END;
$$;
REVOKE ALL ON FUNCTION public.get_pending_bank_sync_details(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_bank_sync_details(bigint) TO service_role;


-- SOURCE: eshop_bank_sync/bank_sync_health.sql
-- BankSync observations and one durable notification incident per connection.
CREATE TABLE IF NOT EXISTS eshop.bank_sync_health (
  connection_id bigint PRIMARY KEY REFERENCES eshop.bank_sync_connections(id) ON DELETE CASCADE,
  checked_at timestamptz NOT NULL DEFAULT now(),
  ingest_enabled boolean,
  polling_enabled boolean,
  token_present boolean,
  warning_code text,
  warning_since timestamptz,
  incident_id uuid
);
ALTER TABLE eshop.bank_sync_health ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.bank_sync_health FROM PUBLIC,anon,authenticated,service_role;

-- Internal read helper. Only authorized domain RPCs may expose these details.
CREATE OR REPLACE FUNCTION public.bank_sync_problem(p_connection_id bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
  SELECT CASE
    WHEN c.state='suspended' THEN 'suspended'
    WHEN c.state IN ('provisioning','shadow') THEN 'not_configured'
    WHEN c.mode='email' AND c.pairing_code IS NULL THEN 'email_missing'
    WHEN c.last_error='bank_sync_unavailable' THEN 'unavailable'
    WHEN c.mode='api' AND h.token_present IS FALSE THEN 'token_missing'
    WHEN c.last_error='fio_token_invalid_or_inactive' THEN 'token_invalid'
    WHEN c.last_error='fio_receiving_account_mismatch' THEN 'account_mismatch'
    WHEN c.last_error='fio_temporarily_unavailable' THEN 'temporary_failure'
    WHEN h.ingest_enabled IS FALSE OR (c.mode='api' AND h.polling_enabled IS FALSE) THEN 'connection_disabled'
    WHEN c.last_error IS NOT NULL OR c.state='degraded' THEN 'bank_error'
    -- bank_pull_at is a local copy of BankSync's successful pull timestamp.
    -- Only a fresh remote health observation can prove that polling stalled;
    -- an unmonitored or expired snapshot is not evidence of a bank failure.
    WHEN c.mode='api' AND h.checked_at>now()-interval '10 minutes'
      AND COALESCE(c.bank_pull_at,c.created_at)<now()-interval '30 minutes' THEN 'stale'
    ELSE NULL END
  FROM eshop.bank_sync_connections c LEFT JOIN eshop.bank_sync_health h ON h.connection_id=c.id
  WHERE c.id=p_connection_id;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_problem(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- A lone failed request must not turn into a warning merely as time passes.
-- Require another failed observation at least ten minutes after the first,
-- and a recent observation. Recovery and intervening bank success reset this
-- clock in record_bank_sync_pull, including ordinary account status reads.
CREATE OR REPLACE FUNCTION public.bank_sync_warning_pending(p_connection_id bigint)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
  SELECT COALESCE(c.state IN ('connected','degraded') AND (c.last_error IS NOT NULL OR c.state='degraded') AND (
    c.failure_since IS NULL OR c.failure_observed_at IS NULL
    OR c.failure_observed_at<c.failure_since+interval '10 minutes'
    OR c.failure_observed_at<=now()-interval '10 minutes'),false)
  FROM eshop.bank_sync_connections c WHERE c.id=p_connection_id;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_warning_pending(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_warning(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE v_title text; v_type text; v_connection bigint; v_code text; v_contacts jsonb;
BEGIN
  SELECT title,type INTO v_title,v_type FROM eshop.bank_accounts WHERE id=p_bank_account_id;
  IF NOT FOUND OR v_type='CASH' THEN RETURN NULL; END IF;
  SELECT c.id INTO v_connection FROM eshop.bank_sync_connections c WHERE c.bank_account_id=p_bank_account_id
    OR c.id IN (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_bank_account_id);
  v_code:=CASE WHEN v_connection IS NULL THEN 'not_configured' ELSE public.bank_sync_problem(v_connection) END;
  IF v_code IS NULL THEN RETURN NULL; END IF;
  IF v_code IN ('token_invalid','account_mismatch','temporary_failure','unavailable','bank_error')
    AND public.bank_sync_warning_pending(v_connection) THEN RETURN NULL; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name',NULLIF(btrim(concat_ws(' ',ui.name,ui.surname)),''),
    'email',public.get_user_delivery_email(ui.id)) ORDER BY ui.name,ui.surname,ui.id),'[]'::jsonb)
    INTO v_contacts FROM eshop.bank_account_users bau JOIN public.user_info ui ON ui.id=bau."user"
    WHERE bau.bank_account=p_bank_account_id AND bau.is_admin;
  RETURN jsonb_build_object('code',v_code,'bank_account_title',v_title,'contacts',v_contacts,
    'bank_account_id',p_bank_account_id,'is_admin',EXISTS (
      SELECT 1 FROM eshop.bank_account_users bau WHERE bau.bank_account=p_bank_account_id
        AND bau."user"=auth.uid() AND bau.is_admin));
END;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_warning(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_bank_sync_health_targets(p_organization_id bigint)
RETURNS TABLE(connection_id bigint,remote_bank_account_id text,mode text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  RETURN QUERY SELECT c.id,c.remote_bank_account_id,c.mode FROM eshop.bank_sync_connections c
    WHERE c.legacy_blocked_at IS NOT NULL AND c.state IN ('connected','degraded','suspended')
      AND EXISTS (SELECT 1 FROM eshop.unit_bank_accounts ub JOIN public.units u ON u.id=ub.unit
        WHERE u.organization=p_organization_id AND (ub.bank_account=c.bank_account_id
          OR ub.bank_account IN (SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=c.id)))
    ORDER BY (SELECT h.checked_at FROM eshop.bank_sync_health h WHERE h.connection_id=c.id) NULLS FIRST,c.id LIMIT 100;
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_health_targets(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_health_targets(bigint) TO service_role;

-- Response policy belongs to Festapp, not to the bank transport adapter.
-- Unknown/temporary failures never ask an administrator to replace credentials.
CREATE OR REPLACE FUNCTION public.bank_sync_requires_action(p_code text)
RETURNS boolean LANGUAGE sql IMMUTABLE STRICT SET search_path=public,extensions AS $$
  SELECT p_code IN ('token_missing','token_invalid','account_mismatch','email_missing','connection_disabled');
$$;
REVOKE ALL ON FUNCTION public.bank_sync_requires_action(text) FROM PUBLIC,anon,authenticated,service_role;

-- Shared by admission and the final email validity check. Old observations and
-- recovered connections must not produce delayed, misleading notifications.
CREATE OR REPLACE FUNCTION public.bank_sync_alert_ready(p_connection_id bigint)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
  SELECT COALESCE((SELECT h.warning_code IS NOT NULL
    AND h.warning_since<=now()-CASE WHEN public.bank_sync_requires_action(h.warning_code)
      THEN interval '10 minutes' ELSE interval '60 minutes' END
    AND h.checked_at>now()-interval '10 minutes'
    AND c.state IN ('connected','degraded')
    AND public.bank_sync_problem(c.id)=h.warning_code
    FROM eshop.bank_sync_health h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id
    WHERE c.id=p_connection_id),false);
$$;
REVOKE ALL ON FUNCTION public.bank_sync_alert_ready(bigint) FROM PUBLIC,anon,authenticated,service_role;

DROP FUNCTION IF EXISTS public.record_bank_sync_health(bigint,bigint,timestamptz,text,boolean,boolean,boolean);
CREATE OR REPLACE FUNCTION public.record_bank_sync_health(p_organization_id bigint,p_connection_id bigint,
 p_success_at timestamptz,p_error text,p_ingest_enabled boolean,p_polling_enabled boolean,p_token_present boolean,p_observation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections; v_code text; v_new_incident boolean;
BEGIN
  PERFORM public.require_service_role();
  SELECT c.* INTO STRICT v_connection FROM eshop.bank_sync_connections c
    WHERE c.id=p_connection_id AND EXISTS (SELECT 1 FROM eshop.unit_bank_accounts ub JOIN public.units u ON u.id=ub.unit
      WHERE u.organization=p_organization_id AND (ub.bank_account=c.bank_account_id OR ub.bank_account IN
        (SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=c.id))) FOR UPDATE;
  IF p_error IS NOT NULL AND p_error NOT IN ('fio_token_invalid_or_inactive','fio_receiving_account_mismatch','bank_sync_retry_required',
    'fio_temporarily_unavailable','bank_sync_unavailable') THEN
    RAISE EXCEPTION 'BANK_SYNC_HEALTH_ERROR_INVALID';
  END IF;
  IF NOT public.record_bank_sync_pull(p_connection_id,p_success_at,p_error,p_observation_id) THEN RETURN; END IF;
  INSERT INTO eshop.bank_sync_health(connection_id,checked_at,ingest_enabled,polling_enabled,token_present)
    VALUES(p_connection_id,now(),p_ingest_enabled,p_polling_enabled,p_token_present)
    ON CONFLICT(connection_id) DO UPDATE SET checked_at=now(),
      ingest_enabled=COALESCE(EXCLUDED.ingest_enabled,eshop.bank_sync_health.ingest_enabled),
      polling_enabled=COALESCE(EXCLUDED.polling_enabled,eshop.bank_sync_health.polling_enabled),
      token_present=COALESCE(EXCLUDED.token_present,eshop.bank_sync_health.token_present);
  IF v_connection.mode='email' AND v_connection.state='degraded' AND p_error IS NULL AND p_ingest_enabled IS TRUE THEN
    UPDATE eshop.bank_sync_connections SET state='connected' WHERE id=p_connection_id;
  END IF;
  v_code:=CASE WHEN v_connection.state IN ('connected','degraded') THEN public.bank_sync_problem(p_connection_id) END;
  -- Preserve the outage clock across changing retry symptoms. An actionable
  -- fault starts its own incident so a prior availability warning cannot hide it.
  SELECT (public.bank_sync_requires_action(v_code) IS DISTINCT FROM public.bank_sync_requires_action(warning_code))
    OR (public.bank_sync_requires_action(v_code) AND v_code IS DISTINCT FROM warning_code)
    INTO v_new_incident FROM eshop.bank_sync_health WHERE connection_id=p_connection_id;
  UPDATE eshop.bank_sync_health SET warning_code=v_code,
    warning_since=CASE WHEN v_code IS NULL THEN NULL WHEN v_new_incident THEN now() ELSE COALESCE(warning_since,now()) END,
    incident_id=CASE WHEN v_code IS NULL THEN NULL WHEN v_new_incident THEN gen_random_uuid() ELSE COALESCE(incident_id,gen_random_uuid()) END WHERE connection_id=p_connection_id;
  PERFORM public.notification_center_bank_incident_internal(p_connection_id);
END;
$$;
REVOKE ALL ON FUNCTION public.record_bank_sync_health(bigint,bigint,timestamptz,text,boolean,boolean,boolean,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_bank_sync_health(bigint,bigint,timestamptz,text,boolean,boolean,boolean,bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.configure_bank_sync_health_monitor(p_organization_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_url text;
BEGIN
  PERFORM public.require_service_role();
  IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_organization_id) THEN RAISE EXCEPTION 'ORGANIZATION_NOT_FOUND'; END IF;
  SELECT regexp_replace(worker_url,'/process-email-queue$','/bank-sync-reconcile') INTO v_url FROM public.email_capacity;
  IF v_url IS NULL OR v_url !~ '^https://[^/]+/functions/v1/bank-sync-reconcile$' THEN RAISE EXCEPTION 'BANK_SYNC_MONITOR_URL_REQUIRED'; END IF;
  PERFORM cron.schedule('festapp_bank_sync_health_'||p_organization_id,'*/5 * * * *',
    format('SELECT net.http_post(url:=%L,body:=jsonb_build_object(''requestSecret'',public.generate_request_secret(3600),''monitor_organization_id'',%s),timeout_milliseconds:=360000)',v_url,p_organization_id));
END;
$$;
REVOKE ALL ON FUNCTION public.configure_bank_sync_health_monitor(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configure_bank_sync_health_monitor(bigint) TO service_role;

-- Explicit administrator remediation starts a new observation window. Pending
-- incident mail becomes invalid immediately when synchronization is changed.
CREATE OR REPLACE FUNCTION public.reset_bank_sync_control_health(p_connection_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  DELETE FROM eshop.bank_sync_health WHERE connection_id=p_connection_id;
  PERFORM public.notification_center_bank_incident_internal(p_connection_id);
END;
$$;
REVOKE ALL ON FUNCTION public.reset_bank_sync_control_health(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reset_bank_sync_control_health(bigint) TO service_role;


-- SOURCE: notification_center/email_bank_cutover.sql
-- The source cutover stops producers first. Audit/prepared content stays intact.
DROP FUNCTION IF EXISTS public.enqueue_bank_sync_health_alerts(bigint);
DROP FUNCTION IF EXISTS public.claim_notification_center_bank_health(integer);
DROP FUNCTION IF EXISTS public.complete_notification_center_bank_health(bigint,uuid,timestamptz,text,timestamptz);
DROP TABLE IF EXISTS public.notification_center_bank_health;
-- Ambiguous old center episodes become a baseline, never matched by time/text.
SELECT public.notification_center_prepared_invalidate(id) FROM public.notification_center_events
 WHERE kind='bank_problem' AND NOT data ? 'incidentId' AND status NOT IN ('resolved','recovered');
UPDATE public.notification_center_events SET status='resolved'
 WHERE kind='bank_problem' AND NOT data ? 'incidentId';
UPDATE public.email_messages SET workflow_state='cancelled',last_error='notification_cutover_baseline'
 WHERE code='BANK_SYNC_WARNING' AND workflow_state IN ('blocked','pending','retry_wait') AND lease_token IS NULL;
-- Unknown/in-flight records remain under the original queue reconciliation.
-- No state here claims that unknown messages were delivered.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.email_messages WHERE code='BANK_SYNC_WARNING'
  AND workflow_state IN ('blocked','pending','preparing','sending','retry_wait','unknown')) THEN
  RAISE EXCEPTION 'legacy_bank_notification_drain_required';
 END IF;
END $$;
-- Profiles serialize mandatory mail without opting anyone into optional mail.
-- Historical recipients also retain incident tombstones if their roles change.
WITH eligible AS MATERIALIZED(
 SELECT ui.id,ui.data FROM public.user_info ui WHERE EXISTS(
  SELECT 1 FROM eshop.bank_account_users bu WHERE bu."user"=ui.id AND bu.is_admin)
 OR EXISTS(SELECT 1 FROM public.email_messages m WHERE m.recipient_user=ui.id AND m.code='BANK_SYNC_WARNING'))
INSERT INTO public.notification_center_email_profiles(recipient,stopped,locale)
SELECT id,true,CASE WHEN data->>'locale' IN ('cs','en','de','pl','sk','uk') THEN data->>'locale' ELSE 'cs' END FROM eligible ON CONFLICT DO NOTHING;
-- Bank policy is required and has no editable subscription representation.
UPDATE public.notification_center_email_subscriptions SET kinds=kinds-'bank_problem' WHERE kinds ? 'bank_problem';
DO $$ DECLARE prior bigint; retained bigint; BEGIN
 SELECT count(DISTINCT "user") INTO prior FROM eshop.bank_account_users WHERE is_admin;
 SELECT count(DISTINCT bu."user") INTO retained FROM eshop.bank_account_users bu
 JOIN public.notification_center_email_profiles p ON p.recipient=bu."user" WHERE bu.is_admin
 AND EXISTS(SELECT 1 FROM public.notification_center_organizations a
  CROSS JOIN LATERAL public.notification_center_prepared_allowed_scopes(a.organization,NULL,bu."user") rights WHERE rights.scope LIKE 'bank:%');
 RAISE NOTICE 'bank_notification_recipient_migration: prior=%, retained=%, excluded=%',prior,retained,greatest(prior-retained,0);
END $$;
INSERT INTO public.notification_center_email_items(recipient,delivery_key,disposition)
SELECT DISTINCT p.recipient,'bank:'||(m.data->>'connection_id')||':incident:'||(m.data->>'incident_id'),'baseline'
FROM public.notification_center_email_profiles p JOIN public.email_messages m ON m.recipient_user=p.recipient
WHERE m.code='BANK_SYNC_WARNING' AND m.data->>'incident_id' IS NOT NULL AND m.data->>'connection_id' IS NOT NULL
ON CONFLICT DO NOTHING;
ALTER TABLE eshop.bank_sync_health DROP COLUMN IF EXISTS notified_at;


-- SOURCE: notification_center/maintenance.sql
CREATE OR REPLACE FUNCTION public.initialize_notification_center_internal(p_organization bigint,p_timezone text DEFAULT 'Europe/Prague')
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE baseline_at timestamptz;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('notification-center-organization:'||p_organization,0));
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN RAISE EXCEPTION 'notification_timezone_invalid'; END IF;
 IF EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_organization) THEN RETURN; END IF;
 baseline_at:=clock_timestamp();
 INSERT INTO public.notification_center_organizations(organization,timezone) VALUES(p_organization,p_timezone);
 -- Baseline once: existing incidents and capacity are not historical alerts.
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
 PERFORM public.notification_center_form_availability_internal(f.id,baseline_at,NULL,true) FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE oc.organization=p_organization;
 UPDATE public.notification_center_organizations SET collection_started_at=baseline_at WHERE organization=p_organization;
END $$;
CREATE OR REPLACE FUNCTION public.maintain_notification_center(p_limit integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m record; maximum bigint; after_id bigint; processed integer:=0; projected integer; availability integer; purge_ids uuid[];
BEGIN
 PERFORM public.notification_center_require_service();
 INSERT INTO public.notification_center_maintenance(name) VALUES('email') ON CONFLICT DO NOTHING;
 SELECT cursor INTO after_id FROM public.notification_center_maintenance WHERE name='email' FOR UPDATE SKIP LOCKED;
 IF FOUND THEN
  FOR m IN SELECT em.id,em.message_id FROM public.email_messages em JOIN public.notification_center_organizations a ON a.organization=em.organization
   LEFT JOIN public.notification_center_source_state ns ON ns.organization=em.organization AND ns.source_key='email:'||em.message_id
   WHERE em.id>after_id AND em.workflow_state IN ('pending','preparing','sending','retry_wait','unknown')
   AND (coalesce((ns.state->>'dueAt')::timestamptz,em.target_time)<=clock_timestamp()-interval '30 minutes' OR (em.message_kind='waitlist_offer' AND em.expires_at<=clock_timestamp()+interval '5 minutes'))
   ORDER BY em.id LIMIT greatest(1,least(p_limit,500)) LOOP
   PERFORM public.notification_center_email_internal(m.message_id); maximum:=m.id; processed:=processed+1;
  END LOOP;
  UPDATE public.notification_center_maintenance SET cursor=coalesce(maximum,0) WHERE name='email';
 END IF;
 availability:=public.notification_center_evaluate_forms_internal(p_limit);
 projected:=public.project_notification_center(p_limit);
 -- Retain active incidents; cleanup is projection-only, never business/email history.
 DELETE FROM public.notification_center_deliveries WHERE (event_id,recipient,attention_revision) IN (
  SELECT d.event_id,d.recipient,d.attention_revision FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
  WHERE d.delivered_at<clock_timestamp()-interval '90 days' AND (e.status='recovered' OR e.kind NOT IN ('email_problem','bank_problem','payment_problem','provider_problem','capacity_full','capacity_warning')) LIMIT greatest(1,least(p_limit,500)));
 SELECT array_agg(id) INTO purge_ids FROM (SELECT e.id FROM public.notification_center_events e
  WHERE e.occurred_at<clock_timestamp()-interval '90 days' AND (e.status='recovered' OR e.kind NOT IN ('email_problem','bank_problem','payment_problem','provider_problem','capacity_full','capacity_warning'))
  AND NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries WHERE event_id=e.id) AND e.projected_revision=e.attention_revision
  LIMIT greatest(1,least(p_limit,500)) FOR UPDATE SKIP LOCKED) expired;
 -- Retract derived counts and dirty-source debt before recipients cascade away.
 -- A recovered long-running incident may still have an unprocessed repair.
 IF cardinality(purge_ids)>0 THEN
  PERFORM public.notification_center_prepared_delete_events(purge_ids);
  DELETE FROM public.notification_center_events WHERE id=ANY(purge_ids);
 END IF;
 RETURN jsonb_build_object('evaluated',processed,'projected',projected,'availabilityEvaluated',availability);
END $$;
REVOKE ALL ON FUNCTION public.maintain_notification_center(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.maintain_notification_center(integer) TO service_role;

REVOKE ALL ON FUNCTION public.initialize_notification_center_internal(bigint,text) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: eshop_bank_sync/bank_sync_authority.sql
CREATE OR REPLACE FUNCTION public.bank_sync_accounts_match(p_transaction_id bigint,p_target_account bigint)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
  SELECT EXISTS (
    SELECT 1 FROM eshop.transactions t
    JOIN eshop.bank_transaction_identities i ON i.transaction_id=t.id AND i.identity_kind='movement'
    JOIN eshop.bank_sync_connections c ON c.instance_id=i.instance_id AND c.provider=i.provider
      AND c.physical_account=i.physical_account AND c.bank_account_id=t.bank_account_id
    WHERE t.id=p_transaction_id AND t.ingest_source='banksync_api' AND c.legacy_blocked_at IS NOT NULL
      AND (p_target_account=c.bank_account_id OR p_target_account IN
        (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id))
  );
$$;
REVOKE ALL ON FUNCTION public.bank_sync_accounts_match(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.activate_bank_sync_connection(p_connection_id bigint,p_manifest_sha256 text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO STRICT v_connection FROM eshop.bank_sync_connections WHERE id=p_connection_id;
  IF v_connection.manifest_sha256 IS DISTINCT FROM p_manifest_sha256 OR v_connection.pairing_code IS NULL THEN
    RAISE EXCEPTION 'BANK_SYNC_MANIFEST_OR_PAIRING_MISMATCH';
  END IF;
  IF EXISTS(SELECT 1 FROM eshop.bank_sync_account_aliases WHERE bank_account_id=v_connection.bank_account_id AND connection_id<>p_connection_id)
    OR EXISTS(SELECT 1 FROM eshop.bank_sync_connections c JOIN eshop.bank_sync_account_aliases a ON a.bank_account_id=c.bank_account_id WHERE a.connection_id=p_connection_id AND c.id<>p_connection_id) THEN
    RAISE EXCEPTION 'BANK_SYNC_ALIAS_AUTHORITY_CONFLICT';
  END IF;
  PERFORM 1 FROM eshop.bank_accounts WHERE id=v_connection.bank_account_id OR id IN
    (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection_id)
    ORDER BY id FOR UPDATE;
  -- Adopt known bank movement IDs before the first replay. Historical ledger
  -- rows and manual pairing decisions remain unchanged; the receiver compares
  -- bank facts and quarantines a mismatch instead of crediting history twice.
  IF v_connection.provider='FIO' THEN
    INSERT INTO eshop.bank_transaction_identities(instance_id,provider,physical_account,identity_kind,identity_value,transaction_id)
      SELECT v_connection.instance_id,'FIO',v_connection.physical_account,'movement',t.transaction_id::text,t.id
      FROM eshop.transactions t
      WHERE (t.bank_account_id=v_connection.bank_account_id OR t.bank_account_id IN
        (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection_id))
        AND t.ingest_source IN ('fio_api','legacy_api','legacy') AND t.transaction_id IS NOT NULL
      ON CONFLICT(instance_id,provider,physical_account,identity_kind,identity_value) DO UPDATE
        SET transaction_id=eshop.bank_transaction_identities.transaction_id
        WHERE eshop.bank_transaction_identities.transaction_id=EXCLUDED.transaction_id;
    IF EXISTS(SELECT 1 FROM eshop.transactions t JOIN eshop.bank_transaction_identities i
      ON i.instance_id=v_connection.instance_id AND i.provider='FIO' AND i.physical_account=v_connection.physical_account
        AND i.identity_kind='movement' AND i.identity_value=t.transaction_id::text
      WHERE t.bank_account_id=v_connection.bank_account_id AND t.ingest_source IN ('fio_api','legacy_api','legacy')
        AND i.transaction_id<>t.id) THEN RAISE EXCEPTION 'BANK_SYNC_HISTORICAL_IDENTITY_CONFLICT'; END IF;
  END IF;
  UPDATE eshop.bank_accounts SET is_fetch_enabled=false WHERE id=v_connection.bank_account_id OR id IN
    (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection_id);
  UPDATE eshop.bank_sync_connections SET state='connected',legacy_blocked_at=COALESCE(legacy_blocked_at,now())
    WHERE id=p_connection_id AND manifest_sha256=p_manifest_sha256;
  PERFORM public.notification_center_bank_incident_internal(p_connection_id);
END;
$$;
REVOKE ALL ON FUNCTION public.activate_bank_sync_connection(bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.activate_bank_sync_connection(bigint,text) TO service_role;


-- SOURCE: account_deletion/account_deletion_contract.sql
CREATE OR REPLACE FUNCTION public.create_account_deletion_request(
  p_user uuid,
  p_organization bigint,
  p_token_hash text,
  p_expires_at timestamptz,
  p_masked_email text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_previous public.account_deletion_requests%ROWTYPE;
  v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  IF p_token_hash !~ '^[0-9a-f]{64}$' OR p_expires_at <= clock_timestamp() THEN
    RAISE EXCEPTION 'account_deletion_invalid_request' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_info ui
    WHERE ui.id = p_user AND ui.organization = p_organization
  ) THEN
    RAISE EXCEPTION 'account_deletion_account_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_previous
  FROM public.account_deletion_requests
  WHERE user_id = p_user
    AND status IN ('email_pending','email_sent','deletion_pending')
  ORDER BY created_at DESC LIMIT 1 FOR UPDATE;

  IF v_previous.status = 'deletion_pending' THEN
    RAISE EXCEPTION 'account_deletion_already_pending' USING ERRCODE = '55000';
  END IF;
  IF v_previous.id IS NOT NULL AND v_previous.cooldown_until > clock_timestamp() THEN
    RAISE EXCEPTION 'account_deletion_cooldown' USING ERRCODE = 'P0001';
  END IF;
  IF v_previous.id IS NOT NULL THEN
    UPDATE public.account_deletion_requests
    SET status = 'revoked', token_hash = NULL, masked_email = NULL,
        updated_at = clock_timestamp()
    WHERE id = v_previous.id;
  END IF;

  INSERT INTO public.account_deletion_requests(
    user_id, organization, token_hash, masked_email, expires_at, cooldown_until
  ) VALUES (
    p_user, p_organization, p_token_hash, p_masked_email, p_expires_at,
    clock_timestamp() + interval '5 minutes'
  ) RETURNING * INTO v_request;

  RETURN jsonb_build_object('requestId', v_request.id, 'expiresAt', v_request.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_account_deletion_email_state(
  p_request_id uuid,
  p_delivered boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.require_service_role();
  UPDATE public.account_deletion_requests
  SET status = CASE WHEN p_delivered THEN 'email_sent' ELSE 'revoked' END,
      email_sent_at = CASE WHEN p_delivered THEN clock_timestamp() ELSE NULL END,
      token_hash = CASE WHEN p_delivered THEN token_hash ELSE NULL END,
      masked_email = CASE WHEN p_delivered THEN masked_email ELSE NULL END,
      error_class = CASE WHEN p_delivered THEN NULL ELSE 'email_delivery' END,
      updated_at = clock_timestamp()
  WHERE id = p_request_id AND status = 'email_pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.inspect_account_deletion_token(p_token_hash text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  IF p_token_hash !~ '^[0-9a-f]{64}$' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE token_hash = p_token_hash OR used_token_hash = p_token_hash
  LIMIT 1;
  IF v_request.id IS NULL THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.status = 'completed' THEN RETURN jsonb_build_object('status', 'already_completed'); END IF;
  IF v_request.status <> 'email_sent' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('status', 'expired'); END IF;
  RETURN jsonb_build_object('status', 'valid', 'expiresAt', v_request.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_account_deletion(p_token_hash text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_request public.account_deletion_requests%ROWTYPE;
  v_completion_email text;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE token_hash = p_token_hash OR used_token_hash = p_token_hash
  LIMIT 1 FOR UPDATE;
  IF v_request.id IS NULL THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.status = 'completed' THEN RETURN jsonb_build_object('status', 'already_completed'); END IF;
  IF v_request.status IN ('deletion_pending','failed') AND v_request.used_token_hash = p_token_hash THEN
    RETURN jsonb_build_object('status','processing','requestId',v_request.id,
      'userId',v_request.user_id,'organization',v_request.organization,
      'publicDeleted',v_request.public_deleted,'authDeleted',v_request.auth_deleted,
      'onesignalDeleted',v_request.onesignal_deleted);
  END IF;
  IF v_request.status <> 'email_sent' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('status', 'expired'); END IF;

  v_completion_email := public.get_user_delivery_email(v_request.user_id);

  UPDATE public.account_deletion_requests SET
    status='deletion_pending', used_token_hash=token_hash, token_hash=NULL,
    masked_email=NULL, claimed_at=clock_timestamp(), attempt_count=attempt_count+1,
    updated_at=clock_timestamp()
  WHERE id=v_request.id RETURNING * INTO v_request;
  -- The claim and first-party cleanup share one transaction. Consequently an
  -- already-issued JWT cannot regain domain access between confirmation and a
  -- later Edge call; its public.user_info row is gone before claim commits.
  PERFORM public.cleanup_account_deletion_domain(v_request.id);
  RETURN jsonb_build_object('status','processing','requestId',v_request.id,
    'userId',v_request.user_id,'organization',v_request.organization,
    'completionEmail',v_completion_email,
    'publicDeleted',true,'authDeleted',false,'onesignalDeleted',false);
END;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_account_deletion_domain(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_user uuid; v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE id=p_request_id FOR UPDATE;
  IF v_request.id IS NULL OR v_request.status NOT IN ('deletion_pending','failed') THEN
    RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000';
  END IF;
  IF v_request.public_deleted THEN RETURN jsonb_build_object('status','already_deleted'); END IF;
  v_user := v_request.user_id;
  -- Recipient scheduling disappears before role/profile removal. Queue audit
  -- keeps only its original UUID; final context validation cancels unsent mail.
  PERFORM 1 FROM public.notification_center_email_profiles WHERE recipient=v_user FOR UPDATE;
  DELETE FROM public.notification_center_email_profiles WHERE recipient=v_user;
  DELETE FROM public.notification_center_email_dispatches WHERE recipient=v_user AND state IN ('collecting','omitted');


  PERFORM public.record_account_deletion_sync_v1(
    v_user,v_request.organization);

  UPDATE public.cleaning_reports SET created_by=NULL WHERE created_by=v_user;
  UPDATE public.cleaning_reports SET resolved_by=NULL WHERE resolved_by=v_user;
  UPDATE public.news SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.orders_history SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.bank_account_requests SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.transactions SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.refund_requests SET created_by=NULL WHERE created_by=v_user;
  UPDATE public.client_commits SET actor_id=NULL, actor_display=NULL WHERE actor_id=v_user;
  DELETE FROM public.event_feedback WHERE "user"=v_user;

  DELETE FROM public.client_mutation_receipts WHERE actor_id=v_user;
  DELETE FROM public.client_sync_private_scopes WHERE user_id=v_user;
  DELETE FROM public.activity_assignments WHERE "user"=v_user;
  DELETE FROM public.activity_history WHERE user_id=v_user;
  DELETE FROM public.event_users_saved WHERE "user"=v_user;
  DELETE FROM public.event_users WHERE "user"=v_user;
  DELETE FROM public.user_groups WHERE "user"=v_user;
  DELETE FROM public.user_companions WHERE "user"=v_user OR companion=v_user;
  DELETE FROM public.user_reset_token WHERE "user"=v_user;
  DELETE FROM eshop.bank_account_users WHERE "user"=v_user;
  PERFORM public.notification_center_prepared_invalidate_user(v_user);
  DELETE FROM public.occasion_users WHERE "user"=v_user;
  DELETE FROM public.unit_users WHERE "user"=v_user;
  DELETE FROM public.organization_users WHERE "user"=v_user;
  PERFORM public.invalidate_external_login_for_user_v1(v_user);
  DELETE FROM public.user_info WHERE id=v_user;

  UPDATE public.account_deletion_requests SET public_deleted=true,
    status='deletion_pending', error_class=NULL, updated_at=clock_timestamp()
  WHERE id=p_request_id;
  RETURN jsonb_build_object('status','deleted');
END;
$$;

CREATE OR REPLACE FUNCTION public.update_account_deletion_job(
  p_request_id uuid,
  p_auth_deleted boolean DEFAULT NULL,
  p_onesignal_deleted boolean DEFAULT NULL,
  p_error_class text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_request public.account_deletion_requests%ROWTYPE; v_assets_done boolean;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests WHERE id=p_request_id FOR UPDATE;
  v_assets_done := COALESCE(v_request.assets_prepared AND
    (SELECT active FROM public.canonical_asset_cutover WHERE singleton) AND
    NOT EXISTS(SELECT 1 FROM public.account_deletion_assets WHERE request_id=p_request_id AND deleted_at IS NULL) AND
    NOT EXISTS(SELECT 1 FROM public.canonical_assets WHERE owner_id=v_request.user_id::text AND deleted_at IS NULL),false);
  UPDATE public.account_deletion_requests SET
    auth_deleted=coalesce(p_auth_deleted,auth_deleted),
    onesignal_deleted=coalesce(p_onesignal_deleted,onesignal_deleted),
    error_class=p_error_class,
    status=CASE
      WHEN v_assets_done AND public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN 'completed'
      WHEN p_error_class IS NOT NULL THEN 'failed' ELSE 'deletion_pending' END,
    completed_at=CASE
      WHEN v_assets_done AND public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN clock_timestamp()
      ELSE completed_at END,
    user_id=CASE
      WHEN v_assets_done AND public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN NULL ELSE user_id END,
    updated_at=clock_timestamp()
  WHERE id=p_request_id AND status IN ('deletion_pending','failed')
  RETURNING * INTO v_request;
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000'; END IF;
  RETURN jsonb_build_object('status',v_request.status);
END;
$$;

REVOKE ALL ON FUNCTION public.create_account_deletion_request(uuid,bigint,text,timestamptz,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_account_deletion_email_state(uuid,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_account_deletion(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cleanup_account_deletion_domain(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_account_deletion_job(uuid,boolean,boolean,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_account_deletion_request(uuid,bigint,text,timestamptz,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_account_deletion_email_state(uuid,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_account_deletion(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_account_deletion_domain(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_account_deletion_job(uuid,boolean,boolean,text) TO service_role;
REVOKE ALL ON FUNCTION public.inspect_account_deletion_token(text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.inspect_account_deletion_token(text) TO anon, service_role;


-- SOURCE: eshop_stripe/connections.sql
CREATE OR REPLACE FUNCTION public.check_stripe_unit_manager_internal(p_unit bigint,p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.payment_provider_unit_manager_internal(p_unit,p_actor) THEN
  RAISE insufficient_privilege USING MESSAGE='STRIPE_UNIT_MANAGER_REQUIRED'; END IF;
 IF public.is_demo_unit(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='DEMO_UNIT_READ_ONLY'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_stripe_unit_manager_internal(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.begin_stripe_connection_flow(p_unit bigint,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE nonce text; flow uuid; org bigint; previous uuid; deadline timestamptz;
BEGIN
 PERFORM public.check_stripe_unit_manager_internal(p_unit,auth.uid());
 SELECT organization INTO org FROM public.units WHERE id=p_unit FOR UPDATE;
 IF NOT public.stripe_unit_feature_enabled_internal(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='STRIPE_FEATURE_DISABLED'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.stripe_disconnect_intents intent JOIN eshop.stripe_connections c ON c.id=intent.connection_id
  WHERE c.unit_id=p_unit AND c.livemode=p_livemode AND intent.state<>'completed') THEN RAISE EXCEPTION 'STRIPE_DISCONNECT_PENDING'; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('stripe.connect',p_unit,org),
  jsonb_build_object('actor',auth.uid(),'unit',p_unit,'organization',org));
 SELECT id INTO previous FROM eshop.stripe_connections WHERE unit_id=p_unit AND livemode=p_livemode AND state IN ('connected','restricted');
 nonce:=encode(extensions.gen_random_bytes(32),'hex');
 deadline:=clock_timestamp()+interval '10 minutes';
 INSERT INTO eshop.stripe_connection_flows(state_hash,actor,organization_id,unit_id,livemode,previous_connection_id,expires_at)
 VALUES(encode(extensions.digest(nonce,'sha256'),'hex'),auth.uid(),org,p_unit,p_livemode,previous,deadline) RETURNING id INTO flow;
 RETURN jsonb_build_object('flowId',flow,'state',nonce,'expiresAt',deadline);
END $$;
REVOKE ALL ON FUNCTION public.begin_stripe_connection_flow(bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.begin_stripe_connection_flow(bigint,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_stripe_connection_flow_internal(p_state text,p_actor uuid,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f eshop.stripe_connection_flows; lease uuid;
BEGIN
 PERFORM public.require_service_role();
 IF p_state IS NULL OR p_state !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_INVALID'; END IF;
 SELECT * INTO f FROM eshop.stripe_connection_flows WHERE state_hash=encode(extensions.digest(p_state,'sha256'),'hex')
  AND actor=p_actor AND livemode=p_livemode AND expires_at>clock_timestamp() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_INVALID'; END IF;
 PERFORM public.check_stripe_unit_manager_internal(f.unit_id,p_actor);
 IF NOT EXISTS(SELECT 1 FROM public.units WHERE id=f.unit_id AND organization=f.organization_id) THEN
  RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_INVALID'; END IF;
 IF f.state='completed' THEN RETURN jsonb_build_object('disposition','replay','result',f.result); END IF;
 IF f.state<>'pending' THEN RETURN jsonb_build_object('disposition','uncertain'); END IF;
 lease:=extensions.gen_random_uuid();
 UPDATE eshop.stripe_connection_flows SET state='claimed',lease_token=lease WHERE id=f.id;
 RETURN jsonb_build_object('disposition','claimed','flowId',f.id,'lease',lease,'unitId',f.unit_id,'organizationId',f.organization_id);
END $$;
REVOKE ALL ON FUNCTION public.claim_stripe_connection_flow_internal(text,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stripe_connection_flow_internal(text,uuid,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_stripe_connection_flow_internal(p_flow uuid,p_lease uuid,p_account jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f eshop.stripe_connection_flows; c eshop.stripe_connections; current_connection uuid; v_result jsonb;
 occasion_scope bigint; mutation uuid; members uuid[]; changed_forms jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO f FROM eshop.stripe_connection_flows WHERE id=p_flow AND state='claimed' AND lease_token=p_lease FOR UPDATE;
 IF NOT FOUND OR f.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_INVALID'; END IF;
 PERFORM public.check_stripe_unit_manager_internal(f.unit_id,f.actor);
 -- Checkout and form saves take form before unit. Keep that order while
 -- replacing future recipients; immutable attempts never participate here.
 IF f.previous_connection_id IS NOT NULL THEN
  PERFORM 1 FROM public.forms form JOIN public.occasions occasion ON occasion.id=form.occasion
   WHERE occasion.unit=f.unit_id AND occasion.organization=f.organization_id ORDER BY form.id FOR UPDATE OF form;
 END IF;
 PERFORM 1 FROM public.units WHERE id=f.unit_id AND organization=f.organization_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_INVALID'; END IF;
 IF p_account->>'accountId' IS NULL OR p_account->>'accountId' !~ '^acct_[A-Za-z0-9]+$'
  OR p_account->'modelVerified' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'STRIPE_ACCOUNT_MODEL_UNVERIFIED'; END IF;
 -- Serialize the global identity before checking ownership, without exposing another organizer.
 PERFORM pg_advisory_xact_lock(hashtextextended((p_account->>'accountId')||':'||f.livemode::text,7351));
 SELECT * INTO c FROM eshop.stripe_connections WHERE account_id=p_account->>'accountId' AND livemode=f.livemode FOR UPDATE;
 IF FOUND AND (c.unit_id<>f.unit_id OR c.organization_id<>f.organization_id) THEN RAISE EXCEPTION 'STRIPE_ACCOUNT_UNAVAILABLE'; END IF;
 SELECT id INTO current_connection FROM eshop.stripe_connections WHERE unit_id=f.unit_id AND livemode=f.livemode AND state IN ('connected','restricted') FOR UPDATE;
 IF current_connection IS DISTINCT FROM f.previous_connection_id AND current_connection IS DISTINCT FROM c.id THEN
  RAISE EXCEPTION 'STRIPE_CONNECTION_CHANGED'; END IF;
 IF current_connection IS NOT NULL AND current_connection IS DISTINCT FROM c.id THEN
  UPDATE eshop.stripe_connections SET state='retired',paused=true WHERE id=current_connection;
 END IF;
 IF c.id IS NULL THEN
  INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused)
  VALUES(f.organization_id,f.unit_id,p_account->>'accountId',f.livemode,'candidate',true) RETURNING * INTO c;
 END IF;
 UPDATE eshop.stripe_connections SET business_name=nullif(left(p_account->>'businessName',200),''),country=p_account->>'country',
  charges_enabled=coalesce((p_account->>'chargesEnabled')::boolean,false),payouts_enabled=coalesce((p_account->>'payoutsEnabled')::boolean,false),
  card_payments_active=coalesce((p_account->>'cardPaymentsActive')::boolean,false),model_verified=true,
  state=CASE WHEN p_account->'ready'='true'::jsonb THEN 'connected' ELSE 'restricted' END,
  checked_at=clock_timestamp(),next_check_at=clock_timestamp()+interval '15 minutes',status_failures=0,status_lease=NULL,status_lease_expires_at=NULL WHERE id=c.id;
 IF current_connection IS NOT NULL AND current_connection IS DISTINCT FROM c.id THEN
  FOR occasion_scope IN SELECT DISTINCT form.occasion FROM public.forms form JOIN public.occasions occasion ON occasion.id=form.occasion
   WHERE occasion.unit=f.unit_id AND occasion.organization=f.organization_id
    AND public.payment_provider_connection_internal(form.data->'payments','stripe')=current_connection ORDER BY form.occasion LOOP
   mutation:=substr(encode(extensions.digest(f.id::text||':forms:'||occasion_scope::text,'sha256'),'hex'),1,32)::uuid;
   PERFORM public.begin_anonymous_client_mutation_v1(mutation,'inventory.form.stripe_recipient',occasion_scope,mutation,
    encode(extensions.digest(f.id::text||':'||c.id::text||':'||occasion_scope::text,'sha256'),'hex'));
   SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO members FROM public.occasion_users ou WHERE ou.occasion=occasion_scope;
   WITH updated AS (
    UPDATE public.forms SET data=jsonb_set(data,'{payments}',public.merge_form_payments_internal(data->'payments',NULL)||jsonb_build_object('providerConnections',
      coalesce(public.merge_form_payments_internal(data->'payments',NULL)->'providerConnections','{}')||jsonb_build_object('stripe',c.id))),updated_at=clock_timestamp()
     WHERE occasion=occasion_scope AND public.payment_provider_connection_internal(data->'payments','stripe')=current_connection RETURNING id
   ), versions AS (
    INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
     SELECT 'form','occasion',occasion_scope,id::text,1 FROM updated
     ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
      SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp() RETURNING aggregate_id
   ) SELECT coalesce(jsonb_agg(jsonb_build_object('entityType','form','entityId',aggregate_id::bigint,'operation','update',
     'safeLabel','Card payment recipient','changedFields',jsonb_build_array('configuration'))),'[]'::jsonb) INTO changed_forms FROM versions;
   PERFORM public.complete_profile_inventory_membership_mutation_v1(mutation,occasion_scope,'inventory.form.stripe_recipient',
    changed_forms,members,jsonb_build_object('connectionId',c.id),'service');
  END LOOP;
 END IF;
 -- Existing card forms follow a verified replacement; bank-only forms and
 -- the tenant's payment switch are unchanged. New recipients remain paused.
 v_result:=jsonb_build_object('connectionId',c.id,'unitId',f.unit_id,'connected',true);
 UPDATE eshop.stripe_connection_flows SET state='completed',result=v_result WHERE id=f.id;
 INSERT INTO eshop.stripe_connection_audit(connection_id,flow_id,actor,action)
 VALUES(c.id,f.id,f.actor,CASE WHEN current_connection=c.id THEN 'reconnected' WHEN current_connection IS NOT NULL THEN 'replaced' ELSE 'connected' END);
 PERFORM public.notification_center_provider_connection_internal('stripe',c.id);
 IF current_connection IS NOT NULL AND current_connection IS DISTINCT FROM c.id THEN
  PERFORM public.notification_center_provider_connection_internal('stripe',current_connection);
 END IF;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.complete_stripe_connection_flow_internal(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_stripe_connection_flow_internal(uuid,uuid,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.finish_stripe_connection_flow_error_internal(p_flow uuid,p_lease uuid,p_denied boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.stripe_connection_flows SET state=CASE WHEN p_denied THEN 'denied' ELSE 'uncertain' END
 WHERE id=p_flow AND lease_token=p_lease AND state='claimed';
 IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_INVALID'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.finish_stripe_connection_flow_error_internal(uuid,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.finish_stripe_connection_flow_error_internal(uuid,uuid,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.get_stripe_unit_connection(p_unit bigint,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.check_stripe_unit_manager_internal(p_unit,auth.uid());
 SELECT jsonb_build_object('connectionId',id,'businessName',business_name,'country',country,'state',state,
  'paused',paused,'chargesEnabled',charges_enabled,'payoutsEnabled',payouts_enabled,'cardPaymentsActive',card_payments_active,
  'modelVerified',model_verified,'checkedAt',checked_at,'statusFailures',status_failures,
  'disconnectState',(SELECT state FROM eshop.stripe_disconnect_intents WHERE connection_id=eshop.stripe_connections.id AND state<>'completed'),
  'dashboardUrl','https://dashboard.stripe.com/'||account_id||CASE WHEN livemode THEN '' ELSE '/test' END||'/dashboard') INTO result FROM eshop.stripe_connections
 WHERE unit_id=p_unit AND livemode=p_livemode AND state IN ('connected','restricted','revoked')
 ORDER BY (state IN ('connected','restricted')) DESC,coalesce(checked_at,created_at) DESC LIMIT 1;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_stripe_unit_connection(bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_stripe_unit_connection(bigint,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_stripe_unit_paused(p_unit bigint,p_livemode boolean,p_paused boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE conn uuid; prior_pause boolean; org bigint;
BEGIN
 PERFORM public.check_stripe_unit_manager_internal(p_unit,auth.uid());
 IF p_paused IS NULL THEN RAISE EXCEPTION 'STRIPE_PAUSE_INVALID'; END IF;
 SELECT id,paused,organization_id INTO conn,prior_pause,org FROM eshop.stripe_connections WHERE unit_id=p_unit AND livemode=p_livemode AND state IN ('connected','restricted') FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_CONNECTION_UNAVAILABLE'; END IF;
 IF NOT p_paused AND EXISTS(SELECT 1 FROM eshop.stripe_disconnect_intents WHERE connection_id=conn AND state<>'completed') THEN RAISE EXCEPTION 'STRIPE_DISCONNECT_PENDING'; END IF;
 IF prior_pause=p_paused THEN RETURN; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('stripe.connect',p_unit,org),jsonb_build_object('actor',auth.uid(),'unit',p_unit,'organization',org));
 UPDATE eshop.stripe_connections SET paused=p_paused WHERE id=conn;
 INSERT INTO eshop.stripe_connection_audit(connection_id,actor,action) VALUES(conn,auth.uid(),CASE WHEN p_paused THEN 'paused' ELSE 'resumed' END);
END $$;
REVOKE ALL ON FUNCTION public.set_stripe_unit_paused(bigint,boolean,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.set_stripe_unit_paused(bigint,boolean,boolean) TO authenticated;


-- SOURCE: eshop_stripe/connection_status.sql
CREATE OR REPLACE FUNCTION public.claim_stripe_connection_status_internal(p_account text,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.stripe_connections; lease uuid;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM eshop.stripe_connections WHERE account_id=p_account AND livemode=p_livemode FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('disposition','unrelated'); END IF;
 IF c.status_lease_expires_at>clock_timestamp() THEN RETURN jsonb_build_object('disposition','busy'); END IF;
 lease:=extensions.gen_random_uuid();
 UPDATE eshop.stripe_connections SET status_lease=lease,status_lease_expires_at=clock_timestamp()+interval '120 seconds' WHERE id=c.id;
 RETURN jsonb_build_object('disposition','dispatch','connectionId',c.id,'lease',lease);
END $$;
REVOKE ALL ON FUNCTION public.claim_stripe_connection_status_internal(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stripe_connection_status_internal(text,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.commit_stripe_connection_status_internal(p_connection uuid,p_lease uuid,p_status jsonb,p_event jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.stripe_connections; prior eshop.stripe_event_inbox; next_state text; unavailable boolean; result jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=p_connection FOR UPDATE;
 IF p_event IS NOT NULL THEN
  IF p_event->>'id' IS NULL OR p_event->>'id' !~ '^evt_[A-Za-z0-9]+$' OR p_event->>'bodyHash' IS NULL OR p_event->>'bodyHash' !~ '^[a-f0-9]{64}$'
   OR p_event->>'accountId' IS DISTINCT FROM c.account_id OR (p_event->>'livemode')::boolean IS DISTINCT FROM c.livemode
   OR p_event->>'type' IS NULL OR p_event->>'type' NOT IN ('account.updated','account.application.deauthorized','account.application.authorized') THEN RAISE EXCEPTION 'STRIPE_EVENT_IDENTITY_INVALID'; END IF;
  SELECT * INTO prior FROM eshop.stripe_event_inbox WHERE connection_id=c.id AND event_id=p_event->>'id';
  IF FOUND THEN
   IF prior.body_sha256<>p_event->>'bodyHash' OR prior.receipt IS NULL THEN RAISE EXCEPTION 'STRIPE_EVENT_RECEIPT_INVALID'; END IF;
   -- The duplicate may have claimed a fresh read lease; release only that lease.
   UPDATE eshop.stripe_connections SET status_lease=NULL,status_lease_expires_at=NULL WHERE id=c.id AND status_lease=p_lease;
   RETURN prior.receipt;
  END IF;
 END IF;
 IF p_lease IS NULL OR c.status_lease IS DISTINCT FROM p_lease OR c.status_lease_expires_at IS NULL OR c.status_lease_expires_at<=clock_timestamp()
  OR p_status->>'accountId' IS DISTINCT FROM c.account_id THEN RAISE EXCEPTION 'STRIPE_CONNECTION_STATUS_INVALID'; END IF;
 unavailable:=coalesce(p_status->'accessUnavailable'='true'::jsonb,false);
 IF NOT unavailable AND EXISTS(SELECT 1 FROM unnest(ARRAY['modelVerified','chargesEnabled','payoutsEnabled','cardPaymentsActive']) name
  WHERE jsonb_typeof(p_status->name) IS DISTINCT FROM 'boolean') THEN RAISE EXCEPTION 'STRIPE_CONNECTION_STATUS_INVALID'; END IF;
 next_state:=CASE WHEN c.state='retired' THEN 'retired' WHEN c.state='revoked' OR unavailable THEN 'revoked'
  WHEN p_status->'modelVerified'='true'::jsonb AND p_status->'chargesEnabled'='true'::jsonb AND p_status->'cardPaymentsActive'='true'::jsonb THEN 'connected' ELSE 'restricted' END;
 UPDATE eshop.stripe_connections SET state=next_state,
  business_name=CASE WHEN unavailable THEN business_name ELSE nullif(left(p_status->>'businessName',200),'') END,
  country=CASE WHEN unavailable THEN country ELSE p_status->>'country' END,
  model_verified=CASE WHEN unavailable THEN model_verified ELSE (p_status->>'modelVerified')::boolean END,
  charges_enabled=NOT unavailable AND coalesce((p_status->>'chargesEnabled')::boolean,false),
  payouts_enabled=NOT unavailable AND coalesce((p_status->>'payoutsEnabled')::boolean,false),
  card_payments_active=NOT unavailable AND coalesce((p_status->>'cardPaymentsActive')::boolean,false),
  paused=paused OR next_state IN ('revoked','retired') OR p_status->'modelVerified'='false'::jsonb,
  checked_at=clock_timestamp(),next_check_at=clock_timestamp()+CASE WHEN next_state IN ('retired','revoked') THEN interval '1 day' ELSE interval '15 minutes' END,
  status_failures=0,status_lease=NULL,status_lease_expires_at=NULL WHERE id=c.id;
 IF next_state<>c.state OR unavailable OR c.charges_enabled IS DISTINCT FROM (p_status->>'chargesEnabled')::boolean
  OR c.payouts_enabled IS DISTINCT FROM (p_status->>'payoutsEnabled')::boolean OR c.model_verified IS DISTINCT FROM (p_status->>'modelVerified')::boolean THEN
  INSERT INTO eshop.stripe_connection_audit(connection_id,action) VALUES(c.id,CASE WHEN next_state='revoked' AND c.state<>'revoked' THEN 'revoked' ELSE 'status_changed' END);
 END IF;
 result:=jsonb_build_object('committed',true,'connectionId',c.id);
 IF unavailable THEN
  UPDATE eshop.stripe_disconnect_intents SET state='completed',result=jsonb_build_object('disconnected',true),completed_at=clock_timestamp()
   WHERE connection_id=c.id AND state<>'completed';
 END IF;
 IF p_event IS NOT NULL THEN
  INSERT INTO eshop.stripe_event_inbox(connection_id,event_id,body_sha256,event_type,provider_created_at,committed_at,receipt)
   VALUES(c.id,p_event->>'id',p_event->>'bodyHash',p_event->>'type',to_timestamp((p_event->>'created')::bigint),clock_timestamp(),result);
 END IF;
 PERFORM public.notification_center_provider_connection_internal('stripe',c.id);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.commit_stripe_connection_status_internal(uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.commit_stripe_connection_status_internal(uuid,uuid,jsonb,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.fail_stripe_connection_status_internal(p_connection uuid,p_lease uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.stripe_connections SET status_failures=least(status_failures+1,1000),status_lease=NULL,status_lease_expires_at=NULL,
  next_check_at=clock_timestamp()+make_interval(secs=>least(3600,30*power(2,least(status_failures,7)))::integer)
 WHERE id=p_connection AND status_lease=p_lease AND p_lease IS NOT NULL;
 IF FOUND THEN PERFORM public.notification_center_provider_connection_internal('stripe',p_connection); END IF;
END $$;
REVOKE ALL ON FUNCTION public.fail_stripe_connection_status_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fail_stripe_connection_status_internal(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_recoverable_stripe_connections_internal(p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT coalesce(jsonb_agg(jsonb_build_object('accountId',x.account_id,'connectionId',x.id)),'[]'::jsonb) INTO result FROM (
  SELECT id,account_id FROM eshop.stripe_connections WHERE livemode=p_livemode AND next_check_at<=statement_timestamp()
   AND coalesce(status_lease_expires_at<=statement_timestamp(),true) ORDER BY next_check_at,id LIMIT 2
 ) x;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_recoverable_stripe_connections_internal(boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_recoverable_stripe_connections_internal(boolean) TO service_role;


-- SOURCE: eshop_barion/connections.sql
-- Operator-managed sandbox installation only. This neither discovers keys nor
-- attests production merchant/marketplace/refund eligibility.
CREATE OR REPLACE FUNCTION public.configure_barion_sandbox_connection_internal(p_organization bigint,p_unit bigint,p_shop text,p_name text,p_forms bigint[],p_enabled boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE existing eshop.barion_connections; connection uuid;
BEGIN
 PERFORM public.require_service_role();
 IF p_shop IS NULL OR p_shop !~ '^[a-f0-9]{32}$' OR nullif(p_name,'') IS NULL OR p_forms IS NULL OR cardinality(p_forms)>20 OR p_enabled IS NULL
  OR NOT EXISTS(SELECT 1 FROM public.units WHERE id=p_unit AND organization=p_organization)
  OR EXISTS(SELECT 1 FROM unnest(p_forms) fid WHERE fid IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE f.id=fid AND oc.unit=p_unit AND oc.organization=p_organization))
  THEN RAISE EXCEPTION 'BARION_SANDBOX_SCOPE_INVALID'; END IF;
 PERFORM 1 FROM public.units WHERE id=p_unit FOR UPDATE;
 SELECT * INTO existing FROM eshop.barion_connections WHERE account_id=p_shop FOR UPDATE;
 IF existing.id IS NOT NULL AND (existing.unit_id<>p_unit OR existing.organization_id<>p_organization) THEN RAISE EXCEPTION 'BARION_SANDBOX_SCOPE_INVALID'; END IF;
 INSERT INTO eshop.barion_connections(organization_id,unit_id,account_id,business_name,sandbox_form_ids,enabled) VALUES(p_organization,p_unit,p_shop,p_name,p_forms,p_enabled)
 ON CONFLICT(account_id) DO UPDATE SET business_name=excluded.business_name,sandbox_form_ids=excluded.sandbox_form_ids,enabled=excluded.enabled RETURNING id INTO connection;
 PERFORM public.notification_center_provider_connection_internal('barion',connection);
 RETURN connection;
END $$;
REVOKE ALL ON FUNCTION public.configure_barion_sandbox_connection_internal(bigint,bigint,text,text,bigint[],boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configure_barion_sandbox_connection_internal(bigint,bigint,text,text,bigint[],boolean) TO service_role;
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('barion.checkout.token.minute','barion.checkout','actor','rolling',60,60,5,10),
 ('barion.checkout.unit.minute','barion.checkout','unit','rolling',60,60,100,200),
 ('barion.checkout.organization.day','barion.checkout','organization','rolling',86400,3600,5000,10000)
 ON CONFLICT(rule_key) DO NOTHING;


-- SOURCE: eshop_barion/runtime.sql
-- Single service boundary. Every operation checks service role; browser tokens
-- are independently scoped/hashed and never treated as account credentials.
CREATE OR REPLACE FUNCTION public.barion_runtime_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.barion_attempts; c eshop.barion_connections; cap eshop.barion_capabilities;
 lease uuid; facts jsonb; tx jsonb; existing eshop.barion_movements; before_projection jsonb; source jsonb;
 result jsonb; digest text; seconds integer; total bigint; refunded bigint; held boolean:=false; stamp timestamptz:=clock_timestamp();
BEGIN
 PERFORM public.require_service_role();
 IF p_operation='recoverable' THEN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('attemptId',q.id,'accountId',q.account_id)),'[]') FROM (
   SELECT a.id,c.account_id FROM eshop.barion_attempts a JOIN eshop.barion_connections c ON c.id=a.connection_id
   WHERE a.next_reconcile_at<=stamp AND (a.lease_expires_at IS NULL OR a.lease_expires_at<=stamp)
   ORDER BY a.next_reconcile_at,a.id LIMIT 10) q);
 ELSIF p_operation='callback_schedule' THEN
  IF p_args->>'paymentId' IS NULL OR p_args->>'paymentId' !~ '^[a-f0-9]{32}$' THEN RAISE EXCEPTION 'BARION_CALLBACK_INVALID'; END IF;
  -- Coalesce bursts; callback cannot cause a remote create or overwrite facts.
  UPDATE eshop.barion_attempts SET next_reconcile_at=least(next_reconcile_at,greatest(stamp,coalesce(last_synced_at,'-infinity')+interval '6 seconds')) WHERE remote_id=p_args->>'paymentId';
  RETURN NULL;
 ELSIF p_operation='purge' THEN
  WITH selected AS (SELECT s.attempt_id FROM eshop.barion_sources s JOIN eshop.barion_capabilities c USING(token_hash) WHERE c.expires_at<=stamp ORDER BY c.expires_at LIMIT 100),
   removed AS (DELETE FROM eshop.barion_sources WHERE attempt_id IN(SELECT attempt_id FROM selected) RETURNING 1) SELECT count(*) INTO total FROM removed;
  RETURN to_jsonb(total);
 END IF;
 IF p_operation IN ('claim_checkout','read','handoff') THEN
  IF p_args->>'token' IS NULL OR p_args->>'token' !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  SELECT * INTO cap FROM eshop.barion_capabilities WHERE token_hash=encode(extensions.digest(p_args->>'token','sha256'),'hex')
   AND scope=CASE p_operation WHEN 'claim_checkout' THEN 'order_pay' WHEN 'handoff' THEN 'handoff' ELSE p_args->>'scope' END AND expires_at>stamp;
  IF cap.token_hash IS NULL OR (p_operation='read' AND p_args->>'scope' NOT IN ('order_pay','return_read')) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  SELECT * INTO STRICT a FROM eshop.barion_attempts WHERE id=cap.attempt_id;
 ELSIF p_operation IN ('source','attach_handoff') THEN SELECT * INTO STRICT a FROM eshop.barion_attempts WHERE order_id=(p_args->>'orderId')::bigint;
 ELSE SELECT * INTO STRICT a FROM eshop.barion_attempts WHERE id=(p_args->>'attemptId')::uuid; END IF;
 SELECT * INTO STRICT c FROM eshop.barion_connections WHERE id=a.connection_id;
 IF p_operation='read' THEN RETURN public.provider_order_payment_projection_internal(a.order_id);
 ELSIF p_operation='source' THEN
  SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash,
   'payBaseUrl',regexp_replace(a.return_base_url,'/payments/barion/return$','/payments/barion/pay'),'payment',public.provider_order_payment_projection_internal(a.order_id)) INTO result
  FROM eshop.barion_sources s JOIN eshop.barion_capabilities pc USING(token_hash)
   WHERE s.attempt_id=a.id AND s.command_id=(p_args->>'commandId')::uuid AND pc.scope='order_pay' AND pc.expires_at>stamp;
  IF result IS NULL THEN RETURN jsonb_build_object('payment',public.provider_order_payment_projection_internal(a.order_id)); END IF;
  RETURN result;
 ELSIF p_operation='attach_handoff' THEN
  IF p_args->>'tokenHash' IS NULL OR p_args->>'tokenHash' !~ '^[a-f0-9]{64}$' OR NOT EXISTS(SELECT 1 FROM eshop.barion_sources WHERE attempt_id=a.id AND command_id=(p_args->>'commandId')::uuid) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  INSERT INTO eshop.barion_capabilities(token_hash,attempt_id,scope,expires_at) VALUES(p_args->>'tokenHash',a.id,'handoff',least(a.reservation_expires_at,stamp+interval '30 minutes')) ON CONFLICT DO NOTHING;
  RETURN NULL;
 END IF;
 IF p_operation='claim_checkout' THEN PERFORM public.payment_policy_fence_internal(a.organization_id); END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.order_id]);
 PERFORM 1 FROM eshop.orders WHERE id=a.order_id FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=a.payment_info_id FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.barion_attempts WHERE id=a.id FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info JOIN public.occasions oc ON oc.id=o.occasion
  WHERE o.id=a.order_id AND pi.id=a.payment_info_id AND pi.payment_method='barion' AND pi.barion_connection_id=a.connection_id
   AND pi.amount*100=a.amount_minor AND pi.currency_code=a.currency AND oc.organization=a.organization_id AND oc.unit=a.unit_id) THEN RAISE EXCEPTION 'BARION_SCOPE_INVALID'; END IF;
 before_projection:=public.provider_order_payment_projection_internal(a.order_id);
 IF p_operation='handoff' THEN
  IF p_args->'consume'='true'::jsonb THEN
   UPDATE eshop.barion_capabilities SET consumed_at=stamp WHERE token_hash=cap.token_hash AND consumed_at IS NULL AND expires_at>stamp;
   IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
   SELECT jsonb_build_object('sealed',sealed,'contentHash',content_hash,'tokenHash',token_hash) INTO source FROM eshop.barion_sources WHERE attempt_id=a.id;
   RETURN jsonb_build_object('source',source);
  END IF;
  RETURN jsonb_build_object('payment',before_projection);
 ELSIF p_operation IN ('claim_checkout','claim_sync') THEN
  IF p_operation='claim_checkout' AND public.payment_collection_action_internal(a.order_id)->'allowed' IS DISTINCT FROM 'true'::jsonb THEN RETURN jsonb_build_object('providerId','barion','disposition','read','payment',before_projection); END IF;
  IF p_operation='claim_sync' AND p_args->>'accountId' IS DISTINCT FROM c.account_id THEN RAISE EXCEPTION 'BARION_SCOPE_INVALID'; END IF;
  IF a.lease_expires_at>stamp OR coalesce(a.last_synced_at,'-infinity')>stamp-interval '6 seconds' THEN
   RETURN jsonb_build_object('providerId','barion','disposition','busy','payment',before_projection); END IF;
  IF p_operation='claim_checkout' AND (a.reservation_expires_at<=stamp OR before_projection->>'status' NOT IN ('open','preparing')) THEN
   RETURN jsonb_build_object('providerId','barion','disposition','read','payment',before_projection); END IF;
  SELECT jsonb_build_object('sealed',sealed,'contentHash',content_hash,'tokenHash',token_hash) INTO source FROM eshop.barion_sources WHERE attempt_id=a.id;
  IF p_operation='claim_checkout' AND a.remote_id IS NULL AND (a.dispatched_at IS NOT NULL OR source IS NULL OR NOT c.enabled) THEN
   RETURN jsonb_build_object('providerId','barion','disposition','busy','payment',before_projection); END IF;
  IF p_operation='claim_checkout' THEN
   PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('barion.checkout',a.unit_id,a.organization_id),
    jsonb_build_object('actor',cap.token_hash,'unit',a.unit_id,'organization',a.organization_id));
  END IF;
  lease:=extensions.gen_random_uuid();
  UPDATE eshop.barion_attempts SET lease_token=lease,lease_expires_at=stamp+interval '120 seconds',
   dispatched_at=CASE WHEN p_operation='claim_checkout' AND remote_id IS NULL THEN coalesce(dispatched_at,stamp) ELSE dispatched_at END,
   state=CASE WHEN p_operation='claim_checkout' AND remote_id IS NULL THEN 'uncertain' ELSE state END WHERE id=a.id;
  RETURN jsonb_build_object('providerId','barion','disposition','dispatch','lease',lease,'checkoutId',a.remote_id,'connectorState','{}'::jsonb,'source',source,'returnBaseUrl',a.return_base_url,
   'snapshot',jsonb_build_object('attemptId',a.id,'accountId',c.account_id,'livemode',false,'amountMinor',a.amount_minor,'currency',a.currency,
    'orderReference','Order '||(SELECT order_symbol FROM eshop.orders WHERE id=a.order_id),'createdAt',extract(epoch FROM a.created_at)::bigint,
    'expiresAt',extract(epoch FROM a.reservation_expires_at)::bigint,'idempotencyKey',a.id,'locale',a.locale));
 END IF;
 IF p_args->>'lease' IS NULL OR a.lease_token IS NULL OR a.lease_token IS DISTINCT FROM (p_args->>'lease')::uuid OR a.lease_expires_at<=stamp THEN RAISE EXCEPTION 'BARION_LEASE_LOST'; END IF;
 IF p_operation='commit_checkout' THEN
  facts:=p_args->'checkout';
  IF facts->>'id' IS NULL OR facts->>'id' !~ '^[a-f0-9]{32}$' OR (a.remote_id IS NOT NULL AND a.remote_id<>facts->>'id')
   OR facts->>'url' IS DISTINCT FROM ('https://secure.test.barion.com/Pay?Id='||(facts->>'id'))
   OR (facts->>'expiresAt')::bigint IS DISTINCT FROM extract(epoch FROM a.reservation_expires_at)::bigint THEN RAISE EXCEPTION 'BARION_CHECKOUT_INVALID'; END IF;
  UPDATE eshop.barion_attempts SET remote_id=facts->>'id',checkout_url=facts->>'url',reconcile_failures=0,state=CASE WHEN state IN ('preparing','uncertain') THEN 'open' ELSE state END,
   lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=stamp+interval '6 seconds' WHERE id=a.id;
 ELSIF p_operation IN ('fail','defer') THEN
  seconds:=CASE WHEN p_operation='fail' THEN 60 ELSE (p_args->>'seconds')::integer END;
  IF seconds IS NULL OR seconds NOT BETWEEN 1 AND 3600 THEN RAISE EXCEPTION 'BARION_RECOVERY_INVALID'; END IF;
  IF p_operation='defer' THEN
   PERFORM public.apply_provider_payment_effects_internal('barion',a.id,'unresolved:'||a.id,before_projection,false,true);
  END IF;
  UPDATE eshop.barion_attempts SET lease_token=NULL,lease_expires_at=NULL,reconcile_failures=reconcile_failures+1,next_reconcile_at=stamp+make_interval(secs=>seconds) WHERE id=a.id;
 ELSIF p_operation='ingest' THEN
  facts:=p_args->'facts';
  IF facts->>'checkoutId' IS NULL OR facts->>'checkoutId' !~ '^[a-f0-9]{32}$' OR facts->>'paymentId' IS DISTINCT FROM facts->>'checkoutId'
   OR (a.remote_id IS NOT NULL AND a.remote_id<>facts->>'checkoutId')
   OR facts->>'checkoutStatus' IS NULL OR facts->>'checkoutStatus' NOT IN ('open','complete','expired')
   OR jsonb_typeof(facts->'movements') IS DISTINCT FROM 'array' OR jsonb_array_length(facts->'movements')>100
   OR jsonb_typeof(facts->'disputes') IS DISTINCT FROM 'array' OR jsonb_array_length(facts->'disputes')>1
   OR facts ? 'noCheckoutVerified' THEN RAISE EXCEPTION 'BARION_FACTS_INVALID'; END IF;
  -- An incomplete or changed history never subtracts a previously proved fact.
  held:=a.financial_hold OR jsonb_array_length(facts->'disputes')>0 OR EXISTS(
   SELECT 1 FROM eshop.barion_movements m WHERE m.attempt_id=a.id AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(facts->'movements') x WHERE x->>'providerId'=m.provider_id));
  FOR tx IN SELECT * FROM jsonb_array_elements(facts->'movements') LOOP
   IF tx->>'providerId' IS NULL OR tx->>'providerId' !~ '^[a-f0-9]{32}$' OR tx->>'kind' IS NULL OR tx->>'kind' NOT IN ('payment','refund')
    OR jsonb_typeof(tx->'amountMinor') IS DISTINCT FROM 'number' OR (tx->>'amountMinor')::numeric<>trunc((tx->>'amountMinor')::numeric)
    OR (tx->>'amountMinor')::numeric NOT BETWEEN 1 AND a.amount_minor OR tx->>'currency' IS DISTINCT FROM a.currency
    OR jsonb_typeof(tx->'occurredAt') IS DISTINCT FROM 'number' OR (tx->>'occurredAt')::numeric<>trunc((tx->>'occurredAt')::numeric)
    OR (tx->>'occurredAt')::bigint<extract(epoch FROM a.created_at)::bigint OR (tx->>'occurredAt')::bigint>extract(epoch FROM stamp+interval '1 minute')::bigint
    THEN RAISE EXCEPTION 'BARION_MOVEMENT_INVALID'; END IF;
   SELECT * INTO existing FROM eshop.barion_movements WHERE connection_id=c.id AND provider_id=tx->>'providerId';
   IF FOUND THEN
    IF existing.attempt_id<>a.id OR existing.kind<>tx->>'kind' OR existing.amount_minor<>(tx->>'amountMinor')::bigint OR existing.currency<>tx->>'currency'
      OR existing.occurred_at<>to_timestamp((tx->>'occurredAt')::bigint) THEN RAISE EXCEPTION 'BARION_MOVEMENT_CONFLICT'; END IF;
   ELSE INSERT INTO eshop.barion_movements VALUES(a.id,c.id,tx->>'providerId',tx->>'kind',(tx->>'amountMinor')::bigint,a.currency,to_timestamp((tx->>'occurredAt')::bigint)); END IF;
  END LOOP;
  SELECT coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0),coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0) INTO total,refunded FROM eshop.barion_movements WHERE attempt_id=a.id;
  IF total NOT IN (0,a.amount_minor) OR refunded>total THEN RAISE EXCEPTION 'BARION_TOTALS_INVALID'; END IF;
  digest:=encode(extensions.digest(facts::text,'sha256'),'hex');
  INSERT INTO eshop.barion_observations(attempt_id,digest,facts) VALUES(a.id,digest,facts) ON CONFLICT DO NOTHING;
  UPDATE eshop.barion_attempts SET remote_id=facts->>'checkoutId',financial_hold=held,last_synced_at=stamp,reconcile_failures=0,
   state=CASE WHEN state IN ('preparing','uncertain') THEN 'open' ELSE state END WHERE id=a.id;
  PERFORM public.apply_provider_payment_effects_internal('barion',a.id,digest,before_projection,facts->>'checkoutStatus'='expired',false);
  UPDATE eshop.barion_attempts SET lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=stamp+CASE WHEN total>0 THEN interval '15 minutes' ELSE interval '1 minute' END WHERE id=a.id;
 ELSE RAISE EXCEPTION 'BARION_RUNTIME_OPERATION_UNSUPPORTED';
 END IF;
 PERFORM public.notification_center_provider_connection_internal('barion',a.connection_id);
 RETURN jsonb_build_object('committed',true,'payment',public.provider_order_payment_projection_internal(a.order_id));
END $$;
REVOKE ALL ON FUNCTION public.barion_runtime_internal(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.barion_runtime_internal(text,jsonb) TO service_role;


-- SOURCE: eshop_stripe/disconnect.sql
CREATE OR REPLACE FUNCTION public.get_stripe_disconnect_impact(p_unit bigint,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.stripe_connections; result jsonb;
BEGIN
 PERFORM public.check_stripe_unit_manager_internal(p_unit,auth.uid());
 SELECT * INTO c FROM eshop.stripe_connections WHERE unit_id=p_unit AND livemode=p_livemode AND state IN ('connected','restricted','revoked')
  ORDER BY (state<>'revoked') DESC,created_at DESC LIMIT 1;
 IF c.id IS NULL THEN RAISE EXCEPTION 'STRIPE_CONNECTION_UNAVAILABLE'; END IF;
 SELECT jsonb_build_object('connectionId',c.id,'businessName',c.business_name,
  'openAttempts',count(*) FILTER(WHERE state IN ('preparing','open','uncertain') OR lease_expires_at>statement_timestamp() OR refund_cursor IS NOT NULL OR session_lookup_cursor IS NOT NULL),
  'historyCount',count(*),'lastSyncedAt',CASE WHEN bool_or(last_synced_at IS NULL) THEN NULL ELSE min(last_synced_at) END,
  'disconnectState',(SELECT state FROM eshop.stripe_disconnect_intents WHERE connection_id=c.id AND state<>'completed')) INTO result
 FROM eshop.stripe_checkout_attempts WHERE connection_id=c.id;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_stripe_disconnect_impact(bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_stripe_disconnect_impact(bigint,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.begin_stripe_disconnect(p_unit bigint,p_livemode boolean,p_expected_connection uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.stripe_connections; intent eshop.stripe_disconnect_intents;
BEGIN
 PERFORM public.check_stripe_unit_manager_internal(p_unit,auth.uid());
 PERFORM 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE o.unit=p_unit ORDER BY f.id FOR UPDATE OF f;
 PERFORM 1 FROM public.units WHERE id=p_unit FOR UPDATE;
 -- Completed intents also retain their binding. A lost final response must
 -- resume that same intent after the connection was retired, not dispatch again.
 SELECT i.* INTO intent FROM eshop.stripe_disconnect_intents i
 JOIN eshop.stripe_connections stored ON stored.id=i.connection_id
 WHERE i.connection_id=p_expected_connection AND i.actor=auth.uid()
  AND stored.unit_id=p_unit AND stored.livemode=p_livemode
 ORDER BY i.created_at DESC LIMIT 1;
 IF FOUND THEN RETURN jsonb_build_object('intentId',intent.id); END IF;
 SELECT * INTO c FROM eshop.stripe_connections WHERE id=p_expected_connection AND unit_id=p_unit AND livemode=p_livemode AND state IN ('connected','restricted') FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_RECIPIENT_CHANGED'; END IF;
 SELECT * INTO intent FROM eshop.stripe_disconnect_intents WHERE connection_id=c.id AND state<>'completed';
 IF FOUND THEN
  IF intent.actor<>auth.uid() THEN RAISE EXCEPTION 'STRIPE_DISCONNECT_PENDING'; END IF;
  RETURN jsonb_build_object('intentId',intent.id);
 END IF;
 IF EXISTS(SELECT 1 FROM eshop.stripe_connection_flows WHERE unit_id=p_unit AND livemode=p_livemode AND expires_at>clock_timestamp() AND state IN ('pending','claimed','uncertain')) THEN RAISE EXCEPTION 'STRIPE_CONNECTION_FLOW_PENDING'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts WHERE connection_id=c.id AND
  (state IN ('preparing','open','uncertain') OR lease_expires_at>clock_timestamp() OR refund_cursor IS NOT NULL OR session_lookup_cursor IS NOT NULL)) THEN RAISE EXCEPTION 'STRIPE_DISCONNECT_OPEN_ATTEMPTS'; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('stripe.connect',p_unit,c.organization_id),jsonb_build_object('actor',auth.uid(),'unit',p_unit,'organization',c.organization_id));
 INSERT INTO eshop.stripe_disconnect_intents(connection_id,actor) VALUES(c.id,auth.uid()) RETURNING * INTO intent;
 UPDATE eshop.stripe_connections SET paused=true,next_check_at=clock_timestamp() WHERE id=c.id;
 INSERT INTO eshop.stripe_connection_audit(connection_id,actor,action) VALUES(c.id,auth.uid(),'paused');
 RETURN jsonb_build_object('intentId',intent.id);
END $$;
REVOKE ALL ON FUNCTION public.begin_stripe_disconnect(bigint,boolean,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.begin_stripe_disconnect(bigint,boolean,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_stripe_disconnect_internal(p_intent uuid,p_actor uuid,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE intent eshop.stripe_disconnect_intents; c eshop.stripe_connections;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT intent FROM eshop.stripe_disconnect_intents WHERE id=p_intent AND actor=p_actor FOR UPDATE;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=intent.connection_id AND livemode=p_livemode;
 PERFORM public.check_stripe_unit_manager_internal(c.unit_id,p_actor);
 IF intent.state='completed' THEN RETURN jsonb_build_object('disposition','replay','result',intent.result); END IF;
 IF intent.state<>'pending' THEN RETURN jsonb_build_object('disposition','uncertain'); END IF;
 UPDATE eshop.stripe_disconnect_intents SET state='claimed',claimed_at=clock_timestamp() WHERE id=intent.id;
 RETURN jsonb_build_object('disposition','dispatch','accountId',c.account_id);
END $$;
REVOKE ALL ON FUNCTION public.claim_stripe_disconnect_internal(uuid,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stripe_disconnect_internal(uuid,uuid,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.finish_stripe_disconnect_internal(p_intent uuid,p_success boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE intent eshop.stripe_disconnect_intents; v_result jsonb;
BEGIN
 PERFORM public.require_service_role();
 -- Lock connection before intent, matching lifecycle completion.
 PERFORM 1 FROM eshop.stripe_connections WHERE id=(SELECT connection_id FROM eshop.stripe_disconnect_intents WHERE id=p_intent) FOR UPDATE;
 SELECT * INTO STRICT intent FROM eshop.stripe_disconnect_intents WHERE id=p_intent FOR UPDATE;
 IF intent.state='completed' THEN RETURN intent.result; END IF;
 IF intent.state<>'claimed' OR p_success IS NULL THEN RAISE EXCEPTION 'STRIPE_DISCONNECT_INVALID'; END IF;
 IF NOT p_success THEN
  UPDATE eshop.stripe_disconnect_intents SET state='uncertain' WHERE id=intent.id;
  UPDATE eshop.stripe_connections SET next_check_at=clock_timestamp() WHERE id=intent.connection_id;
  RETURN jsonb_build_object('disconnected',false,'uncertain',true);
 END IF;
 v_result:=jsonb_build_object('disconnected',true);
 UPDATE eshop.stripe_connections SET state='revoked',paused=true,charges_enabled=false,card_payments_active=false,payouts_enabled=false,
  status_lease=NULL,status_lease_expires_at=NULL,checked_at=clock_timestamp(),next_check_at=clock_timestamp()+interval '1 day' WHERE id=intent.connection_id;
 UPDATE eshop.stripe_disconnect_intents SET state='completed',result=v_result,completed_at=clock_timestamp() WHERE id=intent.id;
 INSERT INTO eshop.stripe_connection_audit(connection_id,actor,action) VALUES(intent.connection_id,intent.actor,'revoked');
 PERFORM public.notification_center_provider_connection_internal('stripe',intent.connection_id);
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.finish_stripe_disconnect_internal(uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.finish_stripe_disconnect_internal(uuid,boolean) TO service_role;

-- Notification budgets share the existing admission and usage backend.
-- Conservative default; selected-tenant activation must fit account allocation.
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('email.notification.recipient.burst','email.notification','recipient','rolling',60,60,2,6),
 ('email.notification.recipient.day','email.notification','recipient','rolling',86400,3600,288,576),
 ('email.notification.global.day','email.notification','global','rolling',86400,3600,1000,10000),
 ('email.send.notification.recipient.burst','email.send.notification','recipient','rolling',60,60,2,6),
 ('email.send.notification.recipient.day','email.send.notification','recipient','rolling',86400,3600,288,576),
 ('email.send.notification.global.day','email.send.notification','global','rolling',86400,3600,1000,10000),
 ('email.notification.prepare.recipient.burst','email.notification.prepare','recipient','rolling',60,60,6,12),
 ('email.notification.prepare.global.burst','email.notification.prepare','global','rolling',60,60,60,300),
 ('email.notification.backlog.recipient','email.notification.backlog','recipient','occupancy',NULL,NULL,1,1),
 ('email.notification.backlog.global','email.notification.backlog','global','occupancy',NULL,NULL,1000,5000),
 ('email.notification.backlog.recipient.bytes','email.notification.backlog','recipient','bytes',NULL,NULL,1048576,16777216),
 ('email.notification.backlog.global.bytes','email.notification.backlog','global','bytes',NULL,NULL,134217728,1073741824);

COMMIT;
