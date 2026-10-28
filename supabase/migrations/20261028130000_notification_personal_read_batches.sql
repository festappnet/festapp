-- Generated forward migration: notification-center-personal-read-batches-2026-10-28
-- Prerequisites: 20261021100000_canonical_authorization.sql, 20261024010000_organization_notification_center.sql, 20261024025000_notification_email_recipient.sql, 20261024120000_order_email_recovery.sql, 20261024220000_cancelled_order_email_alerts.sql, 20261024235000_notification_center_canonical_availability.sql, 20261026120000_notification_center_feed.sql, 20261026150000_notification_center_order_periods.sql, 20261026230000_notification_center_unread_snapshot.sql, 20261027210000_notification_center_overview.sql, 20261027220000_notification_center_daily_overview.sql, 20261027234500_notification_group_order_selection.sql, 20261028010000_notification_legacy_place_totals.sql, 20261028013000_notification_category_rollups.sql, 20261028020000_notification_center_lifecycle.sql, 20261028030000_notification_new_orders_exclude_cancelled.sql, 20261028120000_notification_center_current_rollups.sql
BEGIN;
DO $$ BEGIN IF to_regclass('public.notification_center_organizations') IS NULL OR to_regclass('public.notification_center_activation') IS NOT NULL OR to_regclass('public.notification_center_source_state') IS NULL OR to_regprocedure('public.get_notification_center_updates(bigint,bigint,uuid[])') IS NULL THEN RAISE EXCEPTION 'notification_feed_prerequisites_missing'; END IF; END $$;

-- SOURCE: notification_center/read_state.sql
-- Personal attention state: opening sees a snapshot; following reads one batch.
ALTER TABLE public.notification_center_user_state ADD COLUMN IF NOT EXISTS seen_through_sequence bigint NOT NULL DEFAULT 0;
CREATE TABLE IF NOT EXISTS public.notification_center_read_batches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 recipient uuid NOT NULL, group_key text NOT NULL,
 after_sequence bigint NOT NULL, through_sequence bigint NOT NULL,
 read_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(after_sequence>=0 AND through_sequence>after_sequence),
 UNIQUE(organization,recipient,group_key,through_sequence)
);
ALTER TABLE public.notification_center_read_batches ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_center_read_batches FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.notification_center_batch_internal(
 e public.notification_center_events,d public.notification_center_deliveries)
