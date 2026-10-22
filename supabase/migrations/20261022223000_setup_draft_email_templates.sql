BEGIN;
-- The installed finalizer was verified against the preceding canonical body.
-- Refuse an unexpected live definition instead of replacing unrelated changes.
DO $$
BEGIN
 IF (SELECT md5(btrim(prosrc,E' \n\r\t')) FROM pg_proc
     WHERE oid='public.finalize_occasion_setup_draft(uuid,bigint,uuid)'::regprocedure)
    NOT IN ('53f85694372ac68f11e0f5ff1413e0bc','7f4850898ef74a2901a0b1088fc2f880') THEN
  RAISE EXCEPTION 'Unexpected setup finalizer revision';
 END IF;
END $$;
-- Draft overrides cannot target another hierarchy or arbitrary template codes.
CREATE OR REPLACE FUNCTION public.validate_setup_email_templates_internal(p_templates jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:=coalesce(p_templates,'{}'); item record;
BEGIN
 IF jsonb_typeof(result)<>'object' OR octet_length(result::text)>196608 THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid draft email templates'; END IF;
 FOR item IN SELECT * FROM jsonb_each(result) LOOP
  IF item.key NOT IN ('TICKET_ORDER_CONFIRMATION','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER','TICKET_ORDER_STORNO','TICKET_ORDER_UPDATE')
    OR jsonb_typeof(item.value)<>'object' THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid draft email template'; END IF;
  IF jsonb_typeof(item.value->'subject') IS DISTINCT FROM 'string'
    OR jsonb_typeof(item.value->'html') IS DISTINCT FROM 'string'
    OR length(item.value->>'subject')>2000 OR octet_length(item.value->>'html')>65536
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(item.value) k WHERE k NOT IN ('subject','html')) THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid draft email template'; END IF;
 END LOOP;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.validate_setup_email_templates_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

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

