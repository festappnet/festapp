-- Generated forward migration: hidden-member-personal-surfaces-2026-11-01
-- Prerequisites: 20261021100000_canonical_authorization.sql, 20261024010000_organization_notification_center.sql, 20261024025000_notification_email_recipient.sql, 20261024120000_order_email_recovery.sql, 20261024220000_cancelled_order_email_alerts.sql, 20261024235000_notification_center_canonical_availability.sql, 20261026120000_notification_center_feed.sql, 20261026150000_notification_center_order_periods.sql, 20261026230000_notification_center_unread_snapshot.sql, 20261027210000_notification_center_overview.sql, 20261027220000_notification_center_daily_overview.sql, 20261027234500_notification_group_order_selection.sql, 20261028010000_notification_legacy_place_totals.sql, 20261028013000_notification_category_rollups.sql, 20261028020000_notification_center_lifecycle.sql, 20261028030000_notification_new_orders_exclude_cancelled.sql, 20261028120000_notification_center_current_rollups.sql, 20261028130000_notification_personal_read_batches.sql, 20261030093000_notification_deleted_entities.sql, 20261031110000_notification_current_participants.sql, 20261031120000_notification_center_source_alignment.sql, 20261101170000_hidden_participant_notifications.sql
BEGIN;
DO $$ BEGIN IF to_regclass('public.notification_center_organizations') IS NULL OR to_regclass('public.notification_center_activation') IS NOT NULL OR to_regclass('public.notification_center_source_state') IS NULL OR to_regprocedure('public.get_notification_center_updates(bigint,bigint,uuid[])') IS NULL THEN RAISE EXCEPTION 'notification_feed_prerequisites_missing'; END IF; END $$;

-- SOURCE: users/member_visibility.sql
-- Visibility is independent of roles. Callers still own operation authorization.
CREATE OR REPLACE FUNCTION public.organization_member_visible_internal(p_organization bigint,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_organization IS NOT NULL AND p_user IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM public.organization_users m
  WHERE m.organization=p_organization AND m."user"=p_user AND m.is_hidden);
$$;
CREATE OR REPLACE FUNCTION public.occasion_member_visible_internal(p_occasion bigint,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.organization_member_visible_internal(o.organization,p_user)
  FROM public.occasions o WHERE o.id=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.organization_member_visible_internal(bigint,uuid),public.occasion_member_visible_internal(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/subject_visibility.sql
-- Only the person described by an event is a personal subject. An operator is
-- not the customer, and their hidden status must not suppress real business facts.
CREATE OR REPLACE FUNCTION public.notification_center_subject_visible_internal(p_org bigint,p_kind text,p_data jsonb)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT NOT EXISTS(
  SELECT 1 FROM public.organization_users hidden
  JOIN public.user_info u ON u.id=hidden."user" AND u.organization=hidden.organization
  WHERE hidden.organization=p_org AND hidden.is_hidden AND (
   p_data->>'userId'=hidden."user"::text
   OR (p_kind='email_problem' AND EXISTS(
    SELECT 1 FROM public.email_messages m WHERE m.message_id=CASE WHEN p_data->>'messageId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (p_data->>'messageId')::uuid END
    AND m.organization=p_org AND (m.recipient_user=hidden."user"
     OR (nullif(btrim(u.email_readonly),'') IS NOT NULL AND lower(btrim(m.recipient))=lower(btrim(u.email_readonly)))
     OR EXISTS(SELECT 1 FROM eshop.orders email_order JOIN public.occasions email_oc ON email_oc.id=email_order.occasion
      WHERE email_order.id=m.order_id AND email_oc.organization=p_org
      AND nullif(btrim(u.email_readonly),'') IS NOT NULL
      AND lower(btrim(email_order.data->>'email'))=lower(btrim(u.email_readonly))))))
   OR (p_data ? 'orderId' AND EXISTS(
    SELECT 1 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
    WHERE o.id=CASE WHEN p_data->>'orderId' ~ '^[0-9]{1,18}$' THEN (p_data->>'orderId')::bigint END AND oc.organization=p_org
    AND nullif(btrim(u.email_readonly),'') IS NOT NULL
    AND lower(btrim(o.data->>'email'))=lower(btrim(u.email_readonly))))));
$$;
REVOKE ALL ON FUNCTION public.notification_center_subject_visible_internal(bigint,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;


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
-- Participant joins remain relevant only while that person belongs to the occasion.
-- Activity expires from the center, not from the order/email audit history.
CREATE OR REPLACE FUNCTION public.notification_center_in_center_internal(
 e public.notification_center_events,p_anchor timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.notification_center_subject_visible_internal(e.organization,e.kind,e.data) AND CASE WHEN e.kind IN ('email_problem','bank_problem')
  THEN e.status NOT IN ('recovered','resolved')
  ELSE e.occurred_at>=p_anchor-interval '30 days'
   AND (e.kind<>'order_created' OR coalesce(
    (SELECT o.state FROM eshop.orders o
     WHERE o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$'
      THEN (e.data->>'orderId')::bigint END AND o.occasion=e.occasion),
    e.status,'')<>'storno')
   AND (e.kind<>'occasion_joined' OR EXISTS(
    SELECT 1 FROM public.occasion_users m
    JOIN public.user_info u ON u.id=m."user" AND u.organization=e.organization
    WHERE m.occasion=e.occasion AND m."user"::text=e.data->>'userId'
     AND NOT EXISTS(SELECT 1 FROM public.organization_users hidden
      WHERE hidden.organization=e.organization AND hidden."user"=m."user" AND hidden.is_hidden))) END;
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


-- SOURCE: events/get_event_participants_for_edit.sql
CREATE OR REPLACE FUNCTION public.get_event_participants_for_edit(
  p_event bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
  v_occasion bigint;
  v_participants jsonb;
BEGIN
  SELECT e.occasion
  INTO v_occasion
  FROM public.events e
  WHERE e.id = p_event;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('code', 404, 'message', 'Event not found');
  END IF;

  IF NOT public.can_read_schedule_participants(v_occasion) THEN
    RETURN jsonb_build_object('code', 403, 'message', 'Insufficient permissions');
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', ui.id,
        'name', ui.name,
        'surname', ui.surname,
        'companion_parent', (SELECT uc."user" FROM public.user_companions uc WHERE uc.occasion=v_occasion AND uc.companion=ui.id
          AND public.occasion_member_visible_internal(v_occasion,uc."user")
          AND EXISTS(SELECT 1 FROM public.event_users parent WHERE parent.event=p_event AND parent."user"=uc."user") LIMIT 1)
      )
      ORDER BY ui.surname, ui.name, ui.id
    ),
    '[]'::jsonb
  )
  INTO v_participants
  FROM public.event_users eu
  JOIN public.user_info ui ON ui.id = eu."user"
  WHERE eu.event = p_event AND public.occasion_member_visible_internal(v_occasion,ui.id);

  RETURN jsonb_build_object('code', 200, 'data', v_participants);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_event_participants_for_edit(bigint)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_event_participants_for_edit(bigint)
  FROM anon;
GRANT EXECUTE ON FUNCTION public.get_event_participants_for_edit(bigint)
  TO authenticated, service_role;


-- SOURCE: users/get_all_user_group_info.sql
CREATE OR REPLACE FUNCTION public.get_all_user_groups(p_occasion_id bigint, p_type text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
    groups_json jsonb;
    game_defs_json jsonb;
    places_json jsonb;
    result_data jsonb;
BEGIN
    -- Authorization Check: User must have editor view permissions for the occasion.
    IF NOT get_is_editor_view_on_occasion(p_occasion_id) THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;

    SELECT COALESCE(
        jsonb_agg(to_jsonb(p) ORDER BY p."order" NULLS LAST, p.title),
        '[]'::jsonb
    )
    INTO places_json
    FROM public.places p
    WHERE p.occasion = p_occasion_id
      AND NOT p.is_hidden
      AND p.coordinates->'latLng'->>'lat' IS NOT NULL
      AND p.coordinates->'latLng'->>'lng' IS NOT NULL;

    -- If authorized, fetch all matching groups for the occasion.
    SELECT
        COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', ugi.id,
                'title', ugi.title,
                'description', ugi.description,
                'type', ugi.type,
                'data', ugi.data,
                'place', ugi.place,
                'places', ( -- Nested place object
                    SELECT row_to_json(p)::jsonb
                    FROM public.places p
                    WHERE p.id = ugi.place
                ),
                'user_groups', ( -- Nested array of participants with admin status
                    SELECT COALESCE(jsonb_agg(
                        jsonb_build_object(
                            'is_admin', ug.is_admin,
                            -- The user_info object now only contains id, name, and surname.
                            'user_info', jsonb_build_object(
                                'id', p_ui.id,
                                'name', p_ui.name,
                                'surname', p_ui.surname
                            )
                        )
                    ), '[]'::jsonb)
                    FROM public.user_groups ug
                    JOIN public.user_info p_ui ON ug."user" = p_ui.id
                    WHERE ug."group" = ugi.id AND public.occasion_member_visible_internal(ugi.occasion,p_ui.id)
                )
            )
        ), '[]'::jsonb)
    INTO groups_json
    FROM public.user_group_info ugi
    WHERE ugi.occasion = p_occasion_id
      AND (p_type IS NULL AND ugi.type IS NULL OR ugi.type = p_type);

    -- If the requested type is 'game', also fetch the game definitions (checkpoints).
    IF p_type = 'game' THEN
        SELECT jsonb_object_agg(info.id, info.title)
        INTO game_defs_json
        FROM public.information info
        WHERE info.type = 'game' AND info.occasion = p_occasion_id;
    END IF;

    -- Combine the results into a single data object.
    result_data := jsonb_build_object(
        'groups', groups_json,
        'game_definitions', game_defs_json,
        'places', places_json
    );

    -- Return the data directly on success.
    RETURN result_data;