RETURNS TABLE(batch_id text,is_read boolean,after_sequence bigint,through_sequence bigint,group_key text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH state AS (
  SELECT coalesce((SELECT read_through_sequence FROM public.notification_center_user_state
   WHERE organization=d.organization AND recipient=d.recipient),0) baseline,
   CASE WHEN e.occasion IS NOT NULL AND e.kind NOT IN ('email_problem','bank_problem')
    THEN 'occasion-kind:'||e.occasion||':'||e.kind ELSE 'event:'||e.id END key),
 receipt AS (
  SELECT b.* FROM public.notification_center_read_batches b,state s
  WHERE b.organization=d.organization AND b.recipient=d.recipient AND b.group_key=s.key
   AND d.sequence>b.after_sequence AND d.sequence<=b.through_sequence
  ORDER BY b.through_sequence LIMIT 1),
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

CREATE OR REPLACE FUNCTION public.mark_notification_center_item_read(p_organization bigint,p_scope jsonb)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE id text:=p_scope->>'id'; base text; lower_bound bigint; upper_bound bigint;
 actual_upper bigint; baseline bigint; last_read bigint; occ bigint; snap bigint;
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 IF coalesce(p_scope->>'snapshot','') !~ '^[0-9]{1,18}$' THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_snapshot'; END IF;
 SELECT read_through_sequence,least((p_scope->>'snapshot')::bigint,last_delivery_sequence)
  INTO baseline,snap FROM public.notification_center_user_state
  WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 IF id ~ '^occasion-kind:[0-9]{1,18}:[a-z_]+:batch:[0-9]{1,18}$' THEN
  base:=regexp_replace(id,':batch:[0-9]+$','');
  lower_bound:=substring(id from ':batch:([0-9]+)$')::bigint;
  occ:=split_part(id,':',2)::bigint;
  PERFORM public.notification_center_check_context(p_organization,occ);
 ELSIF id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
  base:='event:'||id; lower_bound:=0;
 ELSE
  RETURN false;
 END IF;
 IF p_scope ? 'throughSequence' AND coalesce(p_scope->>'throughSequence','') !~ '^[0-9]{1,18}$' THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_snapshot'; END IF;
 upper_bound:=least(coalesce((p_scope->>'throughSequence')::bigint,snap),snap);
 SELECT max((v.delivery).sequence) INTO actual_upper
 FROM public.notification_center_visible_internal(p_organization,snap,occ) v
 WHERE (v.delivery).sequence>lower_bound AND (v.delivery).sequence<=upper_bound
  AND public.notification_center_in_center_internal(v.event,clock_timestamp())
  AND CASE WHEN occ IS NOT NULL THEN
   'occasion-kind:'||(v.event).occasion||':'||(v.event).kind=base
   ELSE 'event:'||(v.event).id=base END
  AND NOT coalesce((v.event).actor=auth.uid() AND (v.event).kind IN ('order_created','order_cancelled'),false);
 IF actual_upper IS NULL THEN RETURN false; END IF;
 SELECT coalesce(max(through_sequence),0) INTO last_read FROM public.notification_center_read_batches
 WHERE organization=p_organization AND recipient=auth.uid() AND group_key=base;
 lower_bound:=greatest(lower_bound,baseline,last_read);
 IF actual_upper<=lower_bound THEN RETURN true; END IF;
 INSERT INTO public.notification_center_read_batches(organization,recipient,group_key,after_sequence,through_sequence)
 VALUES(p_organization,auth.uid(),base,lower_bound,actual_upper) ON CONFLICT DO NOTHING;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.mark_notification_center_item_read(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.mark_notification_center_item_read(bigint,jsonb) TO authenticated;


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
  IF public.notification_center_allowed(e,u) AND (e.kind IN ('order_created','order_cancelled') OR u IS DISTINCT FROM p_actor OR
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
DECLARE payload jsonb:=e.data-'bankConnectionId'; account bigint; un bigint; impacts jsonb; customer text; actual_state text; contact jsonb; actual_context jsonb; actual_count bigint;
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
  SELECT jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'),o.state,public.notification_center_order_form_context_internal(o.form),
    (SELECT count(DISTINCT x.ticket) FROM eshop.order_product_ticket x WHERE x."order"=o.id)
   INTO contact,actual_state,actual_context,actual_count
   FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization
   WHERE o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion;
  payload:=payload||jsonb_build_object('contact',coalesce(contact,'{}'),'customerName',nullif(trim(concat_ws(' ',contact->>'name',contact->>'surname')),''),'state',coalesce(actual_state,e.data->>'state'));
  -- Legacy events have no captured form context/count; use the authorized live
  -- order only for absent fields. Captured historical facts always win.
  IF public.notification_center_order_activity_internal(e.kind) THEN
   payload:=payload||jsonb_build_object('formContext',coalesce(nullif(e.data->'formContext','null'::jsonb),actual_context),
    'count',coalesce(nullif(e.data->'count','null'::jsonb),CASE WHEN actual_count>0 THEN to_jsonb(actual_count) END));
  END IF;
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
 UPDATE public.notification_center_user_state SET seen_through_sequence=greatest(seen_through_sequence,s.last_delivery_sequence)
 WHERE organization=p_organization AND recipient=auth.uid();
 result:=public.get_notification_center_page(p_organization,p_current_occasion,p_limit,s.last_delivery_sequence,NULL);
 feed:=public.get_notification_center_feed(p_organization,p_current_occasion,s.last_delivery_sequence,NULL,p_limit);
 RETURN result||jsonb_build_object('readThrough',s.last_delivery_sequence,'previousReadThrough',greatest(s.read_through_sequence,s.seen_through_sequence),'feedSupported',true,
 'feedItems',feed->'items',
 'feedNextCursor',feed->'nextCursor','timelineSupported',true,'snapshotAt',clock_timestamp(),
 'oldestOrderAt',(SELECT min((event).occurred_at) FROM public.notification_center_visible_internal(p_organization,s.last_delivery_sequence,p_current_occasion)
 WHERE (event).occasion IS NOT NULL AND public.notification_center_order_activity_internal((event).kind)));
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


-- SOURCE: notification_center/center_policy.sql
-- New-order activity follows the current order state, including older panel snapshots.
-- Activity expires from the center, not from the order/email audit history.
CREATE OR REPLACE FUNCTION public.notification_center_in_center_internal(
 e public.notification_center_events,p_anchor timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN e.kind IN ('email_problem','bank_problem')
  THEN e.status NOT IN ('recovered','resolved')
  ELSE e.occurred_at>=p_anchor-interval '30 days'
   AND (e.kind<>'order_created' OR coalesce(
    (SELECT o.state FROM eshop.orders o
     WHERE o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$'
      THEN (e.data->>'orderId')::bigint END AND o.occasion=e.occasion),
    e.status,'')<>'storno') END;
$$;
REVOKE ALL ON FUNCTION public.notification_center_in_center_internal(public.notification_center_events,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_notification_center_badge(p_organization bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.notification_center_user_state; anchor timestamptz:=clock_timestamp();
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 SELECT * INTO s FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid();
 RETURN jsonb_build_object('feedSupported',true,'timelineSupported',true,'enabled',true,'lastSequence',coalesce(s.last_delivery_sequence,0),'readThrough',coalesce(s.read_through_sequence,0),
 'unread',EXISTS(SELECT 1 FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
 WHERE d.organization=p_organization AND d.recipient=auth.uid() AND d.sequence>greatest(coalesce(s.seen_through_sequence,0),coalesce(s.read_through_sequence,0))
 AND NOT (SELECT is_read FROM public.notification_center_batch_internal(e,d))
 AND public.notification_center_in_center_internal(e,anchor)
 AND public.notification_center_allowed(e,auth.uid()) AND public.notification_center_unmuted(e,auth.uid())));
END $$;

REVOKE ALL ON FUNCTION public.get_notification_center_badge(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_badge(bigint) TO authenticated;


-- SOURCE: notification_center/daily_overview.sql
-- Normalize opaque IDs sent by already-open clients during this migration.
-- This accepts an old identifier, never recreates a daily grouping.
CREATE OR REPLACE FUNCTION public.notification_center_rollup_id_internal(p_id text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path=public,extensions AS $$
 SELECT regexp_replace(p_id,'^order-day:([0-9]+):([a-z_]+):[0-9]{4}-[0-9]{2}-[0-9]{2}$','occasion-kind:\1:\2');
$$;
REVOKE ALL ON FUNCTION public.notification_center_rollup_id_internal(text) FROM PUBLIC,anon,authenticated,service_role;

-- One client RPC opens/acknowledges, pages or refreshes category rollups.
-- Keep the existing RPC signature for installed clients; there is one grouping path.
-- Counts, historical place totals, bounded contact previews and badge state are
-- computed together. Calendar dates use one validated IANA display timezone.
CREATE OR REPLACE FUNCTION public.get_notification_center_daily_overview(
 p_organization bigint,p_current_occasion bigint,p_snapshot bigint DEFAULT NULL,
 p_snapshot_at timestamptz DEFAULT NULL,p_timezone text DEFAULT 'UTC',p_cursor jsonb DEFAULT NULL,
 p_limit integer DEFAULT 30,p_ids text[] DEFAULT NULL,p_open boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE snap bigint; context text; cursor jsonb; items jsonb; tail jsonb; more boolean; truncated boolean;
 anchor timestamptz:=coalesce(p_snapshot_at,clock_timestamp()); previous_read bigint;
 choices jsonb; badge jsonb; lim integer:=greatest(1,least(p_limit,200));
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_timezone'; END IF;
 IF cardinality(p_ids)>10000 OR (p_ids IS NOT NULL AND p_cursor IS NOT NULL AND p_cursor<>'null'::jsonb)
  OR (p_open AND (p_ids IS NOT NULL OR (p_cursor IS NOT NULL AND p_cursor<>'null'::jsonb))) THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_update_limit'; END IF;
 IF p_ids IS NOT NULL THEN lim:=greatest(1,cardinality(p_ids)); END IF;
 IF p_open THEN
  INSERT INTO public.notification_center_user_state(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
  SELECT last_delivery_sequence,greatest(read_through_sequence,seen_through_sequence) INTO snap,previous_read
   FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE;
  anchor:=clock_timestamp();
 ELSE
  SELECT greatest(0,least(p_snapshot,last_delivery_sequence)) INTO snap
   FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid();
 END IF;
 snap:=coalesce(snap,0);
 context:=md5(jsonb_build_array('occasion-kind-overview',auth.uid(),p_organization,p_current_occasion,snap,extract(epoch FROM anchor),p_timezone)::text);
 cursor:=public.notification_center_time_cursor_internal(p_cursor,context);
 WITH visible AS MATERIALIZED (
  SELECT v.*,b.batch_id,b.is_read,b.after_sequence,b.through_sequence,(event).kind NOT IN ('email_problem','bank_problem') AND (event).occasion IS NOT NULL grouped
  FROM public.notification_center_visible_internal(p_organization,snap,p_current_occasion) v
  CROSS JOIN LATERAL public.notification_center_batch_internal(v.event,v.delivery) b
  WHERE public.notification_center_in_center_internal(v.event,anchor)),
 -- Resolve absent legacy facts in batches, never one client request per row.
 legacy_orders AS MATERIALIZED (
  SELECT DISTINCT o.id,o.form FROM visible v
  JOIN eshop.orders o ON o.id=CASE WHEN (v.event).data->>'orderId' ~ '^[0-9]{1,18}$'
   THEN ((v.event).data->>'orderId')::bigint END AND o.occasion=(v.event).occasion
  JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=p_organization
  WHERE v.grouped AND public.notification_center_order_activity_internal((v.event).kind) AND ((v.event).data->>'count' IS NULL
   OR (v.event).data->>'formContext' IS NULL)),
 legacy_counts AS MATERIALIZED (
  SELECT o.id,nullif(count(DISTINCT x.ticket),0) places FROM legacy_orders o
  LEFT JOIN eshop.order_product_ticket x ON x."order"=o.id GROUP BY o.id),
 legacy_forms AS MATERIALIZED (
  SELECT form,public.notification_center_order_form_context_internal(form) context
  FROM (SELECT DISTINCT form FROM legacy_orders) f),
 classified AS MATERIALIZED (
  SELECT v.*,((event).occurred_at AT TIME ZONE p_timezone)::date calendar_day,
   coalesce(CASE WHEN (event).data->>'count' ~ '^[0-9]{1,9}$'
    THEN nullif(greatest(((event).data->>'count')::bigint,0),0) END,c.places) captured_places,
   coalesce(nullif((event).data->'formContext','null'::jsonb),f.context) resolved_context
  FROM visible v LEFT JOIN legacy_orders o ON v.grouped AND o.id=
   CASE WHEN (v.event).data->>'orderId' ~ '^[0-9]{1,18}$' THEN ((v.event).data->>'orderId')::bigint END
  LEFT JOIN legacy_counts c ON c.id=o.id LEFT JOIN legacy_forms f ON f.form=o.form),
 ranked AS (
  SELECT *,row_number() OVER(bucket ORDER BY (event).occurred_at DESC,(event).id DESC) rank,
   count(*) OVER bucket n,count(captured_places) OVER bucket known_counts,sum(captured_places) OVER bucket total_places,
   bool_or(captured_places>1 OR resolved_context->'allowsMultiple'='true'::jsonb) OVER bucket has_multiple,
   max((delivery).sequence) OVER bucket latest FROM classified WHERE grouped
  WINDOW bucket AS(PARTITION BY batch_id)),
 combined AS (
  SELECT (event).id::text id,section,(event).occurred_at at,event,delivery,calendar_day,
   0::bigint activity_count,(delivery).sequence sequence,NULL::bigint place_count,false multiple_places,batch_id,is_read,after_sequence,through_sequence FROM classified WHERE NOT grouped
  UNION ALL
  SELECT batch_id,section,(event).occurred_at,event,delivery,
   calendar_day,n,latest,CASE WHEN has_multiple AND known_counts=n THEN total_places END,coalesce(has_multiple,false),batch_id,is_read,after_sequence,through_sequence FROM ranked WHERE rank=1),
 catalog AS MATERIALIZED (
  SELECT *,row_number() OVER(ORDER BY section,at DESC,id DESC) catalog_position FROM
   (SELECT * FROM combined ORDER BY section,at DESC,id DESC LIMIT 101) bounded),
 rows AS (
  SELECT *,row_number() OVER(ORDER BY section,at DESC,id DESC) position FROM catalog
  WHERE catalog_position<=100 AND (p_ids IS NULL OR EXISTS(SELECT 1 FROM unnest(p_ids) requested WHERE requested=id OR (requested ~ '^(occasion-kind:[0-9]+:[a-z_]+|order-day:)' AND requested !~ ':(pending|batch|self|legacy)(:|$)' AND public.notification_center_rollup_id_internal(requested)=regexp_replace(id,':(pending|batch):.*$|:(self|legacy)$','')))) AND (cursor IS NULL OR section>(cursor->>'section')::int
   OR (section=(cursor->>'section')::int AND (at,id)<((cursor->>'time')::timestamptz,cursor->>'id')))
  ORDER BY section,at DESC,id DESC LIMIT lim+1),
 page AS (SELECT *,public.notification_center_dto(event,delivery)||jsonb_build_object('isRead',is_read,'isSeen',is_read OR sequence<=greatest(coalesce((SELECT seen_through_sequence FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid()),0),coalesce(previous_read,0))) dto,
  coalesce((SELECT requested FROM unnest(p_ids) WITH ORDINALITY r(requested,position)
    WHERE requested=rows.id OR public.notification_center_rollup_id_internal(requested)=regexp_replace(rows.id,':(pending|batch):.*$|:(self|legacy)$','') ORDER BY r.position LIMIT 1),id) response_id
  FROM rows WHERE position<=lim)
 SELECT coalesce((SELECT jsonb_agg(CASE WHEN activity_count=0 THEN dto||jsonb_build_object('section',section,'day',calendar_day)
  WHEN NOT public.notification_center_order_activity_internal((event).kind) THEN
   dto||jsonb_build_object('id',response_id,'section',section,'day',calendar_day,'sequence',sequence,
     'data',(dto->'data')||jsonb_build_object('eventCount',activity_count))
  ELSE dto||jsonb_build_object('id',response_id,'section',section,'day',calendar_day,'sequence',sequence,'data',
   (CASE WHEN activity_count=1 THEN dto->'data' ELSE jsonb_build_object('contact',dto#>'{data,contact}') END)-'orderId'-'orderSymbol'
   ||jsonb_build_object('activityCount',activity_count,'relatedOrders',true,'allowsMultiple',multiple_places,'afterSequence',after_sequence,'throughSequence',sequence)
   ||jsonb_strip_nulls(jsonb_build_object('placeCount',place_count))
   ||jsonb_build_object('previewContacts',(SELECT jsonb_agg(
    public.notification_center_dto(r.event,r.delivery)#>'{data,contact}' ORDER BY r.rank)
    FROM ranked r WHERE r.batch_id=page.batch_id
     AND r.rank<=3))) END ORDER BY position) FROM page),'[]'),
  (SELECT jsonb_build_object('context',context,'section',section,'time',at,'id',id) FROM page ORDER BY position DESC LIMIT 1),
  (SELECT count(*)>lim FROM rows),(SELECT count(*)>100 FROM catalog) INTO items,tail,more,truncated;
 IF p_open THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',oc.id,'title',oc.title,'muted',coalesce(p.muted,false)) ORDER BY oc.title),'[]') INTO choices
  FROM public.occasions oc LEFT JOIN public.occasion_users ou ON ou.occasion=oc.id AND ou."user"=auth.uid()
  LEFT JOIN public.notification_center_preferences p ON p.organization=p_organization AND p.recipient=auth.uid() AND p.occasion=oc.id
  WHERE oc.organization=p_organization AND NOT public.is_demo_occasion(oc.id)
   AND (coalesce(ou.is_editor_order_view,false) OR public.notification_center_app_admin_internal(p_organization,oc.id,auth.uid()));
  -- A failed overview never acknowledges: data and watermark commit together.
  UPDATE public.notification_center_user_state SET seen_through_sequence=greatest(seen_through_sequence,snap)
  WHERE organization=p_organization AND recipient=auth.uid();
 END IF;
 badge:=public.get_notification_center_badge(p_organization);
 RETURN badge||jsonb_build_object('dailySupported',true,'truncated',truncated,'snapshot',snap,'snapshotAt',anchor,
  'snapshotDay',(anchor AT TIME ZONE p_timezone)::date,'timezone',p_timezone,
  'previousReadThrough',previous_read,'occasions',choices,'items',items,
  'nextCursor',CASE WHEN more AND p_ids IS NULL THEN to_jsonb(encode(convert_to(tail::text,'UTF8'),'base64')) END);
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_daily_overview(bigint,bigint,bigint,timestamptz,text,jsonb,integer,text[],boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_daily_overview(bigint,bigint,bigint,timestamptz,text,jsonb,integer,text[],boolean) TO authenticated;


-- SOURCE: notification_center/order_selection.sql
-- Resolve the frozen, authorized group only when the orders page is opened.
-- No target ID arrays are added to the notification feed or badge polling.
CREATE OR REPLACE FUNCTION public.notification_center_order_selection(
 p_occasion bigint,p_group jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE org bigint; snap bigint; zone text; anchor timestamptz; result jsonb; lower_bound bigint; upper_bound bigint; group_id text; selected_id text;
BEGIN
 IF NOT coalesce(public.can_read_orders(p_occasion),false) THEN
  RAISE insufficient_privilege USING MESSAGE='orders_read_denied'; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=p_occasion;
 IF org IS DISTINCT FROM (p_group->>'organization')::bigint THEN
  RAISE insufficient_privilege USING MESSAGE='notification_context_mismatch'; END IF;
 PERFORM public.notification_center_check_context(org,p_occasion);
 IF coalesce(p_group->>'snapshot','') !~ '^[0-9]{1,18}$' THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_snapshot'; END IF;
 anchor:=least(coalesce((p_group->>'snapshotAt')::timestamptz,clock_timestamp()),clock_timestamp());
 zone:=p_group->>'timezone';
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=zone) THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_timezone'; END IF;
 SELECT greatest(0,least((p_group->>'snapshot')::bigint,last_delivery_sequence)) INTO snap
 FROM public.notification_center_user_state WHERE organization=org AND recipient=auth.uid();
 group_id:=public.notification_center_rollup_id_internal(p_group->>'id');
 selected_id:=group_id;
 lower_bound:=coalesce((p_group->>'afterSequence')::bigint,substring(group_id from ':batch:([0-9]+)$')::bigint,0);
 upper_bound:=least(coalesce((p_group->>'throughSequence')::bigint,snap),snap);
 group_id:=regexp_replace(group_id,':(pending|batch):.*$|:(self|legacy)$','');
 IF lower_bound<0 OR upper_bound<lower_bound THEN RAISE invalid_parameter_value USING MESSAGE='notification_invalid_snapshot'; END IF;
 SELECT coalesce(jsonb_agg(DISTINCT ((v.event).data->>'orderId')::bigint),'[]'::jsonb) INTO result
 FROM public.notification_center_visible_internal(org,coalesce(snap,0),p_occasion) v
 WHERE (v.event).occasion=p_occasion
  AND public.notification_center_in_center_internal(v.event,anchor)
  AND public.notification_center_order_activity_internal((v.event).kind)
  AND 'occasion-kind:'||p_occasion||':'||(v.event).kind=
    group_id
  AND (v.delivery).sequence>lower_bound AND (v.delivery).sequence<=upper_bound
  AND CASE WHEN selected_id ~ ':self$' THEN coalesce((v.event).actor=auth.uid(),false)
   WHEN selected_id<>group_id AND (v.event).kind IN ('order_created','order_cancelled')
    THEN (v.event).actor IS DISTINCT FROM auth.uid() ELSE true END
  AND (v.event).data->>'orderId' ~ '^[0-9]{1,18}$';
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_order_selection(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.notification_center_order_selection(bigint,jsonb) TO authenticated;


-- SOURCE: eshop_orders/get_orders_tab_data.sql
DROP FUNCTION IF EXISTS public.get_orders_tab_data(text);
CREATE OR REPLACE FUNCTION public.get_orders_tab_data(
    p_occasion_link TEXT,
    p_notification_group JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_orders_data JSONB;
    v_forms_data JSONB;
    v_notification_ids JSONB := '[]'::jsonb;
BEGIN

    SELECT get_orders(p_occasion_link, NULL, '{}'::jsonb) INTO v_orders_data;

    IF (v_orders_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_orders failed: %', v_orders_data->>'message';
    END IF;

    SELECT get_all_forms_with_fields(p_occasion_link) INTO v_forms_data;

    IF (v_forms_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_all_forms_with_fields failed: %', v_forms_data->>'message';
    END IF;

    v_orders_data:=jsonb_set(v_orders_data,'{data,orders}',coalesce((SELECT jsonb_agg(o) FROM jsonb_array_elements(v_orders_data#>'{data,orders}') o WHERE o->>'state' IS DISTINCT FROM 'stock'),'[]'));
    IF p_notification_group IS NOT NULL THEN
      SELECT public.notification_center_order_selection(
        (v_orders_data->>'occasion_id')::bigint,p_notification_group) INTO v_notification_ids;
      -- Keep only records in the independently authorized orders response.
      SELECT coalesce(jsonb_agg(o->'id'),'[]'::jsonb) INTO v_notification_ids
      FROM jsonb_array_elements(v_orders_data#>'{data,orders}') o
      WHERE (o->>'id')::bigint IN (SELECT value::bigint FROM jsonb_array_elements_text(v_notification_ids));
    END IF;
    IF p_notification_group->>'markRead'='true' THEN
      PERFORM public.mark_notification_center_item_read(
        (p_notification_group->>'organization')::bigint,p_notification_group);
    END IF;
    -- No orders means no delivery status. Do not resolve an ambiguous event slug.
    RETURN (v_orders_data->'data') || jsonb_build_object('notification_order_ids',v_notification_ids,'forms', v_forms_data->'data', 'email_delivery',
      CASE WHEN jsonb_array_length(v_orders_data#>'{data,orders}') = 0
        THEN '{}'::jsonb
        ELSE public.get_order_email_summaries(
          (v_orders_data->>'occasion_id')::bigint,
          ARRAY(SELECT (ord->>'id')::bigint
            FROM jsonb_array_elements(v_orders_data#>'{data,orders}') ord))
      END);
END;
$$;

REVOKE ALL ON FUNCTION public.get_orders_tab_data(text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_orders_tab_data(text,jsonb) TO anon,authenticated,service_role;

COMMIT;
