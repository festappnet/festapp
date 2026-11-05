-- Keep hidden membership subjects out of notification projections.
CREATE OR REPLACE FUNCTION public.notification_center_subject_visible_internal(p_org bigint, p_kind text, p_data jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
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