END;
$$;


-- SOURCE: groups/group_member_read.sql
CREATE OR REPLACE FUNCTION public.get_user_group_info_with_users(p_group_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE
    v_occasion_id bigint;
    v_current_user_is_admin boolean;
    result_json jsonb;
BEGIN
    -- Check if the group exists and get its occasion for permission checks.
    SELECT occasion INTO v_occasion_id FROM public.user_group_info WHERE id = p_group_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'USER_GROUP_NOT_FOUND';
    END IF;

    -- Authorization Check: User must be a member or have editor view permissions on the occasion.
    IF NOT public.can_read_group_members(p_group_id) THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;

    -- Get the current user's admin status for this specific group.
    SELECT is_admin INTO v_current_user_is_admin FROM public.user_groups WHERE "group" = p_group_id AND "user" = auth.uid();

    -- If authorized, build the final JSON object.
    SELECT
        jsonb_build_object(
            'id', ugi.id,
            'title', ugi.title,
            'description', ugi.description,
            'type', ugi.type,
            'data', ugi.data,
            'place', ugi.place, -- This is placeId
            'is_admin', COALESCE(v_current_user_is_admin, false),
            'places', (SELECT row_to_json(p)::jsonb||jsonb_build_object('aggregate_version',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='place' AND scope_type='occasion' AND scope_id=v_occasion_id AND aggregate_id=p.id::text),0)) FROM public.places p WHERE p.id = ugi.place),
            'user_groups', (
                SELECT COALESCE(jsonb_agg(
                    jsonb_build_object(
                        'is_admin', ug.is_admin,
                        'user_info', jsonb_build_object('id',p_ui.id,'name',p_ui.name,'surname',p_ui.surname)
                    )
                ), '[]'::jsonb)
                FROM public.user_groups ug
                JOIN public.user_info p_ui ON ug."user" = p_ui.id
                WHERE ug."group" = ugi.id AND public.occasion_member_visible_internal(ugi.occasion,p_ui.id)
            )
        )
    INTO result_json
    FROM public.user_group_info ugi
    WHERE ugi.id = p_group_id;

    RETURN result_json;
END;
$function$
;


-- SOURCE: groups/group_editor_read.sql
CREATE OR REPLACE FUNCTION public.get_user_group_command_data_v1(p_group bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
  SELECT jsonb_build_object('id',g.id,'title',g.title,
    'description',g.description,'type',g.type,'data',g.data,'place',g.place,
    'is_admin',COALESCE((SELECT is_admin FROM public.user_groups WHERE "group"=g.id AND "user"=auth.uid()),false),
    'aggregate_version',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='user_group' AND scope_type='occasion' AND scope_id=g.occasion AND aggregate_id=g.id::text),0),
    'placeData',(SELECT to_jsonb(p)||jsonb_build_object('aggregate_version',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='place' AND scope_type='occasion' AND scope_id=g.occasion AND aggregate_id=p.id::text),0)) FROM public.places p WHERE p.id=g.place),
    'participants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'userId',ug."user",'isAdmin',ug.is_admin,'is_admin',ug.is_admin,
      'user_info',jsonb_build_object('id',ui.id,'name',ui.name,'surname',ui.surname))
      ORDER BY ug."user") FROM public.user_groups ug JOIN public.user_info ui
      ON ui.id=ug."user" WHERE ug."group"=g.id AND public.occasion_member_visible_internal(g.occasion,ui.id)),'[]'::jsonb))
  FROM public.user_group_info g WHERE g.id=p_group;
$function$
;
REVOKE ALL ON FUNCTION public.get_user_group_command_data_v1(bigint) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.get_user_group_editor_bundle_v1(p_occasion bigint,p_group_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_read_group_editor(p_occasion,p_group_id) THEN
 RAISE insufficient_privilege USING MESSAGE='group editor required'; END IF;
 RETURN (SELECT public.get_user_group_command_data_v1(id) FROM public.user_group_info WHERE id=p_group_id AND occasion=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.get_user_group_editor_bundle_v1(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_user_group_editor_bundle_v1(bigint,bigint) TO authenticated;


-- SOURCE: groups/group_profile_read.sql
CREATE OR REPLACE FUNCTION public.get_private_profile_payload_v1(p_occasion bigint, p_user uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'user',(SELECT jsonb_build_object('id',u.id,'email',u.email_readonly,
      'name',u.name,'surname',u.surname,'sex',u.sex,'phone',u.phone,
      'birthDate',u.birth_date,'data',u.data) FROM public.user_info u
      WHERE u.id=p_user),
    'occasion',(SELECT jsonb_build_object('role',ou.role,'services',ou.services,
      'data',ou.data,'isEditor',ou.is_editor,
      'isEditorView',ou.is_editor_view,
      'isEditorOrder',ou.is_editor_order,
      'isEditorOrderView',ou.is_editor_order_view,
      'isApproved',ou.is_approved,'isApprover',ou.is_approver,
      'isManager',ou.is_manager,
      'isCleaningBlocked',ou.is_cleaning_blocked,
      'isCleaningCrew',ou.is_cleaning_crew,
      'isReceptionist',ou.is_receptionist) FROM public.occasion_users ou
      WHERE ou.occasion=p_occasion AND ou."user"=p_user),
    'companions',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',ui.id,'name',ui.name,'surname',COALESCE(ui.surname,''),
      'group_title',COALESCE(groups.titles,''),'origin',uc.origin,
      'can_owner_delete',uc.origin='self_created',
      'services',COALESCE(companion_membership.services,'{}'::jsonb),
      'event_ids',COALESCE((SELECT jsonb_agg(eu.event ORDER BY eu.event)
        FROM public.event_users eu JOIN public.events e ON e.id=eu.event
        WHERE eu."user"=ui.id AND e.occasion=p_occasion),'[]'::jsonb))
      ORDER BY ui.name,ui.surname,ui.id)
      FROM public.user_companions uc
      JOIN public.user_info ui ON ui.id=uc.companion
      JOIN public.occasion_users companion_membership
        ON companion_membership.occasion=uc.occasion
       AND companion_membership."user"=uc.companion
      LEFT JOIN LATERAL (SELECT string_agg(ugi.title,', ' ORDER BY ugi.title) titles
        FROM public.user_groups ug JOIN public.user_group_info ugi ON ugi.id=ug."group"
        WHERE ug."user"=uc.companion AND ugi.occasion=p_occasion
          AND ugi.type IS NULL) groups ON true
      WHERE uc.occasion=p_occasion AND uc."user"=p_user AND public.occasion_member_visible_internal(p_occasion,ui.id)),'[]'::jsonb),
    'groups',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',g.id,'title',g.title,'description',g.description,'type',g.type,
      'data',g.data,'place',g.place,'isAdmin',mine.is_admin,
      'participants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'userId',members."user",'isAdmin',members.is_admin,
        'name',ui.name,'surname',ui.surname) ORDER BY members."user")
        FROM public.user_groups members JOIN public.user_info ui
          ON ui.id=members."user" WHERE members."group"=g.id AND public.occasion_member_visible_internal(g.occasion,ui.id)),'[]'::jsonb),
      'placeData',(SELECT to_jsonb(p)||jsonb_build_object('aggregate_version',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='place' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p.id::text),0)) FROM public.places p WHERE p.id=g.place))
      ORDER BY g.id) FROM public.user_groups mine JOIN public.user_group_info g
        ON g.id=mine."group" WHERE mine."user"=p_user
        AND g.occasion=p_occasion),'[]'::jsonb));
