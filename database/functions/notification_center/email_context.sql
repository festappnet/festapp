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
