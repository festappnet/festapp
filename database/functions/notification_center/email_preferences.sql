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