$function$
;


-- SOURCE: groups/save_user_group_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.save_user_group_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_group jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_id bigint; v_version bigint; v_begin jsonb;
  v_hash text; v_current jsonb; v_requested jsonb; v_entity jsonb;
  v_participants jsonb; v_current_participants jsonb;
  v_old_users uuid[]; v_new_users uuid[];
  v_old_place bigint; v_old_private boolean:=false; v_place_id bigint;
  v_private_place jsonb; v_place_version bigint; v_private_impacts jsonb;
  v_current_place jsonb; v_requested_place jsonb; v_place_changed boolean:=false;
  v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  PERFORM public.lock_people_scope_internal_v1(p_occasion);
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
  v_id:=(p_group->>'id')::bigint;
  IF v_actor IS NULL OR NOT public.can_write_group(p_occasion,v_id) THEN
    RAISE insufficient_privilege USING MESSAGE='group editor required';
  END IF;
  IF p_group IS NULL OR jsonb_typeof(p_group)<>'object'
    OR octet_length(p_group::text)>524288
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_group) key WHERE key NOT IN
      ('id','title','description','type','placeId','privatePlace','participants'))
    OR NOT (p_group ?& ARRAY['title','participants'])
    OR jsonb_typeof(p_group->'participants')<>'array'
    OR jsonb_array_length(p_group->'participants')>5000
    OR length(btrim(COALESCE(p_group->>'title',''))) NOT BETWEEN 1 AND 500
    OR octet_length(COALESCE(p_group->>'description',''))>262144 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid group aggregate';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId',x.user_id,
    'isAdmin',COALESCE(x.is_admin,false)) ORDER BY x.user_id),'[]'::jsonb),
    COALESCE(array_agg(x.user_id ORDER BY x.user_id),'{}'::uuid[])
    INTO v_participants,v_new_users
  FROM jsonb_to_recordset(p_group->'participants') x(user_id uuid,is_admin boolean);
  IF jsonb_array_length(p_group->'participants')<>cardinality(v_new_users)
    OR cardinality(v_new_users)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_new_users)))
    OR EXISTS (SELECT 1 FROM unnest(v_new_users) id LEFT JOIN public.occasion_users ou
      ON ou."user"=id AND ou.occasion=p_occasion WHERE ou."user" IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid group participants';
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_group->'participants') x WHERE jsonb_typeof(x)<>'object' OR x->>'user_id' IS NULL OR EXISTS(SELECT 1 FROM jsonb_object_keys(x) k WHERE k NOT IN ('user_id','is_admin')))
    OR (p_group->>'placeId' IS NOT NULL AND p_group->'privatePlace' IS NOT NULL AND p_group->'privatePlace'<>'null'::jsonb) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid group participants or place choice'; END IF;
  v_private_place:=p_group->'privatePlace';
  IF v_private_place IS NOT NULL AND v_private_place<>'null'::jsonb AND (
    jsonb_typeof(v_private_place)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_private_place) key WHERE key NOT IN
      ('id','title','description','coordinates','order','icon'))
    OR length(btrim(COALESCE(v_private_place->>'title',''))) NOT BETWEEN 1 AND 500
    OR jsonb_typeof(v_private_place->'coordinates')<>'object'
    OR octet_length(v_private_place::text)>131072) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid private group place';
  END IF;
  IF v_private_place IS NOT NULL AND v_private_place<>'null'::jsonb THEN
    IF jsonb_typeof(v_private_place#>'{coordinates,latLng,lat}') IS DISTINCT FROM 'number'
      OR jsonb_typeof(v_private_place#>'{coordinates,latLng,lng}') IS DISTINCT FROM 'number'
      OR (v_private_place#>>'{coordinates,latLng,lat}')::double precision NOT BETWEEN -90 AND 90
      OR (v_private_place#>>'{coordinates,latLng,lng}')::double precision NOT BETWEEN -180 AND 180
      OR (v_private_place->>'icon' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.icons i JOIN public.occasions o ON o.id=p_occasion AND i.organization=o.organization WHERE i.id=(v_private_place->>'icon')::bigint AND (i.unit=o.unit OR i.unit IS NULL))) THEN
      RAISE invalid_parameter_value USING MESSAGE='invalid private coordinates or icon'; END IF;
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'group',p_group)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.group.save',
    p_occasion,v_actor,v_hash);
  PERFORM public.lock_group_occasion_internal_v1(p_occasion);
  IF v_actor IS NULL OR NOT public.can_write_group(p_occasion,v_id) THEN
    RAISE insufficient_privilege USING MESSAGE='group editor required';
  END IF;
  IF EXISTS(SELECT 1 FROM unnest(v_new_users) id LEFT JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=id WHERE ou."user" IS NULL) THEN RAISE invalid_parameter_value USING MESSAGE='invalid group participants after lock'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_id IS NOT NULL THEN
    PERFORM 1 FROM public.user_group_info g WHERE g.id=v_id
      AND g.occasion=p_occasion FOR UPDATE;
    IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',404,jsonb_build_object('version',0,'group',NULL)); END IF;
    SELECT g.place,COALESCE(p.is_hidden AND p.type='group',false),
      public.get_user_group_command_data_v1(g.id)
      INTO v_old_place,v_old_private,v_current
    FROM public.user_group_info g LEFT JOIN public.places p ON p.id=g.place
    WHERE g.id=v_id;
    SELECT COALESCE(array_agg(ug."user" ORDER BY ug."user"),'{}'::uuid[]),
      COALESCE(jsonb_agg(jsonb_build_object('userId',ug."user",
        'isAdmin',ug.is_admin) ORDER BY ug."user") FILTER(WHERE public.occasion_member_visible_internal(p_occasion,ug."user")),'[]'::jsonb)
      INTO v_old_users,v_current_participants FROM public.user_groups ug
      WHERE ug."group"=v_id;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('user_group','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='user_group' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('version',v_version,'group',v_current)); END IF;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new group must not have expected version';
  END IF;
  IF v_private_place IS NOT NULL AND v_private_place<>'null'::jsonb THEN
    v_place_id:=(v_private_place->>'id')::bigint;
    IF v_place_id IS NULL THEN
      INSERT INTO public.places(title,description,type,coordinates,is_hidden,"order",icon,occasion)
      VALUES (v_private_place->>'title',v_private_place->>'description','group',
        v_private_place->'coordinates',true,(v_private_place->>'order')::bigint,
        (v_private_place->>'icon')::bigint,p_occasion) RETURNING id INTO v_place_id;
      v_place_version:=1;
      v_place_changed:=true;
      INSERT INTO public.client_aggregate_versions
        (aggregate_type,scope_type,scope_id,aggregate_id,version)
      VALUES ('place','occasion',p_occasion,v_place_id::text,v_place_version);
    ELSE
      PERFORM 1 FROM public.places p WHERE p.id=v_place_id AND p.occasion=p_occasion
        AND p.type='group' AND p.is_hidden FOR UPDATE;
      IF NOT FOUND OR v_id IS NULL OR NOT v_old_private
        OR v_place_id IS DISTINCT FROM v_old_place THEN
        RAISE invalid_parameter_value USING MESSAGE='private place is not owned by group';
      END IF;
      PERFORM public.assert_group_place_owner_internal_v1(p_occasion,v_id,v_place_id,false);
      INSERT INTO public.client_aggregate_versions
        (aggregate_type,scope_type,scope_id,aggregate_id,version)
      VALUES ('place','occasion',p_occasion,v_place_id::text,0) ON CONFLICT DO NOTHING;
      SELECT jsonb_build_object('id',p.id,'title',p.title,
        'description',p.description,'coordinates',p.coordinates,
        'order',p."order",'icon',p.icon) INTO v_current_place
      FROM public.places p WHERE p.id=v_place_id;
      v_requested_place:=jsonb_build_object('id',v_place_id,
        'title',v_private_place->>'title','description',v_private_place->>'description',
        'coordinates',v_private_place->'coordinates',
        'order',(v_private_place->>'order')::bigint,
        'icon',(v_private_place->>'icon')::bigint);
      v_place_changed:=v_current_place IS DISTINCT FROM v_requested_place;
      IF v_place_changed THEN
        UPDATE public.places SET title=v_private_place->>'title',
          description=v_private_place->>'description',coordinates=v_private_place->'coordinates',
          "order"=(v_private_place->>'order')::bigint,icon=(v_private_place->>'icon')::bigint
          WHERE id=v_place_id;
        UPDATE public.client_aggregate_versions SET version=version+1,
          updated_at=clock_timestamp() WHERE aggregate_type='place'
          AND scope_type='occasion' AND scope_id=p_occasion
          AND aggregate_id=v_place_id::text RETURNING version INTO v_place_version;
      ELSE
        SELECT version INTO v_place_version FROM public.client_aggregate_versions
        WHERE aggregate_type='place' AND scope_type='occasion'
          AND scope_id=p_occasion AND aggregate_id=v_place_id::text;
      END IF;
    END IF;
  ELSE
    v_place_id:=(p_group->>'placeId')::bigint;
    IF v_place_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.places p
      WHERE p.id=v_place_id AND p.occasion=p_occasion
        AND (NOT p.is_hidden OR (p.id=v_old_place AND p.type='group' AND v_old_private))) THEN
      RAISE invalid_parameter_value USING MESSAGE='invalid shared group place';
    END IF;
  END IF;
  v_requested:=jsonb_build_object('id',v_id,'title',p_group->>'title',
    'description',p_group->>'description','type',p_group->>'type',
    'place',v_place_id,'participants',v_participants);
  IF v_current IS NOT NULL AND jsonb_build_object('id',v_id,
      'title',v_current->>'title','description',v_current->>'description',
      'type',v_current->>'type','place',(v_current->>'place')::bigint,
      'participants',v_current_participants)=v_requested
      AND NOT v_place_changed THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('version',v_version,'group',v_current));
  END IF;
  IF v_old_private AND v_old_place IS DISTINCT FROM v_place_id THEN
    PERFORM public.assert_group_place_owner_internal_v1(p_occasion,v_id,v_old_place,true);
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO public.user_group_info(title,description,type,place,occasion)
    VALUES (p_group->>'title',p_group->>'description',p_group->>'type',v_place_id,p_occasion)
    RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('user_group','occasion',p_occasion,v_id::text,v_version);
  ELSE
    UPDATE public.user_group_info SET title=p_group->>'title',
      description=p_group->>'description',type=p_group->>'type',place=v_place_id
      WHERE id=v_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='user_group'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  END IF;
  -- Hidden memberships are absent from editor payloads, not removed by saving them.
  PERFORM public.write_user_group_members_internal_v1(p_occasion,v_id,(p_group->'participants')||coalesce((
    SELECT jsonb_agg(jsonb_build_object('user_id',ug."user",'is_admin',ug.is_admin))
    FROM public.user_groups ug WHERE ug."group"=v_id
      AND NOT public.occasion_member_visible_internal(p_occasion,ug."user")
      AND NOT ug."user"=ANY(v_new_users)), '[]'::jsonb),true);
  IF v_old_private AND v_old_place IS DISTINCT FROM v_place_id THEN
    IF EXISTS (SELECT 1 FROM public.user_group_info g WHERE g.id<>v_id
      AND g.place=v_old_place) THEN
      RAISE foreign_key_violation USING MESSAGE='private group place has another owner';
    END IF;
    DELETE FROM public.places WHERE id=v_old_place;
    DELETE FROM public.client_aggregate_versions WHERE aggregate_type='place'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_old_place::text;
  END IF;
  v_private_impacts:=public.group_profile_impacts_internal_v1(p_occasion,COALESCE(v_old_users,'{}'::uuid[])||v_new_users);
  v_entity:=public.get_user_group_command_data_v1(v_id)||
    jsonb_build_object('aggregate_version',v_version);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_private_impacts) x WHERE x->>'userId'=v_actor::text) THEN
    v_actor_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.group.save','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_group->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    '{}',v_private_impacts,'[]',jsonb_build_object('version',v_version,'group',v_entity),
    '{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.save_user_group_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_user_group_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated;