-- Materialize the private configuration exactly once. Provisional draft IDs and
-- source product IDs are never accepted as IDs in the new aggregate.
CREATE OR REPLACE FUNCTION public.finalize_occasion_setup_draft(p_id uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE policies jsonb; d public.occasion_setup_drafts; payload jsonb; config jsonb; features jsonb := '[]';
 started jsonb; receipt jsonb; new_id bigint; form_id bigint; form_data jsonb; fields jsonb := '[]';
 field jsonb; pt jsonb; products jsonb; product jsonb; result jsonb; source_id bigint; configuration_source bigint;
 old_products jsonb := '[]'; old_types jsonb := '[]'; type_map jsonb := '{}'; final_features jsonb; new_products jsonb; product_map jsonb := '{}'; idx integer; j integer;
 intro_image text; form_link text; selected_bank bigint; bank_fingerprint text; bank_currencies text[]; required_currencies text[]; wave jsonb; target jsonb; saved_wave jsonb; wave_product bigint;
 has_tickets boolean;
 unit_defaults jsonb; communication_new boolean; reply_email text; form_meta jsonb; reminder_days numeric;
 sale_mode text; sale_start timestamptz; sale_end timestamptz;
 blueprint_mode text; blueprint_id bigint; blueprint_source bigint; v_commit public.client_commits%ROWTYPE;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.data ? 'finalizeResponse' THEN RETURN d.data->'finalizeResponse'; END IF;
 started := public.begin_unit_client_mutation_v1(p_command_id,'occasion.setup.finalize',d.unit,auth.uid(),
  encode(extensions.digest(convert_to(jsonb_build_object('draft',p_id,'revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex'));
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN RAISE serialization_failure USING MESSAGE='Draft changed in another session'; END IF;
 payload := public.normalize_occasion_setup_appearance_internal(d.data);
 blueprint_mode:=CASE payload->>'blueprintMode'
  WHEN 'Bez plánku' THEN 'none' WHEN 'Nový' THEN 'new' WHEN 'Převzít' THEN 'copy'
  ELSE payload->>'blueprintMode' END;
 IF blueprint_mode IS NULL THEN blueprint_mode:=CASE WHEN jsonb_typeof(payload->'blueprintLayoutDraft')='object' THEN 'copy' ELSE 'none' END; END IF;
 IF blueprint_mode NOT IN ('none','new','copy') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid blueprint mode'; END IF;
 -- The form owns its sale window. Absent intent keeps historical drafts closed.
 sale_mode:=coalesce(payload->>'saleMode','preparation');
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN
  IF sale_mode NOT IN ('preparation','scheduled','immediate') THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid sale mode'; END IF;
  sale_end:=coalesce(nullif(payload->>'saleEnd','')::timestamptz,(payload->>'end')::timestamptz);
  IF sale_end IS NULL OR sale_end>(payload->>'end')::timestamptz THEN
   RAISE invalid_parameter_value USING MESSAGE='Sale must end no later than the event'; END IF;
  IF sale_mode='scheduled' THEN
   sale_start:=nullif(payload->>'saleStart','')::timestamptz;
   IF sale_start IS NULL OR sale_start<=clock_timestamp() OR sale_start>=sale_end THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid scheduled sale start'; END IF;
  ELSIF sale_mode='immediate' THEN
   IF sale_end<=clock_timestamp() THEN RAISE invalid_parameter_value USING MESSAGE='Sale has already ended'; END IF;
   sale_start:=clock_timestamp();
  END IF;
 END IF;
 PERFORM public.validate_setup_email_templates_internal(payload->'emailTemplateOverrides');
 communication_new:=payload ? 'communicationTone';
 IF communication_new THEN
  IF coalesce(payload->>'communicationTone','') NOT IN ('inherit','formal','informal')
    OR coalesce(payload->>'replyToMode','') NOT IN ('inherit','custom')
    OR coalesce(payload->>'remindersMode','') NOT IN ('inherit','enabled','disabled') THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid communication options'; END IF;
  IF payload->>'replyToMode'='custom' THEN
   reply_email:=btrim(payload->>'replyToEmail');
   IF reply_email IS NULL OR length(reply_email)>254 OR reply_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid reply email'; END IF;
  END IF;
  SELECT coalesce(u.data,'{}'::jsonb) INTO unit_defaults FROM public.units u WHERE u.id=d.unit;
 END IF;
 source_id := (payload->>'sourceId')::bigint;
 intro_image:=nullif(payload->>'introImage','');
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
  RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 FOREACH configuration_source IN ARRAY ARRAY[nullif(payload->>'formSourceOccasionId','')::bigint,nullif(payload->>'blueprintSourceOccasionId','')::bigint] LOOP
  IF configuration_source IS NOT NULL AND (NOT public.can_copy_occasion_source(configuration_source) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=configuration_source AND organization=d.organization)) THEN
   RAISE insufficient_privilege USING MESSAGE='Configuration source denied'; END IF;
 END LOOP;
 -- A plan can be selected independently of the event/form copy. Resolve its
 -- resource scope from the stored plan, rather than the overall copy source.
 IF blueprint_mode='copy' THEN
  IF nullif(payload->>'blueprintSourceId','') IS NOT NULL THEN
   SELECT occasion INTO blueprint_source FROM eshop.blueprints WHERE id=(payload->>'blueprintSourceId')::bigint;
   IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='Blueprint source missing'; END IF;
  ELSE
   blueprint_source:=coalesce(nullif(payload->>'blueprintSourceOccasionId','')::bigint,
     nullif(payload->>'formSourceOccasionId','')::bigint,source_id);
  END IF;
  IF blueprint_source IS NOT NULL AND (NOT public.can_copy_occasion_source(blueprint_source)
    OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=blueprint_source AND organization=d.organization)) THEN
   RAISE insufficient_privilege USING MESSAGE='Configuration source denied'; END IF;
 END IF;
 IF nullif(btrim(payload->>'title'),'') IS NULL OR (payload->>'reviewConfirmed')::boolean IS DISTINCT FROM true THEN
  RAISE invalid_parameter_value USING MESSAGE='Draft review required'; END IF;
 IF (payload->>'end')::timestamptz < (payload->>'start')::timestamptz THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid event dates'; END IF;
 -- Draft uploads use the existing unit-scoped image writer. Never trust an
 -- arbitrary URL supplied by a client, or adopt another unit's image.
 IF intro_image IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.images WHERE link=intro_image AND unit=d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft image access denied'; END IF;
 IF coalesce((payload->>'isPromoted')::boolean,false) AND intro_image IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='Promotion requires an intro image'; END IF;
 -- Selection is sufficient; current permissions, currencies and account
 -- fingerprint are still verified under locks before materialization.
 SELECT array_agg(DISTINCT coalesce(nullif(p->>'currency_code',''),'CZK')) INTO required_currencies
 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(f#>'{product_type_data,products}','[]')) p
 WHERE coalesce((payload->>'formEnabled')::boolean,true) AND NOT coalesce((f->>'is_hidden')::boolean,false)
   AND NOT coalesce((p->>'is_hidden')::boolean,false) AND (p->>'price')::numeric>0;
 IF required_currencies IS NOT NULL AND (payload ? 'bankAccountId' OR payload ? 'bankAccountConfirmed') THEN
  IF nullif(payload->>'bankAccountId','') IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='Bank account selection required'; END IF;
  selected_bank:=(payload->>'bankAccountId')::bigint;
  PERFORM 1 FROM eshop.bank_accounts ba JOIN eshop.unit_bank_accounts u ON u.bank_account=ba.id
   WHERE u.unit=d.unit AND ba.id=selected_bank AND ba.type<>'CASH' FOR SHARE OF ba,u;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='Bank account access denied'; END IF;
  -- Take a fresh statement snapshot after acquiring locks: a concurrent account
  -- update may have committed while the locking statement was waiting.
  SELECT ba.supported_currencies,public.occasion_setup_bank_fingerprint_internal(ba.id)
   INTO bank_currencies,bank_fingerprint FROM eshop.bank_accounts ba WHERE ba.id=selected_bank;
  IF bank_currencies IS NULL OR NOT required_currencies <@ bank_currencies THEN
   RAISE invalid_parameter_value USING MESSAGE='Bank account currency mismatch'; END IF;
  IF bank_fingerprint IS DISTINCT FROM payload->>'bankAccountFingerprint' THEN
   RAISE serialization_failure USING MESSAGE='Bank account details changed; select again'; END IF;
 END IF;
 -- Active form choices own enabled features, not whether an editor was visited.
 has_tickets:=coalesce((payload->>'formEnabled')::boolean,true) AND EXISTS(
  SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
  WHERE f->>'type'='ticket' AND NOT coalesce((f->>'is_hidden')::boolean,false));
 IF has_tickets THEN
  features:=features||jsonb_build_array((coalesce(nullif(payload->'ticketDraft','null'::jsonb),'{}'::jsonb)-'layout')
    ||'{"code":"ticket","is_enabled":true}'::jsonb);
 END IF;
 IF blueprint_mode<>'none' AND (
  NOT coalesce((payload->>'formEnabled')::boolean,true) OR
  NOT EXISTS(
   SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,seatBindings}','[]')) binding
   JOIN jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,layout,nodes}','[]')) node ON node->>'id'=binding->>'nodeId'
   WHERE node->>'kind'='seat' AND binding->>'productId' IS NOT NULL AND NOT coalesce((binding->>'blocked')::boolean,false)
   UNION ALL
   SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,areaBindings}','[]')) binding
   JOIN jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,layout,nodes}','[]')) node ON node->>'id'=binding->>'nodeId'
   WHERE node->>'kind'='capacityArea' AND binding->>'productId' IS NOT NULL
    AND (binding->>'inventoryContextId' IS NOT NULL OR coalesce((binding->>'capacity')::numeric,0)>0)
  )) THEN RAISE invalid_parameter_value USING MESSAGE='Selected blueprint requires a form and sellable places'; END IF;
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN
  features := features || jsonb_build_array(jsonb_build_object('code','form','is_enabled',true) ||
    CASE WHEN communication_new THEN jsonb_build_object(
      'reminder_is_enabled',coalesce((unit_defaults->>'is_reminder_enabled')::boolean,true),
      'reminder_interval_seconds',coalesce((unit_defaults->>'reminder_interval_seconds')::bigint,86400)) ELSE '{}'::jsonb END);
 END IF;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN features := features || '[{"code":"schedule","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN features := features || '[{"code":"information","is_enabled":true}]'; END IF;
 config := jsonb_build_object('unit',d.unit,'organization',d.organization,
  'title',payload->>'title','link',payload->>'link','description',coalesce(payload->>'description',''),
  'start_time',payload->>'start','end_time',payload->>'end','is_hidden',true,'is_open',false,
  'is_promoted',coalesce((payload->>'isPromoted')::boolean,false),
  'features',features,'data',jsonb_strip_nulls(jsonb_build_object('client_sync_v1',false,
   'setup_listing_intent',coalesce((payload->>'listPubliclyOnPublish')::boolean,true),
   'image',intro_image,'place_name',nullif(btrim(payload->>'placeName'),''),'reply_to',reply_email)));
 policies:=public.abuse_policy_bundle_v1(ARRAY['occasion.creation','occasion.copy'],d.unit,d.organization);
 IF source_id IS NOT NULL AND (coalesce((payload->>'copyProgram')::boolean,false) OR coalesce((payload->>'copyInformation')::boolean,false) OR coalesce((payload->>'copyEmails')::boolean,false)) THEN
  PERFORM public.admit_occasion_copy_v1(source_id,d.unit,d.organization,policies->'occasion.copy'); END IF;
 PERFORM public.admit_occasion_creation_v1(auth.uid(),d.unit,d.organization,NULL,policies->'occasion.creation');
 PERFORM public.update_occasion_internal_v1(config);
 new_id := currval(pg_get_serial_sequence('public.occasions','id'));
 SELECT o.features INTO features FROM public.occasions o WHERE o.id=new_id;
 INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor,is_editor_view,is_editor_order,is_editor_order_view)
 VALUES(new_id,auth.uid(),true,true,true,true,true);
 form_data := payload->'formDraft';
 IF form_data IS NOT NULL AND form_data<>'null'::jsonb AND coalesce((payload->>'formEnabled')::boolean,true) THEN
  IF communication_new THEN
   -- Semantic choices override legacy source metadata. Inherited values stay
   -- absent so reply/tone remain live unit defaults; reminder defaults above
   -- are a creation snapshot and never requeue existing events.
   form_meta:=coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)
     -'communication_tone'-'is_reminder_enabled'-'reminder_interval_seconds';
   IF payload->>'communicationTone'<>'inherit' THEN
    form_meta:=form_meta||jsonb_build_object('communication_tone',payload->>'communicationTone'); END IF;
   IF required_currencies IS NOT NULL THEN
    IF payload->>'remindersMode'<>'inherit' THEN
     form_meta:=form_meta||jsonb_build_object('is_reminder_enabled',payload->>'remindersMode'='enabled'); END IF;
    IF nullif(btrim(payload->>'reminderLeadDays'),'') IS NOT NULL THEN
     reminder_days:=replace(payload->>'reminderLeadDays',',','.')::numeric;
     IF reminder_days<0 OR reminder_days::text IN ('NaN','Infinity','-Infinity') THEN
      RAISE invalid_parameter_value USING MESSAGE='Invalid reminder interval'; END IF;
     form_meta:=form_meta||jsonb_build_object('reminder_interval_seconds',round(reminder_days*86400)::bigint);
    END IF;
   END IF;
   form_data:=jsonb_set(form_data,'{data}',form_meta);
  END IF;
  -- Explicit values also clear dates inherited from a source/default form.
  form_meta:=coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)
    -'start_time'-'end_time'-'enable_countdown';
  form_meta:=jsonb_set(form_meta,'{schedule}',coalesce(nullif(form_meta->'schedule','null'::jsonb),'{}'::jsonb)
   ||jsonb_build_object('start_time',sale_start,'end_time',sale_end,
     'enable_countdown',coalesce((payload->>'saleCountdown')::boolean,false),
     'sale_preparation',sale_mode='preparation'));
  form_data:=jsonb_set(form_data,'{data}',form_meta);
  SELECT id INTO form_id FROM public.forms WHERE occasion=new_id ORDER BY id LIMIT 1;
  IF form_id IS NULL THEN
   result := public.create_form_internal_v1(new_id,NULL,form_data->>'title'); form_id := (result->>'id')::bigint;
  END IF;
  form_link:=nullif(form_data->>'link','');
  IF source_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.forms source_form WHERE source_form.occasion=source_id AND source_form.link=form_link) THEN
   form_link:=(SELECT link FROM public.forms WHERE id=form_id);
  END IF;
  IF coalesce((payload->>'formLinkAutomatic')::boolean,false) THEN
   FOR j IN 1..20 LOOP
    -- Preserve the preview where still free; re-suggest if another writer won.
    IF form_link IS NULL OR EXISTS(SELECT 1 FROM public.form_link_reservations WHERE slug=form_link AND form IS DISTINCT FROM form_id) THEN
     form_link:=public.suggest_occasion_setup_form_link(p_id,payload->>'title',NULL)->>'suggestion';
    END IF;
    BEGIN
     form_link:=public.reserve_public_link_internal('form',form_id,form_link,false);
     EXIT;
    EXCEPTION WHEN unique_violation THEN
     IF j=20 THEN RAISE; END IF;
     form_link:=NULL;
    END;
   END LOOP;
  END IF;
  DELETE FROM public.form_fields WHERE form=form_id;
  DELETE FROM eshop.products WHERE occasion=new_id;
  DELETE FROM eshop.product_types WHERE occasion=new_id;
  -- Active plan owns the public seat selector. Catalog products remain available without it.
  form_data:=jsonb_set(form_data,'{fields}',coalesce((
   SELECT jsonb_agg(f) FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f
   WHERE f->>'type' IS DISTINCT FROM 'spot'),'[]'::jsonb)||
   CASE WHEN blueprint_mode<>'none' THEN jsonb_build_array('{"order":-1}'::jsonb ||
     coalesce((SELECT f FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f WHERE f->>'type'='spot' LIMIT 1),'{}'::jsonb) ||
     '{"type":"spot","is_ticket_field":true,"is_hidden":false,"is_required":true}'::jsonb) ELSE '[]'::jsonb END);
  -- Every field/product is newly owned by this occasion. Retain a local mapping
  -- for seats that referred to draft/source product IDs.
  FOR field IN SELECT value FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) LOOP
   pt := coalesce(nullif(field->'product_type_data','null'::jsonb),field->'product_type');
   IF jsonb_typeof(pt)<>'object' THEN pt := NULL; END IF;
   field := field - 'id' - 'form' - 'product_type';
   IF pt IS NOT NULL AND pt<>'null'::jsonb THEN
    old_products := old_products || coalesce(pt->'products','[]');
    products := '[]';
    FOR product IN SELECT value FROM jsonb_array_elements(coalesce(pt->'products','[]')) LOOP
     products := products || jsonb_build_array(product-'id'-'occasion'-'product_type');
    END LOOP;
    field := (field-'product_type_data') || jsonb_build_object('product_type',(pt-'id'-'occasion') || jsonb_build_object('products',products));
   END IF;
   old_types := old_types || jsonb_build_array(pt->'id');
   fields := fields || jsonb_build_array(field);
  END LOOP;
  result := public.update_form_internal_v1((form_data-'id'-'fields'-'blueprint'-'bank_account') || jsonb_build_object(
   'id',form_id,'occasion',new_id,'link',coalesce(form_link,(SELECT link FROM public.forms WHERE id=form_id)),
   'is_open',sale_mode<>'preparation','bank_account',selected_bank,'form_fields',fields));
  IF result->>'code'<>'200' THEN RAISE EXCEPTION '%',result; END IF;
  IF jsonb_array_length(old_types)>0 THEN
   FOR idx IN 0..jsonb_array_length(old_types)-1 LOOP
    IF old_types->>idx IS NOT NULL THEN type_map := type_map || jsonb_build_object(old_types->>idx,result->'form_fields'->idx->'product_type'->'id'); END IF;
   END LOOP;
  END IF;
  SELECT coalesce(jsonb_agg(p ORDER BY field_order,product_order),'[]') INTO new_products
  FROM (SELECT p,ff.ordinality field_order,pp.ordinality product_order
   FROM jsonb_array_elements(result->'form_fields') WITH ORDINALITY ff(f,ordinality)
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(ff.f->'product_type'->'products','[]')) WITH ORDINALITY pp(p,ordinality)) x;
  IF jsonb_array_length(old_products)>0 THEN
   FOR idx IN 0..jsonb_array_length(old_products)-1 LOOP
    IF old_products->idx->>'id' IS NOT NULL THEN product_map := product_map || jsonb_build_object(old_products->idx->>'id',new_products->idx->'id'); END IF;
   END LOOP;
  END IF;
  IF blueprint_mode<>'none' THEN
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,seatBindings}','[]')) binding
     WHERE binding->>'productId' IS NULL OR product_map->>(binding->>'productId') IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='Every blueprint seat requires a form product'; END IF;
  IF payload->'blueprintLayoutDraft' IS NOT NULL AND payload->'blueprintLayoutDraft'<>'null'::jsonb THEN
   IF payload#>>'{blueprintLayoutDraft,layout,schemaVersion}'='2' THEN
    PERFORM public.copy_blueprint_text_resources_internal(NULL,d.id,new_id,payload#>'{blueprintLayoutDraft,layout}');
   END IF;
   blueprint_id:=public.materialize_setup_blueprint_layout_internal(payload->'blueprintLayoutDraft',product_map,blueprint_source,new_id,d.unit);
   UPDATE public.forms SET blueprint=blueprint_id WHERE id=form_id;
   features:=features||'[{"code":"blueprint","is_enabled":true}]';
  ELSE
   RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_REQUIRED';
  END IF;
  END IF;
 END IF;
 -- Plans are materialized through the existing price-wave commands, using
 -- newly mapped product IDs. No source IDs or second scheduler escape.
 IF coalesce((payload->>'priceWavesEnabled')::boolean,false) AND coalesce((payload->>'formEnabled')::boolean,true)
   AND EXISTS(SELECT 1 FROM eshop.products p JOIN public.form_fields ff ON ff.product_type=p.product_type
     WHERE p.occasion=new_id AND ff.form=form_id AND NOT coalesce(ff.is_hidden,false)
       AND p.price>0 AND NOT coalesce(p.is_hidden,false)) THEN
  FOR wave IN SELECT value FROM jsonb_array_elements(coalesce(payload->'priceWaves','[]')) LOOP
   saved_wave:=public.create_product_price_wave((SELECT link FROM public.occasions WHERE id=new_id),(wave->>'change_time')::timestamptz);
   FOR target IN SELECT value FROM jsonb_array_elements(coalesce(wave->'targets','[]')) LOOP
    wave_product:=(product_map->>(target->>'product'))::bigint;
    IF wave_product IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='Price wave product missing'; END IF;
    PERFORM public.save_product_wave_target((saved_wave->>'id')::bigint,wave_product,(saved_wave->>'revision')::bigint,
      (target->>'price')::numeric,(target->>'is_hidden')::boolean,NULL,NULL);
   END LOOP;
  END LOOP;
 END IF;
 -- Rebind ticket product-type references only after their new IDs exist.
 IF has_tickets AND payload->'ticketDraft' ? 'layout' THEN
  pt := payload->'ticketDraft'||'{"code":"ticket","is_enabled":true}'::jsonb;
  SELECT jsonb_set(pt,'{layout,templates}',jsonb_object_agg(t.key,
    jsonb_set(t.value,'{elements}',coalesce((SELECT jsonb_agg(CASE WHEN e->>'binding'='productType'
      THEN jsonb_set(e,'{productTypeId}',coalesce(type_map->(e->>'productTypeId'),'null'::jsonb)) ELSE e END ORDER BY n)
      FROM jsonb_array_elements(t.value->'elements') WITH ORDINALITY x(e,n)),'[]'::jsonb))))
   INTO pt FROM jsonb_each(pt->'layout'->'templates') t;
  features := (SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' THEN pt ELSE f END) FROM jsonb_array_elements(features) f);
 END IF;
 PERFORM public.validate_ticket_layout_references(new_id,f->'layout') FROM jsonb_array_elements(features) f WHERE f ? 'layout';
 final_features := features;
 UPDATE public.occasions SET features=final_features WHERE id=new_id;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN
  PERFORM public.materialize_occasion_setup_program_internal(coalesce(payload->'sourceProgram','[]'),new_id,d.unit);
 END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN
  INSERT INTO public.information(occasion,unit,title,description,type,data)
  SELECT new_id,d.unit,i->>'title',i->>'description',i->>'type',i->'data'
  FROM jsonb_array_elements(coalesce(payload->'sourceInformation','[]')) i;
 END IF;
 IF coalesce((payload->>'copyEmails')::boolean,false) AND source_id IS NOT NULL THEN
  INSERT INTO public.email_templates(occasion,unit,organization,code,title,subject,html)
  SELECT new_id,d.unit,d.organization,code,title,subject,html FROM public.email_templates WHERE occasion=source_id;
 END IF;
 PERFORM public.admit_occasion_copy_v1(new_id,d.unit,d.organization,policies->'occasion.copy');
 -- Draft edits override copied/inherited content only on the newly created occasion.
 FOR pt IN SELECT jsonb_build_object('code',key,'content',value)
  FROM jsonb_each(coalesce(payload->'emailTemplateOverrides','{}')) LOOP
  DELETE FROM public.email_templates WHERE occasion=new_id AND code=pt->>'code';
  INSERT INTO public.email_templates(occasion,unit,organization,code,subject,html)
  VALUES(new_id,d.unit,d.organization,pt->>'code',pt#>>'{content,subject}',pt#>>'{content,html}');
 END LOOP;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('occasion','occasion',new_id,new_id::text,1);
 INSERT INTO public.client_commits(unit,actor_id,actor_kind,source,change_class)
 VALUES(d.unit,auth.uid(),'user','occasion.setup.finalize','configuration') RETURNING * INTO v_commit;
 INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
 SELECT v_commit.commit_id,0,'occasion',new_id::text,'insert',left(title,240),ARRAY['aggregate'] FROM public.occasions WHERE id=new_id;
 PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,d.unit);
 receipt := jsonb_build_object('status','applied','code',200,'data',
  jsonb_build_object('occasionId',new_id,'link',(SELECT link FROM public.occasions WHERE id=new_id),
   'formLink',(SELECT link FROM public.forms WHERE id=form_id),'saleMode',sale_mode));
 receipt := public.finish_client_mutation_v1(p_command_id,receipt,v_commit.commit_id);
 UPDATE public.occasion_setup_drafts SET data=data || jsonb_build_object('finalizedOccasion',new_id,'finalizeResponse',receipt),revision=revision+1 WHERE id=p_id;
 RETURN receipt;
END $$;
REVOKE ALL ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) TO authenticated;

COMMIT;
