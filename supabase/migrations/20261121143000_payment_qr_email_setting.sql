-- Allow organizers to display the bank payment QR in the body of order emails.

-- SOURCE: eshop_forms/form_settings.sql
-- Metadata patch owner for all administrative form settings. Private helpers;
-- authorization, locking, receipt and side effects stay in the form command.
CREATE OR REPLACE FUNCTION public.form_settings_keys_internal()
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT '{"is_reminder_enabled":null,"reminder_interval_seconds":null,"communication_tone":null,"show_payment_qr_in_email":null,
 "variable_symbol":["type","starting_number"],"payment_message":["type"],
 "payments":["bankEnabled","stripeConnectionId","providerConnections","cashEnabled","cashInstructions"],
 "payment_deadline":["mode"],
 "analytics":["enabled","purchase_timing"],
 "waitlist":["show_count"],
 "design":["embed_inherit_style","is_card_design","primary_color","secondary_color","background_mode","theme_mode","font_family","countdown_style","presale_header"],
 "sale_opening_notifications":["enabled","collection_paused"],
 "schedule":["start_time","end_time","enable_countdown","countdown_title"]}'::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.normalize_form_metadata_internal(p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:='{}'; item jsonb; section jsonb; k text;
BEGIN
 IF p_data IS NULL OR p_data='null'::jsonb THEN RETURN result; END IF;
 IF jsonb_typeof(p_data)='object' THEN result:=p_data;
 ELSIF jsonb_typeof(p_data)='array' THEN
  -- Released readers already normalize historical [null,{metadata}] bundles.
  FOR item IN SELECT value FROM jsonb_array_elements(p_data) LOOP
   IF item='null'::jsonb THEN CONTINUE; END IF;
   IF jsonb_typeof(item)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid form metadata'; END IF;
   result:=result||item;
  END LOOP;
 ELSE RAISE invalid_parameter_value USING MESSAGE='invalid form metadata';
 END IF;
 section:=coalesce(nullif(result->'schedule','null'::jsonb),'{}'::jsonb);
 IF jsonb_typeof(section)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid form schedule'; END IF;
 FOREACH k IN ARRAY ARRAY['start_time','end_time'] LOOP
  -- Match the runtime reader's historical nested/root precedence, then retire
  -- the root alias. Otherwise clearing a nested override resurrects old dates.
  IF (NOT section ? k OR section->k='null'::jsonb) AND result ? k THEN
   section:=section||jsonb_build_object(k,result->k);
  END IF;
  result:=result-k;
  IF section->>k='' THEN section:=section-k;
  ELSIF section->>k IS NOT NULL AND (section->>k) !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' THEN
   -- Interpret released timestamps exactly as the existing runtime did. Emit
   -- an explicit instant for current editors; new patches still require ISO.
   section:=section||jsonb_build_object(k,(section->>k)::timestamptz);
  END IF;
 END LOOP;
 IF section='{}'::jsonb THEN result:=result-'schedule';
 ELSE result:=result||jsonb_build_object('schedule',section); END IF;
 RETURN result;
END $$;

