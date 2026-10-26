-- Generated forward migration: notification-center-feed-2026-10-26
-- Prerequisites: 20261021100000_canonical_authorization.sql, 20261024010000_organization_notification_center.sql, 20261024025000_notification_email_recipient.sql, 20261024120000_order_email_recovery.sql, 20261024220000_cancelled_order_email_alerts.sql, 20261024235000_notification_center_canonical_availability.sql
BEGIN;
DO $$ BEGIN IF to_regclass('public.notification_center_organizations') IS NULL OR to_regclass('public.notification_center_activation') IS NOT NULL OR to_regclass('public.notification_center_source_state') IS NULL OR to_regprocedure('public.get_notification_center_updates(bigint,bigint,uuid[])') IS NULL THEN RAISE EXCEPTION 'notification_feed_prerequisites_missing'; END IF; END $$;

-- SOURCE: notification_center/feed_schema_delta.sql
ALTER TABLE public.notification_center_source_state ADD COLUMN next_evaluation_at timestamptz;
CREATE INDEX notification_center_feed_snapshot ON public.notification_center_deliveries(organization,recipient,sequence DESC);
CREATE INDEX notification_center_feed_revision ON public.notification_center_deliveries(event_id,recipient,sequence DESC);
CREATE INDEX notification_center_availability_due ON public.notification_center_source_state(next_evaluation_at,organization,source_key) WHERE next_evaluation_at IS NOT NULL;


-- SOURCE: eshop_forms/form_availability.sql
-- Sole owner of the manual/time gate, including the legacy inclusive end.
CREATE OR REPLACE FUNCTION public.get_form_availability_from_config_internal(p_config jsonb,p_at timestamptz)
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH c AS (SELECT (p_config->>'manualOpen')::boolean manual_open,
 (p_config->>'startAt')::timestamptz start_at,(p_config->>'endAt')::timestamptz end_at), gate AS (
 SELECT *,CASE WHEN NOT manual_open THEN 'manual_closed' WHEN p_at<start_at THEN 'before_start'
 WHEN p_at>end_at THEN 'ended' ELSE 'open' END value FROM c)
 SELECT p_config||jsonb_build_object('gate',value,'isWindowOpen',value='open','nextEvaluationAt',
 CASE WHEN manual_open IS NOT FALSE THEN (SELECT min(t) FROM (VALUES(start_at),(end_at+interval '1 microsecond')) b(t) WHERE t>p_at) END) FROM gate;
