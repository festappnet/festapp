CREATE TABLE IF NOT EXISTS analytics.unit_meta_capi_request (
 unit bigint PRIMARY KEY REFERENCES public.units(id) ON DELETE CASCADE,
 requested_at timestamptz NOT NULL DEFAULT now(),
 requested_by uuid,
 revision integer NOT NULL DEFAULT 1
);
ALTER TABLE analytics.unit_meta_capi_request ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.unit_meta_capi_request FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX IF NOT EXISTS unit_meta_capi_notification_generation
 ON public.email_messages(unit,((data->>'request_revision')::integer))
 WHERE code='META_CAPI_APPROVAL_REQUEST';

-- Unit managers see only the platform decision and their own request; Meta
-- CAPI settings remain organization-administrator only.
CREATE OR REPLACE FUNCTION public.unit_meta_capi_approval_internal(p_unit bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH status AS (
  SELECT u.id,public.meta_purchase_platform_allowed_internal(u.id) AND NOT public.is_demo_unit(u.id) approved,q.requested_at,
   EXISTS(SELECT FROM public.email_messages m
    JOIN public.organization_users ou ON ou.organization=u.organization
     AND ou."user"=m.recipient_user AND ou.is_admin
    WHERE m.unit=u.id AND m.organization=u.organization AND m.code='META_CAPI_APPROVAL_REQUEST'
     AND (m.data->>'request_revision')::integer=q.revision
     AND public.get_user_delivery_email(ou."user")=m.recipient
     -- Same retry rule as the measurement request: accepted or ambiguous
     -- sends are not duplicated; terminal or expired generations are.
     AND (m.workflow_state IN ('accepted','sending','unknown') OR
      (m.workflow_state IN ('pending','retry_wait','preparing','blocked') AND m.expires_at>now()))) active_request
  FROM public.units u
  LEFT JOIN analytics.unit_meta_capi_request q ON q.unit=u.id WHERE u.id=p_unit
 ) SELECT jsonb_build_object('approved',approved,'requested_at',requested_at,
  'request_state',CASE WHEN requested_at IS NULL THEN 'not_requested'
    WHEN active_request THEN 'requested' ELSE 'retry_available' END,
  'can_request',NOT public.is_demo_unit(id) AND NOT approved AND NOT active_request) FROM status;
$$;
REVOKE ALL ON FUNCTION public.unit_meta_capi_approval_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_unit_meta_capi_approval(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.can_read_unit_administration(p_unit) OR public.can_manage_unit_configuration(p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='unit Meta CAPI approval read denied';
 END IF;
 RETURN public.unit_meta_capi_approval_internal(p_unit);
END $$;
REVOKE ALL ON FUNCTION public.get_unit_meta_capi_approval(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_unit_meta_capi_approval(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.request_unit_meta_capi_approval(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE u public.units; o public.organizations; a record; status jsonb; msg jsonb; origin text; sent integer:=0; request_revision integer;
BEGIN
 -- Same boundary as the measurement request: Unit managers ask, demo readers get a no-op.
 IF auth.uid() IS NULL OR NOT (public.can_manage_unit_configuration(p_unit)
  OR (public.is_demo_unit(p_unit) AND public.can_read_unit_administration(p_unit))) THEN
  RAISE insufficient_privilege USING MESSAGE='unit Meta CAPI approval request denied';
 END IF;
 -- Serialize requests for this Unit without blocking the delivery FK's key-share lock.
 SELECT * INTO u FROM public.units WHERE id=p_unit FOR NO KEY UPDATE;
 status:=public.unit_meta_capi_approval_internal(p_unit);
 IF status->'can_request' IS DISTINCT FROM 'true'::jsonb THEN RETURN status; END IF;
 SELECT * INTO o FROM public.organizations WHERE id=u.organization;
 origin:=rtrim(o.data->>'DEFAULT_URL','/');
 IF origin IS NULL OR origin !~ '^https://[^/?#[:space:]]+$' THEN RAISE EXCEPTION 'meta_capi_notification_origin_missing'; END IF;
 INSERT INTO analytics.unit_meta_capi_request(unit,requested_by) VALUES(p_unit,auth.uid())
 ON CONFLICT(unit) DO UPDATE SET requested_at=clock_timestamp(),requested_by=auth.uid(),
  revision=analytics.unit_meta_capi_request.revision+1
 RETURNING revision INTO request_revision;
 FOR a IN SELECT ou."user" id,public.get_user_delivery_email(ou."user") email
  FROM public.organization_users ou WHERE ou.organization=u.organization AND ou.is_admin ORDER BY ou."user"
 LOOP
  IF a.email IS NULL THEN CONTINUE; END IF;
  msg:=public.enqueue_email('custom',jsonb_build_object('organization',u.organization,'unit',p_unit,'recipient_user',a.id),a.email,
   jsonb_build_object('request_revision',request_revision,'unit_id',p_unit,'unit_title',u.title,'organization_title',o.title,
    'review_url',origin||'/organizationEdit/'||u.organization,'lang',CASE WHEN o.data->>'DEFAULT_LANGUAGE'='en' THEN 'en' ELSE 'cs' END),
   'meta-capi-approval:'||p_unit||':'||a.id||':'||request_revision,'META_CAPI_APPROVAL_REQUEST',now(),now()+interval '30 days');
  UPDATE public.email_messages SET tracking_policy='disabled' WHERE message_id=(msg->>'message_id')::uuid;
  sent:=sent+1;
 END LOOP;
 -- Nobody could be notified: roll back the request so it stays retryable.
 IF sent=0 THEN RAISE EXCEPTION 'meta_capi_request_no_recipient'; END IF;
 RETURN public.unit_meta_capi_approval_internal(p_unit);
END $$;
REVOKE ALL ON FUNCTION public.request_unit_meta_capi_approval(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.request_unit_meta_capi_approval(bigint) TO authenticated;