-- SOURCE: users/get_user_info_for_users.sql
CREATE OR REPLACE FUNCTION public.get_user_info_for_users(user_ids uuid[], oc bigint)
RETURNS jsonb
SECURITY definer
SET search_path = public, extensions
AS $$
DECLARE
  companions jsonb;
BEGIN
  -- Check if the user is a manager, editor, or approver for the occasion
  IF (SELECT public.can_read_participant_contacts(oc)) <> TRUE THEN
      RETURN jsonb_build_object('code', 403);
  END IF;

  -- Aggregate the user information as JSON
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', ui.id,
      'created_at', ui.created_at,
      'updated_at', ui.updated_at,
      'email_readonly', ui.email_readonly,
      'name', ui.name,
      'surname', ui.surname,
      'sex', ui.sex,
      'phone', ui.phone,
      'data', ui.data,
      'birth_date', ui.birth_date,
      'companion_parent', (
        SELECT jsonb_build_object(
          'id', parent_ui.id,
          'created_at', parent_ui.created_at,
          'updated_at', parent_ui.updated_at,
          'email_readonly', parent_ui.email_readonly,
          'name', parent_ui.name,
          'surname', parent_ui.surname,
          'sex', parent_ui.sex,
          'phone', parent_ui.phone,
          'data', parent_ui.data,
          'birth_date', parent_ui.birth_date
        )
        FROM public.user_info parent_ui
        WHERE parent_ui.id = uc."user" AND public.occasion_member_visible_internal(oc,parent_ui.id)
      )
    )
  ) INTO companions
  FROM public.user_info ui
  LEFT JOIN public.user_companions uc ON ui.id = uc.companion AND uc.occasion=oc
  WHERE ui.id = ANY(user_ids) AND public.occasion_member_visible_internal(oc,ui.id);

  -- If no companions are found, return an empty array
  IF companions IS NULL THEN
    companions := '[]'::jsonb;
  END IF;

  RETURN jsonb_build_object(
    'code', 200,
    'data', companions
  );