$$;
CREATE OR REPLACE FUNCTION public.get_form_availability_snapshot_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.get_form_availability_from_config_internal(jsonb_build_object('manualOpen',f.is_open,
 'startAt',nullif(coalesce(d#>>'{schedule,start_time}',d->>'start_time'),'')::timestamptz,
 'endAt',nullif(coalesce(d#>>'{schedule,end_time}',d->>'end_time'),'')::timestamptz),p_at)
 FROM public.forms f CROSS JOIN LATERAL (SELECT public.get_effective_form_data(f.id) d) data WHERE f.id=p_form;
$$;
REVOKE ALL ON FUNCTION public.get_form_availability_from_config_internal(jsonb,timestamptz),
 public.get_form_availability_snapshot_internal(bigint,timestamptz) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: eshop_waitlist/form_capacity.sql
CREATE OR REPLACE FUNCTION public.get_form_capacity_snapshot_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH counts AS (
 SELECT f.*, (SELECT count(DISTINCT t.id) FROM eshop.tickets t JOIN eshop.order_product_ticket x ON x.ticket=t.id JOIN eshop.orders o ON o.id=x."order"
  WHERE o.form=f.id AND t.state IS DISTINCT FROM 'storno' AND t.state IS DISTINCT FROM 'waitlisted' AND o.state IS DISTINCT FROM 'storno') occupied,
 (SELECT count(*) FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE s.form_id=f.id AND s.outcome='pending' AND w.expires_at>p_at) reserved,
 (SELECT count(DISTINCT t.id) FROM eshop.tickets t JOIN eshop.order_product_ticket x ON x.ticket=t.id JOIN eshop.orders o ON o.id=x."order"
  WHERE o.form=f.id AND o.state='waitlisted' AND public.get_effective_waitlist_ticket_lifecycle_internal(t.id)='waiting') waiting
 FROM public.forms f WHERE f.id=p_form), free AS (
 SELECT *,greatest(participant_capacity-occupied-reserved,0) available FROM counts)
 SELECT jsonb_build_object('enabled',participant_capacity IS NOT NULL,'limit',participant_capacity,
 'remainingPublic',CASE WHEN participant_capacity IS NOT NULL THEN greatest(available-waiting,0) END,
 'showRemaining',show_remaining_capacity,'occupiedPeople',occupied,'offeredPlaces',reserved,'waitingPeople',waiting,
 'offerablePlaces',available,'heldForWaiting',least(available,waiting),'revision',capacity_revision,
 'canSendOffers',waitlist_enabled AND available>0,'blockedReason',CASE WHEN NOT waitlist_enabled THEN 'WAITLIST_NOT_AVAILABLE'
 WHEN available=0 THEN 'FORM_CAPACITY_EXCEEDED' END,'serverTime',p_at) FROM free;
$$;
CREATE OR REPLACE FUNCTION public.get_form_registration_mode_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; d jsonb; c jsonb;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form; d:=public.get_effective_form_data(p_form);
 IF NOT (public.get_form_availability_snapshot_internal(p_form,p_at)->>'isWindowOpen')::boolean THEN RETURN 'closed'; END IF;
 IF f.blueprint IS NOT NULL AND EXISTS (
  SELECT 1 FROM public.occasions o WHERE o.id=f.occasion
  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
 ) THEN RETURN 'blueprint'; END IF;
 c:=public.get_form_capacity_snapshot_internal(p_form,p_at);
 IF f.participant_capacity IS NULL OR (c->>'remainingPublic')::bigint>0 THEN RETURN 'regular'; END IF;
 RETURN CASE WHEN f.waitlist_enabled THEN 'waitlist' ELSE 'full' END;
END $$;
CREATE OR REPLACE FUNCTION public.check_form_capacity_settings_internal(p_form bigint,p_input jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; c jsonb; n integer; enabled boolean; bp bigint;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form FOR UPDATE;
 c:=public.get_form_capacity_snapshot_internal(p_form);
 n:=CASE WHEN p_input ? 'participant_capacity' THEN (p_input->>'participant_capacity')::integer ELSE f.participant_capacity END;
 enabled:=CASE WHEN p_input ? 'waitlist_enabled' THEN (p_input->>'waitlist_enabled')::boolean ELSE f.waitlist_enabled END;
 bp:=CASE WHEN p_input ? 'blueprint' THEN nullif(p_input->>'blueprint','')::bigint ELSE f.blueprint END;
 -- A retained blueprint is inactive when the occasion feature is disabled.
 IF NOT EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=f.occasion
  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN bp:=NULL; END IF;
 IF n IS NOT NULL AND n<(c->>'occupiedPeople')::bigint+(c->>'offeredPlaces')::bigint+coalesce((c->>'heldForWaiting')::bigint,0) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','CAPACITY_BELOW_COMMITTED','capacity',c)::text; END IF;
 IF ((NOT enabled) OR n IS NULL OR bp IS NOT NULL) AND
 ((c->>'waitingPeople')::bigint>0 OR (c->>'offeredPlaces')::bigint>0) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','WAITLIST_HAS_ACTIVE_ENTRIES','capacity',c)::text; END IF;
 IF bp IS NOT NULL AND (n IS NOT NULL OR enabled) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','BLUEPRINT_CONFLICT')::text; END IF;
END $$;
REVOKE ALL ON FUNCTION public.get_form_capacity_snapshot_internal(bigint,timestamptz),
 public.get_form_registration_mode_internal(bigint,timestamptz),public.check_form_capacity_settings_internal(bigint,jsonb)
 FROM PUBLIC,anon,authenticated;


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
 SELECT p_user IS NOT NULL AND (
 CASE WHEN p_event.kind IN ('event_capacity_full','occasion_joined') THEN
 public.notification_center_app_admin_internal(p_event.organization,p_event.occasion,p_user)
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
DECLARE e public.notification_center_events; u uuid;
BEGIN
 SELECT * INTO e FROM public.notification_center_events WHERE id=p_event;
 IF NOT FOUND THEN RETURN; END IF;
 FOR u IN SELECT "user" FROM public.organization_users WHERE organization=e.organization AND is_admin
 UNION SELECT ou."user" FROM public.occasion_users ou JOIN public.occasions oc ON oc.id=ou.occasion WHERE oc.organization=e.organization AND (ou.is_editor_order_view OR public.participant_contacts_read_rule(ou.is_editor,ou.is_manager,false))
 UNION SELECT bu."user" FROM eshop.bank_account_users bu JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account
 JOIN public.units un ON un.id=uba.unit WHERE un.organization=e.organization AND bu.is_admin LOOP
  IF public.notification_center_allowed(e,u) AND (u IS DISTINCT FROM p_actor OR
   CASE WHEN e.kind IN ('event_capacity_full','occasion_joined') THEN
     NOT public.notification_center_app_admin_internal(e.organization,e.occasion,p_actor)
   ELSE NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=e.occasion AND "user"=p_actor AND is_editor_order)
     AND NOT EXISTS(SELECT 1 FROM public.organization_users WHERE organization=e.organization AND "user"=p_actor AND is_admin) END) THEN
   INSERT INTO public.notification_center_recipients(event_id,recipient,eligible_revision) VALUES(e.id,u,e.attention_revision)
   ON CONFLICT(event_id,recipient) DO UPDATE SET eligible_revision=excluded.eligible_revision;
  END IF;
 END LOOP;
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
DECLARE e public.notification_center_events; u uuid; n integer:=0; seq bigint; budget integer:=greatest(1,least(p_limit,500)); tz text;
BEGIN
 PERFORM public.notification_center_require_service();
 IF NOT pg_try_advisory_xact_lock(5831290471283) THEN RETURN 0; END IF;
 -- Row locks are the transaction lease. Rollback releases claims, including sequence allocation.
 FOR e IN SELECT ev.* FROM public.notification_center_events ev JOIN public.notification_center_organizations a ON a.organization=ev.organization
 WHERE ev.projected_revision<ev.attention_revision ORDER BY ev.organization,ev.occurred_at,ev.id
 LIMIT greatest(1,least(p_limit,500)) FOR UPDATE OF ev SKIP LOCKED LOOP
  SELECT timezone INTO tz FROM public.notification_center_organizations WHERE organization=e.organization;
  FOR u IN SELECT recipient FROM public.notification_center_recipients WHERE event_id=e.id AND eligible_revision=e.attention_revision AND processed_revision<e.attention_revision ORDER BY recipient LIMIT budget-n LOOP
   UPDATE public.notification_center_recipients SET processed_revision=e.attention_revision WHERE event_id=e.id AND recipient=u;
   n:=n+1;
   IF NOT public.notification_center_allowed(e,u) OR EXISTS(SELECT 1 FROM public.notification_center_deliveries
    WHERE event_id=e.id AND recipient=u AND attention_revision=e.attention_revision) THEN CONTINUE; END IF;
   IF NOT public.notification_center_unmuted(e,u) THEN CONTINUE; END IF;
   INSERT INTO public.notification_center_user_state(organization,recipient) VALUES(e.organization,u) ON CONFLICT DO NOTHING;
   UPDATE public.notification_center_user_state SET last_delivery_sequence=last_delivery_sequence+1
    WHERE organization=e.organization AND recipient=u RETURNING last_delivery_sequence INTO seq;
   INSERT INTO public.notification_center_deliveries(event_id,recipient,organization,attention_revision,sequence,group_key)
    VALUES(e.id,u,e.organization,e.attention_revision,seq,
     CASE WHEN e.kind='email_problem' THEN coalesce(e.occasion::text,'shared')||':email_problem:'||coalesce(e.data->>'reason','problem')||':'||(e.occurred_at AT TIME ZONE tz)::date::text
     WHEN e.kind IN ('order_created','waitlist_registered','order_cancelled','occasion_joined') THEN
      coalesce(e.occasion::text,'shared')||':'||e.kind||':'||(e.occurred_at AT TIME ZONE tz)::date::text ELSE e.id::text END);
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM public.notification_center_recipients WHERE event_id=e.id AND eligible_revision=e.attention_revision AND processed_revision<e.attention_revision) THEN
   UPDATE public.notification_center_events SET projected_revision=e.attention_revision WHERE id=e.id;
  END IF;
  EXIT WHEN n>=budget;
 END LOOP;
 RETURN n;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_dto(e public.notification_center_events,d public.notification_center_deliveries)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE payload jsonb:=e.data-'bankConnectionId'; account bigint; un bigint; impacts jsonb; customer text; actual_state text; contact jsonb;
BEGIN
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
  SELECT jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'),o.state INTO contact,actual_state
   FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization
   WHERE o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion;
  payload:=payload||jsonb_build_object('contact',coalesce(contact,'{}'),'customerName',nullif(trim(concat_ws(' ',contact->>'name',contact->>'surname')),''),'state',coalesce(actual_state,e.data->>'state'));
 END IF;
 IF e.kind='bank_problem' THEN
  SELECT bu.bank_account,u.id INTO account,un FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu
   ON bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
   JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account JOIN public.units u ON u.id=uba.unit
   WHERE c.id=(e.data->>'bankConnectionId')::bigint AND bu."user"=auth.uid() AND public.notification_center_bank_admin(bu.bank_account,auth.uid()) AND u.organization=e.organization AND EXISTS(SELECT 1 FROM public.unit_users um WHERE um.unit=u.id AND um."user"=auth.uid() AND um.is_manager) ORDER BY u.id LIMIT 1;
  IF account IS NOT NULL THEN payload:=payload||jsonb_build_object('bankAccountId',account,'unitId',un); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',oc.id,'title',oc.title,'link',oc.link)),'[]') INTO impacts
   FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id AND ou."user"=auth.uid() AND ou.is_editor_order_view
   WHERE oc.organization=e.organization AND oc.id=ANY(e.affected_occasions);
  payload:=payload||jsonb_build_object('affectedOccasions',impacts);
 END IF;
 RETURN (SELECT jsonb_build_object('id',e.id,'sequence',d.sequence,'kind',e.kind,'occurredAt',e.occurred_at,
 'status',e.status,'data',payload,'occasionId',e.occasion,'occasionLink',oc.link,'occasionTitle',oc.title)
 FROM (SELECT 1) seed LEFT JOIN public.occasions oc ON oc.id=e.occasion AND oc.organization=e.organization);
END $$;
-- One authorized snapshot selector shared by feed, hydration and external legacy serializers.
CREATE OR REPLACE FUNCTION public.notification_center_visible_internal(p_org bigint,p_snapshot bigint,p_current bigint DEFAULT NULL)
RETURNS TABLE(event public.notification_center_events,delivery public.notification_center_deliveries,section integer)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT e,d,CASE WHEN e.occasion IS NULL AND (p_current IS NULL OR cardinality(e.affected_occasions)=0 OR p_current=ANY(e.affected_occasions)) THEN 0
 WHEN e.occasion=p_current THEN 1 ELSE 2 END
 FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
 WHERE d.organization=p_org AND d.recipient=auth.uid() AND d.sequence<=p_snapshot AND public.notification_center_allowed(e,auth.uid())
 AND NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries newer WHERE newer.event_id=d.event_id AND newer.recipient=d.recipient
 AND newer.sequence<=p_snapshot AND newer.sequence>d.sequence);
$$;
REVOKE ALL ON FUNCTION public.notification_center_visible_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_notification_center_feed(p_organization bigint,p_current_occasion bigint DEFAULT NULL,
 p_snapshot bigint DEFAULT NULL,p_cursor jsonb DEFAULT NULL,p_limit integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE snap bigint; tuple jsonb; items jsonb; tail jsonb; more boolean; lim integer:=greatest(1,least(p_limit,100));
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 SELECT least(coalesce(p_snapshot,last_delivery_sequence),last_delivery_sequence) INTO snap FROM public.notification_center_user_state
 WHERE organization=p_organization AND recipient=auth.uid(); snap:=coalesce(snap,0);
 IF p_cursor IS NOT NULL AND p_cursor<>'null'::jsonb THEN
  BEGIN
   IF jsonb_typeof(p_cursor)<>'string' THEN RAISE EXCEPTION 'invalid cursor'; END IF;
   tuple:=convert_from(decode(p_cursor#>>'{}','base64'),'UTF8')::jsonb;
   IF jsonb_typeof(tuple)<>'object' OR NOT tuple ?& ARRAY['organization','snapshot','occasion','section','time','id']
    OR (tuple->>'organization')::bigint IS DISTINCT FROM p_organization OR (tuple->>'snapshot')::bigint IS DISTINCT FROM snap
    OR (tuple->>'occasion')::bigint IS DISTINCT FROM p_current_occasion OR (tuple->>'section')::int NOT BETWEEN 0 AND 2
    OR (tuple->>'time')::timestamptz IS NULL OR (tuple->>'id')::uuid IS NULL THEN RAISE EXCEPTION 'invalid cursor'; END IF;
  EXCEPTION WHEN OTHERS THEN RAISE invalid_parameter_value USING MESSAGE='notification_invalid_cursor'; END;
 END IF;
 WITH rows AS (SELECT v.*,row_number() OVER(ORDER BY section,(event).occurred_at DESC,(event).id DESC) position
 FROM public.notification_center_visible_internal(p_organization,snap,p_current_occasion) v
 WHERE tuple IS NULL OR section>(tuple->>'section')::int OR (section=(tuple->>'section')::int
 AND ((event).occurred_at,(event).id)<((tuple->>'time')::timestamptz,(tuple->>'id')::uuid))
 ORDER BY section,(event).occurred_at DESC,(event).id DESC LIMIT lim+1), page AS (SELECT * FROM rows WHERE position<=lim)
 SELECT coalesce((SELECT jsonb_agg(public.notification_center_dto(event,delivery)||jsonb_build_object('section',section) ORDER BY position) FROM page),'[]'),
 (SELECT jsonb_build_object('organization',p_organization,'snapshot',snap,'occasion',p_current_occasion,'section',section,'time',(event).occurred_at,'id',(event).id) FROM page ORDER BY position DESC LIMIT 1),
 (SELECT count(*)>lim FROM rows) INTO items,tail,more;
 RETURN jsonb_build_object('snapshot',snap,'items',items,'nextCursor',CASE WHEN more THEN to_jsonb(encode(convert_to(tail::text,'UTF8'),'base64')) END);
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_feed(bigint,bigint,bigint,jsonb,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_feed(bigint,bigint,bigint,jsonb,integer) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_notification_center_badge(p_organization bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.notification_center_user_state;
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 SELECT * INTO s FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid();
 RETURN jsonb_build_object('feedSupported',true,'enabled',true,'lastSequence',coalesce(s.last_delivery_sequence,0),'readThrough',coalesce(s.read_through_sequence,0),
 'unread',EXISTS(SELECT 1 FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
 WHERE d.organization=p_organization AND d.recipient=auth.uid() AND d.sequence>coalesce(s.read_through_sequence,0)
 AND public.notification_center_allowed(e,auth.uid()) AND public.notification_center_unmuted(e,auth.uid())));
END $$;
CREATE OR REPLACE FUNCTION public.get_notification_center_group(p_organization bigint,p_group_key text,p_snapshot bigint,
 p_cursor bigint DEFAULT NULL,p_limit integer DEFAULT 5) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE items jsonb; next_cursor bigint;
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 -- External legacy serializer for previously shipped clients only.
 WITH rows AS (SELECT public.notification_center_dto(event,delivery) item,(delivery).sequence FROM
 public.notification_center_visible_internal(p_organization,p_snapshot) WHERE (delivery).group_key=p_group_key
 AND (p_cursor IS NULL OR (delivery).sequence<p_cursor) ORDER BY (delivery).sequence DESC LIMIT greatest(1,least(p_limit,50)))
 SELECT coalesce(jsonb_agg(item ORDER BY sequence DESC),'[]'),CASE WHEN count(*)=greatest(1,least(p_limit,50)) THEN min(sequence) END INTO items,next_cursor FROM rows;
 RETURN jsonb_build_object('items',items,'nextCursor',next_cursor);
END $$;
CREATE OR REPLACE FUNCTION public.get_notification_center_page(p_organization bigint,p_current_occasion bigint DEFAULT NULL,
 p_limit integer DEFAULT 30,p_snapshot bigint DEFAULT NULL,p_cursor jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE groups jsonb; choices jsonb; snap bigint; tail jsonb;
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 SELECT least(coalesce(p_snapshot,last_delivery_sequence),last_delivery_sequence) INTO snap FROM public.notification_center_user_state
 WHERE organization=p_organization AND recipient=auth.uid(); snap:=coalesce(snap,0);
 -- External legacy grouped page; authorization and revision selection share the feed owner.
 WITH available AS (SELECT (delivery).*,(event).kind,(event).occasion,oc.title,v.section
 FROM public.notification_center_visible_internal(p_organization,snap,p_current_occasion) v
 LEFT JOIN public.occasions oc ON oc.id=(event).occasion AND oc.organization=p_organization), grouped AS (
 SELECT group_key,kind,occasion,title,section,count(*) n,max(sequence) latest FROM available GROUP BY group_key,kind,occasion,title,section
 ), page AS (SELECT * FROM grouped WHERE p_cursor IS NULL OR section>(p_cursor->>'section')::int OR
 (section=(p_cursor->>'section')::int AND (latest,group_key)<((p_cursor->>'sequence')::bigint,p_cursor->>'key'))
 ORDER BY section,latest DESC,group_key DESC LIMIT greatest(1,least(p_limit,100)))
 SELECT coalesce(jsonb_agg(jsonb_build_object('key',group_key,'section',section,'occasionId',occasion,'occasionTitle',title,'kind',kind,'day',CASE WHEN kind IN ('order_created','waitlist_registered','order_cancelled','occasion_joined','email_problem') THEN right(group_key,10) END,'count',n,
 'lastSequence',latest,'items',public.get_notification_center_group(p_organization,group_key,snap,NULL,5)->'items') ORDER BY section,latest DESC,group_key DESC),'[]'),
 (jsonb_agg(jsonb_build_object('section',section,'sequence',latest,'key',group_key) ORDER BY section DESC,latest,group_key)->0) INTO groups,tail FROM page;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',oc.id,'title',oc.title,'muted',coalesce(p.muted,false)) ORDER BY oc.title),'[]') INTO choices
 FROM public.occasions oc LEFT JOIN public.occasion_users ou ON ou.occasion=oc.id AND ou."user"=auth.uid()
 LEFT JOIN public.notification_center_preferences p ON p.organization=p_organization AND p.recipient=auth.uid() AND p.occasion=oc.id
 WHERE oc.organization=p_organization AND NOT public.is_demo_occasion(oc.id)
 AND (coalesce(ou.is_editor_order_view,false) OR public.notification_center_app_admin_internal(p_organization,oc.id,auth.uid()));
 RETURN jsonb_build_object('snapshot',snap,'groups',groups,'nextCursor',CASE WHEN jsonb_array_length(groups)=greatest(1,least(p_limit,100)) THEN tail END,'occasions',choices);
END $$;
CREATE OR REPLACE FUNCTION public.open_notification_center(p_organization bigint,p_current_occasion bigint DEFAULT NULL,p_limit integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.notification_center_user_state; result jsonb; feed jsonb;
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 INSERT INTO public.notification_center_user_state(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
 SELECT * INTO s FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE;
 UPDATE public.notification_center_user_state SET read_through_sequence=greatest(read_through_sequence,s.last_delivery_sequence)
 WHERE organization=p_organization AND recipient=auth.uid();
 result:=public.get_notification_center_page(p_organization,p_current_occasion,p_limit,s.last_delivery_sequence,NULL);
 feed:=public.get_notification_center_feed(p_organization,p_current_occasion,s.last_delivery_sequence,NULL,p_limit);
 RETURN result||jsonb_build_object('readThrough',s.last_delivery_sequence,'feedSupported',true,
 'feedItems',feed->'items',
 'feedNextCursor',feed->'nextCursor');
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
 public.notification_center_dto(public.notification_center_events,public.notification_center_deliveries),public.project_notification_center(integer)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.project_notification_center(integer) TO service_role;
REVOKE ALL ON FUNCTION public.get_notification_center_badge(bigint),public.open_notification_center(bigint,bigint,integer),
 public.get_notification_center_page(bigint,bigint,integer,bigint,jsonb),public.get_notification_center_group(bigint,text,bigint,bigint,integer),
 public.set_notification_center_muted(bigint,bigint,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_badge(bigint),public.open_notification_center(bigint,bigint,integer),
 public.get_notification_center_page(bigint,bigint,integer,bigint,jsonb),public.get_notification_center_group(bigint,text,bigint,bigint,integer),
 public.set_notification_center_muted(bigint,bigint,boolean) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_notification_center_updates(p_organization bigint,p_snapshot bigint,p_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 IF coalesce(cardinality(p_ids),0)>200 THEN RAISE EXCEPTION 'notification_update_limit'; END IF;
 SELECT coalesce(jsonb_agg(public.notification_center_dto(event,delivery) ORDER BY (delivery).sequence DESC),'[]') INTO result
 FROM public.notification_center_visible_internal(p_organization,p_snapshot) WHERE (event).id=ANY(p_ids);
 RETURN jsonb_build_object('items',result);
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_updates(bigint,bigint,uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_updates(bigint,bigint,uuid[]) TO authenticated;


-- SOURCE: notification_center/orders.sql
CREATE OR REPLACE FUNCTION public.notification_center_order_internal(p_order bigint,p_kind text,p_transition text,p_actor uuid DEFAULT auth.uid(),p_extra jsonb DEFAULT '{}')
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; org bigint; event uuid; ticket_count bigint; form_context jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF NOT FOUND OR o.state='stock' THEN RETURN; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=o.occasion;
 SELECT count(DISTINCT ticket) INTO ticket_count FROM eshop.order_product_ticket WHERE "order"=o.id;
 SELECT jsonb_build_object('formId',f.id,'allowsMultiple',least(public.ticket_order_limit(),coalesce(min(CASE WHEN ff.data->>'max_tickets' ~ '^[0-9]{1,9}$' THEN greatest(1,(ff.data->>'max_tickets')::integer) ELSE 1 END),1))>1)
 INTO form_context FROM public.forms f LEFT JOIN public.form_fields ff ON ff.form=f.id AND ff.type='ticket' WHERE f.id=o.form GROUP BY f.id;
 event:=public.notification_center_publish_internal(org,o.occasion,p_kind,p_kind||':'||p_order||':'||p_transition,
 jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,'state',o.state,'formContext',form_context)||
 CASE WHEN p_kind IN ('order_created','waitlist_registered') THEN jsonb_build_object('count',ticket_count) ELSE '{}'::jsonb END||p_extra,p_actor);
 UPDATE public.notification_center_events SET status=o.state WHERE id=event;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_order_state_internal(p_order bigint)
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 UPDATE public.notification_center_events e SET status=o.state,data=e.data||jsonb_build_object('state',o.state)
 FROM eshop.orders o WHERE o.id=p_order AND e.data->>'orderId'=p_order::text
 AND e.occasion=o.occasion AND e.kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted');
$$;
REVOKE ALL ON FUNCTION public.notification_center_order_internal(bigint,text,text,uuid,jsonb),public.notification_center_order_state_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/capacity.sql
CREATE OR REPLACE FUNCTION public.notification_center_initialized_internal(p_org bigint) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-organization:'||p_org,0));
 RETURN EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_org);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_initialized_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
-- Runs under the existing form/product/inventory locks, never takes a recipient lock.
CREATE OR REPLACE FUNCTION public.notification_center_capacity_transition_internal(p_org bigint,p_occ bigint,p_key text,p_snapshot jsonb,p_actor uuid DEFAULT auth.uid(),p_cause uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE old public.notification_center_source_state; nc_episode bigint; next_state jsonb; crossing text; high boolean; remaining bigint; lim bigint; used bigint; event uuid;
BEGIN
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-organization:'||p_org,0));
 PERFORM 1 FROM public.notification_center_organizations WHERE organization=p_org FOR SHARE;
 IF NOT FOUND THEN RETURN; END IF;
 lim:=(p_snapshot->>'limit')::bigint; remaining:=(p_snapshot->>'remainingPublic')::bigint;
 IF lim IS NULL OR lim<=0 THEN
  SELECT * INTO old FROM public.notification_center_source_state WHERE organization=p_org AND source_key=p_key FOR UPDATE;
  IF FOUND THEN UPDATE public.notification_center_events SET status='recovered',data=data||p_snapshot WHERE organization=p_org AND source_key=p_key||':episode:'||old.episode; END IF;
  INSERT INTO public.notification_center_source_state(organization,source_key,state) VALUES(p_org,p_key,p_snapshot||jsonb_build_object('high',false))
  ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,observed_at=clock_timestamp();
  RETURN;
 END IF;
 used:=lim-coalesce(remaining,0);
 SELECT * INTO old FROM public.notification_center_source_state WHERE organization=p_org AND source_key=p_key FOR UPDATE;
 high:=CASE WHEN used::numeric/lim<0.85 THEN false WHEN used::numeric/lim>=0.9 THEN true ELSE coalesce((old.state->>'high')::boolean,false) END;
 next_state:=p_snapshot||jsonb_build_object('high',high);
 IF NOT FOUND THEN
  INSERT INTO public.notification_center_source_state(organization,source_key,state,episode,observed_at) VALUES(p_org,p_key,next_state,0,clock_timestamp()) ON CONFLICT DO NOTHING;
  RETURN;
 END IF;
 crossing:=CASE WHEN remaining=0 AND (coalesce((old.state->>'limit')::bigint,0)<=0 OR coalesce((old.state->>'remainingPublic')::bigint,1)>0) THEN 'capacity_full'
 WHEN remaining>0 AND (old.state->>'remainingPublic')::bigint=0 THEN 'capacity_reopened'
 WHEN high AND NOT coalesce((old.state->>'high')::boolean,false) THEN 'capacity_warning' END;
 IF NOT high AND coalesce((old.state->>'high')::boolean,false) THEN
  UPDATE public.notification_center_events SET status='recovered',data=data||next_state WHERE organization=p_org AND source_key=p_key||':episode:'||old.episode;
 END IF;
 nc_episode:=old.episode;
 IF crossing IS NOT NULL THEN
  -- Full/reopen is one episode. Reopen updates it without another unread event.
  IF crossing='capacity_reopened' THEN
   UPDATE public.notification_center_events SET status='recovered',data=data||next_state WHERE organization=p_org AND source_key=p_key||':episode:'||nc_episode;
  ELSIF crossing='capacity_full' AND old.state->>'episodeEvent' IS NOT NULL THEN
   UPDATE public.notification_center_events SET kind='capacity_full',data=data||next_state,status='active',attention_revision=attention_revision+CASE WHEN created_xid=pg_current_xact_id() THEN 0 ELSE 1 END
    WHERE id=(old.state->>'episodeEvent')::uuid RETURNING id INTO event;
   IF event IS NOT NULL THEN PERFORM public.notification_center_capture_recipients_internal(event,p_actor);
   ELSE
    nc_episode:=nc_episode+1;
    event:=public.notification_center_publish_internal(p_org,p_occ,crossing,p_key||':episode:'||nc_episode,next_state,p_actor);
   END IF;
  ELSE
   nc_episode:=nc_episode+1;
   IF p_cause IS NULL THEN
    event:=public.notification_center_publish_internal(p_org,p_occ,crossing,p_key||':episode:'||nc_episode,next_state,p_actor);
   ELSE
    UPDATE public.notification_center_events SET data=data||jsonb_build_object('capacity',next_state) WHERE id=p_cause;
   END IF;
  END IF;
 END IF;
 IF p_cause IS NOT NULL AND crossing IS NOT NULL THEN UPDATE public.notification_center_events SET data=data||jsonb_build_object('capacity',next_state) WHERE id=p_cause; END IF;
 next_state:=next_state||jsonb_build_object('episodeEvent',coalesce(event::text,CASE WHEN remaining=0 OR high THEN old.state->>'episodeEvent' END));
 UPDATE public.notification_center_source_state SET state=next_state,episode=nc_episode,observed_at=clock_timestamp() WHERE organization=p_org AND source_key=p_key;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_form_capacity_internal(p_form bigint,p_actor uuid DEFAULT auth.uid(),p_cause uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; org bigint;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form;
 SELECT organization INTO org FROM public.occasions WHERE id=f.occasion;
 IF NOT public.notification_center_initialized_internal(org) THEN RETURN; END IF;
 PERFORM public.notification_center_capacity_transition_internal(org,f.occasion,'form:'||f.id,
 public.get_form_capacity_snapshot_internal(f.id)||jsonb_build_object('formId',f.id,'title',f.title),p_actor,p_cause);
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_product_capacity_internal(p_product bigint,p_actor uuid DEFAULT auth.uid())
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE p eshop.products; org bigint; used bigint;
BEGIN
 SELECT * INTO p FROM eshop.products WHERE id=p_product;
 SELECT organization INTO org FROM public.occasions WHERE id=p.occasion;
 IF NOT public.notification_center_initialized_internal(org) THEN RETURN; END IF;
 -- The product materializer's canonical maximum counts the committed product links.
 SELECT count(*) INTO used FROM eshop.order_product_ticket WHERE product=p.id;
 PERFORM public.notification_center_capacity_transition_internal(org,p.occasion,'product:'||p.id,
 jsonb_build_object('productId',p.id,'title',p.title,'limit',p.maximum,'remainingPublic',greatest(p.maximum-used,0)),p_actor);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_capacity_transition_internal(bigint,bigint,text,jsonb,uuid,uuid),
 public.notification_center_form_capacity_internal(bigint,uuid,uuid),public.notification_center_product_capacity_internal(bigint,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_inventory_capacity_internal(p_context bigint,p_actor uuid DEFAULT auth.uid())
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ctx public.inventory_contexts; pool public.inventory_pools; org bigint; lim bigint; occupied bigint;
BEGIN
 SELECT * INTO ctx FROM public.inventory_contexts WHERE id=p_context;
 SELECT * INTO pool FROM public.inventory_pools WHERE id=ctx.inventory_pool;
 SELECT organization INTO org FROM public.occasions WHERE id=pool.occasion;
 IF NOT public.notification_center_initialized_internal(org) THEN RETURN; END IF;
 SELECT least(count(*),coalesce(pool.sellable_capacity,count(*))),count(*) FILTER(WHERE order_product_ticket IS NOT NULL)
 INTO lim,occupied FROM eshop.spots WHERE inventory_context=ctx.id;
 -- Same physical/commercial limits as apply_allocations. Temporary buyer holds are deliberately excluded.
 PERFORM public.notification_center_capacity_transition_internal(org,pool.occasion,'inventory:'||ctx.id,
 jsonb_build_object('inventoryContextId',ctx.id,'title',pool.title,'limit',lim,'remainingPublic',greatest(lim-occupied,0)),p_actor);
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_blueprint_capacity_internal(p_blueprint bigint,p_actor uuid DEFAULT auth.uid())
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE bp eshop.blueprints; lim bigint; occupied bigint;
BEGIN
 SELECT * INTO bp FROM eshop.blueprints WHERE id=p_blueprint;
 IF NOT public.notification_center_initialized_internal(bp.organization) THEN RETURN; END IF;
 SELECT count(*),count(*) FILTER(WHERE s.order_product_ticket IS NOT NULL) INTO lim,occupied
 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot
 WHERE sb.blueprint=bp.id AND s.blueprint=bp.id AND s.occasion=bp.occasion AND NOT sb.blocked;
 PERFORM public.notification_center_capacity_transition_internal(bp.organization,bp.occasion,'blueprint:'||bp.id,
 jsonb_build_object('blueprintId',bp.id,'title',bp.title,'limit',lim,'remainingPublic',greatest(lim-occupied,0)),p_actor);
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_order_capacity_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE item record; bp bigint; org bigint;
BEGIN
 SELECT oc.organization INTO org FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order;
 IF NOT public.notification_center_initialized_internal(org) THEN RETURN; END IF;
 PERFORM public.notification_center_form_capacity_internal((SELECT form FROM eshop.orders WHERE id=p_order));
 FOR item IN SELECT DISTINCT product FROM eshop.order_product_ticket WHERE "order"=p_order AND product IS NOT NULL LOOP
  PERFORM public.notification_center_product_capacity_internal(item.product);
 END LOOP;
 FOR item IN SELECT DISTINCT s.inventory_context FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
 WHERE x."order"=p_order AND s.inventory_context IS NOT NULL LOOP
  PERFORM public.notification_center_inventory_capacity_internal(item.inventory_context);
 END LOOP;
 SELECT f.blueprint INTO bp FROM public.forms f JOIN eshop.orders o ON o.form=f.id WHERE o.id=p_order;
 IF bp IS NOT NULL THEN PERFORM public.notification_center_blueprint_capacity_internal(bp); END IF;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_inventory_capacity_internal(bigint,uuid),public.notification_center_blueprint_capacity_internal(bigint,uuid),
 public.notification_center_order_capacity_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/form_availability.sql
-- Callers hold the activation gate before the domain form lock, then source state.
CREATE OR REPLACE FUNCTION public.notification_center_form_availability_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp(),p_actor uuid DEFAULT auth.uid(),p_baseline boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; org bigint; old public.notification_center_source_state; current_config jsonb;
 previous jsonb; evaluated jsonb; boundary record; serial bigint; reason text;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form;
 SELECT organization INTO org FROM public.occasions WHERE id=f.occasion;
 IF org IS NULL OR NOT public.notification_center_initialized_internal(org) THEN RETURN; END IF;
 PERFORM 1 FROM public.forms WHERE id=p_form FOR UPDATE;
 SELECT * INTO old FROM public.notification_center_source_state WHERE organization=org AND source_key='form-availability:'||p_form FOR UPDATE;
 IF FOUND THEN p_at:=greatest(p_at,old.observed_at); END IF;
 current_config:=public.get_form_availability_snapshot_internal(p_form,p_at)||jsonb_build_object('title',f.title,'formId',f.id);
 IF old.state->>'createdXid'=pg_current_xact_id()::text THEN
  p_baseline:=true;
  current_config:=current_config||jsonb_build_object('createdXid',pg_current_xact_id()::text);
 END IF;
 IF old.source_key IS NULL OR p_baseline THEN
  INSERT INTO public.notification_center_source_state(organization,source_key,state,next_evaluation_at,observed_at)
  VALUES(org,'form-availability:'||p_form,current_config,(current_config->>'nextEvaluationAt')::timestamptz,p_at)
  ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,next_evaluation_at=excluded.next_evaluation_at,observed_at=excluded.observed_at;
  RETURN;
 END IF;
 previous:=old.state; serial:=old.episode;
 -- Replay the OLD configuration before comparing a newly saved configuration.
 FOR boundary IN SELECT t,occurred,why FROM (VALUES
  ((previous->>'startAt')::timestamptz,(previous->>'startAt')::timestamptz,'schedule_start'),
  ((previous->>'endAt')::timestamptz+interval '1 microsecond',(previous->>'endAt')::timestamptz,'schedule_end')) b(t,occurred,why)
  WHERE t>old.observed_at AND t<=p_at ORDER BY t LOOP
  evaluated:=public.get_form_availability_from_config_internal(previous,boundary.t);
  IF (previous->>'isWindowOpen')::boolean IS DISTINCT FROM (evaluated->>'isWindowOpen')::boolean THEN
   serial:=serial+1;
   PERFORM public.notification_center_publish_internal(org,f.occasion,CASE WHEN (evaluated->>'isWindowOpen')::boolean THEN 'form_opened' ELSE 'form_closed' END,
    'form-availability:'||p_form||':transition:'||serial,
    jsonb_build_object('formId',f.id,'title',previous->>'title','from',previous->>'gate','to',evaluated->>'gate','reason',boundary.why,
     'effectiveAt',boundary.occurred,'registrationMode',public.get_form_registration_mode_internal(f.id,boundary.t)),NULL,boundary.occurred);
  END IF;
  previous:=evaluated;
 END LOOP;
 evaluated:=public.get_form_availability_from_config_internal(previous,p_at);
 IF (evaluated->>'isWindowOpen')::boolean IS DISTINCT FROM (current_config->>'isWindowOpen')::boolean THEN
  serial:=serial+1;
  reason:=CASE WHEN evaluated->'manualOpen' IS DISTINCT FROM current_config->'manualOpen' THEN 'manual' ELSE 'schedule_changed' END;
  PERFORM public.notification_center_publish_internal(org,f.occasion,CASE WHEN (current_config->>'isWindowOpen')::boolean THEN 'form_opened' ELSE 'form_closed' END,
   'form-availability:'||p_form||':transition:'||serial,
   jsonb_build_object('formId',f.id,'title',f.title,'from',evaluated->>'gate','to',current_config->>'gate','reason',reason,
    'effectiveAt',p_at,'registrationMode',public.get_form_registration_mode_internal(f.id,p_at)),p_actor,p_at);
 END IF;
 UPDATE public.notification_center_source_state SET state=current_config,episode=serial,observed_at=p_at,
 next_evaluation_at=(current_config->>'nextEvaluationAt')::timestamptz WHERE organization=org AND source_key='form-availability:'||p_form;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_evaluate_forms_internal(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE candidate record; n integer:=0; at_time timestamptz:=clock_timestamp(); after_id bigint; last_id bigint;
BEGIN
 INSERT INTO public.notification_center_maintenance(name) VALUES('form-availability') ON CONFLICT DO NOTHING;
 SELECT cursor INTO after_id FROM public.notification_center_maintenance WHERE name='form-availability' FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN RETURN 0; END IF;
 -- Never lock a source before its form. Busy forms remain due for the next tick.
 FOR candidate IN SELECT s.organization,(s.state->>'formId')::bigint form_id FROM public.notification_center_source_state s
 JOIN public.notification_center_organizations a ON a.organization=s.organization
 WHERE s.next_evaluation_at<=at_time ORDER BY ((s.state->>'formId')::bigint>after_id) DESC,(s.state->>'formId')::bigint LIMIT greatest(1,least(p_limit,500)) LOOP
  last_id:=candidate.form_id;
  IF NOT pg_try_advisory_xact_lock_shared(hashtextextended('notification-center-organization:'||candidate.organization,0)) THEN CONTINUE; END IF;
  PERFORM 1 FROM public.forms WHERE id=candidate.form_id FOR UPDATE SKIP LOCKED;
  IF FOUND THEN
   PERFORM public.notification_center_form_availability_internal(candidate.form_id,at_time,NULL); n:=n+1;
  ELSIF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=candidate.form_id) THEN
   DELETE FROM public.notification_center_source_state WHERE organization=candidate.organization AND source_key='form-availability:'||candidate.form_id;
  END IF;
 END LOOP;
 UPDATE public.notification_center_maintenance SET cursor=coalesce(last_id,0) WHERE name='form-availability';
 RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_form_availability_internal(bigint,timestamptz,uuid,boolean),
 public.notification_center_evaluate_forms_internal(integer) FROM PUBLIC,anon,authenticated,service_role;

-- Wizard/create/copy commands may save the new form again in the same transaction.
-- That authoring is still creation, not an existing form opening for recipients.
CREATE OR REPLACE FUNCTION public.notification_center_form_created_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_form_availability_internal(p_form,clock_timestamp(),auth.uid(),true);
 UPDATE public.notification_center_source_state SET state=state||jsonb_build_object('createdXid',pg_current_xact_id()::text)
 WHERE source_key='form-availability:'||p_form AND organization=(SELECT oc.organization FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE f.id=p_form);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_form_created_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;


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
DECLARE m record; maximum bigint; after_id bigint; processed integer:=0; projected integer; availability integer;
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
  WHERE d.delivered_at<clock_timestamp()-interval '90 days' AND (e.status='recovered' OR e.kind NOT IN ('email_problem','bank_problem','capacity_full','capacity_warning')) LIMIT greatest(1,least(p_limit,500)));
 DELETE FROM public.notification_center_events WHERE id IN(SELECT e.id FROM public.notification_center_events e
  WHERE e.occurred_at<clock_timestamp()-interval '90 days' AND (e.status='recovered' OR e.kind NOT IN ('email_problem','bank_problem','capacity_full','capacity_warning'))
  AND NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries WHERE event_id=e.id) AND e.projected_revision=e.attention_revision LIMIT greatest(1,least(p_limit,500)));
 RETURN jsonb_build_object('evaluated',processed,'projected',projected,'availabilityEvaluated',availability);
END $$;
REVOKE ALL ON FUNCTION public.maintain_notification_center(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.maintain_notification_center(integer) TO service_role;

REVOKE ALL ON FUNCTION public.initialize_notification_center_internal(bigint,text) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: eshop_forms/update_form.sql
CREATE OR REPLACE FUNCTION public.update_form_internal_v1(input_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    ----------------------------------------------------------------------------
    -- Declarations
    ----------------------------------------------------------------------------
    result JSONB;
    availability_at timestamptz;
    availability_new boolean;
    deleted_fields BIGINT[];
    deleted_products BIGINT[];
    deletion_reason TEXT;
    deletion_row RECORD;

    form_id          BIGINT;               -- ID of the form being created/updated
    occasion_id      BIGINT;               -- ID of the occasion to which the form belongs
    now_ts           TIMESTAMPTZ := NOW(); -- Current timestamp for record updates

    link_param           TEXT;         -- Unique link for the form, must not conflict within the same org
    occasion_org         BIGINT;       -- Organization stored in the occasions table
    occasion_unit        BIGINT;       -- The 'unit' that must match for bank accounts
    conflict_check       INT;          -- Used for verifying uniqueness constraints
    deadline_val         BIGINT;       -- Field for validating form deadlines
    price_val            NUMERIC;      -- Field for validating product price

    bank_account_val     BIGINT;       -- Bank account from input_data
    bank_account_unit    BIGINT;       -- Unit of the bank account, must match occasion_unit

    v_seconds_before_deadline BIGINT; -- For calling the reminder queue function

    ----------------------------------------------------------------------------
    -- Since product_type data is now inside form_fields, we no longer read from
    -- a top-level product_types array. Instead, we will parse product_type objects
    -- directly from each form_field (if present).
    ----------------------------------------------------------------------------

    product_type_data    JSONB;        -- The JSONB data for product_type within a form_field
    product_type_id      BIGINT;       -- ID (new or existing) of the product_type
    product_type_occ     BIGINT;       -- For checking product_type's occasion

    products_data        JSONB;        -- JSONB array of products inside a product_type
    product_array_data   JSONB;        -- Rebuilt array of products
    product_data         JSONB;        -- Each product object from the products array
    product_id           BIGINT;       -- ID for a product (new or existing)
    product_occ          BIGINT;       -- Occasion check for an existing product

    ----------------------------------------------------------------------------
    -- form_fields data
    ----------------------------------------------------------------------------
    form_fields_data     JSONB := '[]'::JSONB; -- Final array of form_fields for the response
    field_data           JSONB;                -- Each form_field from input
    field_id             BIGINT;               -- ID for a form_field (new or existing)
    field_product_type   BIGINT;               -- Will store the final product_type.id for the form_field
    field_occ            BIGINT;               -- Verify product_type's occasion if referenced
BEGIN
    BEGIN
        /* All logic is inside this sub-block so we can catch exceptions similarly
           to how it's done in create_ticket_order, with a single EXCEPTION WHEN OTHERS THEN.
           We raise exceptions in JSON form, and if it's JSON, we return it as-is; otherwise,
           we build a default JSON error response. */

        ----------------------------------------------------------------------------
        -- Begin main logic
        ----------------------------------------------------------------------------

        -- Validate that input_data and essential fields exist
        IF input_data IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4001, 'message', 'Input data is missing')::TEXT;
        END IF;

        IF input_data->>'occasion' IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Missing occasion ID in input data')::TEXT;
        END IF;

        occasion_id := (input_data->>'occasion')::BIGINT;
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Invalid or missing occasion ID')::TEXT;
        END IF;

        -- Ensure user is authorized to edit this occasion
        IF NOT COALESCE(can_write_orders(occasion_id), false) THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 403, 'message', 'User is not authorized to edit this occasion')::TEXT;
        END IF;

        -- Retrieve the occasion's organization and unit
        SELECT o.organization, o.unit
          INTO occasion_org, occasion_unit
          FROM public.occasions o
         WHERE o.id = occasion_id
         LIMIT 1;

        IF occasion_org IS NULL OR occasion_unit IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4017, 'message', 'Occasion not found or missing required fields')::TEXT;
        END IF;

        IF NOT public.is_service_role() AND NOT public.can_author_forms(occasion_id) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
        PERFORM public.notification_center_initialized_internal(occasion_org);
        availability_at:=clock_timestamp();
        form_id := NULLIF(input_data->>'id','')::bigint;
        availability_new:=form_id IS NULL;
        IF form_id IS NOT NULL THEN
          IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id) THEN RAISE invalid_parameter_value USING MESSAGE='Form does not match occasion'; END IF;
          PERFORM 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id FOR UPDATE;
          PERFORM public.notification_center_form_availability_internal(form_id,availability_at);
        END IF;
        IF form_id IS NULL THEN
          INSERT INTO public.forms(created_at,occasion) VALUES(now_ts,occasion_id) RETURNING id INTO form_id;
          link_param := public.reserve_public_link_internal('form',form_id,input_data->>'link',true);
        ELSE
          IF NOT EXISTS (SELECT 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id) THEN
            RAISE invalid_parameter_value USING MESSAGE='Form does not match occasion'; END IF;
          link_param := public.reserve_public_link_internal('form',form_id,input_data->>'link',false);
        END IF;

        -- Explicit removals are part of this save transaction, never inferred from
        -- omitted fields in partial/older-client payloads. Exceptions roll back the save.
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_fields
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_field_ids', '[]'::jsonb));
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_products
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_product_ids', '[]'::jsonb));

        IF EXISTS (SELECT 1 FROM unnest(deleted_fields) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM public.form_fields ff WHERE ff.id = removed.id AND ff.form = form_id))
          OR EXISTS (SELECT 1 FROM unnest(deleted_products) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
            WHERE p.id = removed.id AND ff.form = form_id)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;

        -- Removing the ticket container also removes its nested fields.
        IF EXISTS (SELECT 1 FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields) AND ff.type = 'ticket') THEN
            SELECT deleted_fields || COALESCE(array_agg(ff.id), '{}'::bigint[]) INTO deleted_fields
            FROM public.form_fields ff WHERE ff.form = form_id AND ff.is_ticket_field;
        END IF;

        -- Serialize product-type references and product FK insertions before checking
        -- usage, including ON DELETE CASCADE inventory links.
        PERFORM 1 FROM eshop.product_types pt WHERE pt.id IN (
            SELECT ff.product_type FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
            UNION SELECT p.product_type FROM eshop.products p WHERE p.id = ANY(deleted_products)
        ) ORDER BY pt.id FOR UPDATE;
        SELECT deleted_products || COALESCE(array_agg(p.id), '{}'::bigint[]) INTO deleted_products
        FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
        WHERE ff.id = ANY(deleted_fields);
        PERFORM 1 FROM eshop.products p WHERE p.id = ANY(deleted_products) ORDER BY p.id FOR UPDATE;

        FOR deletion_row IN SELECT ff.* FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
        LOOP
            SELECT CASE WHEN EXISTS (
          SELECT 1 FROM (
            SELECT current_order.id, current_order.form, current_order.data FROM eshop.orders current_order WHERE current_order.form = ff.form
          ) o
          WHERE o.form = ff.form AND (
            EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.data->'fields') = 'array' THEN o.data->'fields' ELSE '[]'::jsonb END) answer
              WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
            OR (ff.type = 'ticket' AND jsonb_path_exists(o.data, '$.tickets[*]'))
            OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(o.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
            OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt."order" = o.id AND opt.ticket IS NOT NULL))
            OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (
              SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id = opt.ticket
              WHERE opt."order" = o.id AND NULLIF(t.note, '') IS NOT NULL))
          )) OR EXISTS(SELECT 1 FROM eshop.tickets person CROSS JOIN LATERAL jsonb_array_elements(
            CASE WHEN jsonb_typeof(person.data->'fields')='array' THEN person.data->'fields' ELSE '[]' END) answer
            WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket=person.id AND q.form=ff.form) AND answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb))
           OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket IS NOT NULL AND q.form=ff.form)) THEN 'responses'
        ELSE (
          SELECT reason FROM public.form_fields member
          JOIN eshop.products p ON p.product_type = member.product_type
          CROSS JOIN LATERAL (SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END AS reason) usage
          WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
            AND reason IS NOT NULL
          ORDER BY p.id LIMIT 1
        ) END INTO deletion_reason
            FROM public.form_fields ff WHERE ff.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        FOR deletion_row IN SELECT p.* FROM eshop.products p WHERE p.id = ANY(deleted_products)
        LOOP
            SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END INTO deletion_reason
            FROM eshop.products p WHERE p.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f
            WHERE (f->>'id')::bigint = ANY(deleted_fields))
          OR EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f,
            jsonb_array_elements(COALESCE(NULLIF(f->'product_type'->'products', 'null'::jsonb), '[]'::jsonb)) p
            WHERE (p->>'id')::bigint = ANY(deleted_products)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;
        DELETE FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields);
        DELETE FROM eshop.planned_changes WHERE subject_id=ANY(deleted_products) AND change_type IN('products.price','products.is_hidden') AND NOT applied;
        DELETE FROM eshop.products p WHERE p.id = ANY(deleted_products);
        DELETE FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion'
          AND scope_id=occasion_id AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(deleted_products) id));

        ----------------------------------------------------------------------------
        -- Process form_fields array from input_data if present
        -- Each form_field may contain a product_type object. If so, we insert/update
        -- the product_type and its products, then set the resulting product_type.id
        -- in the form_field.
        ----------------------------------------------------------------------------
        IF (input_data->'form_fields') IS NOT NULL THEN
            form_fields_data := '[]'::JSONB;

            FOR field_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'form_fields')
            LOOP
                IF field_data->>'type' IN ('select_one','select_many') THEN
                    IF jsonb_typeof(field_data#>'{data,options}') IS DISTINCT FROM 'array' THEN
                        RAISE EXCEPTION '%', jsonb_build_object('code', 422,
                            'message', 'FORM_SELECTION_OPTIONS_REQUIRED', 'fieldId', field_data->'id')::text;
                    END IF;
                    IF jsonb_array_length(field_data#>'{data,options}') = 0
                       OR EXISTS (SELECT 1 FROM jsonb_array_elements(field_data#>'{data,options}') option
                           WHERE jsonb_typeof(option->'value') IS DISTINCT FROM 'string'
                              OR btrim(option->>'value') = '') THEN
                        RAISE EXCEPTION '%', jsonb_build_object('code', 422,
                            'message', 'FORM_SELECTION_OPTIONS_REQUIRED', 'fieldId', field_data->'id')::text;
                    END IF;
                END IF;
                field_id := NULLIF(field_data->>'id', '')::BIGINT;

                ----------------------------------------------------------------------------
                -- product_type logic now lives here, inside each form_field
                ----------------------------------------------------------------------------
                product_type_data := field_data->'product_type';  -- This is JSONB (could be null)
                IF field_data->>'type' = 'ticket' AND field_data#>>'{data,max_tickets}' IS NOT NULL THEN
                    IF (field_data#>>'{data,max_tickets}')::numeric < 1 OR
                       (field_data#>>'{data,max_tickets}')::numeric > public.ticket_order_limit() OR
                       trunc((field_data#>>'{data,max_tickets}')::numeric) <> (field_data#>>'{data,max_tickets}')::numeric THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 400,
                            'message', 'Invalid maximum tickets per order',
                            'limit', public.ticket_order_limit())::TEXT;
                    END IF;
                END IF;
                field_product_type := NULL;                        -- We'll store numeric ID here if we have a product_type

                IF product_type_data IS NOT NULL AND product_type_data::TEXT <> 'null' THEN
                    -- Attempt to parse the product_type.id if it exists
                    product_type_id := NULLIF(product_type_data->>'id', '')::BIGINT;

                    IF product_type_id IS NULL THEN
                        ----------------------------------------------------------------------------
                        -- New product_type
                        ----------------------------------------------------------------------------
                        INSERT INTO eshop.product_types (
                            created_at,
                            updated_at,
                            occasion,
                            title,
                            description,
                            type,
                            data
                        )
                        VALUES (
                            now_ts,
                            now_ts,
                            occasion_id,
                            product_type_data->>'title',
                            product_type_data->>'description',
                            product_type_data->>'type',
                            product_type_data->'data'
                        )
                        RETURNING id INTO product_type_id;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{id}',
                            TO_JSONB(product_type_id)
                        );
                    ELSE
                        ----------------------------------------------------------------------------
                        -- Existing product_type: check existence and occasion
                        ----------------------------------------------------------------------------
                        SELECT pt.occasion
                          INTO product_type_occ
                          FROM eshop.product_types pt
                         WHERE pt.id = product_type_id
                         LIMIT 1;

                        IF NOT FOUND THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4006,
                                    'message', 'Product type not found',
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        IF product_type_occ <> occasion_id THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4007,
                                    'message', 'product_type occasion does not match form occasion',
                                    'product_type_occasion', product_type_occ,
                                    'form_occasion', occasion_id,
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        PERFORM 1 FROM public.occasions WHERE id=occasion_id FOR UPDATE;
                        UPDATE eshop.product_types
                           SET
                               updated_at = now_ts,
                               title = product_type_data->>'title',
                               description = product_type_data->>'description',
                               type = product_type_data->>'type',
                               data = product_type_data->'data'
                         WHERE id = product_type_id;
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Process products within this product_type, if any
                    ----------------------------------------------------------------------------
                    PERFORM public.advance_ticketing_authoring_version_internal_v1('product_type',occasion_id,product_type_id);
                    products_data := product_type_data->'products';
                    IF products_data IS NOT NULL AND products_data::TEXT <> 'null' THEN
                        product_array_data := '[]'::JSONB;

                        FOR product_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(products_data)
                        LOOP
                            product_id := NULLIF(product_data->>'id', '')::BIGINT;

                            -- Validate product price must be > 0
                            price_val := COALESCE(NULLIF(product_data->>'price',''), '0')::NUMERIC;
                            IF price_val < 0 THEN
                                RAISE EXCEPTION '%',
                                    JSONB_BUILD_OBJECT(
                                        'code', 4015,
                                        'message', 'Product price must be greater or equal to zero',
                                        'details', product_data
                                    )::TEXT;
                            END IF;

                            IF product_id IS NULL THEN
                                ----------------------------------------------------------------------------
                                -- New product
                                ----------------------------------------------------------------------------
                                PERFORM public.validate_product_price(price_val,product_data->'data',left(product_data->>'currency_code',3));
                                INSERT INTO eshop.products (
                                    created_at,
                                    updated_at,
                                    product_type,
                                    occasion,
                                    title,
                                    description,
                                    price,
                                    currency_code,
                                    data,
                                    is_hidden,
                                    "order",
                                    maximum
                                )
                                VALUES (
                                    now_ts,
                                    now_ts,
                                    product_type_id,
                                    occasion_id,
                                    product_data->>'title',
                                    product_data->>'description',
                                    price_val,
                                    left(product_data->>'currency_code', 3),
                                    product_data->'data',
                                    COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                    NULLIF(product_data->>'order','')::BIGINT,
                                    NULLIF(product_data->>'maximum','')::BIGINT
                                )
                                RETURNING id INTO product_id;

                                product_data := jsonb_set(product_data, '{id}', TO_JSONB(product_id));
                            ELSE
                                ----------------------------------------------------------------------------
                                -- Existing product: must match the same occasion and product_type
                                ----------------------------------------------------------------------------
                                SELECT p.occasion
                                  INTO product_occ
                                  FROM eshop.products p
                                 WHERE p.id = product_id
                                   AND p.product_type = product_type_id
                                 LIMIT 1;

                                IF NOT FOUND THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4008,
                                            'message', 'Product not found or does not match product_type',
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                IF product_occ <> occasion_id THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4009,
                                            'message', 'Product occasion does not match form occasion',
                                            'product_occasion', product_occ,
                                            'form_occasion', occasion_id,
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                PERFORM public.validate_product_price_update(product_id,price_val,product_data->'data',left(product_data->>'currency_code',3));
                                UPDATE eshop.products
                                   SET
                                       updated_at = now_ts,
                                       title = product_data->>'title',
                                       description = product_data->>'description',
                                       price = price_val,
                                       currency_code = left(product_data->>'currency_code', 3),
                                       data = product_data->'data',
                                       is_hidden = COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                       "order" = NULLIF(product_data->>'order','')::BIGINT,
                                       maximum = NULLIF(product_data->>'maximum','')::BIGINT
                                 WHERE id = product_id
                                   AND product_type = product_type_id;
                            END IF;

                            PERFORM public.advance_ticketing_authoring_version_internal_v1('product',occasion_id,product_id);
                            product_array_data := product_array_data || product_data;
                        END LOOP;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{products}',
                            product_array_data
                        );
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Store product_type_id in field_product_type for the form_fields table
                    ----------------------------------------------------------------------------
                    field_product_type := product_type_id;

                    ----------------------------------------------------------------------------
                    -- Merge updated product_type_data back into the field_data
                    ----------------------------------------------------------------------------
                    field_data := jsonb_set(field_data, '{product_type}', product_type_data);
                END IF;

                ----------------------------------------------------------------------------
                -- Insert or update the form_field itself
                ----------------------------------------------------------------------------
                IF field_id IS NOT NULL THEN
                    -- Update existing form_field
                    UPDATE public.form_fields
                       SET
                           title = field_data->>'title',
                           description = field_data->>'description',
                           data = field_data->'data',
                           type = field_data->>'type',
                           is_required = COALESCE((field_data->>'is_required')::BOOLEAN, false),
                           is_hidden = COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                           "order" = NULLIF(field_data->>'order','')::BIGINT,
                           product_type = field_product_type,
                           is_ticket_field = COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false),
                           form = form_id
                     WHERE id = field_id
                       AND form = form_id;

                    IF NOT FOUND THEN
                        RAISE EXCEPTION '%',
                            JSONB_BUILD_OBJECT(
                                'code', 4012,
                                'message', 'No matching form_field found to update (or does not belong to this form)',
                                'details', field_data
                            )::TEXT;
                    END IF;
                ELSE
                    -- Insert new form_field
                    INSERT INTO public.form_fields (
                        created_at,
                        title,
                        description,
                        data,
                        type,
                        is_required,
                        form,
                        is_hidden,
                        "order",
                        product_type,
                        is_ticket_field
                    )
                    VALUES (
                        now_ts,
                        field_data->>'title',
                        field_data->>'description',
                        field_data->'data',
                        field_data->>'type',
                        COALESCE((field_data->>'is_required')::BOOLEAN, false),
                        form_id,
                        COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                        NULLIF(field_data->>'order','')::BIGINT,
                        field_product_type,
                        COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false)
                    )
                    RETURNING id INTO field_id;

                    field_data := jsonb_set(field_data, '{id}', TO_JSONB(field_id));
                END IF;

                form_fields_data := form_fields_data || field_data;
            END LOOP;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate that deadline_duration_seconds is zero, positive, or null
        ----------------------------------------------------------------------------
        IF (input_data->'data'->>'reminder_interval_seconds')::bigint < 0 THEN
            RAISE EXCEPTION 'reminder_interval_seconds must be zero or higher or null';
        END IF;
        deadline_val := NULLIF(input_data->>'deadline_duration_seconds','')::BIGINT;
        IF deadline_val IS NOT NULL AND deadline_val < 0 THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT(
                    'code', 4016,
                    'message', 'deadline_duration_seconds must be zero or higher or null'
                )::TEXT;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate bank_account belongs to the same unit as the occasion, if provided
        ----------------------------------------------------------------------------
        bank_account_val := NULLIF(input_data->>'bank_account','')::BIGINT;
        IF bank_account_val IS NOT NULL THEN
            SELECT ba.unit
              INTO bank_account_unit
              FROM eshop.unit_bank_accounts ba
             WHERE ba.bank_account = bank_account_val
               AND ba.unit = occasion_unit
             LIMIT 1;

            IF NOT FOUND THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4020,
                        'message', 'Bank account not found',
                        'bank_account', bank_account_val
                    )::TEXT;
            END IF;

            IF bank_account_unit <> occasion_unit THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4021,
                        'message', 'Bank account does not belong to the same unit as the occasion',
                        'bank_account_unit', bank_account_unit,
                        'occasion_unit', occasion_unit
                    )::TEXT;
            END IF;
        END IF;

        ----------------------------------------------------------------------------
        -- Update the main form record with all validated fields
        ----------------------------------------------------------------------------
        IF input_data->>'blueprint' IS NOT NULL AND NOT EXISTS(
          SELECT 1 FROM eshop.blueprints WHERE id=(input_data->>'blueprint')::bigint AND occasion=occasion_id) THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',403,'message','Foreign blueprint')::text; END IF;
        PERFORM public.check_form_capacity_settings_internal(form_id,input_data);
        UPDATE public.forms
           SET
               participant_capacity = CASE WHEN input_data ? 'participant_capacity' THEN (input_data->>'participant_capacity')::integer ELSE participant_capacity END,
               waitlist_enabled = CASE WHEN input_data ? 'waitlist_enabled' THEN (input_data->>'waitlist_enabled')::boolean ELSE waitlist_enabled END,
               show_remaining_capacity = CASE WHEN input_data ? 'show_remaining_capacity' THEN (input_data->>'show_remaining_capacity')::boolean ELSE show_remaining_capacity END,
               waitlist_offer_duration_seconds = CASE WHEN input_data ? 'waitlist_offer_duration_seconds' THEN (input_data->>'waitlist_offer_duration_seconds')::integer ELSE waitlist_offer_duration_seconds END,
               capacity_revision = capacity_revision+1,
               title = CASE WHEN input_data ? 'title' THEN input_data->>'title' ELSE title END,
               -- Opening the real form ends its initial preparation phase.
               -- Later closing it is a pause, irrespective of test orders.
               data = CASE WHEN coalesce((input_data->>'is_open')::boolean,is_open) THEN
                 jsonb_set(coalesce(CASE WHEN input_data ? 'data' THEN input_data->'data' ELSE data END,'{}'::jsonb),'{schedule}',
                  coalesce((CASE WHEN input_data ? 'data' THEN input_data->'data' ELSE data END)->'schedule','{}'::jsonb)
                   ||'{"sale_preparation":false}'::jsonb)
                 ELSE CASE WHEN input_data ? 'data' THEN input_data->'data' ELSE data END END,
               header = CASE WHEN input_data ? 'header' THEN input_data->>'header' ELSE header END,
               header_off = CASE WHEN input_data ? 'header_off' THEN input_data->>'header_off' ELSE header_off END,
               link = link_param,
               blueprint = CASE WHEN input_data ? 'blueprint' THEN NULLIF(input_data->>'blueprint','')::BIGINT ELSE blueprint END,
               bank_account = CASE WHEN input_data ? 'bank_account' THEN bank_account_val ELSE bank_account END,
               deadline_duration_seconds = CASE WHEN input_data ? 'deadline_duration_seconds' THEN deadline_val ELSE deadline_duration_seconds END,
               is_open = CASE WHEN input_data ? 'is_open' THEN (input_data->>'is_open')::boolean ELSE is_open END
         WHERE id = form_id;

        PERFORM public.validate_form_payment_configuration_internal(form_id);

        ----------------------------------------------------------------------------
        -- After updating the form, requeue payment reminders for the whole occasion
        -- as the form's settings (e.g., is_reminder_enabled) might have changed.
        ----------------------------------------------------------------------------
        -- First, find the 'seconds_before_deadline' setting from the occasion's 'form' feature.
        SELECT (elem->>'reminder_interval_seconds')::BIGINT
          INTO v_seconds_before_deadline
          FROM public.occasions, jsonb_array_elements(features) AS elem
         WHERE id = occasion_id
           AND elem->>'code' = 'form'
         LIMIT 1;

        -- If the setting is found, call the function to rebuild the reminder queue.
        PERFORM public.queue_payment_reminders(occasion_id, COALESCE(v_seconds_before_deadline,86400));

        ----------------------------------------------------------------------------
        -- Prepare a success response
        ----------------------------------------------------------------------------
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'message', 'Form updated successfully',
            'form_id', form_id,
            'link', link_param,
            'form_fields', form_fields_data
        );

        IF availability_new THEN
          PERFORM public.notification_center_form_created_internal(form_id);
        ELSE
          PERFORM public.notification_center_form_availability_internal(form_id,availability_at);
        END IF;
        PERFORM public.notification_center_form_capacity_internal(form_id);
    EXCEPTION WHEN raise_exception THEN
        -- Catch any exception and attempt to parse it as JSON; if not JSON, wrap it in our own JSON.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 5001, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.update_form_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: eshop_forms/form_creation_domain.sql
