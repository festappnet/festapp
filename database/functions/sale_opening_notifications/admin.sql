CREATE OR REPLACE FUNCTION public.get_sale_opening_summary(p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occ bigint; c public.sale_opening_campaigns;
BEGIN
 SELECT occasion INTO occ FROM public.forms WHERE id=p_form;
 IF occ IS NULL OR NOT public.can_author_forms(occ) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 SELECT * INTO c FROM public.sale_opening_campaigns WHERE form_id=p_form;
 RETURN jsonb_build_object('phase',c.phase,'openedAt',c.opened_at,
 'subscribers',coalesce((SELECT jsonb_object_agg(state,n) FROM (SELECT state,count(*) n FROM public.sale_opening_subscriptions WHERE campaign_id=c.id GROUP BY state) x),'{}'),
 'messages',coalesce((SELECT jsonb_object_agg(state,n) FROM (SELECT public.email_reporting_state(m) state,count(*) n FROM public.email_messages m
 WHERE m.message_kind='sale_opening_opened' AND m.data->>'campaign_id'=c.id::text GROUP BY public.email_reporting_state(m)) x),'{}'));
END $$;
REVOKE ALL ON FUNCTION public.get_sale_opening_summary(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_sale_opening_summary(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_sale_opening_subscribers(p_form bigint,p_after uuid DEFAULT NULL,p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occ bigint;
BEGIN
 SELECT occasion INTO occ FROM public.forms WHERE id=p_form;
 IF occ IS NULL OR NOT public.can_read_sale_opening_subscribers(occ) THEN RAISE insufficient_privilege USING MESSAGE='subscriber contacts required'; END IF;
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE invalid_parameter_value USING MESSAGE='invalid subscriber page'; END IF;
 RETURN coalesce((SELECT jsonb_agg(row ORDER BY id) FROM (
 SELECT s.id,s.email_normalized email,s.lang,s.state,s.created_at,
  (SELECT jsonb_agg(jsonb_build_object('message_id',m.message_id,'state',public.email_reporting_state(m),'message_kind',m.message_kind) ORDER BY m.created_at DESC)
   FROM public.email_messages m WHERE m.data->>'subscription_id'=s.id::text AND m.message_kind ='sale_opening_opened') messages
 FROM public.sale_opening_subscriptions s JOIN public.sale_opening_campaigns c ON c.id=s.campaign_id
 WHERE c.form_id=p_form AND (p_after IS NULL OR s.id>p_after) ORDER BY s.id LIMIT p_limit) row),'[]');
END $$;
REVOKE ALL ON FUNCTION public.get_sale_opening_subscribers(bigint,uuid,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_sale_opening_subscribers(bigint,uuid,integer) TO authenticated;