END;
$$ LANGUAGE plpgsql;


-- SOURCE: users/get_last_sign_in_at_for_users.sql
CREATE OR REPLACE FUNCTION get_last_sign_in_at_for_users(user_ids uuid[], oc bigint)
RETURNS jsonb
SECURITY definer
SET search_path = public, extensions
AS $$
BEGIN
  -- Check if the user is a manager for the occasion
  IF (SELECT get_is_manager_on_occasion(oc)) <> TRUE THEN
    RETURN jsonb_build_object('code', 403);
  END IF;

  -- Aggregate the last sign-in data as JSON
  RETURN jsonb_build_object(
    'code', 200,
    'data', (
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', au.id,
        'last_sign_in_at', au.last_sign_in_at
      ))
      FROM auth.users au
      JOIN public.occasion_users ou ON au.id = ou."user"
      WHERE au.id = ANY(user_ids)
        AND ou.occasion = oc AND public.occasion_member_visible_internal(oc,au.id)
    )
  );
END;
$$ LANGUAGE plpgsql;

-- SOURCE: users/occasion_directory_reads.sql
-- Supported directory envelopes share one operation owner. The internal
-- invitation/companion stages retain their service-only direct grants.

CREATE OR REPLACE FUNCTION public.get_occasion_users_for_edit_invitation_base_v1(p_occasion_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    users_data JSON;
    forms_data JSON;
    services_data JSONB;
    org_id BIGINT;
BEGIN
    -- 0. Retrieve the Organization ID
    -- We need this to check against the organization_users table later
    SELECT organization INTO org_id
    FROM public.occasions
    WHERE id = p_occasion_id;

    -- Authorization check: Ensure the user has editor rights for the occasion.
    IF NOT public.can_read_occasion_directory(p_occasion_id) THEN
        RETURN json_build_object('code', 403, 'message', 'User is not authorized to view this occasion''s data');
    END IF;

    -- 1. Get all users associated with the occasion. Resolve order and group
    -- metadata once for the whole occasion instead of running correlated
    -- subqueries for every user.
    WITH visible_users AS MATERIALIZED (
        SELECT ou.*
        FROM public.occasion_users ou
        LEFT JOIN public.organization_users org_u
          ON org_u."user" = ou."user"
         AND org_u.organization = org_id
        WHERE ou.occasion = p_occasion_id
          AND org_u.is_hidden IS NOT TRUE
    ),
    order_info AS (
        SELECT DISTINCT ON (opt.ticket)
            opt.ticket,
            o.data->>'form' AS form_id,
            o.created_at
        FROM visible_users vu
        JOIN eshop.order_product_ticket opt ON opt.ticket = vu.ticket
        JOIN eshop.orders o ON o.id = opt."order"
        ORDER BY opt.ticket, opt.id
    ),
    standard_groups AS (
        SELECT
            ug."user",
            string_agg(ugi.title, ', ' ORDER BY ugi.title) AS titles
        FROM visible_users vu
        JOIN public.user_groups ug ON ug."user" = vu."user"
        JOIN public.user_group_info ugi ON ugi.id = ug."group"
        WHERE ugi.occasion = p_occasion_id
          AND ugi.type IS NULL
        GROUP BY ug."user"
    ),
    companion_owners AS (
        SELECT uc.companion, uc."user" AS owner_id, uc.origin,
               concat_ws(' ', owner_info.name, owner_info.surname) AS owner_name
        FROM public.user_companions uc
        JOIN public.user_info owner_info ON owner_info.id = uc."user"
        WHERE uc.occasion = p_occasion_id AND public.occasion_member_visible_internal(p_occasion_id,owner_info.id)
    )
    SELECT json_agg(row_to_json(user_row))
    INTO users_data
    FROM (
        SELECT
            vu.occasion,
            vu.created_at,
            vu."user",
            vu.is_editor,
            vu.is_manager,
            vu.is_approved,
            vu.is_approver,
            -- Occasion data remains authoritative for event-specific fields.
            -- Overlay only the dedicated global profile columns; user_info.data
            -- also contains historical occasion fields and must not leak across
            -- events. A LEFT JOIN preserves legacy occasion rows without a
            -- matching user_info record.
            COALESCE(vu.data, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
                'email', ui.email_readonly,
                'name', ui.name,
                'surname', ui.surname,
                'sex', ui.sex,
                'phone', COALESCE(ui.phone, ui.data->>'phone'),
                'birthDate', COALESCE(
                    to_char(ui.birth_date, 'YYYY-MM-DD'),
                    ui.data->>'birthDate'
                )
            )) AS data,
            vu.role,
            vu.services,
            vu.is_editor_view,
            vu.is_editor_order,
            vu.is_editor_order_view,
            vu.is_cleaning_crew,
            vu.is_cleaning_blocked,
            vu.is_receptionist,
            vu.ticket,
            order_info.form_id,
            order_info.created_at AS order_created_at,
            au.last_sign_in_at,
            standard_groups.titles AS group_title,
            companion_owners.owner_id AS companion_owner_id,
            companion_owners.owner_name AS companion_owner_name,
            companion_owners.origin AS companion_origin
        FROM visible_users vu
        LEFT JOIN public.user_info ui ON ui.id = vu."user"
        LEFT JOIN auth.users au ON au.id = vu."user"
        LEFT JOIN order_info ON order_info.ticket = vu.ticket
        LEFT JOIN standard_groups ON standard_groups."user" = vu."user"
        LEFT JOIN companion_owners ON companion_owners.companion = vu."user"
    ) user_row;

    -- 2. Get all forms associated with the occasion, selecting only the specified fields.
    SELECT json_agg(
        json_build_object(
            'key', f.key,
            'type', f.type,
            'id', f.id,
            'title', f.title,
            'link', f.link
        )
    )
    INTO forms_data
    FROM public.forms f
    WHERE f.occasion = p_occasion_id;

    -- 3. Return the service catalog in the same RPC response. Both the Users
    -- and Stay tabs need these options to render editable accommodation/food
    -- columns; keeping them here avoids extra requests and PostgREST's 1000-row
    -- cap on direct occasion_users queries.
    SELECT catalog.services || jsonb_build_object(
        'accommodation',
        COALESCE((
            SELECT jsonb_agg(
                service_item.item || jsonb_build_object('place_title', p.title)
                ORDER BY service_item.position
            )
            FROM jsonb_array_elements(
                CASE
                    WHEN jsonb_typeof(catalog.services->'accommodation') = 'array'
                        THEN catalog.services->'accommodation'
                    ELSE '[]'::jsonb
                END
            ) WITH ORDINALITY AS service_item(item, position)
            LEFT JOIN public.places p
              ON p.id = CASE
                  WHEN service_item.item->>'reference' ~ '^[0-9]+$'
                      THEN (service_item.item->>'reference')::bigint
                  ELSE NULL
              END
             AND p.occasion = p_occasion_id
        ), '[]'::jsonb)
    )
    INTO services_data
    FROM (
        SELECT CASE
            WHEN jsonb_typeof(o.services) = 'object' THEN o.services
            ELSE '{}'::jsonb
        END AS services
        FROM public.occasions o
        WHERE o.id = p_occasion_id
    ) catalog;

    -- Assemble the final JSON object without reparsing the complete roster as
    -- JSONB. Both the Users and Stay tabs consume this same bundle.
    RETURN json_build_object(
        'code', 200,
        'message', 'Occasion users and forms retrieved successfully.',
        'data', json_build_object(
            'occasion_users', COALESCE(users_data, '[]'::json),
            'forms',          COALESCE(forms_data, '[]'::json),
            'services',       COALESCE(services_data, '{}'::jsonb)
        )
    );
END;
$function$
;

