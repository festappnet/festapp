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
