-- Draft-scoped read projection. No caller-provided hierarchy or template ID is accepted.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_email_preview(
 p_id uuid,p_expected_revision bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; unit_data jsonb; resolved jsonb; copied jsonb;
 source_id bigint; tone text; reply_to text;
 template_code text; templates jsonb:='[]'; overrides jsonb; effective jsonb;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR
   public.can_create_occasion(d.unit) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN
  RAISE serialization_failure USING MESSAGE='Draft revision conflict'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft is finalized'; END IF;
 SELECT data INTO unit_data FROM public.units WHERE id=d.unit AND organization=d.organization;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='Draft hierarchy denied'; END IF;
 tone:=coalesce(nullif(nullif(d.data->>'communicationTone',''),'inherit'),CASE WHEN unit_data->>'communication_tone'='informal' THEN 'informal' ELSE 'formal' END);
 IF tone NOT IN ('formal','informal') THEN RAISE invalid_parameter_value USING MESSAGE='Invalid tone'; END IF;
 IF coalesce(d.data->>'replyToMode','inherit') NOT IN ('inherit','custom') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid reply mode'; END IF;
 reply_to:=CASE WHEN d.data->>'replyToMode'='custom' THEN btrim(d.data->>'replyToEmail') ELSE unit_data->>'reply_to' END;
 IF d.data->>'replyToMode'='custom' AND nullif(reply_to,'') IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid reply address'; END IF;
 IF reply_to IS NOT NULL AND (length(reply_to)>254 OR reply_to !~ '^[^[:space:]<>@]+@[^[:space:]<>@]+[.][^[:space:]<>@]+$') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid reply address'; END IF;
 -- Finalization copies occasion templates only. An inherited source template or
 -- source wrapper must not replace the destination hierarchy in this preview.
 IF coalesce((d.data->>'copyEmails')::boolean,false) AND nullif(d.data->>'sourceId','') IS NOT NULL THEN
  source_id:=(d.data->>'sourceId')::bigint;
  IF NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(
   SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization) THEN
   RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
 END IF;
 overrides:=public.validate_setup_email_templates_internal(d.data->'emailTemplateOverrides');
 FOREACH template_code IN ARRAY ARRAY['TICKET_ORDER_CONFIRMATION','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER','TICKET_ORDER_STORNO','TICKET_ORDER_UPDATE'] LOOP
  effective:=public.get_email_template_and_wrapper(template_code,jsonb_build_object('unit',d.unit,'organization',d.organization));
  IF source_id IS NOT NULL THEN
   SELECT to_jsonb(t) INTO copied FROM public.email_templates t
   WHERE t.occasion=source_id AND t.code=template_code ORDER BY t.id DESC LIMIT 1;
   IF copied IS NOT NULL THEN effective:=jsonb_set(effective,'{template}',copied); END IF;
  END IF;
  IF overrides ? template_code THEN
   effective:=jsonb_set(effective,'{template}',coalesce(effective->'template','{}')||(overrides->template_code));
  END IF;
  templates:=templates||jsonb_build_array(jsonb_build_object('code',template_code,
   'template',effective->'template','customized',overrides ? template_code));
  IF template_code='TICKET_ORDER_CONFIRMATION' THEN resolved:=effective; END IF;
 END LOOP;
 RETURN jsonb_build_object('revision',d.revision,'title',coalesce(nullif(d.data->>'title',''),'Ukázková událost'),
  'tone',tone,'replyTo',reply_to,'resolved',resolved,
  'emailTemplates',templates,'emailScope',jsonb_build_object(
   'unit',jsonb_build_object('id',d.unit,'title',(SELECT title FROM public.units WHERE id=d.unit)),
   'organization',jsonb_build_object('id',d.organization,'title',(SELECT title FROM public.organizations WHERE id=d.organization))),
  'deadlineDurationSeconds',coalesce(nullif(d.data#>>'{formDraft,deadline_duration_seconds}','')::numeric,nullif(d.data->>'deadline','')::numeric*86400),
  'paymentInfo',(SELECT jsonb_build_object('account_number',b.account_number,
    'account_number_human_readable',coalesce(nullif(b.account_number_human_readable,''),b.account_number))
    FROM eshop.unit_bank_accounts u JOIN eshop.bank_accounts b ON b.id=u.bank_account
    WHERE u.unit=d.unit AND b.id::text=d.data->>'bankAccountId' AND b.type<>'CASH'),
  'ticketsEnabled',coalesce((d.data->>'formEnabled')::boolean,true) AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) f WHERE f->>'type'='ticket' AND NOT coalesce((f->>'is_hidden')::boolean,false)),
  'sampleProducts',coalesce((SELECT jsonb_agg(p) FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) f CROSS JOIN LATERAL (SELECT p FROM jsonb_array_elements(coalesce(f#>'{product_type_data,products}','[]')) p WHERE NOT coalesce((p->>'is_hidden')::boolean,false) LIMIT 1) products(p) WHERE NOT coalesce((f->>'is_hidden')::boolean,false)),'[]'::jsonb),
  'has_custom_template',coalesce((overrides ? 'TICKET_ORDER_CONFIRMATION') OR (resolved->'template'->>'occasion') IS NOT NULL
    OR (resolved->'template'->>'unit') IS NOT NULL OR (resolved->'template'->>'organization') IS NOT NULL,false));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint) TO authenticated;
