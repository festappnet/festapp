CREATE TABLE IF NOT EXISTS analytics.unit_measurement_request (
 unit bigint PRIMARY KEY REFERENCES public.units(id) ON DELETE CASCADE,
 requested_at timestamptz NOT NULL DEFAULT now(),
 requested_by uuid
);
ALTER TABLE analytics.unit_measurement_request ADD COLUMN IF NOT EXISTS requested_origins jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE analytics.unit_measurement_request ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 1;
ALTER TABLE analytics.unit_measurement_request ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.unit_measurement_request FROM PUBLIC,anon,authenticated,service_role;

-- Platform approval only: organizer switches, destinations and privacy settings
-- remain independent. Structural runtime support has one shared private owner.
CREATE OR REPLACE FUNCTION public.unit_measurement_approval_internal(p_unit bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH status AS (
  SELECT coalesce(p.enabled,false) allowed,
   public.form_measurement_runtime_supported_internal(r.runtime_profile,r.runtime_origin,r.parent_origins)
    AND NOT public.is_demo_unit(u.id) supported,q.requested_at,coalesce(to_jsonb(r.parent_origins),'[]'::jsonb) approved_origins,
   coalesce(q.requested_origins,'[]'::jsonb) requested_origins
  FROM public.units u
  LEFT JOIN analytics.organization_policy p ON p.organization=u.organization
  LEFT JOIN analytics.unit_runtime r ON r.unit=u.id
  LEFT JOIN analytics.unit_measurement_request q ON q.unit=u.id WHERE u.id=p_unit
 ) SELECT jsonb_build_object('approved',allowed AND supported,'organization_allowed',allowed,
  'runtime_supported',supported,'requested_at',requested_at,'approved_origins',approved_origins,'requested_origins',requested_origins) FROM status;
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
DECLARE u public.units; o public.organizations; a record; status jsonb; msg jsonb; origin text; sent integer:=0; websites jsonb; pending jsonb; request_revision integer;
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
 websites:=coalesce(u.data->'measurement_websites','[]'::jsonb);
 PERFORM public.validate_configuration_value_internal_v1(websites,public.configuration_settings_contract_internal_v1()#>'{unit,measurement_websites}');
 SELECT coalesce(jsonb_agg(DISTINCT value ORDER BY value),'[]'::jsonb) INTO pending
 FROM jsonb_array_elements(websites) WHERE NOT (status->'approved_origins' @> jsonb_build_array(value));
 IF public.is_demo_unit(p_unit) OR
  ((status->'approved'='true'::jsonb OR status->>'requested_at' IS NOT NULL)
   AND NOT EXISTS(SELECT FROM jsonb_array_elements(pending) x WHERE NOT (status->'requested_origins' @> jsonb_build_array(x.value)))) THEN
  RETURN status;
 END IF;
 SELECT * INTO o FROM public.organizations WHERE id=u.organization;
 origin:=rtrim(o.data->>'DEFAULT_URL','/');
 IF origin IS NULL OR origin !~ '^https://[^/?#[:space:]]+$' THEN RAISE EXCEPTION 'measurement_notification_origin_missing'; END IF;
 INSERT INTO analytics.unit_measurement_request(unit,requested_by,requested_origins) VALUES(p_unit,auth.uid(),websites)
 ON CONFLICT(unit) DO UPDATE SET requested_at=clock_timestamp(),requested_by=auth.uid(),
  requested_origins=EXCLUDED.requested_origins,revision=analytics.unit_measurement_request.revision+1
 RETURNING revision INTO request_revision;
 FOR a IN SELECT ou."user" id,public.get_user_delivery_email(ou."user") email
  FROM public.organization_users ou WHERE ou.organization=u.organization AND ou.is_admin ORDER BY ou."user"
 LOOP
  IF a.email IS NULL THEN CONTINUE; END IF;
  msg:=public.enqueue_email('custom',jsonb_build_object('organization',u.organization,'unit',p_unit,'recipient_user',a.id),a.email,
   jsonb_build_object('proposed_websites',websites,'request_revision',request_revision,'unit_id',p_unit,'unit_title',u.title,'organization_title',o.title,
    'review_url',origin||'/organizationEdit/'||u.organization,'lang',CASE WHEN o.data->>'DEFAULT_LANGUAGE'='en' THEN 'en' ELSE 'cs' END),
   'measurement-approval:'||p_unit||':'||a.id||CASE WHEN request_revision=1 THEN '' ELSE ':'||request_revision END,'MEASUREMENT_APPROVAL_REQUEST',now(),now()+interval '30 days');
  UPDATE public.email_messages SET tracking_policy='disabled' WHERE message_id=(msg->>'message_id')::uuid;
  sent:=sent+1;
 END LOOP;
 -- Nobody could be notified: roll back the request so it stays retryable.
 IF sent=0 THEN RAISE EXCEPTION 'measurement_request_no_recipient'; END IF;
 RETURN public.unit_measurement_approval_internal(p_unit);
END $$;
REVOKE ALL ON FUNCTION public.request_unit_measurement_approval(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.request_unit_measurement_approval(bigint) TO authenticated;
