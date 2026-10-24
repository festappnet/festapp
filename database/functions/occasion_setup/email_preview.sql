-- Retire the earlier two-argument overload before adding defaulted preview options.
DROP FUNCTION IF EXISTS public.get_occasion_setup_email_preview(uuid,bigint);
-- Draft-scoped read projection. No caller-provided hierarchy or template ID is accepted.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_email_preview(
 p_id uuid,p_expected_revision bigint,p_tone text,p_reply_to text,
 p_message_type text,p_occasion bigint,p_delivery_mode text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; unit_data jsonb; resolved jsonb; copied jsonb;
 source_id bigint; tone text; reply_to text; template_code text; o public.occasions;
BEGIN
 IF p_message_type NOT IN ('order_confirmation','order_tickets') OR p_message_type IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid preview message type'; END IF;
 template_code:=CASE p_message_type WHEN 'order_tickets' THEN 'TICKET_ORDER_PAYMENT_DONE' ELSE 'TICKET_ORDER_CONFIRMATION' END;
 IF p_occasion IS NOT NULL THEN
  IF p_id IS NOT NULL OR auth.uid() IS NULL OR NOT public.can_edit_ticket_layout(p_occasion) THEN
   RAISE insufficient_privilege USING MESSAGE='Occasion preview denied'; END IF;
  SELECT * INTO o FROM public.occasions WHERE id=p_occasion;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='Occasion preview denied'; END IF;
  d.unit:=o.unit; d.organization:=o.organization;
  d.data:=jsonb_build_object('title',o.title,'replyTo',o.data->>'reply_to','ticketDraft',
    (SELECT f FROM jsonb_array_elements(o.features) f WHERE f->>'code'='ticket'));
 ELSE
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT
   (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN
  RAISE serialization_failure USING MESSAGE='Draft revision conflict'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft is finalized'; END IF;
 END IF;
 SELECT data INTO unit_data FROM public.units WHERE id=d.unit AND organization=d.organization;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='Draft hierarchy denied'; END IF;
 tone:=coalesce(p_tone,nullif(nullif(d.data->>'communicationTone',''),'inherit'),unit_data->>'communication_tone','formal');
 IF tone NOT IN ('formal','informal') THEN RAISE invalid_parameter_value USING MESSAGE='Invalid tone'; END IF;
 reply_to:=coalesce(nullif(btrim(coalesce(p_reply_to,d.data->>'replyTo')),''),nullif(btrim(unit_data->>'reply_to'),''));
 IF reply_to IS NOT NULL AND (length(reply_to)>254 OR reply_to !~ '^[^[:space:]<>@]+@[^[:space:]<>@]+[.][^[:space:]<>@]+$') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid reply address'; END IF;
 resolved:=public.get_email_template_and_wrapper(template_code,
  jsonb_build_object('unit',d.unit,'organization',d.organization,'occasion',p_occasion));
 -- Finalization copies occasion templates only. An inherited source template or
 -- source wrapper must not replace the destination hierarchy in this preview.
 IF coalesce((d.data->>'copyEmails')::boolean,false) AND nullif(d.data->>'sourceId','') IS NOT NULL THEN
  source_id:=(d.data->>'sourceId')::bigint;
  IF NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(
   SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization) THEN
   RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
  SELECT to_jsonb(t) INTO copied FROM public.email_templates t
   WHERE t.occasion=source_id AND t.code=template_code ORDER BY t.id DESC LIMIT 1;
  IF copied IS NOT NULL THEN resolved:=jsonb_set(resolved,'{template}',copied); END IF;
 END IF;
 IF p_delivery_mode IS NOT NULL THEN
  PERFORM public.ticket_delivery_mode(jsonb_build_object('delivery_mode',p_delivery_mode)); END IF;
 RETURN jsonb_build_object('messageType',p_message_type,'deliveryMode',coalesce(p_delivery_mode,public.ticket_delivery_mode(d.data->'ticketDraft')),
  'ticketEnabled',coalesce((d.data#>>'{ticketDraft,is_enabled}')::boolean,false),'occasion',to_jsonb(o),
  'sampleProducts',CASE WHEN p_occasion IS NOT NULL THEN public.get_products_and_types(p_occasion)::jsonb ELSE
    jsonb_build_object('product_types',coalesce((SELECT jsonb_agg(t || jsonb_build_object('occasion',0)) FROM
      (SELECT coalesce(f->'product_type_data',f->'product_type') t FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) f) x WHERE jsonb_typeof(t)='object'),'[]'::jsonb),
     'products',coalesce((SELECT jsonb_agg(p || jsonb_build_object('product_type',(t->>'id')::bigint)) FROM
       (SELECT coalesce(f->'product_type_data',f->'product_type') t FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) f) x
        CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'products','[]')) p WHERE jsonb_typeof(t)='object'),'[]'::jsonb)) END,
  'ticketFeature',d.data->'ticketDraft','revision',d.revision,'title',coalesce(nullif(d.data->>'title',''),'Ukázková událost'),
  'tone',tone,'replyTo',reply_to,'resolved',resolved,
  'has_custom_template',coalesce((resolved->'template'->>'occasion') IS NOT NULL
    OR (resolved->'template'->>'unit') IS NOT NULL OR (resolved->'template'->>'organization') IS NOT NULL,false));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,text,text,bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,text,text,bigint,text) TO authenticated;

-- Preserve the existing confirmation-preview contract and ACL.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_email_preview(
 p_id uuid,p_expected_revision bigint,p_tone text DEFAULT NULL,p_reply_to text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.get_occasion_setup_email_preview(p_id,p_expected_revision,p_tone,p_reply_to,'order_confirmation',NULL,NULL);
$$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,text) TO authenticated;