-- Full released-client metadata is translated to the same known-settings patch.
CREATE OR REPLACE FUNCTION public.form_settings_from_metadata_internal(p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:='{}'; d jsonb:=public.normalize_form_metadata_internal(p_data); spec record; k text; section jsonb;
BEGIN
 FOR spec IN SELECT * FROM jsonb_each(public.form_settings_keys_internal()) LOOP
  IF spec.key IN ('payments','sale_opening_notifications','analytics','waitlist','show_payment_qr_in_email') AND NOT d ? spec.key THEN CONTINUE; END IF;
  IF spec.value='null'::jsonb OR NOT d ? spec.key OR d->spec.key='null'::jsonb THEN
   result:=result||jsonb_build_object(spec.key,coalesce(d->spec.key,'null'::jsonb));
  ELSE
   IF spec.key='payments' THEN result:=result||jsonb_build_object(spec.key,d->spec.key); CONTINUE; END IF;
   IF jsonb_typeof(d->spec.key)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid form settings section: '||spec.key; END IF;
   section:='{}';
   FOR k IN SELECT jsonb_array_elements_text(spec.value) LOOP
    IF spec.key<>'analytics' OR (d->spec.key) ? k THEN
     section:=section||jsonb_build_object(k,coalesce(d->spec.key->k,'null'::jsonb));
    END IF;
   END LOOP;
   result:=result||jsonb_build_object(spec.key,section);
  END IF;
 END LOOP;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.apply_form_settings_internal(p_data jsonb,p_patch jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:=public.normalize_form_metadata_internal(p_data); spec jsonb:=public.form_settings_keys_internal();
 entry record; field record; section jsonb; v jsonb; k text; path text; n numeric; starts timestamptz; ends timestamptz;
BEGIN
 IF result ? 'analytics' AND result->'analytics'<>'null'::jsonb AND (jsonb_typeof(result->'analytics')<>'object' OR
   EXISTS(SELECT 1 FROM jsonb_object_keys(result->'analytics') analytics_key WHERE analytics_key NOT IN ('enabled','purchase_timing'))) THEN
  RAISE invalid_parameter_value USING MESSAGE='unsupported analytics setting'; END IF;
 IF p_patch IS NULL OR jsonb_typeof(p_patch)<>'object' OR octet_length(p_patch::text)>131072 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid form settings patch'; END IF;
 FOR entry IN SELECT * FROM jsonb_each(p_patch) LOOP
  IF NOT spec ? entry.key THEN RAISE invalid_parameter_value USING MESSAGE='unsupported form setting: '||entry.key; END IF;
  IF spec->entry.key='null'::jsonb THEN
   IF entry.value='null'::jsonb THEN result:=result-entry.key; CONTINUE; END IF;
   IF entry.key='is_reminder_enabled' AND jsonb_typeof(entry.value)<>'boolean' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid reminder mode'; END IF;
   IF entry.key='show_payment_qr_in_email' AND jsonb_typeof(entry.value)<>'boolean' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid payment QR email setting'; END IF;
   IF entry.key='reminder_interval_seconds' THEN
    IF jsonb_typeof(entry.value)<>'number' THEN RAISE invalid_parameter_value USING MESSAGE='invalid reminder interval'; END IF;
    n:=(entry.value::text)::numeric;
    IF n<>trunc(n) OR n<0 OR n>9007199254740991 THEN RAISE invalid_parameter_value USING MESSAGE='invalid reminder interval'; END IF;
   END IF;
   IF entry.key='communication_tone' AND entry.value NOT IN ('"formal"'::jsonb,'"informal"'::jsonb) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid communication tone'; END IF;
   result:=result||jsonb_build_object(entry.key,entry.value);
   CONTINUE;
  END IF;
  IF entry.value<>'null'::jsonb AND jsonb_typeof(entry.value)<>'object' THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid form settings section: '||entry.key; END IF;
  IF entry.key='payments' THEN
   result:=jsonb_set(result,'{payments}',public.merge_form_payments_internal(result->'payments',entry.value));
   CONTINUE;
  END IF;
  section:=coalesce(nullif(result->entry.key,'null'::jsonb),'{}'::jsonb);
  IF jsonb_typeof(section)<>'object' THEN section:='{}'; END IF;
  FOR field IN
   SELECT * FROM jsonb_each(CASE WHEN entry.value='null'::jsonb THEN
    (SELECT jsonb_object_agg(value,'null'::jsonb) FROM jsonb_array_elements_text(spec->entry.key)) ELSE entry.value END)
  LOOP
   k:=field.key;v:=field.value;path:=entry.key||'.'||k;
   IF NOT (spec->entry.key) ? k THEN RAISE invalid_parameter_value USING MESSAGE='unsupported form setting: '||path; END IF;
   IF v='null'::jsonb THEN section:=section-k;CONTINUE; END IF;
   IF path IN ('waitlist.show_count','analytics.enabled','payments.bankEnabled','design.embed_inherit_style','design.is_card_design','schedule.enable_countdown','sale_opening_notifications.enabled','sale_opening_notifications.collection_paused') THEN
    IF jsonb_typeof(v)<>'boolean' THEN RAISE invalid_parameter_value USING MESSAGE='invalid boolean setting: '||path; END IF;
   ELSIF path='analytics.purchase_timing' THEN
    IF v NOT IN ('"order"'::jsonb,'"paid"'::jsonb) THEN RAISE invalid_parameter_value USING MESSAGE='invalid purchase timing'; END IF;
   ELSIF path='payments.providerConnections' THEN
    IF jsonb_typeof(v)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid provider connections'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_each(v) x WHERE jsonb_typeof(x.value)<>'string' OR NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=x.key AND hosted_checkout)) THEN
     RAISE invalid_parameter_value USING MESSAGE='unknown payment provider'; END IF;
    PERFORM (x.value#>>'{}')::uuid FROM jsonb_each(v) x;
   ELSIF path='variable_symbol.starting_number' THEN
    IF jsonb_typeof(v)<>'number' OR v::text !~ '^[0-9]{1,10}$' OR (v::text)::bigint NOT BETWEEN 1 AND 9999999999 THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid sequence starting number'; END IF;
   ELSE
    IF jsonb_typeof(v)<>'string' THEN RAISE invalid_parameter_value USING MESSAGE='invalid string setting: '||path; END IF;
    IF length(v#>>'{}')>(CASE WHEN path IN ('schedule.countdown_title') THEN 65536 ELSE 128 END) THEN
     RAISE invalid_parameter_value USING MESSAGE='form setting too long: '||path; END IF;
    IF path='payment_deadline.mode' AND v NOT IN ('"inherit"'::jsonb,'"custom"'::jsonb,'"none"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid payment deadline mode'; END IF;
    IF path='variable_symbol.type'  AND v NOT IN ('"random"'::jsonb,'"sequence"'::jsonb) OR
       path='payment_message.type' AND v NOT IN ('"name_surname"'::jsonb,'"none"'::jsonb,'"occasion_title"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid setting mode: '||path; END IF;
    IF path='design.presale_header' AND v NOT IN ('"event_and_date"'::jsonb,'"date"'::jsonb,'"none"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid presale header'; END IF;
    IF path='design.theme_mode'  AND v NOT IN ('"system"'::jsonb,'"light"'::jsonb,'"dark"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid form theme mode'; END IF;
    IF path='design.background_mode' AND v NOT IN ('"solid"'::jsonb,'"gradient"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid background mode'; END IF;
    IF path IN ('design.primary_color','design.secondary_color') AND (v#>>'{}') !~ '^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$' THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid design color'; END IF;
    IF path IN ('design.font_family','design.countdown_style') AND length(btrim(v#>>'{}'))=0 THEN
     RAISE invalid_parameter_value USING MESSAGE='empty design setting'; END IF;
    IF path='payments.stripeConnectionId' THEN PERFORM (v#>>'{}')::uuid; END IF;
    IF path IN ('schedule.start_time','schedule.end_time') THEN
     IF (v#>>'{}') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' THEN
      RAISE invalid_parameter_value USING MESSAGE='schedule requires an ISO instant with explicit timezone'; END IF;
     PERFORM (v#>>'{}')::timestamptz;
    END IF;
   END IF;
   section:=section||jsonb_build_object(k,v);
  END LOOP;
  -- Section reset removes only known authoring keys, preserving lifecycle flags
  -- (sale_preparation) and unrelated metadata owned by other contracts.
  IF section='{}'::jsonb THEN result:=result-entry.key;
  ELSE result:=result||jsonb_build_object(entry.key,section); END IF;
 END LOOP;
 IF p_patch ? 'variable_symbol' AND result#>>'{variable_symbol,type}'='sequence' AND
   (coalesce(result#>>'{variable_symbol,starting_number}','') !~ '^[0-9]{1,10}$' OR
    (result#>>'{variable_symbol,starting_number}')::bigint NOT BETWEEN 1 AND 9999999999) THEN
  RAISE invalid_parameter_value USING MESSAGE='sequence requires starting number'; END IF;
 IF p_patch ? 'schedule' THEN
  starts:=nullif(result#>>'{schedule,start_time}','')::timestamptz;
  ends:=nullif(result#>>'{schedule,end_time}','')::timestamptz;
  IF ends<starts THEN RAISE invalid_parameter_value USING MESSAGE='form sale end precedes start'; END IF;
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.form_settings_keys_internal(),public.normalize_form_metadata_internal(jsonb),
 public.form_settings_from_metadata_internal(jsonb),public.apply_form_settings_internal(jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: occasion_setup/email_preview.sql
-- Draft-scoped read projection. No caller-provided hierarchy or template ID is accepted.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_email_preview(
 p_id uuid,p_expected_revision bigint,p_message_type text,p_occasion bigint,p_delivery_mode text,p_wallet_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; unit_data jsonb; resolved jsonb; copied jsonb;
 email_banner text; inherited_banner text; source_id bigint; tone text; reply_to text;
 payment_metadata jsonb; payment_policy jsonb; payment_method text; payment_info jsonb; payment_duration bigint;
 o public.occasions; selected_code text; feature jsonb; ticket_catalog jsonb; template_code text; templates jsonb:='[]'; overrides jsonb; effective jsonb;
BEGIN
 IF p_message_type IS NULL OR p_message_type NOT IN ('order_confirmation','order_tickets') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid preview message type'; END IF;
 selected_code:=CASE p_message_type WHEN 'order_tickets' THEN 'TICKET_ORDER_PAYMENT_DONE' ELSE 'TICKET_ORDER_CONFIRMATION' END;
 IF p_occasion IS NOT NULL THEN
  IF p_id IS NOT NULL OR auth.uid() IS NULL OR public.can_read_ticket_layout(p_occasion) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='Occasion preview denied'; END IF;
  SELECT * INTO o FROM public.occasions WHERE id=p_occasion;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='Occasion preview denied'; END IF;
  d.unit:=o.unit;d.organization:=o.organization;
  SELECT f INTO feature FROM jsonb_array_elements(o.features) f WHERE f->>'code'='ticket';
  d.data:=jsonb_build_object('title',o.title,'ticketDraft',feature,'communicationTone','inherit',
    'replyToMode',CASE WHEN nullif(o.data->>'reply_to','') IS NULL THEN 'inherit' ELSE 'custom' END,'replyToEmail',o.data->>'reply_to');
  ticket_catalog:=public.get_products_and_types(p_occasion)::jsonb;
 ELSE
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR
   public.can_create_occasion(d.unit) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN
  RAISE SQLSTATE 'PT409' USING MESSAGE='Draft revision conflict'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft is finalized'; END IF;
 END IF;
 SELECT data INTO unit_data FROM public.units WHERE id=d.unit AND organization=d.organization;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='Draft hierarchy denied'; END IF;
 email_banner:=CASE WHEN p_occasion IS NULL THEN d.data->>'emailBanner' END;
 IF nullif(email_banner,'') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.images WHERE link=email_banner AND unit=d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft email banner access denied'; END IF;
 SELECT coalesce(unit_data->>'email_banner',data->>'email_banner') INTO inherited_banner FROM public.organizations WHERE id=d.organization;
 IF nullif(nullif(d.data->>'communicationTone',''),'inherit') IS NOT NULL
  AND public.parse_communication_tone(d.data->>'communicationTone') IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid tone'; END IF;
 tone:=public.resolve_communication_tone(d.data->>'communicationTone',unit_data->>'communication_tone');
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
  effective:=public.get_email_template_and_wrapper(template_code,jsonb_build_object('unit',d.unit,'organization',d.organization,'occasion',p_occasion));
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
  IF template_code=selected_code THEN resolved:=effective; END IF;
 END LOOP;
 IF email_banner IS NOT NULL THEN
  resolved:=jsonb_set(resolved,'{wrapper}',jsonb_build_object('html',
    public.email_banner_wrapper_internal(email_banner,d.data->>'title')));
 END IF;
 feature:=coalesce(feature,d.data->'ticketDraft');
 IF p_delivery_mode IS NOT NULL THEN PERFORM public.ticket_delivery_mode(jsonb_build_object('delivery_mode',p_delivery_mode)); END IF;
 IF ticket_catalog IS NULL THEN
  SELECT jsonb_build_object('product_types',coalesce(jsonb_agg(t||jsonb_build_object('occasion',0)),'[]'::jsonb),
    'products',coalesce((SELECT jsonb_agg(p||jsonb_build_object('product_type',(pt->>'id')::bigint))
       FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) fld
       CROSS JOIN LATERAL (SELECT fld->'product_type_data' pt) x
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(pt->'products','[]')) p),'[]'::jsonb)) INTO ticket_catalog
  FROM (SELECT fld->'product_type_data' t FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) fld WHERE jsonb_typeof(fld->'product_type_data')='object') x;
 END IF;
 -- Preview facts use the same SQL policy owner as real checkout. No draft
 -- preview creates an order, reference or payment attempt.
 payment_metadata:=public.normalize_form_metadata_internal(d.data#>'{formDraft,data}');
 payment_metadata:=payment_metadata||jsonb_build_object('payments',public.normalize_setup_payments_internal(d.data)->'payments');
 payment_method:=CASE WHEN payment_metadata#>'{payments,cashEnabled}'='true'::jsonb THEN 'cash' WHEN payment_metadata#>'{payments,bankEnabled}'='true'::jsonb THEN 'bank' ELSE coalesce((SELECT k FROM jsonb_object_keys(coalesce(payment_metadata#>'{payments,providerConnections}','{}')) k ORDER BY k LIMIT 1),public.resolve_payment_method_policy_internal(d.organization,d.unit)->>'preferredMethod') END;
 payment_duration:=coalesce(nullif(d.data#>>'{formDraft,deadline_duration_seconds}','')::numeric,
   nullif(d.data->>'deadline','')::numeric*86400)::bigint;
 payment_policy:=public.resolve_payment_policy_internal(payment_metadata,payment_duration,
   (SELECT elem FROM jsonb_array_elements(coalesce(o.features,'[]')) elem WHERE elem->>'code'='form'),payment_method);
 SELECT jsonb_build_object('account_number',b.account_number,'account_number_human_readable',coalesce(nullif(b.account_number_human_readable,''),b.account_number))
 INTO payment_info FROM eshop.unit_bank_accounts u JOIN eshop.bank_accounts b ON b.id=u.bank_account
 WHERE u.unit=d.unit AND b.id::text=d.data->>'bankAccountId' AND b.type<>'CASH' AND payment_method='bank' AND public.payment_method_policy_enabled_internal(d.unit,'bank');
 payment_info:=coalesce(payment_info,'{}')||jsonb_build_object('payment_method',payment_method,
   'collectionAction',jsonb_build_object('method',payment_method,'purpose','collect_payment','allowed',payment_method='bank' AND payment_metadata#>'{payments,bankEnabled}'='true'::jsonb AND payment_info IS NOT NULL AND public.payment_method_policy_enabled_internal(d.unit,'bank')),
   'show_payment_qr_in_email',coalesce(payment_metadata->'show_payment_qr_in_email'='true'::jsonb,false),
   'data',jsonb_build_object('payment_policy',payment_policy-'durationSeconds'),
   'deadline',CASE WHEN payment_policy->>'mode'='custom' THEN statement_timestamp()+make_interval(secs=>(payment_policy->>'durationSeconds')::bigint) END);
 RETURN jsonb_build_object('messageType',p_message_type,'deliveryMode',coalesce(p_delivery_mode,public.ticket_delivery_mode(feature)),
  'ticketFeature',feature,'ticketCatalog',ticket_catalog,'occasion',CASE WHEN p_occasion IS NOT NULL THEN to_jsonb(o) ELSE jsonb_build_object('id',0,'title',d.data->>'title','start_time',d.data->>'start','end_time',d.data->>'end','data',jsonb_build_object('place_name',d.data->>'placeName')) END,
  'revision' ,d.revision,'title',coalesce(nullif(d.data->>'title',''),'Ukázková událost'),
  'tone',tone,'replyTo',reply_to,'resolved',resolved,
  'emailBanner',email_banner,'inheritedEmailBanner',inherited_banner,
  'emailTemplates',templates,'emailScope',jsonb_build_object(
   'unit',jsonb_build_object('id',d.unit,'title',(SELECT title FROM public.units WHERE id=d.unit)),
   'organization',jsonb_build_object('id',d.organization,'title',(SELECT title FROM public.organizations WHERE id=d.organization))),
  'deadlineDurationSeconds',payment_policy->'durationSeconds',
  'paymentInfo',payment_info,
  'ticketsEnabled',coalesce((feature->>'is_enabled')::boolean,p_occasion IS NULL) AND (p_occasion IS NOT NULL OR coalesce((d.data->>'formEnabled')::boolean,true) AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) f WHERE f->>'type'='ticket' AND NOT coalesce((f->>'is_hidden')::boolean,false))),
  'walletEnabled',coalesce(p_wallet_enabled,public.ticket_wallet_enabled(feature)),
  'walletReady',public.ticket_wallet_ready(d.organization),
  'walletProviders',coalesce((SELECT jsonb_build_object('google',publishing_ready,'apple',apple_publishing_ready) FROM eshop.ticket_wallet_integrations WHERE organization=d.organization AND NOT paused),'{}'::jsonb),
  'walletCollectionEnabled',coalesce((SELECT collection_enabled FROM eshop.ticket_wallet_integrations WHERE organization=d.organization),false),
  'lang',(SELECT coalesce(data->>'DEFAULT_LANGUAGE','cs') FROM public.organizations WHERE id=d.organization),
  'sampleProducts',coalesce((SELECT jsonb_agg(p) FROM jsonb_array_elements(coalesce(d.data#>'{formDraft,fields}','[]')) f CROSS JOIN LATERAL (SELECT p FROM jsonb_array_elements(coalesce(f#>'{product_type_data,products}','[]')) p WHERE NOT coalesce((p->>'is_hidden')::boolean,false) LIMIT 1) products(p) WHERE NOT coalesce((f->>'is_hidden')::boolean,false)),'[]'::jsonb),
  'has_custom_template',coalesce((overrides ? selected_code) OR (resolved->'template'->>'occasion') IS NOT NULL
    OR (resolved->'template'->>'unit') IS NOT NULL OR (resolved->'template'->>'organization') IS NOT NULL,false));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,bigint,text,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,bigint,text,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_email_preview(p_id uuid,p_expected_revision bigint,p_message_type text,p_occasion bigint,p_delivery_mode text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.get_occasion_setup_email_preview(p_id,p_expected_revision,p_message_type,p_occasion,p_delivery_mode,NULL);
$$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,bigint,text) TO authenticated;

-- Keep the supported confirmation/catalog preview contract unchanged.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_email_preview(p_id uuid,p_expected_revision bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.get_occasion_setup_email_preview(p_id,p_expected_revision,'order_confirmation',NULL,NULL);
$$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint) TO authenticated;
