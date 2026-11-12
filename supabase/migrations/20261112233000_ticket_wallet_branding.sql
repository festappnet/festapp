-- Tenant-owned Wallet branding and inert, representative email previews. No provider activation or customer sends.

-- SOURCE: ticket_wallet/projection.sql
-- The current paid-delivery boundary, never scanner configuration overrides.
CREATE OR REPLACE FUNCTION public.ticket_wallet_projection_internal(p_ticket bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE t eshop.tickets; o public.occasions; f jsonb; c eshop.ticket_wallet_capabilities; state text; details jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO t FROM eshop.tickets WHERE id=p_ticket;
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 SELECT * INTO o FROM public.occasions WHERE id=t.occasion;
 SELECT x INTO f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket';
 state:='INACTIVE';
 IF t.id IS NOT NULL AND t.occasion=c.occasion AND o.organization=c.organization
 AND coalesce((f->>'is_enabled')::boolean,false) AND c.revoked_at IS NULL
 AND o.start_time IS NOT NULL AND o.end_time IS NOT NULL AND nullif(btrim(o.title),'') IS NOT NULL
 AND t.ticket_symbol IS NOT NULL AND t.state IN ('paid','sent','used')
 AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders ord ON ord.id=x."order"
  WHERE x.ticket=t.id AND ord.id=c.order_id AND ord.occasion=t.occasion AND ord.state IN ('paid','sent'))
 AND NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders ord ON ord.id=x."order"
  WHERE x.ticket=t.id AND (ord.occasion IS DISTINCT FROM t.occasion OR ord.state NOT IN ('paid','sent')))
 AND public.provider_ticket_admission_allowed_internal(t.id) THEN
  state:=CASE WHEN o.end_time<=now() OR c.expires_at<=now() THEN 'EXPIRED' WHEN t.state='used' THEN 'COMPLETED' ELSE 'ACTIVE' END;
 END IF;
 IF t.id IS NOT NULL THEN
  SELECT x INTO details FROM jsonb_array_elements(public.get_tickets_with_details(c.order_id)) x WHERE (x->>'id')::bigint=t.id;
 END IF;
 RETURN jsonb_build_object('state',state,
 'branding',(SELECT jsonb_build_object('APP_NAME',data->'APP_NAME','DEFAULT_URL',data->'DEFAULT_URL','WALLET_LOGO_URL',data->'WALLET_LOGO_URL') FROM public.organizations WHERE id=o.organization),
 'ticket',jsonb_build_object('id',t.id,'ticket_symbol',t.ticket_symbol,
 'order_product_ticket',(SELECT coalesce(jsonb_agg(x||jsonb_build_object('product',jsonb_build_object('title',p.title))),'[]') FROM jsonb_array_elements(details->'order_product_ticket') x LEFT JOIN eshop.products p ON p.id=(x->>'product')::bigint)),
 'occasion',jsonb_build_object('id',o.id,'organization',o.organization,'title',o.title,'start_time',o.start_time,'end_time',o.end_time,
 'ticketFeature',jsonb_build_object('ticket_type',f->'ticket_type','background',f->'background','lightColor',f->'lightColor','layout',f->'layout','wallet_appearance',f->'wallet_appearance'),
 'data',jsonb_build_object('place_name',o.data->'place_name','timezone',o.data->'timezone','logo',o.data->'logo')));
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_projection_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_projection_internal(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.refresh_ticket_wallet_term_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.ticket_wallet_capabilities c SET event_end_at=o.end_time,expires_at=o.end_time+interval '7 days'
 FROM public.occasions o JOIN eshop.tickets t ON t.occasion=o.id
 WHERE c.ticket_id=p_ticket AND t.id=c.ticket_id AND o.id=c.occasion AND o.organization=c.organization
 AND c.revoked_at IS NULL AND c.reissue_after IS NULL AND o.end_time IS NOT NULL AND c.event_end_at IS DISTINCT FROM o.end_time;
END $$;
REVOKE ALL ON FUNCTION public.refresh_ticket_wallet_term_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_ticket_wallet_term_internal(bigint) TO service_role;

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

-- SOURCE: others/get_entity_email_templates.sql
CREATE OR REPLACE FUNCTION public.get_entity_email_templates(p_entity_type text, p_entity_id bigint)
RETURNS jsonb
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
    v_unit_id     bigint;
    v_org_id      bigint;

    context       jsonb;
    email_data    jsonb;

    occasion_data jsonb;
    unit_data     jsonb;
    org_data      jsonb;

    final_result  jsonb;
BEGIN
    -- 1. Resolve Hierarchy based on Entity Type
    IF p_entity_type = 'occasion' THEN
        v_occasion_id := p_entity_id;

        -- Get Unit & Org from Occasion
        SELECT unit, organization INTO v_unit_id, v_org_id
        FROM public.occasions WHERE id = v_occasion_id;

        IF v_unit_id IS NULL THEN
            RAISE EXCEPTION 'Occasion not found: %', p_entity_id;
        END IF;

    ELSIF p_entity_type = 'unit' THEN
        v_unit_id := p_entity_id;
        v_occasion_id := NULL;

        -- Get Org from Unit
        SELECT organization INTO v_org_id
        FROM public.units WHERE id = v_unit_id;

        IF v_org_id IS NULL THEN
            RAISE EXCEPTION 'Unit not found: %', p_entity_id;
        END IF;
    ELSE
        RAISE EXCEPTION 'Invalid entity type: %', p_entity_type;
    END IF;

    -- 2. Build Context for Template Retrieval
    context := jsonb_build_object(
        'occasion', v_occasion_id,
        'unit', v_unit_id,
        'organization', v_org_id
    );

    -- 3. Retrieve Templates (using core logic)
    email_data := public.get_all_email_templates(context);

    -- 4. Retrieve Entity Details for Response

    -- Organization
    SELECT jsonb_build_object('id', id, 'title', title, 'data', data)
    INTO org_data
    FROM public.organizations WHERE id = v_org_id;

    -- Unit
    SELECT jsonb_build_object('id', id, 'title', title, 'data', COALESCE(data, '{}'::jsonb), 'email', data->>'reply_to')
    INTO unit_data
    FROM public.units WHERE id = v_unit_id;

    -- Occasion (if applicable)
    IF v_occasion_id IS NOT NULL THEN
        SELECT jsonb_build_object('id', id, 'title', title, 'features', features, 'data', COALESCE(data, '{}'::jsonb), 'email', data->>'reply_to')
        INTO occasion_data
        FROM public.occasions WHERE id = v_occasion_id;
    ELSE
        occasion_data := NULL;
    END IF;

    -- 5. Build Final Result
    final_result := jsonb_build_object(
        'occasion',     occasion_data,
        'unit',         unit_data,
        'organization', org_data,
        'templates',    email_data,
        'walletReady', public.ticket_wallet_ready(v_org_id),
        'banner', public.get_email_banner_state_internal(context)
    );

    RETURN final_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_entity_email_templates(text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_entity_email_templates(text, bigint) TO authenticated, service_role;

-- SOURCE: others/get_ticket_layout_write_contract_v1.sql
-- Generated by automation/generate_ticket_layout_write_contract.py.
-- A readiness probe, not a write dispatcher or a grant to any new executor.
CREATE OR REPLACE FUNCTION public.get_ticket_layout_write_contract_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ready boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid()) THEN
  RAISE insufficient_privilege USING MESSAGE='authenticated user required'; END IF;
 SELECT coalesce(bool_and(p.oid IS NOT NULL AND md5(btrim(p.prosrc,E' \n\r\t'))=expected.body_md5
  AND p.prosecdef=expected.definer AND (EXISTS(SELECT 1 FROM unnest(p.proconfig) setting
   WHERE regexp_replace(setting,'[[:space:]]','','g')='search_path=public,extensions')=expected.needs_path)),false)
 INTO ready FROM (VALUES
  ('public.active_membership(boolean,boolean)','2dd31a8b531c745b2ed16af90e0260ea',false,false),
  ('public.administration_navigation_rule(boolean,boolean,boolean,boolean,boolean)','7a9559975e19ae53e8b15a23a4b8b68a',false,false),
  ('public.blueprint_write_rule(boolean,boolean)','0c68680b6879b48966f2bf3bc0210d37',false,false),
  ('public.can_create_occasion(bigint)','f13b39c68d18a53dbb79125c23d7dc23',true,true),
  ('public.can_delete_orders(bigint)','8db8081db5e65a6948f4cefe1b109f93',true,true),
  ('public.can_edit_occasion(bigint,bigint)','af8850fc3a3bed9a06274880669c340d',true,true),
  ('public.can_edit_ticket_layout(bigint)','bb45fdb1e72cd16860e9719c8f9ab84f',true,true),
  ('public.can_edit_ticket_layout_as_actor_internal_v1(uuid,bigint)','f6ee7e318387522f6146e13b3c4854f7',true,true),
  ('public.can_manage_occasion_participants(bigint)','8cb3dd4327ae5c9302da134994dd5d07',true,true),
  ('public.can_manage_unit_users(bigint)','700c32f30396d2bc5bb21553c2f42ca8',true,true),
  ('public.can_preview_ticket_readonly(bigint)','48efb47c1529b5106cbab4edf641fd0a',true,true),
  ('public.can_read_information_editor_bundle(bigint)','ba203be730cbf9acca46c0b3e63363ad',true,true),
  ('public.can_read_map_editor_bundle(bigint)','02c9fbcfcd61c8598e88407a9f3070fa',true,true),
  ('public.can_read_orders(bigint)','795b29c048acb37bc949683bfc586f43',true,true),
  ('public.can_read_ticket_layout(bigint)','50105a20a0ff5d89389f80e5dd9f891c',true,true),
  ('public.can_read_unit_users(bigint)','76b08038f169406ba1ba56652e44608e',true,true),
  ('public.can_write_orders(bigint)','680cbd3862cc0f6abc89d7d2497c7fb1',true,true),
  ('public.can_write_orders_as_actor_internal(uuid,bigint)','064d9d9fe95cfbb62ccbe39efa120a62',false,false),
  ('public.cleaning_crew_navigation_rule(boolean)','30e845096d248f7112e1d570bb489e6a',false,false),
  ('public.client_activity_read_rule(boolean,boolean,boolean)','002ce7bce477126bcdab9e94db022734',false,false),
  ('public.client_commit_read_rule(boolean,boolean,boolean)','229306cbca2f8a160f4d66b2598fc127',false,false),
  ('public.closed_occasion_enrolment_rule(boolean,boolean,boolean,boolean)','9f7f53c36711c06eb5a130dc339b325b',false,false),
  ('public.companion_assignment_rule(boolean,boolean)','7d53e2d7e2196b118c29f85cc90d0ab2',false,false),
  ('public.context_private_access_rule(boolean,boolean,boolean)','a187283398f1802a1b79b46963ff98b6',false,false),
  ('public.demo_own_work_rule(boolean,boolean,boolean,boolean)','3dd99e356714a2005743f678f09f7ae9',false,false),
  ('public.email_template_read_rule(boolean,boolean)','6501d868e3a245da411c8685a6c39406',false,false),
  ('public.email_template_write_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.event_attendance_read_rule(boolean,boolean)','e85f194d54fb7db63b079e5d689de085',false,false),
  ('public.form_authoring_rule(boolean,boolean)','378d42348079d8d5df8ed0d914f5d007',false,false),
  ('public.form_catalog_read_rule(boolean,boolean,boolean)','7a7263f988a28c0272c14f0234b12563',false,false),
  ('public.form_copy_source_rule(boolean,boolean)','0fff049746a86488382290a67c8c9838',false,false),
  ('public.group_assignments_write_rule(boolean,boolean,boolean,boolean)','0221c1b7823f38a4d5afa4abe5e0912f',false,false),
  ('public.group_data_read_rule(boolean,boolean)','a5a4e0f5924790a0c9e68e79bc606a1e',false,false),
  ('public.group_editor_read_rule(boolean,boolean,boolean)','c1fd67eb4de0001ed5aaffb65d36b437',false,false),
  ('public.group_members_read_rule(boolean,boolean,boolean)','c8e7fdf47b08fac95a18ed026d4d07bc',false,false),
  ('public.group_members_write_rule(boolean,boolean)','46f6cef5344290b2caf0182185c3ce4e',false,false),
  ('public.group_places_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','937805bab351b685970512e7f5e6f285',false,false),
  ('public.group_write_rule(boolean,boolean,boolean)','3dd26a325ee3dd2e391136570cbc5f60',false,false),
  ('public.inventory_copy_target_rule(boolean,boolean)','604bd24712dc418a35616de6d38e0578',false,false),
  ('public.map_editor_read_rule(boolean,boolean)','3f4dc9022d50562b6a48d6e46b0c5928',false,false),
  ('public.merge_ticket_appearance_internal_v1(bigint,jsonb,jsonb)','337628341725ae78a7c14a130a0fe7a4',false,true),
  ('public.merge_ticket_layout_features(jsonb,jsonb,jsonb,boolean)','d8c6d2e6a64880af2fa1e5553dbf85f5',false,true),
  ('public.news_data_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','f68f00938a5a8efee47af7edc0062f94',false,false),
  ('public.occasion_commit_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.occasion_context_read_rule(boolean,boolean,boolean)','b54f8cf02bc1580acba23e2497d1cc9f',false,false),
  ('public.occasion_create_rule(boolean,boolean)','faa2f799767b4c9edb52c58944b4a66b',false,false),
  ('public.occasion_directory_read_rule(boolean,boolean)','d4937332739a00292987baae5b876b2b',false,false),
  ('public.occasion_edit_rule(boolean,boolean)','1d4987935db34cc6011f633ef3f6f291',false,false),
  ('public.occasion_editor_read_rule(boolean,boolean,boolean)','1702aa0f9d1003c29f02ef70a017dee6',false,false),
  ('public.occasion_list_read_rule(boolean,boolean)','7ecb040f0c43bb540a15e2ab868ac31e',false,false),
  ('public.occasion_media_upload_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.occasion_staff_navigation_rule(boolean,boolean,boolean,boolean,boolean)','6c7cfeabfb173e0283543f575272d4d8',false,false),
  ('public.occasion_users_write_rule(boolean,boolean,boolean)','2a1ee1bc8a910030a6010ff778df7bc4',false,false),
  ('public.operator_occasion_discovery_rule(boolean,boolean,boolean,boolean,boolean,boolean,boolean)','939699b1b32832f4e2ad0c3af5f22210',false,false),
  ('public.order_delete_rule(boolean,boolean,boolean)','6fdbd70c92f774e10d2be6e0e30eb219',false,false),
  ('public.order_editor_membership_as_actor_internal(uuid,bigint)','aa05414eef3f73d8792cdaaa22023c39',false,false),
  ('public.order_read_rule(boolean,boolean,boolean)','d8acd43d69e2797bbd63063512eb4e69',false,false),
  ('public.order_write_rule(boolean,boolean)','4dd2fa01cd16e5c36983aa7aeb280d3f',false,false),
  ('public.participant_contacts_read_rule(boolean,boolean,boolean)','c371f5c035213b1fd9c8a5f15ba3c6e3',false,false),
  ('public.participant_manage_rule(boolean,boolean)','2ddebfa1df2bdd7becf910d5b619a3c0',false,false),
  ('public.place_move_rule(boolean,boolean,boolean,boolean)','73f870eaea9c56088435b4d80cbf5315',false,false),
  ('public.public_publication_actor_rule(boolean,boolean,boolean)','47ad63e39013d34b5a4105a18f04457d',false,false),
  ('public.readable_membership(boolean,boolean,boolean)','057c3a891e1c41c9b77dc8af67983e20',false,false),
  ('public.reception_enabled(jsonb)','0844ea35e4e7bfad821b8f09f81e8fbb',false,false),
  ('public.reception_use_rule(boolean,boolean,boolean,boolean)','99350a72fb204f5160cb72714b85882c',false,false),
  ('public.reviewed_blueprint_write_rule(boolean,boolean,boolean,boolean)','53eb537fe636ad48274e61bafb683e4a',false,false),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)','56bf52d069b80a2ffa254509afdaa5a1',true,true),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)','00af445f9e641905e395adaca48ce248',true,true),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)','eda19f32835616334b3adc0f4d2cd2f6',true,true),
  ('public.scanner_settings_rule(boolean,boolean,boolean)','2b1717b65933cede78c39b44f5d6230d',false,false),
  ('public.schedule_entry_navigation_rule(boolean)','f0258b7a3cc8e3a024dee1a96d34d407',false,false),
  ('public.schedule_feedback_read_rule(boolean,boolean)','a546bbfc24dce06e231e832a11ddb4b4',false,false),
  ('public.schedule_participants_read_rule(boolean,boolean,boolean)','7f6977ddb21f0e2044e154b4428275d1',false,false),
  ('public.ticket_delivery_mode(jsonb)','c2590b2701840fc3cba0df9e8d0359cd',false,true),
  ('public.ticket_layout_rule(boolean,boolean)','8bc8e0cd6a5a45d10d57f79cec655768',false,false),
  ('public.ticket_layout_uses_product_type(bigint,bigint)','dddc7962230734dd5835601b455d8bb4',false,true),
  ('public.ticket_wallet_enabled(jsonb)','ccbb73fd52b030315763e2be50b8e7a7',false,true),
  ('public.ticket_wallet_fingerprint(bigint)','b925aa31ec85daa749b9be964813dfbd',true,true),
  ('public.ticket_wallet_ready(bigint)','d1827ba2afea0b03bf617631d00c9515',true,true),
  ('public.unit_abuse_policy_read_rule(boolean,boolean)','42fc89183ec978eccce36173bc6c3a50',false,false),
  ('public.unit_discovery_rule(boolean,boolean,boolean)','d49526989a25babf6f7ca9ba34b3061c',false,false),
  ('public.unit_landing_read_rule(boolean,boolean,boolean,boolean)','14e7808464b1206a6842240b8db567ff',false,false),
  ('public.unit_legal_profile_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.unit_template_read_rule(boolean,boolean,boolean)','a22a3f456bfac47bcc58b72c2ec5f75f',false,false),
  ('public.unit_users_read_rule(boolean,boolean,boolean)','a7131760aa20a35fa57d63f718037a34',false,false),
  ('public.unit_workspace_navigation_rule(boolean,boolean,boolean,boolean)','5ba3417d0406073b8ce9421770304558',false,false),
  ('public.update_occasion(jsonb)','0425e6f46c20d2c30a2ffd054619b2b0',true,true),
  ('public.update_occasion_182(jsonb)','bdcda71506ac0abb50a466bb18eb1cc7',true,true),
  ('public.update_occasion_203(jsonb)','916b23b47758d87e478b3b7d84a50ee2',true,true),
  ('public.update_occasion_internal_v1(jsonb)','2446d470f7e49092199946b0cc8fa6bd',true,true),
  ('public.validate_ticket_layout(jsonb)','53d7703a06dbde87349a0ac04e50cd54',false,true),
  ('public.validate_ticket_layout_references(bigint,jsonb)','aad01d93c9f0a7035efa243caa3d5a20',false,true),
  ('public.validate_ticket_wallet_appearance(jsonb)','bdcc55cb2a986056fbae005acee1990c',false,true)
 ) expected(signature,body_md5,definer,needs_path)
 LEFT JOIN pg_proc p ON p.oid=to_regprocedure(expected.signature);
 ready:=ready AND NOT EXISTS(
  SELECT 1 FROM (VALUES('authenticated'),('anon')) actor(role_name)
  WHERE has_table_privilege(actor.role_name,'public.occasions','INSERT,UPDATE,DELETE,TRUNCATE')
   OR has_any_column_privilege(actor.role_name,'public.occasions','INSERT,UPDATE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion_internal_v1(jsonb)'),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)'),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)')
 ) private(signature) WHERE has_function_privilege('authenticated',to_regprocedure(private.signature),'EXECUTE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion(jsonb)'),('public.update_occasion_203(jsonb)'),('public.update_occasion_182(jsonb)'),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)')
 ) boundary(signature) WHERE NOT has_function_privilege('authenticated',to_regprocedure(boundary.signature),'EXECUTE')
 OR has_function_privilege('anon',to_regprocedure(boundary.signature),'EXECUTE'));
 RETURN jsonb_build_object('family','ticket_layouts','contractVersion',1,'ready',coalesce(ready,false));
END $$;
REVOKE ALL ON FUNCTION public.get_ticket_layout_write_contract_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ticket_layout_write_contract_v1() TO authenticated;
