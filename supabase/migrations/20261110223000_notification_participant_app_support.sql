-- Generated forward migration: notification-participant-app-support-2026-11-10
-- Prerequisites: 20261021100000_canonical_authorization.sql, 20261024010000_organization_notification_center.sql, 20261024025000_notification_email_recipient.sql, 20261024120000_order_email_recovery.sql, 20261024220000_cancelled_order_email_alerts.sql, 20261024235000_notification_center_canonical_availability.sql, 20261026120000_notification_center_feed.sql, 20261026150000_notification_center_order_periods.sql, 20261026230000_notification_center_unread_snapshot.sql, 20261027210000_notification_center_overview.sql, 20261027220000_notification_center_daily_overview.sql, 20261027234500_notification_group_order_selection.sql, 20261028010000_notification_legacy_place_totals.sql, 20261028013000_notification_category_rollups.sql, 20261028020000_notification_center_lifecycle.sql, 20261028030000_notification_new_orders_exclude_cancelled.sql, 20261028120000_notification_center_current_rollups.sql, 20261028130000_notification_personal_read_batches.sql, 20261030093000_notification_deleted_entities.sql, 20261031110000_notification_current_participants.sql, 20261031120000_notification_center_source_alignment.sql, 20261101170000_hidden_participant_notifications.sql, 20261105070000_notification_subject_lookup_performance.sql, 20261105110000_notification_center_delivery_draining.sql, 20261105120000_notification_center_prepared_views.sql, 20261105181000_notification_prepared_retention.sql, 20261105190000_notification_prepared_scope_discovery.sql, 20261105203000_notification_idle_wake.sql, 20261105213000_notification_open_work.sql, 20261105230000_notification_read_history_compaction.sql, 20261105233000_notification_order_visibility.sql, 20261106010000_notification_order_email_recovery.sql, 20261106110000_notification_canonical_orders.sql
BEGIN;
DO $$ BEGIN IF to_regclass('public.notification_center_organizations') IS NULL OR to_regclass('public.notification_center_activation') IS NOT NULL OR to_regclass('public.notification_center_source_state') IS NULL OR to_regclass('public.notification_center_view_members') IS NULL OR to_regprocedure('public.notification_center_prepared_scope(bigint,jsonb)') IS NULL OR to_regprocedure('public.mark_notification_center_view_item_read(bigint,jsonb)') IS NULL THEN RAISE EXCEPTION 'notification_feed_prerequisites_missing'; END IF; END $$;

-- SOURCE: notification_center/shared.sql
-- Shared notification classification, DTO and receipt grouping.
-- Serving adapters own scopes; these owners retain domain policy and history.
CREATE OR REPLACE FUNCTION public.notification_center_order_activity_internal(p_kind text)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_kind IN ('order_created','order_cancelled','waitlist_registered','offer_accepted','offer_declined','offer_expired');
$$;

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