-- Shared form construction. Invoker-only, private to explicit checked owners.
CREATE OR REPLACE FUNCTION public.insert_form_for_occasion_internal_v1(p_occasion_id bigint, p_link text, p_title text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    new_form_id BIGINT;
    new_form JSONB;
    new_product_type_id BIGINT;
    now TIMESTAMPTZ := NOW();
    payment_default text;
    initial_data jsonb := '{"is_reminder_enabled": true}'::jsonb;
BEGIN
    SELECT org.data->>'DEFAULT_FORM_PAYMENT_METHOD' INTO payment_default
    FROM public.occasions o JOIN public.organizations org ON org.id=o.organization
    WHERE o.id=p_occasion_id;
    IF payment_default = 'stripe' THEN
      -- A closed draft can await Connect without inventing a recipient or bank.
      initial_data := initial_data || '{"payments":{"bankEnabled":false}}'::jsonb;
    END IF;
    PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=p_occasion_id));
    -- Create the new form
    INSERT INTO public.forms(
        title,
        is_open,
        link,
        occasion,
        created_at,
        updated_at,
        deadline_duration_seconds,
        data
    )
    VALUES (
        p_title,
        false,
        NULL,
        p_occasion_id,
        now,
        now,
        604800, -- Default to 7 days
        initial_data
    )
    RETURNING to_jsonb(public.forms.*) INTO new_form;

    new_form_id := (new_form->>'id')::BIGINT;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',new_form_id,p_link,true) WHERE id=new_form_id;
    SELECT to_jsonb(f) INTO new_form FROM public.forms f WHERE id=new_form_id;

    -- Create default 'email' and 'ticket' fields
    INSERT INTO public.form_fields(title, type, is_required, form, "order")
    VALUES ('', 'email', true, new_form_id, 0),
           ('', 'ticket', true, new_form_id, 1);

    -- Ensure 'spot' product type exists for the occasion
    IF NOT EXISTS (SELECT 1 FROM eshop.product_types WHERE occasion = p_occasion_id AND type = 'spot') THEN
        INSERT INTO eshop.product_types(title, type, occasion)
        VALUES ('Spot', 'spot', p_occasion_id)
        RETURNING id INTO new_product_type_id;
    ELSE
        SELECT id INTO new_product_type_id FROM eshop.product_types WHERE occasion = p_occasion_id AND type = 'spot' LIMIT 1;
    END IF;

    -- Ensure the 'spot' product type has at least one product
    IF NOT EXISTS (SELECT 1 FROM eshop.products WHERE occasion = p_occasion_id AND product_type = new_product_type_id) THEN
        INSERT INTO eshop.products(title, price, product_type, occasion, currency_code, "order")
        VALUES ('Variant 1', 100, new_product_type_id, p_occasion_id, 'CZK', 0);
    END IF;

    -- Create the 'product_type' form field linked to 'spot'
    INSERT INTO public.form_fields(title, type, is_required, form, "order", product_type, is_ticket_field)
    VALUES ('Spot', 'product_type', false, new_form_id, 2, new_product_type_id, true);

    -- Return the raw data of the newly created form
    PERFORM public.notification_center_form_created_internal(new_form_id);
    RETURN new_form;
