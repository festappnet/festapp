CREATE TABLE IF NOT EXISTS analytics.organization_meta_capi_request (
 organization bigint PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
 unit bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
 requested_at timestamptz NOT NULL DEFAULT now(),
 requested_by uuid,
 fulfilled_at timestamptz,
 revision integer NOT NULL DEFAULT 1
);
ALTER TABLE analytics.organization_meta_capi_request ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.organization_meta_capi_request FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX IF NOT EXISTS unit_meta_capi_notification_generation
 ON public.email_messages(unit,((data->>'request_revision')::integer))
 WHERE code='META_CAPI_APPROVAL_REQUEST';

-- Unit managers see only the platform decision and their own request; Meta
-- CAPI settings remain organization-administrator only.
CREATE OR REPLACE FUNCTION public.unit_meta_capi_approval_internal(p_unit bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH status AS (
  SELECT u.id,public.meta_purchase_platform_allowed_internal(u.id) AND NOT public.is_demo_unit(u.id) approved,q.requested_at,
   q.fulfilled_at IS NULL AND EXISTS(SELECT FROM public.email_messages m
    JOIN public.organization_users ou ON ou.organization=u.organization
     AND ou."user"=m.recipient_user AND ou.is_admin
    WHERE m.unit=q.unit AND m.organization=q.organization AND m.code='META_CAPI_APPROVAL_REQUEST'
     AND (m.data->>'request_revision')::integer=q.revision
     AND public.get_user_delivery_email(ou."user")=m.recipient
     -- Same retry rule as the measurement request: accepted or ambiguous
     -- sends are not duplicated; terminal or expired generations are.
     AND (m.workflow_state IN ('accepted','sending','unknown') OR
      (m.workflow_state IN ('pending','retry_wait','preparing','blocked') AND m.expires_at>now()))) active_request
  FROM public.units u
  LEFT JOIN analytics.organization_meta_capi_request q ON q.organization=u.organization WHERE u.id=p_unit
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
 RETURN public.unit_meta_capi_approval_internal(p_unit) ||
  CASE WHEN public.can_manage_unit_configuration(p_unit) THEN '{}'::jsonb
   ELSE '{"can_request":false}'::jsonb END;
END $$;
REVOKE ALL ON FUNCTION public.get_unit_meta_capi_approval(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_unit_meta_capi_approval(bigint) TO authenticated;

-- A platform approval fulfils the current request even if the mail has not
-- been claimed. Serialize the policy decision with the request's organization.
CREATE OR REPLACE FUNCTION public.fulfil_meta_capi_approval_internal()
RETURNS trigger LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 IF NEW.meta_capi_enabled THEN
  PERFORM 1 FROM public.organizations WHERE id=NEW.organization FOR NO KEY UPDATE;
  UPDATE analytics.organization_meta_capi_request SET fulfilled_at=clock_timestamp()
   WHERE organization=NEW.organization AND fulfilled_at IS NULL;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.fulfil_meta_capi_approval_internal() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE TRIGGER fulfil_meta_capi_approval
 AFTER INSERT OR UPDATE OF meta_capi_enabled ON analytics.organization_policy
 FOR EACH ROW EXECUTE FUNCTION public.fulfil_meta_capi_approval_internal();

CREATE OR REPLACE FUNCTION public.request_unit_meta_capi_approval(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE u public.units; org public.organizations; a record; status jsonb; msg jsonb; origin text; sent integer:=0; request_revision integer;
BEGIN
 -- Same boundary as the measurement request: Unit managers ask, demo readers get a no-op.
 IF auth.uid() IS NULL OR NOT (public.can_manage_unit_configuration(p_unit)
  OR (public.is_demo_unit(p_unit) AND public.can_read_unit_administration(p_unit))) THEN
  RAISE insufficient_privilege USING MESSAGE='unit Meta CAPI approval request denied';
 END IF;
 SELECT o.* INTO org FROM public.units target
 JOIN public.organizations o ON o.id=target.organization
 WHERE target.id=p_unit FOR NO KEY UPDATE OF o;
 SELECT * INTO u FROM public.units WHERE id=p_unit AND organization=org.id FOR KEY SHARE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 status:=public.unit_meta_capi_approval_internal(p_unit);
 IF status->'can_request' IS DISTINCT FROM 'true'::jsonb THEN RETURN status; END IF;
 origin:=rtrim(org.data->>'DEFAULT_URL','/');
 IF origin IS NULL OR origin !~ '^https://[a-z0-9.-]+(:[0-9]{1,5})?$'
    OR substring(origin FROM ':([0-9]{1,5})$')::integer NOT BETWEEN 1 AND 65535
 THEN RAISE EXCEPTION 'meta_capi_notification_origin_missing'; END IF;
 INSERT INTO analytics.organization_meta_capi_request(organization,unit,requested_by)
 VALUES(u.organization,p_unit,auth.uid())
 ON CONFLICT(organization) DO UPDATE SET unit=EXCLUDED.unit, requested_at=clock_timestamp(),
  requested_by=auth.uid(), fulfilled_at=NULL, revision=analytics.organization_meta_capi_request.revision+1
 RETURNING revision INTO request_revision;
 FOR a IN SELECT ou."user" id,public.get_user_delivery_email(ou."user") email
  FROM public.organization_users ou WHERE ou.organization=u.organization AND ou.is_admin ORDER BY ou."user"
 LOOP
  IF a.email IS NULL THEN CONTINUE; END IF;
  msg:=public.enqueue_email('custom',jsonb_build_object('organization',u.organization,'unit',p_unit,'recipient_user',a.id),a.email,
   jsonb_build_object('request_revision',request_revision,'unit_id',p_unit,'unit_title',u.title,'organization_title',org.title,
    'review_url',origin||'/organizationEdit/'||u.organization,'lang',CASE WHEN org.data->>'DEFAULT_LANGUAGE'='en' THEN 'en' ELSE 'cs' END),
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
