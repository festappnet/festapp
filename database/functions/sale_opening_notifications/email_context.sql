CREATE OR REPLACE FUNCTION public.get_sale_opening_email_context(p_message uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; s public.sale_opening_subscriptions; c public.sale_opening_campaigns; f public.forms; o public.occasions;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT m FROM public.email_messages WHERE message_id=p_message AND message_kind ='sale_opening_opened';
 IF NOT public.sale_opening_intent_valid_internal(m) THEN RAISE invalid_parameter_value USING MESSAGE='sale_opening_intent_invalid'; END IF;
 SELECT * INTO STRICT s FROM public.sale_opening_subscriptions WHERE id=(m.data->>'subscription_id')::uuid;
 SELECT * INTO STRICT c FROM public.sale_opening_campaigns WHERE id=s.campaign_id;
 SELECT * INTO STRICT f FROM public.forms WHERE id=c.form_id;
 SELECT * INTO STRICT o FROM public.occasions WHERE id=f.occasion;
 RETURN jsonb_build_object('organization',o.organization,'occasion',o.id,'unit',o.unit,'recipient',s.email_normalized,
  'occasionTitle',o.title,'hasTickets',public.sale_opening_has_tickets_internal(f.id),'formLink',f.link,'lang',s.lang,'tone',public.get_effective_form_data(f.id)->>'communication_tone',
  'webLink',(SELECT data->>'DEFAULT_URL' FROM public.organizations WHERE id=o.organization),
  'replyTo',coalesce(o.data->>'reply_to',(SELECT data->>'reply_to' FROM public.units WHERE id=o.unit)),
  'capabilities',(SELECT jsonb_object_agg(purpose,jsonb_build_object('hash',token_hash,'envelope',envelope))
   FROM public.sale_opening_capabilities WHERE subscription_id=s.id AND source_version=s.version AND revoked_at IS NULL AND expires_at>statement_timestamp()));
END $$;
REVOKE ALL ON FUNCTION public.get_sale_opening_email_context(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_sale_opening_email_context(uuid) TO service_role;