END;
$function$;
REVOKE ALL ON FUNCTION public.insert_form_for_occasion_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.insert_form_for_occasion_internal_v1(bigint,text,text) TO postgres;

-- Only the explicit occasion-create owner calls this initial-form boundary.
-- Manager-only creation uses its own domain right, not a fabricated editor role.
CREATE OR REPLACE FUNCTION public.create_initial_occasion_form_internal_v1(p_occasion_id bigint,p_link text,p_title text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE v_unit bigint;
BEGIN
  SELECT unit INTO v_unit FROM public.occasions WHERE id=p_occasion_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(v_unit)
    OR EXISTS(SELECT 1 FROM public.forms WHERE occasion=p_occasion_id) THEN
    RAISE insufficient_privilege USING MESSAGE='initial occasion form creation unavailable';
  END IF;
  PERFORM public.check_occasion_writable(p_occasion_id);
  RETURN public.insert_form_for_occasion_internal_v1(p_occasion_id,p_link,p_title);
END $$;
REVOKE ALL ON FUNCTION public.create_initial_occasion_form_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_initial_occasion_form_internal_v1(bigint,text,text) TO postgres;


-- SOURCE: eshop_forms/duplicate_form_to_occasion.sql
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion_internal_v1(
    source_form_id BIGINT,
    target_occasion_link TEXT,
    p_locale TEXT DEFAULT 'en'
)
RETURNS BIGINT -- Returns the ID of the new form
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    user_id UUID := auth.uid();
    target_occasion_id BIGINT;
    target_organization_id BIGINT;
    source_occasion_id BIGINT;
    source_unit_id BIGINT;
    has_source_permission BOOLEAN;
    has_target_permission BOOLEAN;
    new_form_id BIGINT;
    v_new_form_link TEXT;
    form_field_record RECORD;
    new_product_type_id BIGINT;
    product_record RECORD;
BEGIN
    -- Step 1: Resolve the target occasion ID and its organization ID from its link.
    SELECT id, organization INTO target_occasion_id, target_organization_id
    FROM public.occasions WHERE id = public.resolve_occasion_link_internal(target_occasion_link);
    IF target_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Target occasion not found for link: %', target_occasion_link;
    END IF;

    PERFORM public.check_occasion_writable(target_occasion_id);

    PERFORM public.notification_center_initialized_internal(target_organization_id);
    -- Step 2: Get the source occasion and unit IDs for permission checking.
    SELECT f.occasion, o.unit
    INTO source_occasion_id, source_unit_id
    FROM public.forms f
    JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = source_form_id;

    IF source_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Source form not found.';
    END IF;

    -- Step 3: Check if the user has editor_view rights on the source occasion or its unit.
    SELECT public.can_copy_form_source(source_occasion_id)
    INTO has_source_permission;

    IF NOT has_source_permission THEN
        RAISE EXCEPTION 'Insufficient permissions to view the source form.';
    END IF;

    -- Step 4: Check if the user has editor rights on the target occasion.
    SELECT public.can_copy_form_target(target_occasion_id)
    INTO has_target_permission;

    IF NOT has_target_permission THEN
        RAISE EXCEPTION 'Insufficient permissions to create a form in the target occasion.';
    END IF;

    -- Step 6: Copy the main form record to the target occasion.
    INSERT INTO public.forms (title, data, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds)
    SELECT
        public.copy_occasion_title_internal(title,p_locale),
        CASE WHEN source_unit_id IS DISTINCT FROM (SELECT unit FROM public.occasions WHERE id=target_occasion_id)
          THEN data #- '{payments,stripeConnectionId}' ELSE data END,
        target_occasion_id,
        type,
        bank_account,
        deadline_duration_seconds,
        CASE WHEN source_unit_id IS DISTINCT FROM (SELECT unit FROM public.occasions WHERE id=target_occasion_id)
          AND data#>'{payments,bankEnabled}'='false'::jsonb THEN false ELSE is_open END,
        NULL,
        blueprint,
        header,
        header_off,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds
    FROM public.forms
    WHERE id = source_form_id
    RETURNING id INTO new_form_id;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',new_form_id,NULL,true) WHERE id=new_form_id;

    -- Step 7: Loop through each field of the source form and perform a deep copy.
    FOR form_field_record IN
        SELECT * FROM public.form_fields WHERE form = source_form_id
    LOOP
        -- Check if the field is linked to a product type.
        IF form_field_record.product_type IS NOT NULL THEN
            -- A) If yes, perform a deep copy of the product type and its products.
            INSERT INTO eshop.product_types (title, description, type, data, occasion, maximum)
            SELECT title, description, type, data, target_occasion_id, maximum
            FROM eshop.product_types
            WHERE id = form_field_record.product_type
            RETURNING id INTO new_product_type_id;

            FOR product_record IN
                SELECT * FROM eshop.products WHERE product_type = form_field_record.product_type
            LOOP
                INSERT INTO eshop.products (title, description, price, data, product_type, occasion, is_hidden, currency_code, "order", maximum)
                VALUES (
                    product_record.title, product_record.description, product_record.price, product_record.data,
                    new_product_type_id, target_occasion_id, product_record.is_hidden, product_record.currency_code,
                    product_record.order, product_record.maximum
                );
            END LOOP;

            INSERT INTO public.form_fields (title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
            VALUES (
                form_field_record.title, form_field_record.description, form_field_record.data, form_field_record.type,
                form_field_record.is_required, new_form_id, form_field_record.is_hidden, form_field_record.order,
                new_product_type_id, form_field_record.is_ticket_field
            );
        ELSE
            -- B) If not, perform a simple copy of the form field.
            INSERT INTO public.form_fields (title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
            VALUES (
                form_field_record.title, form_field_record.description, form_field_record.data, form_field_record.type,
                form_field_record.is_required, new_form_id, form_field_record.is_hidden, form_field_record.order,
                NULL, form_field_record.is_ticket_field
            );
        END IF;
    END LOOP;

    -- Step 8: Return the ID of the newly created form.
    PERFORM public.notification_center_form_created_internal(new_form_id);
    RETURN new_form_id;
END;
$$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion(source_form_id bigint,target_occasion_link text)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT (public.duplicate_form_to_occasion_client_sync_v1(source_form_id,target_occasion_link,gen_random_uuid())#>>'{data,formId}')::bigint;
$$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_form_to_occasion(bigint,text) TO authenticated;


-- SOURCE: others/duplicate_occasion.sql
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint, p_target_unit bigint, p_locale text)
RETURNS bigint
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  new_occ         bigint;
  rec             record;
  new_info_id     bigint;
  v_new_id        bigint;
  new_place_id    bigint;
  new_event_id    bigint;
  new_bp_id       bigint;
  new_pt_id       bigint;
  new_product_id  bigint;
  new_form_id     bigint;
  v_source_unit bigint;
  v_target_unit bigint;
  v_organization bigint;
  v_demo boolean;
  v_layout_ids jsonb; v_copied_layout jsonb; v_resource_copy jsonb;
BEGIN
  SELECT unit, organization INTO v_source_unit, v_organization
  FROM public.occasions WHERE id = oc;
  v_target_unit := COALESCE(p_target_unit, v_source_unit);
  v_demo := public.is_demo_occasion(oc);
  IF auth.uid() IS NULL OR v_source_unit IS NULL OR v_target_unit IS NULL
     OR NOT public.can_copy_occasion_source(oc)
     OR public.is_demo_unit(v_target_unit)
     OR NOT public.can_copy_occasion_target(v_target_unit)
     OR NOT EXISTS (SELECT 1 FROM public.units
       WHERE id = v_target_unit AND organization = v_organization) THEN
    RAISE insufficient_privilege USING MESSAGE = 'source and target unit manager required within one organization';
  END IF;

  IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE occasion=oc AND layout IS NULL) THEN
    RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_MIGRATION_REQUIRED';
  END IF;

  PERFORM public.notification_center_initialized_internal(v_organization);
  ------------------------------------------------------------------
  -- 1. Duplicate the main occasion record.
  --    Modify the link to ensure uniqueness by appending a unique suffix.
  ------------------------------------------------------------------
  INSERT INTO public.occasions
    (created_at, updated_at, data, is_hidden, is_open, is_promoted, start_time, end_time, link, title, organization, services, unit, features, occasion_hidden, description)
  SELECT now(), now(), data, CASE WHEN v_demo THEN true ELSE is_hidden END,
         CASE WHEN v_demo THEN false ELSE is_open END, CASE WHEN v_demo THEN false ELSE is_promoted END, start_time, end_time,
         '' AS link,
         public.copy_occasion_title_internal(title,p_locale), v_organization, services, v_target_unit, features, NULL, description
  FROM public.occasions
  WHERE id = oc
  RETURNING id INTO new_occ;

  UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',new_occ,NULL,true) WHERE id=new_occ;

  ------------------------------------------------------------------
  -- 2. Create temporary mapping tables (old id → new id)
  ------------------------------------------------------------------
  CREATE TEMP TABLE tmp_places (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_events (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_exclusive_groups (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_blueprints (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_blueprint_layout_ids (blueprint bigint,old_id uuid,new_id uuid,PRIMARY KEY(blueprint,old_id)) ON COMMIT DROP;
  PERFORM 1 FROM public.occasions WHERE id=oc FOR UPDATE;
  CREATE TEMP TABLE tmp_product_types (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_products (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_spots (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_inventory_pools (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_inventory_contexts (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_resources (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_resource_slots (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_scanner_fields (old_id bigint,new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_forms (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_information_hidden (old_id bigint, new_id bigint) ON COMMIT DROP;

  ------------------------------------------------------------------
  -- 3. Duplicate tables that reference the occasion directly
  ------------------------------------------------------------------

  -- 3a. Email Templates
  INSERT INTO public.email_templates (html, occasion, unit, subject, organization, code, title)
  SELECT DISTINCT ON (code) html, new_occ, v_target_unit, subject, v_organization, code, title
  FROM public.email_templates
  WHERE occasion = oc
  ORDER BY code, (unit IS NOT DISTINCT FROM v_source_unit) DESC,
    (organization IS NOT DISTINCT FROM v_organization) DESC, id DESC;

  -- 3b. Duplicate information_hidden rows using a loop and record mapping.
  FOR rec IN
    SELECT id, data
    FROM public.information_hidden
    WHERE occasion = oc AND NOT v_demo
  LOOP
    INSERT INTO public.information_hidden (created_at, data, occasion)
    VALUES (now(), rec.data, new_occ)
    RETURNING id INTO new_info_id;

    INSERT INTO tmp_information_hidden (old_id, new_id)
    VALUES (rec.id, new_info_id);
  END LOOP;

  -- 3c. Information – update its foreign key to information_hidden using the mapping.
  INSERT INTO public.information
    (created_at, title, description, is_hidden, "order", updated_at, type, occasion, data, information_hidden, unit)
  SELECT now(), title, description, is_hidden, "order", now(), type, new_occ, data,
         CASE WHEN information_hidden IS NOT NULL
              THEN (SELECT tih.new_id FROM tmp_information_hidden AS tih WHERE tih.old_id = information_hidden)
              ELSE NULL END,
         v_target_unit
  FROM public.information
  WHERE occasion = oc;

  -- 3d. Role Info
  INSERT INTO public.role_info (title, occasion)
  SELECT title, new_occ
  FROM public.role_info
  WHERE occasion = oc;

  ------------------------------------------------------------------
  -- 4. Duplicate tables with additional foreign keys (using loops)
  ------------------------------------------------------------------

  -- 4a. Places
  FOR rec IN
    SELECT id, title, description, type, created_at, coordinates, is_hidden, "order", icon, unit
    FROM public.places
    WHERE occasion = oc
  LOOP
    INSERT INTO public.places
      (title, description, type, created_at, coordinates, is_hidden, updated_at, occasion, "order", icon, unit)
    VALUES (rec.title, rec.description, rec.type, rec.created_at, rec.coordinates, rec.is_hidden, now(), new_occ, rec."order", rec.icon, v_target_unit)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_places (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4b. Exclusive Groups
  FOR rec IN
    SELECT id, title
    FROM public.exclusive_groups
    WHERE occasion = oc
  LOOP
    INSERT INTO public.exclusive_groups (title, occasion)
    VALUES (rec.title, new_occ)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_exclusive_groups (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4c. Events – adjust the "place" foreign key using tmp_places.
  FOR rec IN
    SELECT id, title, start_time, end_time, max_participants, description, place, split_for_men_women, is_group_event, is_hidden, type
    FROM public.events
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_place_id
      FROM tmp_places AS t
      WHERE t.old_id = rec.place;

    INSERT INTO public.events
      (created_at, title, start_time, end_time, max_participants, description, place, split_for_men_women, is_group_event, updated_at, is_hidden, occasion, type)
    VALUES (now(), rec.title, rec.start_time, rec.end_time, rec.max_participants, rec.description,
            COALESCE(new_place_id, rec.place), rec.split_for_men_women, rec.is_group_event, now(), rec.is_hidden, new_occ, rec.type)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_events (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4d. Event Groups – update both parent and child using the event mapping.
  INSERT INTO public.event_groups (event_parent, event_child)
  SELECT
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = eg.event_parent),
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = eg.event_child)
  FROM public.event_groups eg
  WHERE eg.event_parent IN (SELECT old_id FROM tmp_events)
    AND eg.event_child IN (SELECT old_id FROM tmp_events);

  -- 4e. Event Roles – update event using mapping.
  INSERT INTO public.event_roles (event, role)
  SELECT (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = er.event), er.role
  FROM public.event_roles er
  WHERE er.event IN (SELECT old_id FROM tmp_events);

  -- 4f. Exclusive Events – update both event and group using mappings.
  INSERT INTO public.exclusive_events (event, "group")
  SELECT
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = ee.event),
    (SELECT teg.new_id FROM tmp_exclusive_groups AS teg WHERE teg.old_id = ee."group")
  FROM public.exclusive_events ee
  WHERE ee.event IN (SELECT old_id FROM tmp_events)
    AND ee."group" IN (SELECT old_id FROM tmp_exclusive_groups);

  ------------------------------------------------------------------
  -- 5. Duplicate ESHOP tables (using loops)
  ------------------------------------------------------------------

  -- 5a. Blueprints
  FOR rec IN
    SELECT id, data, title, organization, layout
    FROM eshop.blueprints
    WHERE occasion = oc
  LOOP
    PERFORM public.copy_blueprint_image_resources_internal(oc,new_occ,rec.layout);
    v_layout_ids:='{}';v_copied_layout:=rec.layout;
    IF rec.layout IS NOT NULL THEN
      -- Collect every declared record UUID, including nested preset documents.
      WITH RECURSIVE records(value) AS (
        SELECT rec.layout UNION ALL SELECT child.value FROM records CROSS JOIN LATERAL (
          SELECT item.value FROM jsonb_each(CASE WHEN jsonb_typeof(records.value)='object' THEN records.value ELSE '{}'::jsonb END) item
          UNION ALL SELECT item.value FROM jsonb_array_elements(CASE WHEN jsonb_typeof(records.value)='array' THEN records.value ELSE '[]'::jsonb END) item
        ) child
      )
      INSERT INTO tmp_blueprint_layout_ids(blueprint,old_id,new_id)
      SELECT rec.id,(value->>'id')::uuid,extensions.gen_random_uuid() FROM records WHERE jsonb_typeof(value)='object' AND value ? 'id'
      ON CONFLICT(blueprint,old_id) DO NOTHING;
      SELECT coalesce(jsonb_object_agg(old_id::text,new_id),'{}') INTO v_layout_ids FROM tmp_blueprint_layout_ids WHERE blueprint=rec.id;
      v_copied_layout:=public.remap_blueprint_layout_ids_internal(rec.layout,v_layout_ids);
      PERFORM public.validate_blueprint_layout_internal(v_copied_layout);
       PERFORM public.copy_blueprint_text_resources_internal(oc,NULL,new_occ,v_copied_layout);
       PERFORM public.check_blueprint_text_resources_internal(v_copied_layout,new_occ);
      PERFORM public.check_blueprint_image_resource_internal(v_copied_layout,new_occ);
    END IF;
    INSERT INTO eshop.blueprints
      (created_at, data, title, organization, occasion, updated_at,layout,layout_revision,layout_text_resource_ids)
    VALUES (now(), rec.data, rec.title, v_organization, new_occ, now(),v_copied_layout,0,CASE WHEN v_copied_layout IS NULL THEN '{}'::text[] ELSE public.blueprint_text_resource_ids_internal(v_copied_layout,new_occ) END)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_blueprints (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5b. Product Types
  FOR rec IN
    SELECT id, title, description, type, data
    FROM eshop.product_types
    WHERE occasion = oc
  LOOP
    INSERT INTO eshop.product_types
      (created_at, updated_at, title, description, type, data, occasion)
    VALUES (now(), now(), rec.title, rec.description, rec.type, rec.data, new_occ)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_product_types (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5c. Products – adjust product_type via mapping.
  FOR rec IN
    SELECT id, title, description, price, data, product_type, is_hidden, currency_code, "order", maximum
    FROM eshop.products
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_pt_id
      FROM tmp_product_types AS t
      WHERE t.old_id = rec.product_type;

    INSERT INTO eshop.products
      (created_at, updated_at, title, description, price, data, product_type, occasion, is_hidden, currency_code, "order", maximum)
    VALUES (now(), now(), rec.title, rec.description, rec.price, rec.data,
            COALESCE(new_pt_id, rec.product_type), new_occ, rec.is_hidden, rec.currency_code, rec."order", rec.maximum)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_products (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- Inventory configuration is copied, never its allocations or reservations.
  FOR rec IN SELECT * FROM public.inventory_pools WHERE occasion=oc LOOP
    INSERT INTO public.inventory_pools(title,description,type,data,sellable_capacity,occasion)
    VALUES(rec.title,rec.description,rec.type,rec.data,rec.sellable_capacity,new_occ)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_inventory_pools VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT c.* FROM public.inventory_contexts c
    JOIN tmp_inventory_pools m ON m.old_id=c.inventory_pool LOOP
    INSERT INTO public.inventory_contexts(inventory_pool,block_date,title,"order",data)
    VALUES((SELECT new_id FROM tmp_inventory_pools WHERE old_id=rec.inventory_pool),
      rec.block_date,rec.title,rec."order",rec.data) RETURNING id INTO v_new_id;
    INSERT INTO tmp_inventory_contexts VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT r.* FROM public.resources r
    JOIN tmp_inventory_pools m ON m.old_id=r.inventory_pool LOOP
    v_resource_copy:=public.copy_inventory_resource_configuration_internal(rec.id,
      (SELECT new_id FROM tmp_inventory_pools WHERE old_id=rec.inventory_pool),
      (SELECT new_id FROM tmp_places WHERE old_id=rec.place));
    INSERT INTO tmp_resources VALUES(rec.id,(v_resource_copy->>'resourceId')::bigint);
    INSERT INTO tmp_resource_slots(old_id,new_id)
      SELECT key::bigint,value::text::bigint FROM jsonb_each(v_resource_copy->'slotMap');
  END LOOP;
  INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity)
    SELECT p.new_id,c.new_id,x.quantity FROM eshop.product_inventory_contexts x
    JOIN tmp_products p ON p.old_id=x.product
    JOIN tmp_inventory_contexts c ON c.old_id=x.inventory_context;

  -- 5d. Spots – adjust foreign keys for product and blueprint.
  FOR rec IN
    SELECT id, product, secret, secret_expiration_time, title, order_product_ticket, blueprint, inventory_context, resource, resource_slot
    FROM eshop.spots
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_product_id
      FROM tmp_products AS t
      WHERE t.old_id = rec.product;

    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    v_new_id:=public.copy_empty_inventory_spot_internal(rec.id,new_occ,COALESCE(new_product_id, rec.product),COALESCE(new_bp_id, rec.blueprint),
      (SELECT new_id FROM tmp_inventory_contexts WHERE old_id=rec.inventory_context),
      (SELECT new_id FROM tmp_resources WHERE old_id=rec.resource),
      (SELECT new_id FROM tmp_resource_slots WHERE old_id=rec.resource_slot));

    INSERT INTO tmp_spots (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  ------------------------------------------------------------------
  -- Copied geometry and commercial state share the same new UUID mapping.
  -- Holds/orders are deliberately absent and numeric spots/products remap too.
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked,product_assignment_mode)
  SELECT bp.new_id,node_map.new_id,sp.new_id,unit_map.new_id,group_map.new_id,sb.blocked,sb.product_assignment_mode
  FROM eshop.blueprint_seat_bindings sb JOIN tmp_blueprints bp ON bp.old_id=sb.blueprint JOIN tmp_spots sp ON sp.old_id=sb.spot
  JOIN tmp_blueprint_layout_ids node_map ON node_map.blueprint=sb.blueprint AND node_map.old_id=sb.node_id
  LEFT JOIN tmp_blueprint_layout_ids unit_map ON unit_map.blueprint=sb.blueprint AND unit_map.old_id=sb.selection_unit
  LEFT JOIN tmp_blueprint_layout_ids group_map ON group_map.blueprint=sb.blueprint AND group_map.old_id=sb.group_node;
  INSERT INTO eshop.blueprint_group_products(blueprint,group_node,product)
  SELECT bp.new_id,node_map.new_id,p.new_id FROM eshop.blueprint_group_products gp
  JOIN tmp_blueprints bp ON bp.old_id=gp.blueprint JOIN tmp_products p ON p.old_id=gp.product
  JOIN tmp_blueprint_layout_ids node_map ON node_map.blueprint=gp.blueprint AND node_map.old_id=gp.group_node;
  INSERT INTO eshop.blueprint_area_bindings(blueprint,node_id,inventory_context,product)
  SELECT bp.new_id,node_map.new_id,c.new_id,p.new_id FROM eshop.blueprint_area_bindings ab JOIN tmp_blueprints bp ON bp.old_id=ab.blueprint
  JOIN tmp_inventory_contexts c ON c.old_id=ab.inventory_context JOIN tmp_products p ON p.old_id=ab.product
  JOIN tmp_blueprint_layout_ids node_map ON node_map.blueprint=ab.blueprint AND node_map.old_id=ab.node_id;

  -- 7. Duplicate Forms and Form Fields
  ------------------------------------------------------------------

  -- 7a. Forms – adjust the blueprint foreign key via mapping and update the link to be unique.
  FOR rec IN
    SELECT id, data, key, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, title, participant_capacity, waitlist_enabled, show_remaining_capacity, waitlist_offer_duration_seconds
    FROM public.forms
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    INSERT INTO public.forms
      (created_at, data, key, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, updated_at, title, participant_capacity, waitlist_enabled, show_remaining_capacity, waitlist_offer_duration_seconds)
    VALUES (now(), rec.data, uuid_generate_v4(), new_occ, rec.type,
            CASE WHEN v_demo THEN NULL WHEN v_source_unit = v_target_unit OR EXISTS (
              SELECT 1 FROM eshop.unit_bank_accounts uba
              WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN rec.bank_account ELSE NULL END,
            rec.deadline_duration_seconds,
            CASE WHEN v_demo THEN false WHEN v_source_unit <> v_target_unit AND rec.bank_account IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM eshop.unit_bank_accounts uba
                WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN false ELSE rec.is_open END,
            NULL,
            COALESCE(new_bp_id, rec.blueprint), rec.header, rec.header_off, now(), rec.title, rec.participant_capacity, rec.waitlist_enabled, rec.show_remaining_capacity, rec.waitlist_offer_duration_seconds)
    RETURNING id INTO v_new_id;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',v_new_id,NULL,true) WHERE id=v_new_id;

    INSERT INTO tmp_forms (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 7b. Form Fields – update the "form" foreign key and product_type via mapping tables.
  FOR rec IN SELECT * FROM public.form_fields WHERE form IN (SELECT old_id FROM tmp_forms) LOOP
    INSERT INTO public.form_fields(created_at,title,description,data,type,is_required,form,is_hidden,"order",product_type,is_ticket_field)
    VALUES(now(),rec.title,rec.description,rec.data,rec.type,rec.is_required,
      (SELECT new_id FROM tmp_forms WHERE old_id=rec.form),rec.is_hidden,rec."order",
      (SELECT new_id FROM tmp_product_types WHERE old_id=rec.product_type),rec.is_ticket_field) RETURNING id INTO v_new_id;
    INSERT INTO tmp_scanner_fields VALUES(rec.id,v_new_id);
  END LOOP;
  INSERT INTO public.scanner_settings(occasion_id,config)
  SELECT new_occ,jsonb_set(jsonb_set(config,'{products}',jsonb_build_object('mode',config#>>'{products,mode}',
    'ids',coalesce((SELECT jsonb_agg(m.new_id ORDER BY n) FROM jsonb_array_elements(config#>'{products,ids}') WITH ORDINALITY x(p,n) JOIN tmp_products m ON m.old_id=p::text::bigint),'[]'::jsonb),
    'order',coalesce((SELECT jsonb_agg(m.new_id ORDER BY n) FROM jsonb_array_elements(config#>'{products,order}') WITH ORDINALITY x(p,n) JOIN tmp_products m ON m.old_id=p::text::bigint),'[]'::jsonb))),
    '{fields}',coalesce((SELECT jsonb_agg(CASE WHEN f->>'source'='builtin' THEN f ELSE
      f||jsonb_build_object('form_id',fm.new_id,'field_id',ff.new_id,'key',(CASE WHEN f->>'source'='ticket_field' THEN 'ticket' ELSE 'order' END)||':'||fm.new_id||':'||ff.new_id) END ORDER BY n)
      FROM jsonb_array_elements(config->'fields') WITH ORDINALITY x(f,n)
      LEFT JOIN tmp_forms fm ON fm.old_id=(f->>'form_id')::bigint LEFT JOIN tmp_scanner_fields ff ON ff.old_id=(f->>'field_id')::bigint
      WHERE f->>'source'='builtin' OR (fm.new_id IS NOT NULL AND ff.new_id IS NOT NULL)),'[]'::jsonb))
  FROM public.scanner_settings WHERE occasion_id=oc;


  ------------------------------------------------------------------
  -- 8. Return the new occasion id
  ------------------------------------------------------------------
  -- References are remapped only after the complete type map exists.
  UPDATE public.occasions o SET features=(SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' AND f ? 'layout'
    THEN jsonb_set(f,'{layout,templates}',(SELECT jsonb_object_agg(t.key,jsonb_set(t.value,'{elements}',
      (SELECT jsonb_agg(CASE WHEN e->>'binding'='productType' THEN jsonb_set(e,'{productTypeId}',
        to_jsonb((SELECT m.new_id FROM tmp_product_types m WHERE m.old_id=(e->>'productTypeId')::bigint))) ELSE e END ORDER BY n)
       FROM jsonb_array_elements(t.value->'elements') WITH ORDINALITY x(e,n)))) FROM jsonb_each(f->'layout'->'templates') t)) ELSE f END ORDER BY n)
    FROM jsonb_array_elements(o.features) WITH ORDINALITY x(f,n)) WHERE o.id=new_occ;
  PERFORM public.validate_ticket_layout_references(new_occ,f->'layout') FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=new_occ AND f->>'code'='ticket' AND f ? 'layout';
  DROP TABLE tmp_places, tmp_events, tmp_exclusive_groups, tmp_blueprints,tmp_blueprint_layout_ids,
    tmp_product_types, tmp_products, tmp_spots, tmp_forms, tmp_information_hidden,
    tmp_inventory_pools,tmp_inventory_contexts,tmp_resources,tmp_resource_slots,tmp_scanner_fields;
  PERFORM public.notification_center_form_created_internal(id) FROM public.forms WHERE occasion=new_occ;
  RETURN new_occ;
END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint)
  FROM PUBLIC, anon, authenticated, service_role;

-- Existing internal callers retain same-unit semantics.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.duplicate_occasion_internal_v1(oc, NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint)
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint,p_target_unit bigint)
RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = public, extensions AS $$
 SELECT public.duplicate_occasion_internal_v1(oc,p_target_unit,'en');
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: eshop_forms/delete_form_internal_v1.sql
CREATE OR REPLACE FUNCTION public.delete_form_internal_v1(p_form_id bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_response_count INT;
    v_form_key UUID;
    v_product_type_ids_to_check BIGINT[];
    v_deletable_product_type_ids BIGINT[];
BEGIN
    -- Step 1: Check if the form has any responses. If so, prevent deletion.
    -- This part of the logic remains unchanged.
    SELECT key INTO v_form_key FROM public.forms WHERE id = p_form_id;

    IF v_form_key IS NOT NULL THEN
        SELECT COUNT(*)
        INTO v_response_count
        FROM eshop.orders
        WHERE (data->>'form')::uuid = v_form_key;

        IF v_response_count > 0 THEN
            RAISE EXCEPTION 'This form cannot be deleted because it has responses.';
        END IF;
    END IF;

    -- Step 2: Collect all product_type IDs associated with this form's fields.
    -- We need this list to attempt a cleanup after deleting the fields.
    SELECT ARRAY_AGG(DISTINCT product_type)
    INTO v_product_type_ids_to_check
    FROM public.form_fields
    WHERE form = p_form_id AND product_type IS NOT NULL;

    PERFORM 1 FROM public.occasions WHERE id=(SELECT occasion FROM public.forms WHERE id=p_form_id) FOR UPDATE;
    IF EXISTS(SELECT 1 FROM eshop.product_types pt WHERE pt.id=ANY(v_product_type_ids_to_check) AND public.ticket_layout_uses_product_type(pt.occasion,pt.id) AND NOT EXISTS(SELECT 1 FROM eshop.products p WHERE p.product_type=pt.id) AND NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.product_type=pt.id AND ff.form<>p_form_id))
    THEN RAISE EXCEPTION 'ticket_product_type_in_use'; END IF;
    -- Step 3: Delete the form fields unconditionally (after the response check).
    -- This severs the link from the form to the product types, fulfilling the
    -- requirement to "delete field anyway".
    DELETE FROM public.form_fields WHERE form = p_form_id;

    -- Step 4: Attempt to clean up the product types that were associated with the form.
    -- We will only delete product types that are not referenced by any existing products.
    IF v_product_type_ids_to_check IS NOT NULL AND array_length(v_product_type_ids_to_check, 1) > 0 THEN
        -- From our list of candidates, find which ones are NOT used by any products.
        SELECT ARRAY_AGG(pt.id)
        INTO v_deletable_product_type_ids
        FROM unnest(v_product_type_ids_to_check) AS pt(id)
        WHERE NOT EXISTS (
            SELECT 1
            FROM eshop.products p
            WHERE p.product_type = pt.id
        ) AND NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.product_type=pt.id);

        -- If we found any deletable product types, delete them.
        IF v_deletable_product_type_ids IS NOT NULL AND array_length(v_deletable_product_type_ids, 1) > 0 THEN
            DELETE FROM eshop.product_types
            WHERE id = ANY(v_deletable_product_type_ids);
        END IF;
    END IF;

    -- Step 5: Finally, delete the form itself.
    DELETE FROM public.notification_center_source_state WHERE source_key='form-availability:'||p_form_id;
    DELETE FROM public.forms WHERE id = p_form_id;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_form_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: others/delete_occasion.sql
CREATE OR REPLACE FUNCTION public.delete_occasion_internal_v1(oc bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    unit_id BIGINT;
BEGIN
  PERFORM public.check_occasion_writable(oc);

  SELECT unit
  INTO unit_id
  FROM public.occasions
  WHERE id = oc;

  IF NOT public.can_delete_occasion_in_unit(unit_id) THEN RAISE EXCEPTION 'User is not manager.'; END IF;

  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=oc));

-- ***********************************************************
  -- 0. SAFETY CHECK: Strict Order Check
  --    Prevent deletion if ANY order exists (even storno).
  -- ***********************************************************
  IF EXISTS (
      SELECT 1
      FROM eshop.orders
      WHERE occasion = oc
  ) THEN
      RAISE EXCEPTION 'Cannot delete occasion % because it contains orders (including storno).', oc;
  END IF;

  -- ***********************************************************
  -- 1. Delete records that depend on 'events'.
  -- ***********************************************************
  DELETE FROM public.event_groups
    WHERE event_parent IN (SELECT id FROM public.events WHERE occasion = oc)
       OR event_child  IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_roles
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_users
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_users_saved
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.exclusive_events
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  -- ***********************************************************
  -- 2. Delete the 'events' themselves.
  -- ***********************************************************
  DELETE FROM public.events
    WHERE occasion = oc;

  -- ***********************************************************
  -- 3. Delete 'orders' dependent records.
  -- ***********************************************************
  DELETE FROM eshop.order_product_ticket
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  DELETE FROM eshop.orders_history
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  DELETE FROM eshop.bank_account_requests
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  -- ***********************************************************
  -- 4. Delete form-related records.
  -- ***********************************************************
  DELETE FROM public.form_fields
    WHERE form IN (SELECT id FROM public.forms WHERE occasion = oc);

  DELETE FROM public.notification_center_source_state WHERE source_key LIKE 'form-availability:%'
    AND (state->>'formId')::bigint IN (SELECT id FROM public.forms WHERE occasion=oc);
  DELETE FROM public.forms
    WHERE occasion = oc;

  -- ***********************************************************
  -- 5. Delete records from tables that reference the occasion directly.
  -- ***********************************************************
  DELETE FROM public.email_templates
    WHERE occasion = oc;

  DELETE FROM public.email_wrappers
    WHERE occasion = oc;

  DELETE FROM public.information
    WHERE occasion = oc;

  DELETE FROM public.information_hidden
    WHERE occasion = oc;

  DELETE FROM public.log_notifications
    WHERE occasion = oc;

  UPDATE public.email_messages SET workflow_state='cancelled',last_error='occasion_deleted',data='{}',prepared=NULL,recipient=NULL,occasion=NULL,unit=NULL
    WHERE occasion = oc;

  DELETE FROM public.log_emails
    WHERE occasion = oc;

  DELETE FROM public.news
    WHERE occasion = oc;

  DELETE FROM public.occasion_users
    WHERE occasion = oc;

  DELETE FROM public.user_news
    WHERE occasion = oc;

  DELETE FROM public.places
    WHERE occasion = oc;

  DELETE FROM public.role_info
    WHERE occasion = oc;

  DELETE FROM public.user_groups
    WHERE "group" IN (SELECT id FROM public.user_group_info WHERE occasion = oc);

  DELETE FROM public.user_group_info
    WHERE occasion = oc;

  DELETE FROM public.exclusive_groups
    WHERE occasion = oc;

  -- ***********************************************************
  -- 6. Delete remaining records from the eshop schema.
  -- ***********************************************************
  DELETE FROM eshop.tickets
    WHERE occasion = oc;

  -- Configuration bindings depend on seats/products as well as their plan.
  DELETE FROM eshop.blueprint_seat_bindings WHERE blueprint IN (SELECT id FROM eshop.blueprints WHERE occasion=oc);
  DELETE FROM eshop.blueprint_group_products WHERE blueprint IN (SELECT id FROM eshop.blueprints WHERE occasion=oc);
  DELETE FROM eshop.blueprint_area_bindings WHERE blueprint IN (SELECT id FROM eshop.blueprints WHERE occasion=oc);

  DELETE FROM eshop.spots
    WHERE occasion = oc;

  DELETE FROM eshop.products
    WHERE occasion = oc;

  DELETE FROM eshop.product_types
    WHERE occasion = oc;

  DELETE FROM eshop.planned_changes
    WHERE occasion = oc;

  DELETE FROM eshop.bank_account_requests
    WHERE occasion = oc;


  DELETE FROM eshop.blueprints
    WHERE occasion = oc;

  -- Delete orders (Safe now: we checked for non-storno orders at step 0,
  -- and deleted dependents in step 3).
  DELETE FROM eshop.orders
    WHERE occasion = oc;

  -- ***********************************************************
  -- 7. Null out referencing images.
  -- ***********************************************************
  UPDATE public.images
    SET occasion = NULL
    WHERE occasion = oc;

  -- ***********************************************************
  -- 8. Finally, delete the occasion itself.
  -- ***********************************************************
  DELETE FROM public.occasions
    WHERE id = oc;

  RETURN;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_occasion_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.delete_occasion(oc bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
BEGIN
  PERFORM public.delete_occasion_client_sync_v1(oc,extensions.gen_random_uuid());
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_occasion(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion(bigint) TO authenticated;


-- SOURCE: eshop_forms/update_form_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.update_form_client_sync_v1(p_form jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_form bigint;
  v_begin jsonb; v_hash text; v_version bigint; v_expected bigint; v_users uuid[]; v_result jsonb; v_check record; v_current bigint;
BEGIN
  IF p_form IS NULL OR jsonb_typeof(p_form)<>'object'
    OR octet_length(p_form::text)>4194304 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid form aggregate'; END IF;
  v_occasion:=NULLIF(p_form->>'occasion','')::bigint;
  v_form:=NULLIF(p_form->>'id','')::bigint;
  IF v_actor IS NULL OR v_occasion IS NULL OR v_form IS NULL
    OR NOT public.can_write_orders(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'form',p_form)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=v_form AND occasion=v_occasion) THEN RAISE insufficient_privilege USING MESSAGE='foreign form'; END IF;
  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=v_occasion));
  -- Parent order matches checkout: form, product, blueprint, then seats.
  PERFORM 1 FROM public.forms WHERE id=v_form AND occasion=v_occasion FOR UPDATE;
  PERFORM 1 FROM eshop.product_types WHERE occasion=v_occasion ORDER BY id FOR UPDATE;
  PERFORM 1 FROM eshop.products WHERE occasion=v_occasion ORDER BY id FOR UPDATE;
  IF v_form IS NOT NULL THEN
    INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('form','occasion',v_occasion,v_form::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='form' AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_form::text FOR UPDATE;
  ELSE v_version:=0; END IF;
  -- Missing baseline remains an installed-client adapter, explicitly not MCP-ready.
  v_expected:=CASE WHEN p_form ? 'expected_aggregate_version' THEN (p_form->>'expected_aggregate_version')::bigint ELSE v_version END;
  IF v_expected IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('aggregate_version',v_version)); END IF;
  -- These maps were frozen when the editor loaded. No read-before-write rebasing.
  -- Missing maps are the bounded released-client facade, not MCP-ready authoring.
  IF p_form ? 'expected_product_versions' OR p_form ? 'expected_product_type_versions' THEN
    IF jsonb_typeof(p_form->'expected_product_versions') IS DISTINCT FROM 'object'
      OR jsonb_typeof(p_form->'expected_product_type_versions') IS DISTINCT FROM 'object' THEN
      RAISE invalid_parameter_value USING MESSAGE='original product versions required'; END IF;
    FOR v_check IN
      SELECT DISTINCT 'product'::text kind, (p->>'id')::bigint id FROM jsonb_array_elements(coalesce(p_form->'form_fields','[]')) f
        CROSS JOIN LATERAL jsonb_array_elements(coalesce(nullif(f#>'{product_type,products}','null'),'[]')) p WHERE p->>'id' IS NOT NULL
      UNION SELECT 'product',value::bigint FROM jsonb_array_elements_text(coalesce(p_form->'deleted_product_ids','[]'))
      UNION SELECT DISTINCT 'product',p.id FROM eshop.products p JOIN public.form_fields ff ON ff.product_type=p.product_type
        WHERE ff.form=v_form AND ff.id IN (SELECT value::bigint FROM jsonb_array_elements_text(coalesce(p_form->'deleted_field_ids','[]')))
      UNION SELECT DISTINCT 'product_type',(f#>>'{product_type,id}')::bigint FROM jsonb_array_elements(coalesce(p_form->'form_fields','[]')) f
        WHERE f#>>'{product_type,id}' IS NOT NULL
      ORDER BY 1,2
    LOOP
      IF NOT (CASE v_check.kind WHEN 'product' THEN p_form->'expected_product_versions'
        ELSE p_form->'expected_product_type_versions' END) ? v_check.id::text THEN
        RAISE invalid_parameter_value USING MESSAGE='missing original product baseline'; END IF;
      IF (v_check.kind='product' AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=v_check.id AND occasion=v_occasion))
        OR (v_check.kind='product_type' AND NOT EXISTS(SELECT 1 FROM eshop.product_types WHERE id=v_check.id AND occasion=v_occasion)) THEN
        RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('entity_type',v_check.kind,'entity_id',v_check.id,'deleted',true)); END IF;
      SELECT coalesce(v.version,0) INTO v_current FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
        ON v.aggregate_type=v_check.kind AND v.scope_type='occasion' AND v.scope_id=v_occasion AND v.aggregate_id=v_check.id::text;
      IF ((CASE v_check.kind WHEN 'product' THEN p_form->'expected_product_versions' ELSE p_form->'expected_product_type_versions' END)->>v_check.id::text)::bigint IS DISTINCT FROM v_current THEN
        RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
          jsonb_build_object('aggregate_version',v_version,'entity_type',v_check.kind,'entity_id',v_check.id,'entity_version',v_current));
      END IF;
    END LOOP;
  END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou JOIN eshop.order_product_ticket opt
    ON opt.ticket=ou.ticket JOIN eshop.products p ON p.id=opt.product
  WHERE ou.occasion=v_occasion AND p.occasion=v_occasion;
  BEGIN
    v_result:=public.update_form_internal_v1(p_form-'expected_aggregate_version'-'expected_product_versions'-'expected_product_type_versions');
    IF coalesce((v_result->>'code')::integer,500)<>200 THEN
      RAISE SQLSTATE 'P0F01' USING MESSAGE='authoring domain rejected'; END IF;
  EXCEPTION WHEN SQLSTATE 'P0F01' THEN NULL;
  END;
  IF coalesce((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN (v_result->>'code')::integer BETWEEN 100 AND 599 THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  v_form:=(v_result->>'form_id')::bigint;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('form','occasion',v_occasion,v_form::text,1)
    ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp()
    RETURNING version INTO v_version;
  v_result:=v_result||jsonb_build_object('aggregate_version',v_version,
    'product_versions',public.get_ticketing_product_versions_internal_v1(v_occasion,'product'),
    'product_type_versions',public.get_ticketing_product_versions_internal_v1(v_occasion,'product_type'));
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.form.save',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form,'operation','update',
      'safeLabel',left(p_form->>'title',240),'changedFields',jsonb_build_array(
        'configuration','products'))),v_users,v_result);
END; $function$;

REVOKE ALL ON FUNCTION public.update_form_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_form_client_sync_v1(jsonb,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_form(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.update_form_client_sync_v1(input_data,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',result->'code')||result->'data';
END $$;
REVOKE ALL ON FUNCTION public.update_form(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_form(jsonb) TO authenticated;


-- SOURCE: eshop_forms/delete_form_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.delete_form_domain_command_internal_v1(p_form_id bigint,p_command_id uuid,p_expected_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); oc bigint; title text; begin_result jsonb; hash text; version bigint; used bigint; original_key uuid;
BEGIN
 SELECT occasion INTO oc FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=actor AND command_name='inventory.form.delete';
 IF NOT FOUND THEN SELECT t.occasion INTO oc FROM public.forms t WHERE id=p_form_id; END IF;
 IF actor IS NULL OR oc IS NULL OR public.can_author_forms(oc) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 hash:=encode(extensions.digest(convert_to((jsonb_build_object('formId',p_form_id)||CASE WHEN p_expected_version IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('expectedVersion',p_expected_version) END)::text,'UTF8'),'sha256'),'hex');
 begin_result:=public.begin_client_mutation_v1(p_command_id,'inventory.form.delete',oc,actor,hash);
 IF begin_result->>'disposition'='replay' THEN RETURN begin_result->'response'; END IF;
  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=oc));
 PERFORM 1 FROM public.forms WHERE occasion=oc ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.product_types WHERE occasion=oc ORDER BY id FOR UPDATE;
 SELECT t.title,t.key INTO title,original_key FROM public.forms t WHERE id=p_form_id AND occasion=oc FOR UPDATE;
 IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',404,jsonb_build_object('formId',p_form_id)); END IF;
 SELECT coalesce(v.version,0) INTO version FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type='form' AND v.scope_type='occasion' AND v.scope_id=oc AND v.aggregate_id=p_form_id::text;
 IF p_expected_version IS NOT NULL AND p_expected_version IS DISTINCT FROM version THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('aggregate_version',version)); END IF;
 SELECT count(*) INTO used FROM eshop.orders WHERE form=p_form_id OR data->>'form'=original_key::text;
 IF used>0 THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('message','form is in use')); END IF;
 PERFORM public.delete_form_internal_v1(p_form_id);
 DELETE FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_type='occasion' AND scope_id=oc AND aggregate_id=p_form_id::text;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,oc,'inventory.form.delete',jsonb_build_array(jsonb_build_object('entityType','form','entityId',p_form_id,'operation','delete','safeLabel',left(title,240),'changedFields',jsonb_build_array('aggregate'))),'{}'::uuid[],jsonb_build_object('formId',p_form_id));
END $$;
REVOKE ALL ON FUNCTION public.delete_form_domain_command_internal_v1(bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.delete_form_client_sync_v1(p_form_id bigint,p_command_id uuid,p_expected_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF p_expected_version IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='original form version required'; END IF;
 RETURN public.delete_form_domain_command_internal_v1(p_form_id,p_command_id,p_expected_version);
END $$;
REVOKE ALL ON FUNCTION public.delete_form_client_sync_v1(bigint,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_form_client_sync_v1(bigint,uuid,bigint) TO authenticated;
-- Published two-argument shape retains its original receipt hash. It cannot
-- reconstruct an editor baseline and remains subject to the client upgrade gate.
CREATE OR REPLACE FUNCTION public.delete_form_client_sync_v1(p_form_id bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.delete_form_domain_command_internal_v1(p_form_id,p_command_id,NULL);
$$;
REVOKE ALL ON FUNCTION public.delete_form_client_sync_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_form_client_sync_v1(bigint,uuid) TO authenticated;


-- SOURCE: others/save_occasion_domain_command_internal_v1.sql

-- The public save wrapper and the settings UI allow unit editors. The renamed
-- canonical domain command retained its older occasion-only guard, so it must
-- accept the same role before it reaches update_occasion_internal_v1.
CREATE OR REPLACE FUNCTION public.save_occasion_domain_command_internal_v1(
  p_occasion bigint,
  p_command_id uuid,
  p_expected_version bigint,
  p_config jsonb
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_version bigint;
  v_begin jsonb;
  v_hash text;
  v_entity jsonb;
  v_old_hidden boolean;
  v_new_hidden boolean;
  v_old_unit bigint;
  v_new_unit bigint;
  v_features jsonb;
  v_fanout_units bigint[] := '{}';
BEGIN
  SELECT o.unit INTO v_old_unit
  FROM public.occasions o
  WHERE o.id = p_occasion;

  IF v_actor IS NULL OR NOT public.can_edit_occasion(p_occasion,(p_config->>'unit')::bigint) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor required';
  END IF;

  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object'
    OR octet_length(p_config::text) > 1048576
    OR (p_config->>'id')::bigint IS DISTINCT FROM p_occasion
    OR EXISTS (
      SELECT 1
      FROM jsonb_object_keys(p_config) key
      WHERE key NOT IN (
        'id', 'start_time', 'end_time', 'is_open', 'is_hidden', 'is_promoted',
        'link', 'title', 'description', 'data', 'services', 'organization',
        'unit', 'features', 'form_link', 'has_orders', 'stats', 'ticket_layout_change'
      )
    )
  THEN
    RAISE invalid_parameter_value USING MESSAGE = 'invalid occasion aggregate';
  END IF;

  v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion', p_occasion,
    'expectedVersion', p_expected_version,
    'config', p_config
  )::text, 'UTF8'), 'sha256'), 'hex');
  v_begin := public.begin_client_mutation_v1(
    p_command_id,
    'occasion.config.save',
    p_occasion,
    v_actor,
    v_hash
  );
  IF v_begin->>'disposition' = 'replay' THEN
    RETURN v_begin->'response';
  END IF;

  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=p_occasion));
  IF NOT (p_config ? 'ticket_layout_change' AND p_config-ARRAY['id','ticket_layout_change']='{}'::jsonb) THEN
    PERFORM 1 FROM public.forms WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
  END IF;

  SELECT o.is_hidden, o.unit INTO v_old_hidden, v_old_unit
  FROM public.occasions o
  WHERE o.id = p_occasion
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,
      'rejected',
      404,
      jsonb_build_object('version', 0, 'occasion', NULL)
    );
  END IF;

  INSERT INTO public.client_aggregate_versions(
    aggregate_type, scope_type, scope_id, aggregate_id, version
  ) VALUES ('occasion', 'occasion', p_occasion, p_occasion::text, 0)
  ON CONFLICT DO NOTHING;
  SELECT version INTO v_version
  FROM public.client_aggregate_versions
  WHERE aggregate_type = 'occasion'
    AND scope_type = 'occasion'
    AND scope_id = p_occasion
    AND aggregate_id = p_occasion::text
  FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    SELECT to_jsonb(o) || jsonb_build_object('aggregate_version', v_version)
    INTO v_entity
    FROM public.occasions o
    WHERE o.id = p_occasion;
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,
      'conflict',
      409,
      jsonb_build_object('version', v_version, 'occasion', v_entity)
    );
  END IF;

  IF p_config ? 'ticket_layout_change' AND p_config - ARRAY['id','ticket_layout_change']='{}'::jsonb THEN
    IF NOT public.can_edit_ticket_layout(p_occasion) THEN
      RAISE insufficient_privilege USING MESSAGE='unit editor required';
    END IF;
    SELECT features INTO v_features FROM public.occasions WHERE id=p_occasion;
    v_features:=public.merge_ticket_layout_features(v_features,v_features,p_config->'ticket_layout_change');
    v_features:=public.merge_ticket_appearance_internal_v1(p_occasion,v_features,p_config#>'{ticket_layout_change,appearance}');
    PERFORM public.validate_ticket_layout_references(p_occasion,f->'layout')
      FROM jsonb_array_elements(v_features) f WHERE f->>'code'='ticket' AND f ? 'layout';
    UPDATE public.occasions SET features=v_features,updated_at=clock_timestamp() WHERE id=p_occasion;
  ELSE
    PERFORM public.update_occasion_internal_v1(p_config);
  END IF;
  UPDATE public.client_aggregate_versions
  SET version = version + 1, updated_at = clock_timestamp()
  WHERE aggregate_type = 'occasion'
    AND scope_type = 'occasion'
    AND scope_id = p_occasion
    AND aggregate_id = p_occasion::text
  RETURNING version INTO v_version;
  SELECT to_jsonb(o) || jsonb_build_object('aggregate_version', v_version)
  INTO v_entity
  FROM public.occasions o
  WHERE o.id = p_occasion;

  v_new_hidden := (v_entity->>'is_hidden')::boolean;
  v_new_unit := (v_entity->>'unit')::bigint;
  IF NOT v_old_hidden THEN
    v_fanout_units := array_append(v_fanout_units, v_old_unit);
  END IF;
  IF NOT v_new_hidden AND v_new_unit IS DISTINCT FROM v_old_unit THEN
    v_fanout_units := array_append(v_fanout_units, v_new_unit);
  ELSIF NOT v_new_hidden AND v_old_hidden THEN
    v_fanout_units := array_append(v_fanout_units, v_new_unit);
  END IF;

  RETURN public.complete_client_mutation_applied_v1(
    p_command_id,
    p_occasion,
    'occasion.config.save',
    'configuration',
    jsonb_build_array(jsonb_build_object(
      'entityType', 'occasion',
      'entityId', p_occasion,
      'operation', 'update',
      'safeLabel', left(v_entity->>'title', 240),
      'changedFields', jsonb_build_array('configuration')
    )),
    CASE WHEN v_old_hidden AND NOT v_new_hidden THEN ARRAY[
      'occasion_config', 'program_catalog', 'map_catalog', 'content_catalog',
      'live_public'
    ] ELSE ARRAY['occasion_config'] END,
    '[]',
    '[]',
    jsonb_build_object('version', v_version, 'occasion', v_entity),
    CASE WHEN NOT v_new_hidden THEN ARRAY['occasion_config'] ELSE '{}'::text[] END,
    '[]',
    'user',
    NULL,
    '[]',
    v_fanout_units
  );
END;
$$;

REVOKE ALL ON FUNCTION public.save_occasion_domain_command_internal_v1(
  bigint, uuid, bigint, jsonb
) FROM PUBLIC, anon, authenticated;



-- SOURCE: notification_center/feed_baseline.sql
-- Quiet upgrade baseline without enabling, disabling or changing activation generation.
DO $$ DECLARE a record; f record; baseline_at timestamptz:=clock_timestamp(); BEGIN
 FOR a IN SELECT organization FROM public.notification_center_organizations ORDER BY organization LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('notification-center-organization:'||a.organization,0));
  FOR f IN SELECT forms.id FROM public.forms JOIN public.occasions oc ON oc.id=forms.occasion WHERE oc.organization=a.organization ORDER BY forms.id LOOP
   PERFORM public.notification_center_form_availability_internal(f.id,baseline_at,NULL,true);
  END LOOP;
 END LOOP;
END $$;

COMMIT;
