CREATE TABLE IF NOT EXISTS analytics.unit_measurement_request (
 unit bigint PRIMARY KEY REFERENCES public.units(id) ON DELETE CASCADE,
 requested_at timestamptz NOT NULL DEFAULT now(),
 requested_by uuid
);
ALTER TABLE analytics.unit_measurement_request ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.unit_measurement_request FROM PUBLIC,anon,authenticated,service_role;

-- Platform approval only: organizer switches, destinations and privacy settings
-- remain independent. Structural runtime support has one shared private owner.
CREATE OR REPLACE FUNCTION public.unit_measurement_approval_internal(p_unit bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH status AS (
  SELECT coalesce(p.enabled,false) allowed,
   public.form_measurement_runtime_supported_internal(r.runtime_profile,r.runtime_origin,r.parent_origins)
    AND NOT public.is_demo_unit(u.id) supported,q.requested_at
  FROM public.units u
  LEFT JOIN analytics.organization_policy p ON p.organization=u.organization
  LEFT JOIN analytics.unit_runtime r ON r.unit=u.id
  LEFT JOIN analytics.unit_measurement_request q ON q.unit=u.id WHERE u.id=p_unit
 ) SELECT jsonb_build_object('approved',allowed AND supported,'organization_allowed',allowed,
  'runtime_supported',supported,'requested_at',requested_at) FROM status;
$$;
REVOKE ALL ON FUNCTION public.unit_measurement_approval_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_unit_measurement_approval(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.can_read_unit_administration(p_unit) OR public.can_manage_unit_configuration(p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='unit measurement approval read denied';
 END IF;
 RETURN public.unit_measurement_approval_internal(p_unit);
END $$;
REVOKE ALL ON FUNCTION public.get_unit_measurement_approval(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_unit_measurement_approval(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.request_unit_measurement_approval(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE u public.units; o public.organizations; a record; status jsonb; msg jsonb; origin text; sent integer:=0;
BEGIN
 -- Demo configuration is read-only: an authorized administration reader may
 -- receive the no-op status, while every live request needs settings write.
 IF auth.uid() IS NULL OR NOT (public.can_manage_unit_configuration(p_unit)
  OR (public.is_demo_unit(p_unit) AND public.can_read_unit_administration(p_unit))) THEN
  RAISE insufficient_privilege USING MESSAGE='unit measurement approval request denied';
 END IF;
 -- Serialize retries for this Unit, including concurrent callers.
 SELECT * INTO u FROM public.units WHERE id=p_unit FOR UPDATE;
 status:=public.unit_measurement_approval_internal(p_unit);
 IF public.is_demo_unit(p_unit) OR status->'approved'='true'::jsonb OR status->>'requested_at' IS NOT NULL THEN
  RETURN status;
 END IF;
 SELECT * INTO o FROM public.organizations WHERE id=u.organization;
 origin:=rtrim(o.data->>'DEFAULT_URL','/');
 IF origin IS NULL OR origin !~ '^https://[^/?#[:space:]]+$' THEN RAISE EXCEPTION 'measurement_notification_origin_missing'; END IF;
 INSERT INTO analytics.unit_measurement_request(unit,requested_by) VALUES(p_unit,auth.uid()) ON CONFLICT(unit) DO NOTHING;
 IF NOT FOUND THEN RETURN public.unit_measurement_approval_internal(p_unit); END IF;
 FOR a IN SELECT ou."user" id,public.get_user_delivery_email(ou."user") email
  FROM public.organization_users ou WHERE ou.organization=u.organization AND ou.is_admin ORDER BY ou."user"
 LOOP
  IF a.email IS NULL THEN CONTINUE; END IF;
  msg:=public.enqueue_email('custom',jsonb_build_object('organization',u.organization,'unit',p_unit,'recipient_user',a.id),a.email,
   jsonb_build_object('unit_id',p_unit,'unit_title',u.title,'organization_title',o.title,
    'review_url',origin||'/organizationEdit/'||u.organization,'lang',CASE WHEN o.data->>'DEFAULT_LANGUAGE'='en' THEN 'en' ELSE 'cs' END),
   'measurement-approval:'||p_unit||':'||a.id,'MEASUREMENT_APPROVAL_REQUEST',now(),now()+interval '30 days');
  UPDATE public.email_messages SET tracking_policy='disabled' WHERE message_id=(msg->>'message_id')::uuid;
  sent:=sent+1;
 END LOOP;
 -- Nobody could be notified: roll back the request so it stays retryable.
 IF sent=0 THEN RAISE EXCEPTION 'measurement_request_no_recipient'; END IF;
 RETURN public.unit_measurement_approval_internal(p_unit);
END $$;
REVOKE ALL ON FUNCTION public.request_unit_measurement_approval(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.request_unit_measurement_approval(bigint) TO authenticated;