REVOKE ALL ON FUNCTION public.notification_center_order_activity_internal(text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.notification_center_dto(public.notification_center_events,public.notification_center_deliveries) FROM PUBLIC,anon,authenticated;


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
DECLARE e public.notification_center_events; u uuid; was_pending boolean;
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


-- SOURCE: notification_center/center_policy.sql
-- Only the current incident for a connection remains actionable. Historical
-- episodes can retain deliveries/read receipts, but must not duplicate alerts.
CREATE OR REPLACE FUNCTION public.notification_center_bank_episode_current(e public.notification_center_events)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT e.kind<>'bank_problem' OR NOT EXISTS(
  SELECT 1 FROM public.notification_center_source_state s
  WHERE s.organization=e.organization AND s.source_key='bank:'||(e.data->>'bankConnectionId')
   AND s.state->>'eventId' IS NOT NULL
   AND (s.state->>'eventId'<>e.id::text OR NOT coalesce((s.state->>'problem')::boolean,false)));
$$;
REVOKE ALL ON FUNCTION public.notification_center_bank_episode_current(public.notification_center_events) FROM PUBLIC,anon,authenticated,service_role;

-- New-order activity follows the current order state, including older panel snapshots.
-- Participant joins remain relevant only while that person belongs to the occasion.
-- Activity expires from the center, not from the order/email audit history.
CREATE OR REPLACE FUNCTION public.notification_center_in_center_internal(
 e public.notification_center_events,p_anchor timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.notification_center_subject_visible_internal(e.organization,e.kind,e.data) AND CASE WHEN e.kind IN ('email_problem','bank_problem')
  THEN e.status NOT IN ('recovered','resolved') AND public.notification_center_bank_episode_current(e)
  ELSE e.occurred_at>=p_anchor-interval '30 days'
   AND (e.kind<>'order_created' OR coalesce(
    (SELECT o.state FROM eshop.orders o
     WHERE o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$'
      THEN (e.data->>'orderId')::bigint END AND o.occasion=e.occasion),
    e.status,'')<>'storno')
   AND (e.kind<>'occasion_joined' OR (EXISTS(SELECT 1 FROM public.organizations org
    WHERE org.id=e.organization AND org.data->>'IS_APP_SUPPORTED'='true') AND EXISTS(
    SELECT 1 FROM public.occasion_users m
    JOIN public.user_info u ON u.id=m."user" AND u.organization=e.organization
    WHERE m.occasion=e.occasion AND m."user"::text=e.data->>'userId'
     AND NOT EXISTS(SELECT 1 FROM public.organization_users hidden
      WHERE hidden.organization=e.organization AND hidden."user"=m."user" AND hidden.is_hidden)))) END;
$$;
REVOKE ALL ON FUNCTION public.notification_center_in_center_internal(public.notification_center_events,timestamptz) FROM PUBLIC,anon,authenticated,service_role;


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
 AND CASE WHEN e.kind IN ('email_problem','bank_problem') THEN e.status NOT IN ('recovered','resolved') AND public.notification_center_bank_episode_current(e)
 ELSE e.occurred_at>=p_anchor-interval '30 days'
  AND (e.kind<>'order_created' OR coalesce((SELECT o.state FROM eshop.orders o WHERE o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (e.data->>'orderId')::bigint END AND o.occasion=e.occasion),e.status,'')<>'storno')
  AND (e.kind<>'occasion_joined' OR (EXISTS(SELECT 1 FROM public.organizations org
    WHERE org.id=e.organization AND org.data->>'IS_APP_SUPPORTED'='true') AND EXISTS(SELECT 1 FROM public.occasion_users m JOIN public.user_info u ON u.id=m."user" AND u.organization=e.organization
   WHERE m.occasion=e.occasion AND m."user"::text=e.data->>'userId'))) END;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_apply(e public.notification_center_events,d public.notification_center_deliveries,p_anchor timestamptz DEFAULT clock_timestamp(),p_privacy jsonb DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
#variable_conflict use_column
DECLARE old public.notification_center_view_members; b record; id text; visible boolean; places bigint; context jsonb; multi boolean; legacy_count bigint;
BEGIN
 SELECT * INTO old FROM public.notification_center_view_members WHERE organization=d.organization AND recipient=d.recipient AND event_id=d.event_id;
 IF FOUND AND old.sequence>d.sequence THEN RETURN; END IF;
 SELECT * INTO b FROM public.notification_center_prepared_batch_at(e,d,p_anchor);
 id:=CASE WHEN e.kind IN ('email_problem','bank_problem') OR e.occasion IS NULL THEN e.id::text WHEN b.is_read THEN b.group_key||':history:read' ELSE b.batch_id||':unread' END;
 visible:=public.notification_center_prepared_policy(e,p_anchor,coalesce(p_privacy,(SELECT privacy FROM public.notification_center_projection_scopes WHERE organization=d.organization AND recipient=d.recipient)));
 places:=CASE WHEN e.data->>'count' ~ '^[0-9]{1,9}$' THEN nullif((e.data->>'count')::bigint,0) END;
 context:=nullif(e.data->'formContext','null'::jsonb);
 IF public.notification_center_order_activity_internal(e.kind) AND (e.data->>'count' IS NULL OR context IS NULL) THEN
  SELECT nullif(count(DISTINCT x.ticket),0),public.notification_center_order_form_context_internal(o.form)
   INTO legacy_count,context FROM eshop.orders o LEFT JOIN eshop.order_product_ticket x ON x."order"=o.id
   WHERE o.occasion=e.occasion AND o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (e.data->>'orderId')::bigint END GROUP BY o.id;
  places:=coalesce(places,legacy_count);context:=coalesce(nullif(e.data->'formContext','null'::jsonb),context);
 END IF;
 multi:=coalesce(places>1 OR context->'allowsMultiple'='true'::jsonb,false);
 IF old.eligible THEN
  UPDATE public.notification_center_batch_summaries SET activity_count=activity_count-1,known_count=known_count-(old.places IS NOT NULL)::int,
   places=places-coalesce(old.places,0),multiple_count=multiple_count-old.multiple::int
   WHERE organization=d.organization AND recipient=d.recipient AND id=old.batch_id;
 END IF;
 INSERT INTO public.notification_center_view_members(organization,recipient,event_id,sequence,attention_revision,source_revision,group_key,batch_id,is_read,after_sequence,through_sequence,eligible,occurred_at,expires_at,places,multiple)
 VALUES(d.organization,d.recipient,e.id,d.sequence,d.attention_revision,e.view_revision,b.group_key,id,b.is_read,b.after_sequence,b.through_sequence,visible,e.occurred_at,
  CASE WHEN e.kind NOT IN ('email_problem','bank_problem') THEN e.occurred_at+interval '30 days' END,places,multi)
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
  next_expiry=least(next_expiry,CASE WHEN e.kind NOT IN ('email_problem','bank_problem') AND public.notification_center_prepared_policy(e,clock_timestamp(),s.privacy) THEN e.occurred_at+interval '30 days' END)
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
  AND e.kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted','offer_declined','offer_expired')
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


-- SOURCE: notification_center/order_selection.sql
-- Resolve the frozen, authorized group only when the orders page is opened.
-- No target ID arrays are added to the notification feed or badge polling.
CREATE OR REPLACE FUNCTION public.notification_center_order_selection(
 p_occasion bigint,p_group jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF p_group ? 'viewToken' THEN
  p_group:=public.notification_center_prepared_scope((p_group->>'organization')::bigint,p_group);
  IF (p_group->>'occasion')::bigint IS DISTINCT FROM p_occasion THEN RAISE insufficient_privilege USING MESSAGE='notification_context_mismatch'; END IF;
  IF NOT coalesce(public.can_read_orders(p_occasion),false) THEN RAISE insufficient_privilege USING MESSAGE='orders_read_denied'; END IF;
  -- Frozen envelopes select every captured member, independent of preview/page size.
  -- Live authorization/privacy and source eligibility still apply on this request.
  SELECT coalesce(jsonb_agg(DISTINCT (e.data->>'orderId')::bigint),'[]'::jsonb) INTO result
  FROM public.notification_center_view_members m
  JOIN public.notification_center_events e ON e.id=m.event_id
  JOIN public.notification_center_deliveries d ON d.event_id=e.id AND d.organization=m.organization AND d.recipient=m.recipient
  WHERE m.organization=(p_group->>'organization')::bigint AND m.recipient=auth.uid() AND m.eligible
   AND e.occasion=p_occasion AND d.sequence<=(p_group->>'snapshot')::bigint
   AND NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries newer WHERE newer.event_id=d.event_id AND newer.recipient=d.recipient AND newer.sequence<=(p_group->>'snapshot')::bigint AND newer.sequence>d.sequence)
   AND public.notification_center_allowed(e,auth.uid())
   AND public.notification_center_in_center_internal(e,(p_group->>'capturedAt')::timestamptz)
   AND public.notification_center_order_activity_internal(e.kind)
   AND public.notification_center_prepared_scope_member(e,d,p_group->>'groupKey',p_group->>'id',
    (p_group->>'afterSequence')::bigint,(p_group->>'throughSequence')::bigint,
    (p_group->>'capturedAt')::timestamptz,(p_group->>'captureIsRead')::boolean)
   AND e.data->>'orderId' ~ '^[0-9]{1,18}$';
  RETURN result;
 END IF;
 RAISE invalid_parameter_value USING MESSAGE='notification_view_token_required';
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
      PERFORM public.mark_notification_center_view_item_read(
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


-- SOURCE: notification_center/serving_contraction.sql
-- Retire obsolete admin-center serving only. Mobile news/push delivery is unchanged.
-- Explicit signatures, no CASCADE and no receipt/baseline/data deletion.
DROP FUNCTION IF EXISTS public.get_notification_center_badge(bigint);
DROP FUNCTION IF EXISTS public.get_notification_center_daily_overview(bigint,bigint,bigint,timestamp with time zone,text,jsonb,integer,text[],boolean);
DROP FUNCTION IF EXISTS public.get_notification_center_feed(bigint,bigint,bigint,jsonb,integer);
DROP FUNCTION IF EXISTS public.get_notification_center_group(bigint,text,bigint,bigint,integer);
DROP FUNCTION IF EXISTS public.get_notification_center_overview(bigint,bigint,bigint,jsonb,integer,text[]);
DROP FUNCTION IF EXISTS public.get_notification_center_page(bigint,bigint,integer,bigint,jsonb);
DROP FUNCTION IF EXISTS public.get_notification_center_timeline(bigint,bigint,bigint,timestamp with time zone,jsonb,jsonb,integer);
DROP FUNCTION IF EXISTS public.get_notification_center_timeline_group(bigint,bigint,bigint,timestamp with time zone,bigint,jsonb,jsonb,integer);
DROP FUNCTION IF EXISTS public.get_notification_center_timeline_group_updates(bigint,bigint,bigint,timestamp with time zone,jsonb);
DROP FUNCTION IF EXISTS public.get_notification_center_updates(bigint,bigint,uuid[]);
DROP FUNCTION IF EXISTS public.mark_notification_center_item_read(bigint,jsonb);
DROP FUNCTION IF EXISTS public.open_notification_center(bigint,bigint,integer);
DROP FUNCTION IF EXISTS public.notification_center_periods_internal(jsonb,timestamp with time zone);
DROP FUNCTION IF EXISTS public.notification_center_rollup_id_internal(text);
DROP FUNCTION IF EXISTS public.notification_center_time_cursor_internal(jsonb,text);
DROP FUNCTION IF EXISTS public.notification_center_visible_internal(bigint,bigint,bigint);


-- SOURCE: notification_center/participant_app_support_repair.sql
-- Rebuild retained projections so participant history and badges follow app support.
-- Source events and personal read receipts remain audit history.
DO $$ DECLARE item record; BEGIN
 FOR item IN SELECT e.id FROM public.notification_center_events e
 JOIN public.organizations org ON org.id=e.organization
 WHERE e.kind='occasion_joined' AND org.data->>'IS_APP_SUPPORTED' IS DISTINCT FROM 'true'
 LOOP PERFORM public.notification_center_prepared_invalidate(item.id); END LOOP;
END $$;

COMMIT;