REVOKE ALL ON FUNCTION public.get_occasion_users_for_edit_invitation_base_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.get_occasion_users_for_edit_invitation_base_v1(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.get_occasion_users_for_edit_internal_companion_v1(p_occasion_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    users_data JSON;
    forms_data JSON;
    services_data JSONB;
    org_id BIGINT;
BEGIN
    -- 0. Retrieve the Organization ID
    -- We need this to check against the organization_users table later
    SELECT organization INTO org_id
    FROM public.occasions
    WHERE id = p_occasion_id;

    -- Authorization check: Ensure the user has editor rights for the occasion.
    IF NOT public.can_read_occasion_directory(p_occasion_id) THEN
        RETURN json_build_object('code', 403, 'message', 'User is not authorized to view this occasion''s data');
    END IF;

    -- 1. Get all users associated with the occasion. Resolve order and group
    -- metadata once for the whole occasion instead of running correlated
    -- subqueries for every user.
    WITH visible_users AS MATERIALIZED (
        SELECT ou.*
        FROM public.occasion_users ou
        LEFT JOIN public.organization_users org_u
          ON org_u."user" = ou."user"
         AND org_u.organization = org_id
        WHERE ou.occasion = p_occasion_id
          AND org_u.is_hidden IS NOT TRUE
    ),
    order_info AS (
        SELECT DISTINCT ON (opt.ticket)
            opt.ticket,
            o.data->>'form' AS form_id,
            o.created_at
        FROM visible_users vu
        JOIN eshop.order_product_ticket opt ON opt.ticket = vu.ticket
        JOIN eshop.orders o ON o.id = opt."order"
        ORDER BY opt.ticket, opt.id
    ),
    standard_groups AS (
        SELECT
            ug."user",
            string_agg(ugi.title, ', ' ORDER BY ugi.title) AS titles
        FROM visible_users vu
        JOIN public.user_groups ug ON ug."user" = vu."user"
        JOIN public.user_group_info ugi ON ugi.id = ug."group"
        WHERE ugi.occasion = p_occasion_id
          AND ugi.type IS NULL
        GROUP BY ug."user"
    )
    SELECT json_agg(row_to_json(user_row))
    INTO users_data
    FROM (
        SELECT
            vu.occasion,
            vu.created_at,
            vu."user",
            vu.is_editor,
            vu.is_manager,
            vu.is_approved,
            vu.is_approver,
            -- Occasion data remains authoritative for event-specific fields.
            -- Overlay only the dedicated global profile columns; user_info.data
            -- also contains historical occasion fields and must not leak across
            -- events. A LEFT JOIN preserves legacy occasion rows without a
            -- matching user_info record.
            COALESCE(vu.data, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
                'email', ui.email_readonly,
                'name', ui.name,
                'surname', ui.surname,
                'sex', ui.sex,
                'phone', COALESCE(ui.phone, ui.data->>'phone'),
                'birthDate', COALESCE(
                    to_char(ui.birth_date, 'YYYY-MM-DD'),
                    ui.data->>'birthDate'
                )
            )) AS data,
            vu.role,
            vu.services,
            vu.is_editor_view,
            vu.is_editor_order,
            vu.is_editor_order_view,
            vu.is_cleaning_crew,
            vu.is_cleaning_blocked,
            vu.ticket,
            order_info.form_id,
            order_info.created_at AS order_created_at,
            au.last_sign_in_at,
            standard_groups.titles AS group_title
        FROM visible_users vu
        LEFT JOIN public.user_info ui ON ui.id = vu."user"
        LEFT JOIN auth.users au ON au.id = vu."user"
        LEFT JOIN order_info ON order_info.ticket = vu.ticket
        LEFT JOIN standard_groups ON standard_groups."user" = vu."user"
    ) user_row;

    -- 2. Get all forms associated with the occasion, selecting only the specified fields.
    SELECT json_agg(
        json_build_object(
            'key', f.key,
            'type', f.type,
            'id', f.id,
            'title', f.title,
            'link', f.link
        )
    )
    INTO forms_data
    FROM public.forms f
    WHERE f.occasion = p_occasion_id;

    -- 3. Return the service catalog in the same RPC response. Both the Users
    -- and Stay tabs need these options to render editable accommodation/food
    -- columns; keeping them here avoids extra requests and PostgREST's 1000-row
    -- cap on direct occasion_users queries.
    SELECT catalog.services || jsonb_build_object(
        'accommodation',
        COALESCE((
            SELECT jsonb_agg(
                service_item.item || jsonb_build_object('place_title', p.title)
                ORDER BY service_item.position
            )
            FROM jsonb_array_elements(
                CASE
                    WHEN jsonb_typeof(catalog.services->'accommodation') = 'array'
                        THEN catalog.services->'accommodation'
                    ELSE '[]'::jsonb
                END
            ) WITH ORDINALITY AS service_item(item, position)
            LEFT JOIN public.places p
              ON p.id = CASE
                  WHEN service_item.item->>'reference' ~ '^[0-9]+$'
                      THEN (service_item.item->>'reference')::bigint
                  ELSE NULL
              END
             AND p.occasion = p_occasion_id
        ), '[]'::jsonb)
    )
    INTO services_data
    FROM (
        SELECT CASE
            WHEN jsonb_typeof(o.services) = 'object' THEN o.services
            ELSE '{}'::jsonb
        END AS services
        FROM public.occasions o
        WHERE o.id = p_occasion_id
    ) catalog;

    -- Assemble the final JSON object without reparsing the complete roster as
    -- JSONB. Both the Users and Stay tabs consume this same bundle.
    RETURN json_build_object(
        'code', 200,
        'message', 'Occasion users and forms retrieved successfully.',
        'data', json_build_object(
            'occasion_users', COALESCE(users_data, '[]'::json),
            'forms',          COALESCE(forms_data, '[]'::json),
            'services',       COALESCE(services_data, '{}'::jsonb)
        )
    );
END;
$function$
;

REVOKE ALL ON FUNCTION public.get_occasion_users_for_edit_internal_companion_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.get_occasion_users_for_edit_internal_companion_v1(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.get_occasion_users_for_editor(p_occasion_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    users_data JSONB;
    forms_data JSONB;
BEGIN
    -- Authorization check: Ensure the user has editor rights for the occasion.
    IF NOT public.can_read_occasion_directory(p_occasion_id) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to view this occasion''s data');
    END IF;

    -- 1. Get all users associated with the occasion.
    -- This query merges the full user_info and occasion_users rows into a single JSON object
    -- for each user, and then adds the form_id and order_created_at from the corresponding order.
    SELECT jsonb_agg(
        to_jsonb(ui) || to_jsonb(ou) ||
        jsonb_build_object(
            'form_id', order_info.form_id,
            'order_created_at', order_info.created_at -- Added order creation date
        )
    )
    INTO users_data
    FROM public.occasion_users ou
    JOIN public.user_info ui ON ou."user" = ui.id
    LEFT JOIN eshop.tickets t ON ou.ticket = t.id
    LEFT JOIN LATERAL (
        SELECT
            o.data->>'form' AS form_id,
            o.created_at AS created_at -- Selecting the order's creation date
        FROM eshop.order_product_ticket opt
        JOIN eshop.orders o ON opt."order" = o.id
        WHERE opt.ticket = t.id
        LIMIT 1
    ) AS order_info ON true
    WHERE ou.occasion = p_occasion_id AND public.occasion_member_visible_internal(p_occasion_id,ui.id);

    -- 2. Get all forms associated with the occasion, selecting only the specified fields.
    SELECT jsonb_agg(
        jsonb_build_object(
            'key', f.key,
            'type', f.type,
            'id', f.id,
            'link', f.link
        )
    )
    INTO forms_data
    FROM public.forms f
    WHERE f.occasion = p_occasion_id;

    -- Assemble the final JSONB object.
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Occasion users and forms retrieved successfully.',
        'data', jsonb_build_object(
            'occasion_users', COALESCE(users_data, '[]'::jsonb),
            'forms',          COALESCE(forms_data, '[]'::jsonb)
        )
    );
END;
$function$
;

REVOKE ALL ON FUNCTION public.get_occasion_users_for_editor(bigint) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.get_occasion_users_for_editor(bigint) TO PUBLIC,anon;

GRANT EXECUTE ON FUNCTION public.get_occasion_users_for_editor(bigint) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_occasion_users_for_editor(bigint) TO authenticated;


-- SOURCE: users/get_occasion_users_editor_bundle_v1.sql
CREATE OR REPLACE FUNCTION public.get_occasion_users_editor_bundle_v1(p_occasion bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_result jsonb; v_users jsonb;
BEGIN
  v_result:=public.get_occasion_users_for_edit(p_occasion)::jsonb;
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN RETURN v_result; END IF;
  WITH companion_owners AS (
    SELECT uc.companion,uc."user" owner_id,uc.origin,
      concat_ws(' ',owner_info.name,owner_info.surname) owner_name
    FROM public.user_companions uc
    JOIN public.user_info owner_info ON owner_info.id=uc."user"
    WHERE uc.occasion=p_occasion AND public.occasion_member_visible_internal(p_occasion,owner_info.id)
  )
  SELECT COALESCE(jsonb_agg(row.value||jsonb_strip_nulls(jsonb_build_object(
      'aggregate_version',COALESCE(v.version,0),
      'companion_owner_id',owners.owner_id,
      'companion_owner_name',owners.owner_name,
      'companion_origin',owners.origin))),'[]'::jsonb)
  INTO v_users
  FROM jsonb_array_elements(v_result#>'{data,occasion_users}') row
  LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='occasion_user'
    AND v.scope_type='occasion' AND v.scope_id=p_occasion
    AND v.aggregate_id=row.value->>'user'
  LEFT JOIN companion_owners owners ON owners.companion=(row.value->>'user')::uuid;
  RETURN jsonb_set(v_result,'{data,occasion_users}',v_users);
END $function$
;
REVOKE ALL ON FUNCTION public.get_occasion_users_editor_bundle_v1(p_occasion bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_users_editor_bundle_v1(p_occasion bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.get_occasion_users_editor_bundle_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_users_editor_bundle_v1(bigint) TO authenticated,service_role;


-- SOURCE: users/get_occasion_membership_for_edit_v1.sql
CREATE OR REPLACE FUNCTION public.get_occasion_membership_for_edit_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT(auth.uid()=p_user OR public.can_manage_occasion_participants(p_occasion)) THEN RAISE insufficient_privilege USING MESSAGE='profile owner or manager required'; END IF;
 RETURN (SELECT to_jsonb(ou)||jsonb_build_object('aggregate_version',coalesce(v.version,0)) FROM public.occasion_users ou LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='occasion_user' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=p_user::text WHERE ou.occasion=p_occasion AND ou."user"=p_user AND (p_user=auth.uid() OR public.occasion_member_visible_internal(p_occasion,p_user)));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_membership_for_edit_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_membership_for_edit_v1(bigint,uuid) TO authenticated;


-- SOURCE: users/get_all_user_basics_from_occasion.sql
CREATE OR REPLACE FUNCTION public.get_all_user_basics_from_occasion(oc bigint)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  org_id bigint;
  user_basics jsonb;
BEGIN
  -----------------------------------------------------
  -- 1. Permission Check
  -----------------------------------------------------
  -- Check if the user is a manager, editor, or approver for the occasion
  IF (SELECT public.can_read_participant_contacts(oc)) <> TRUE THEN
      RETURN jsonb_build_object('code', 403);
  END IF;

  -----------------------------------------------------
  -- 2. Get Organization ID
  -----------------------------------------------------
  -- We need the org_id to check the specific organization_users table
  SELECT organization INTO org_id
  FROM public.occasions
  WHERE id = oc;

  -----------------------------------------------------
  -- 3. Aggregate User Data
  -----------------------------------------------------
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', ui.id,
      'name', ui.name,
      'surname', ui.surname,
      'sex', ui.sex,
      'email_readonly', ui.email_readonly,
      'companion_parent', (
        SELECT jsonb_build_object(
          'id', parent_ui.id,
          'name', parent_ui.name,
          'surname', parent_ui.surname,
          'sex', parent_ui.sex,
          'email_readonly', parent_ui.email_readonly
        )
        FROM public.user_info parent_ui
        WHERE parent_ui.id = uc."user" AND public.organization_member_visible_internal(org_id,parent_ui.id)
      )
    )
  ) INTO user_basics
  FROM public.user_info ui
  LEFT JOIN public.user_companions uc ON ui.id = uc.companion AND uc.occasion=oc
  JOIN public.occasion_users uo ON ui.id = uo."user"

  -- LEFT JOIN to check visibility settings
  LEFT JOIN public.organization_users ou ON ui.id = ou."user" AND ou.organization = org_id

  WHERE uo.occasion = oc

  -- FILTER: Exclude only if explicitly hidden
  -- (NULL or FALSE means visible)
  AND (ou.is_hidden IS NOT TRUE);

  -----------------------------------------------------
  -- 4. Handle Empty Results & Return
  -----------------------------------------------------
  -- If no users are found, return an empty array
  IF user_basics IS NULL THEN
    user_basics := '[]'::jsonb;
  END IF;

  RETURN jsonb_build_object(
    'code', 200,
    'data', user_basics
  );
END;
$$ LANGUAGE plpgsql;


-- SOURCE: users/get_all_user_basics_for_scan.sql
CREATE OR REPLACE FUNCTION public.get_all_user_basics_for_scan(scan_code text)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  oid bigint;
  org_id bigint;
  user_basics jsonb;
BEGIN
  -----------------------------------------------------
  -- 1. Validate Code & Get Occasion AND Organization ID
  -----------------------------------------------------
  SELECT o.id, o.organization INTO oid, org_id
  FROM public.get_scanner_occasion_for_scan_code_internal(scan_code) o
  LIMIT 1;

  -- Security Check: If ID is null, the code is invalid
  IF oid IS NULL THEN
      RAISE EXCEPTION 'Invalid scan code';
  END IF;

  -----------------------------------------------------
  -- 2. Retrieve User Data for this Occasion
  -----------------------------------------------------
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', ui.id,
      'name', ui.name,
      'surname', ui.surname,
      'sex', ui.sex,
      'email_readonly', ui.email_readonly,
      'companion_parent', (
        SELECT jsonb_build_object(
          'id', parent_ui.id,
          'name', parent_ui.name,
          'surname', parent_ui.surname,
          'sex', parent_ui.sex,
          'email_readonly', parent_ui.email_readonly
        )
        FROM public.user_info parent_ui
        WHERE parent_ui.id = uc."user" AND public.organization_member_visible_internal(org_id,parent_ui.id)
      )
    )
  ) INTO user_basics
  FROM public.user_info ui
  LEFT JOIN public.user_companions uc ON ui.id = uc.companion AND uc.occasion=oid
  JOIN public.occasion_users uo ON ui.id = uo."user"

  -- This keeps the user in the list even if they have no record in organization_users
  LEFT JOIN public.organization_users ou ON ui.id = ou."user" AND ou.organization = org_id

  WHERE uo.occasion = oid

  -- "IS NOT TRUE" covers two cases:
  -- 1. is_hidden is FALSE
  -- 2. is_hidden is NULL (record doesn't exist)
  AND (ou.is_hidden IS NOT TRUE);

  -----------------------------------------------------
  -- 3. Handle Empty Results & Return
  -----------------------------------------------------
  IF user_basics IS NULL THEN
    user_basics := '[]'::jsonb;
  END IF;

  RETURN user_basics;
END;
$$ LANGUAGE plpgsql;


-- SOURCE: users/get_all_user_basics_from_occasion_unit.sql
CREATE OR REPLACE FUNCTION public.get_all_user_basics_from_occasion_unit(p_unit_id bigint)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  user_basics jsonb;
  org_id bigint;
BEGIN
  -- Step 1: Retrieve the organization for the given unit
  SELECT organization INTO org_id
  FROM public.units
  WHERE id = p_unit_id;

  -- If the unit does not exist, return a 404 error
  IF org_id IS NULL THEN
    RAISE EXCEPTION 'Unit not found' USING ERRCODE = 'P0002'; -- no_data_found
  END IF;

  -- Step 2: Check if the caller is a manager of the unit
  IF public.can_manage_unit_users(p_unit_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;

  -- Step 3: Aggregate user information and roles for sorting
  WITH relevant_occasions AS (
    -- Occasions under the same unit
    SELECT id AS occasion_id FROM public.occasions WHERE unit = p_unit_id
    UNION
    -- Occasions where the current user has privileged rights
    SELECT occasion AS occasion_id
    FROM public.occasion_users
    WHERE "user" = auth.uid()
      AND public.participant_contacts_read_rule(is_editor,is_manager,is_approver)
  ),
  raw_user_roles AS (
    -- Roles from occasion_users in relevant occasions
    SELECT
      uo."user",
      uo.is_manager,
      uo.is_editor,
      uo.is_editor_order,
      uo.is_editor_view,
      uo.is_editor_order_view,
      uo.is_approver
    FROM public.occasion_users uo
    WHERE uo.occasion IN (SELECT occasion_id FROM relevant_occasions)

    UNION ALL

    -- Roles from unit_users (mapping available columns)
    SELECT
      uu."user",
      uu.is_manager,
      uu.is_editor,
      false AS is_editor_order,       -- Not in unit_users
      uu.is_editor_view,
      false AS is_editor_order_view,  -- Not in unit_users
      false AS is_approver            -- Not in unit_users
    FROM public.unit_users uu
    WHERE uu.unit = p_unit_id
  ),
  aggregated_user_roles AS (
    -- Consolidate roles per user (taking true if any occurrence is true)
    SELECT
      "user",
      bool_or(is_manager) AS is_manager,
      bool_or(is_editor) AS is_editor,
      bool_or(is_editor_order) AS is_editor_order,
      bool_or(is_editor_view) AS is_editor_view,
      bool_or(is_editor_order_view) AS is_editor_order_view,
      bool_or(is_approver) AS is_approver
    FROM raw_user_roles
    GROUP BY "user"
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', ui.id,
      'name', ui.name,
      'surname', ui.surname,
      'sex', ui.sex,
      'email_readonly', ui.email_readonly,
      'companion_parent', (
        SELECT jsonb_build_object(
          'id', parent_ui.id,
          'name', parent_ui.name,
          'surname', parent_ui.surname,
          'sex', parent_ui.sex,
          'email_readonly', parent_ui.email_readonly
        )
        FROM public.user_info parent_ui
        WHERE parent_ui.id = uc."user" AND public.organization_member_visible_internal(org_id,parent_ui.id)
      )
    ) ORDER BY
      aur.is_manager DESC,
      aur.is_editor DESC,
      aur.is_editor_order DESC,
      aur.is_editor_view DESC,
      aur.is_editor_order_view DESC,
      aur.is_approver DESC,
      ui.surname ASC NULLS LAST,
      ui.name ASC NULLS LAST
  ) INTO user_basics
  FROM public.user_info ui
  JOIN aggregated_user_roles aur ON ui.id = aur."user"
  LEFT JOIN public.user_companions uc ON ui.id = uc.companion
    AND uc.occasion IN (SELECT id FROM public.occasions WHERE unit=p_unit_id)
  LEFT JOIN public.organization_users ou ON ui.id = ou."user" AND ou.organization = org_id
  WHERE (ou.is_hidden IS NOT TRUE);

  -- Step 4: Handle cases with no users found
  IF user_basics IS NULL THEN
    user_basics := '[]'::jsonb;
  END IF;

  -- Step 5: Return the aggregated JSON response
  RETURN user_basics;
END;
$$ LANGUAGE plpgsql;


-- SOURCE: events/get_event_feedback_for_edit.sql
CREATE OR REPLACE FUNCTION public.get_event_feedback_for_edit(p_event bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_occasion BIGINT;
    v_summary JSONB;
    v_items JSONB;
BEGIN
    SELECT occasion
    INTO v_occasion
    FROM public.events
    WHERE id = p_event;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Event not found');
    END IF;

    IF NOT public.get_is_editor_view_on_occasion(v_occasion) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'Insufficient permissions'
        );
    END IF;

    IF NOT public.get_is_event_feedback_enabled_on_occasion(v_occasion) THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Feedback feature is not enabled for this occasion'
        );
    END IF;

    SELECT jsonb_build_object(
        'total', COUNT(*),
        'happy', COUNT(*) FILTER (WHERE rating = 'happy'),
        'neutral', COUNT(*) FILTER (WHERE rating = 'neutral'),
        'sad', COUNT(*) FILTER (WHERE rating = 'sad')
    )
    INTO v_summary
    FROM public.event_feedback
    WHERE event = p_event;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', f.id,
                'created_at', f.created_at,
                'updated_at', f.updated_at,
                'rating', f.rating,
                'note', f.note,
                'user_name', NULLIF(
                    btrim(CONCAT_WS(' ', ui.name, ui.surname)), ''
                ),
                'is_anonymous', ui.id IS NULL
            )
            ORDER BY f.updated_at DESC
        ),
        '[]'::jsonb
    )
    INTO v_items
    FROM public.event_feedback f
    LEFT JOIN public.user_info ui ON ui.id = f."user" AND public.organization_member_visible_internal(ui.organization,ui.id)
    WHERE f.event = p_event;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'summary', v_summary,
            'items', v_items
        )
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_event_feedback_for_edit(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_event_feedback_for_edit(bigint)
  TO authenticated, service_role;


-- SOURCE: events/get_event_feedback_export_for_edit.sql
CREATE OR REPLACE FUNCTION public.get_event_feedback_export_page_internal_v1(
    p_occasion bigint
,p_after bigint DEFAULT NULL,p_limit integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_items JSONB;
BEGIN
    IF NOT public.can_read_schedule_feedback(p_occasion) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'Insufficient permissions'
        );
    END IF;

    IF NOT public.get_is_event_feedback_enabled_on_occasion(p_occasion) THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Feedback feature is not enabled for this occasion'
        );
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'event_id', e.id,
                'event_title', e.title,
                'event_start_time', e.start_time,
                'event_end_time', e.end_time,
                'feedback_id', f.id,
                'created_at', f.created_at,
                'updated_at', f.updated_at,
                'rating', f.rating,
                'note', f.note,
                'user_name', NULLIF(
                    btrim(CONCAT_WS(' ', ui.name, ui.surname)), ''
                ),
                'is_anonymous', ui.id IS NULL
            )
            ORDER BY e.start_time ASC, e.title ASC, f.updated_at DESC
        ),
        '[]'::jsonb
    )
    INTO v_items
    FROM (SELECT * FROM public.event_feedback WHERE occasion=p_occasion AND (p_after IS NULL OR id>p_after) ORDER BY id LIMIT p_limit) f
    JOIN public.events e ON e.id = f.event
    LEFT JOIN public.user_info ui ON ui.id = f."user" AND public.organization_member_visible_internal(ui.organization,ui.id)
    WHERE f.occasion = p_occasion;

    RETURN jsonb_build_object('code', 200, 'data', v_items);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_event_feedback_export_page_internal_v1(bigint,bigint,integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_event_feedback_export_for_edit(p_occasion bigint)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_event_feedback_export_page_internal_v1(p_occasion,NULL,NULL);
$$;
REVOKE ALL ON FUNCTION public.get_event_feedback_export_for_edit(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_event_feedback_export_for_edit(bigint) TO authenticated;

COMMIT;
