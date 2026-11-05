-- Queue validity has a purpose-specific branch before the generic no-order path.
CREATE OR REPLACE FUNCTION public.sale_opening_intent_valid_internal(m public.email_messages)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.sale_opening_subscriptions s
 JOIN public.sale_opening_campaigns c ON c.id=s.campaign_id
 JOIN public.forms f ON f.id=c.form_id JOIN public.occasions o ON o.id=f.occasion
 WHERE s.id::text=m.data->>'subscription_id' AND s.version=m.source_version
 AND s.email_normalized=m.recipient AND o.id=m.occasion AND o.organization=m.organization AND o.unit=m.unit
 AND c.phase<>'cancelled' AND NOT public.is_demo_occasion(o.id)
 AND m.message_kind='sale_opening_opened' AND s.state='active' AND c.opened_at IS NOT NULL
 AND c.opened_at+interval '24 hours'>statement_timestamp()
 AND public.get_form_registration_mode_internal(f.id) IN ('regular','blueprint'));
$$;
REVOKE ALL ON FUNCTION public.sale_opening_intent_valid_internal(public.email_messages) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.enqueue_sale_opening_internal(p_subscription uuid,p_kind text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE s public.sale_opening_subscriptions; c public.sale_opening_campaigns; f public.forms; o public.occasions; expires timestamptz;
BEGIN
 SELECT * INTO STRICT s FROM public.sale_opening_subscriptions WHERE id=p_subscription;
 SELECT * INTO STRICT c FROM public.sale_opening_campaigns WHERE id=s.campaign_id;
 SELECT * INTO STRICT f FROM public.forms WHERE id=c.form_id;
 SELECT * INTO STRICT o FROM public.occasions WHERE id=f.occasion;
 IF p_kind<>'sale_opening_opened' THEN RAISE invalid_parameter_value USING MESSAGE='invalid sale opening email kind'; END IF;
 IF c.opened_at IS NULL OR c.phase='cancelled' OR s.state<>'active' OR
  c.opened_at+interval '24 hours'<=clock_timestamp() OR public.get_form_registration_mode_internal(f.id) NOT IN ('regular','blueprint') THEN RETURN; END IF;
 expires:=least(c.opened_at+interval '24 hours',nullif(public.get_effective_form_data(f.id)#>>'{schedule,end_time}','')::timestamptz);
 -- A stable launch key survives retries, resubscription and source changes.
 IF EXISTS(SELECT 1 FROM public.email_messages WHERE organization=o.organization AND message_kind=p_kind
  AND dedupe_key=c.id||':'||s.id||':opened') THEN RETURN; END IF;
 PERFORM public.enqueue_email(p_kind,jsonb_build_object('organization',o.organization,'occasion',o.id,'unit',o.unit),
 s.email_normalized,jsonb_build_object('subscription_id',s.id,'campaign_id',c.id,'lang',s.lang),
 c.id||':'||s.id||':opened',
 p_kind,now(),expires,NULL,s.version);
END $$;
REVOKE ALL ON FUNCTION public.enqueue_sale_opening_internal(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
