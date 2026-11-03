-- Reuse the existing notification log and its UUID. No queue or sender is added.
-- Only canonical stored content can reach the existing signed webhook adapter.
CREATE OR REPLACE FUNCTION public.charge_notification_intent_v1(p_occasion bigint,p_actor uuid,p_to jsonb,p_heading text,p_content text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o public.occasions; policy jsonb; cap bigint; targets bigint; recipients jsonb;
BEGIN
 SELECT * INTO STRICT o FROM public.occasions WHERE id=p_occasion;
 policy:=public.abuse_effective_rules_v1('push.delivery',o.unit,o.organization);
 SELECT (r->>'base_limit')::bigint INTO cap FROM jsonb_array_elements(policy->'rules') r WHERE r->>'rule_key'='push.delivery.targets';
 IF cap IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 IF p_to IS NOT NULL AND p_to<>'null'::jsonb THEN
  recipients:=CASE jsonb_typeof(p_to) WHEN 'array' THEN p_to WHEN 'string' THEN jsonb_build_array(p_to) ELSE NULL END;
  IF recipients IS NULL OR jsonb_array_length(recipients)=0 OR jsonb_array_length(recipients)>cap THEN RAISE invalid_parameter_value USING MESSAGE='invalid notification recipients'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(recipients) r WHERE NOT EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=o.id AND ou."user"::text=r)) THEN
   RAISE insufficient_privilege USING MESSAGE='notification recipient outside occasion'; END IF;
  SELECT count(DISTINCT r) INTO targets FROM jsonb_array_elements_text(recipients) r;
 ELSE
  SELECT count(*) INTO targets FROM (SELECT 1 FROM public.occasion_users WHERE occasion=o.id LIMIT cap+1) audience;
 END IF;
 PERFORM public.abuse_charge_v1(policy,jsonb_build_object('actor',p_actor,'unit',o.unit,'organization',o.organization,'global','all'),
  jsonb_build_object('push.targets.unit.day',targets,'push.targets.organization.day',targets,'push.targets.global.day',targets,
   'push.delivery.targets',targets,'push.payload.bytes',octet_length(jsonb_build_object('heading',p_heading,'content',p_content,'to',p_to)::text),'push.delivery.age.seconds',0));
END $$;
REVOKE ALL ON FUNCTION public.charge_notification_intent_v1(bigint,uuid,jsonb,text,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.enqueue_notification_v1(p_occasion bigint,p_heading text,p_content text,p_to jsonb DEFAULT NULL,p_data jsonb DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE notification uuid;
BEGIN
 IF auth.uid() IS NULL OR public.get_is_editor_on_occasion(p_occasion) IS DISTINCT FROM true THEN RAISE insufficient_privilege USING MESSAGE='notification editor required'; END IF;
 IF p_data IS NOT NULL AND (jsonb_typeof(p_data)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_data) k WHERE k<>'path')
  OR coalesce(p_data->>'path','news') NOT IN ('news','cleaning')) THEN RAISE invalid_parameter_value USING MESSAGE='invalid notification data'; END IF;
 PERFORM public.charge_notification_intent_v1(p_occasion,auth.uid(),p_to,p_heading,p_content);
 INSERT INTO public.log_notifications(occasion,organization,user_id,"to",heading,content,data,abuse_admitted_at)
 SELECT p_occasion,organization,auth.uid(),p_to,p_heading,p_content,p_data,statement_timestamp() FROM public.occasions WHERE id=p_occasion RETURNING id INTO notification;
 PERFORM public.dispatch_log_notification_v1(notification);
 RETURN notification;
END $$;
REVOKE ALL ON FUNCTION public.enqueue_notification_v1(bigint,text,text,jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enqueue_notification_v1(bigint,text,text,jsonb,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.admit_notification_delivery_v1(p_notification uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE n public.log_notifications; o public.occasions; policy jsonb; max_age bigint;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO n FROM public.log_notifications WHERE id=p_notification FOR UPDATE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='notification unavailable'; END IF;
 SELECT * INTO STRICT o FROM public.occasions WHERE id=n.occasion;
 IF n.organization IS DISTINCT FROM o.organization THEN RAISE insufficient_privilege USING MESSAGE='notification scope mismatch'; END IF;
 policy:=public.abuse_effective_rules_v1('push.delivery',o.unit,o.organization);
 SELECT (r->>'base_limit')::bigint INTO max_age FROM jsonb_array_elements(policy->'rules') r WHERE r->>'rule_key'='push.delivery.age.seconds';
 IF max_age IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 IF n.created_at>statement_timestamp() OR n.created_at<statement_timestamp()-make_interval(secs=>max_age::integer) THEN
  RAISE invalid_parameter_value USING MESSAGE='notification expired'; END IF;
 IF n.abuse_admitted_at IS NULL THEN
  PERFORM public.charge_notification_intent_v1(n.occasion,n.user_id,n."to",n.heading,n.content);
  UPDATE public.log_notifications SET abuse_admitted_at=statement_timestamp() WHERE id=n.id;
 END IF;
 IF NOT public.abuse_charge_v1(public.abuse_effective_rules_v1('push.dispatch',o.unit,o.organization),jsonb_build_object('unit',o.unit,'global','all'),'{}',true) THEN RETURN jsonb_build_object('allowed',false); END IF;
 RETURN to_jsonb(n)||jsonb_build_object('occasion_link',o.link,'allowed',true);
END $$;
REVOKE ALL ON FUNCTION public.admit_notification_delivery_v1(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admit_notification_delivery_v1(uuid) TO service_role;

-- Current clients use enqueue_notification_v1; REST INSERT cannot silently
-- depend on a row trigger for delivery or run admission from an RLS predicate.
DROP POLICY IF EXISTS "Enable insert for editors" ON public.log_notifications;
REVOKE INSERT ON public.log_notifications FROM PUBLIC,anon,authenticated;
REVOKE INSERT(occasion,organization,"to",heading,content,data) ON public.log_notifications FROM PUBLIC,anon,authenticated;
