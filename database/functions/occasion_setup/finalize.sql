-- Materialize the private configuration exactly once. Provisional draft IDs and
-- source product IDs are never accepted as IDs in the new aggregate.
CREATE OR REPLACE FUNCTION public.finalize_occasion_setup_draft(p_id uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE event_kind text; appearance jsonb; shared_font text; paid boolean; policies jsonb; d public.occasion_setup_drafts; payload jsonb; config jsonb; features jsonb := '[]';
 started jsonb; receipt jsonb; new_id bigint; form_id bigint; form_data jsonb; fields jsonb := '[]';
 field jsonb; pt jsonb; products jsonb; product jsonb; result jsonb; source_id bigint;
 old_products jsonb := '[]'; old_types jsonb := '[]'; type_map jsonb := '{}'; final_features jsonb; new_products jsonb; product_map jsonb := '{}'; idx integer; j integer;
 blueprint_mode text; blueprint_id bigint; objects jsonb := '[]'; obj jsonb; v_commit public.client_commits%ROWTYPE;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.data ? 'finalizeResponse' THEN RETURN d.data->'finalizeResponse'; END IF;
 started := public.begin_unit_client_mutation_v1(p_command_id,'occasion.setup.finalize',d.unit,auth.uid(),
  encode(extensions.digest(convert_to(jsonb_build_object('draft',p_id,'revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex'));
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN RAISE serialization_failure USING MESSAGE='Draft changed in another session'; END IF;
 payload := d.data;
 event_kind:=payload->>'eventKind';
 IF event_kind IS NOT NULL AND (event_kind NOT IN ('regular','concert','ball') OR coalesce((payload->>'eventKindNeedsConfirmation')::boolean,false)) THEN
  RAISE invalid_parameter_value USING MESSAGE='Confirm event kind'; END IF;
 IF event_kind IS NOT NULL THEN
  payload:=jsonb_set(payload,'{formEnabled}','true');
  IF event_kind<>'ball' THEN payload:=payload || '{"blueprintMode":"none"}'; END IF;
  IF event_kind='regular' THEN payload:=payload-'ticketDraft'; END IF;
 END IF;
 IF event_kind IS NOT NULL AND (jsonb_typeof(payload->'formDraft') IS DISTINCT FROM 'object' OR jsonb_typeof(payload->'appearance') IS DISTINCT FROM 'object') THEN
  RAISE invalid_parameter_value USING MESSAGE='Active form and appearance required'; END IF;
 IF event_kind IN ('concert','ball') AND jsonb_typeof(payload->'ticketDraft') IS DISTINCT FROM 'object' THEN
  RAISE invalid_parameter_value USING MESSAGE='Active ticket configuration required'; END IF;
 PERFORM public.ticket_delivery_mode(payload->'ticketDraft');
 appearance:=payload->'appearance';
 IF appearance IS NOT NULL THEN
  IF jsonb_typeof(appearance)<>'object' OR coalesce(appearance->>'primary','') !~ '^[A-Fa-f0-9]{6}$' OR coalesce(appearance->>'secondary','') !~ '^[A-Fa-f0-9]{6}$'
    OR jsonb_typeof(appearance->'gradient') IS DISTINCT FROM 'boolean' THEN RAISE invalid_parameter_value USING MESSAGE='Invalid shared appearance'; END IF;
  shared_font:=CASE appearance->>'fontFamily'
    WHEN 'Roboto' THEN 'builtin:roboto-unpacked:24438383f80387edbbd3a199d7b257258db7003f5b291a7d3fb6fa89483ae57f'
    WHEN 'Roboto Slab' THEN 'builtin:roboto-slab-static:b93b5ad2eada842f450bff812f180ac517c82916c9d0dda446322e8d275b4f09'
    WHEN 'Russo One' THEN 'builtin:russo-one-unpacked:54b087e1ffbcfe8837d59e8cbda823e5690cbb8101afe23b31f3a6c70b6dad6b' END;
  IF shared_font IS NULL AND coalesce((appearance->>'preserveSource')::boolean,false)=false THEN RAISE invalid_parameter_value USING MESSAGE='Unsupported shared font'; END IF;
  IF coalesce((appearance->>'preserveSource')::boolean,false)=false THEN
   IF replace(payload#>>'{formDraft,data,design,primary_color}','#','') IS DISTINCT FROM appearance->>'primary'
    OR replace(payload#>>'{formDraft,data,design,secondary_color}','#','') IS DISTINCT FROM appearance->>'secondary'
    OR payload#>>'{formDraft,data,design,font_family}' IS DISTINCT FROM appearance->>'fontFamily'
    OR payload#>>'{formDraft,data,design,background_mode}' IS DISTINCT FROM (CASE WHEN (appearance->>'gradient')::boolean THEN 'gradient' ELSE 'solid' END)
    THEN RAISE invalid_parameter_value USING MESSAGE='Shared form style mismatch'; END IF;
   IF event_kind IN ('concert','ball') AND public.ticket_delivery_mode(payload->'ticketDraft')<>'inline_qr' AND (payload#>'{ticketDraft,layout,templates}' IS NULL OR EXISTS(
    SELECT 1 FROM jsonb_each(payload#>'{ticketDraft,layout,templates}') t
    WHERE t.value->>'fontId' IS DISTINCT FROM shared_font OR t.value->>'canvasColor' IS DISTINCT FROM appearance->>'primary'
     OR (CASE WHEN (appearance->>'gradient')::boolean THEN t.value->'canvasGradient' IS DISTINCT FROM jsonb_build_array(appearance->>'primary',appearance->>'secondary') ELSE t.value ? 'canvasGradient' END)))
    THEN RAISE invalid_parameter_value USING MESSAGE='Shared ticket style mismatch'; END IF;
  END IF;
  -- A custom copied layout retains its detailed style until the user chooses
  -- a shared style. New shared styles are materialized by the one draft mapper.
  IF appearance->>'id'<>'custom' AND payload#>>'{formDraft,data,design,font_family}' IS DISTINCT FROM appearance->>'fontFamily' THEN
    RAISE invalid_parameter_value USING MESSAGE='Form appearance mismatch'; END IF;
 END IF;

 blueprint_mode := CASE payload->>'blueprintMode'
  WHEN 'none' THEN 'none' WHEN 'Bez plánku' THEN 'none'
  WHEN 'new' THEN 'new' WHEN 'Nový' THEN 'new'
  WHEN 'copy' THEN 'copy' WHEN 'Převzít' THEN 'copy'
  WHEN NULL THEN 'none' ELSE payload->>'blueprintMode' END;
 -- Old drafts without a mode were valid inline plans; keep that explicit legacy adapter.
 IF blueprint_mode IS NULL THEN blueprint_mode := CASE WHEN jsonb_array_length(coalesce(payload->'blueprintObjects','[]'))>0 THEN 'copy' ELSE 'none' END; END IF;
 IF event_kind='ball' AND blueprint_mode='none' THEN RAISE invalid_parameter_value USING MESSAGE='Ball requires seats'; END IF;
 IF blueprint_mode NOT IN ('none','new','copy') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid blueprint mode'; END IF;
 IF blueprint_mode<>'none' AND (
  coalesce((payload->>'formEnabled')::boolean,true) IS NOT TRUE OR
  payload->'formDraft' IS NULL OR payload->'formDraft'='null'::jsonb OR
  NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(payload->'blueprintObjects','[]')) o WHERE o->>'type'='spot')
 ) THEN RAISE invalid_parameter_value USING MESSAGE='Blueprint requires a form and sellable seats'; END IF;
 source_id := (payload->>'sourceId')::bigint;
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
  RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 FOREACH source_id IN ARRAY ARRAY[nullif(payload->>'formSourceOccasionId','')::bigint,nullif(payload->>'blueprintSourceOccasionId','')::bigint] LOOP
  IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
   RAISE insufficient_privilege USING MESSAGE='Configuration source denied'; END IF;
 END LOOP;
 source_id := (payload->>'sourceId')::bigint;
 IF nullif(btrim(payload->>'title'),'') IS NULL OR (payload->>'reviewConfirmed')::boolean IS DISTINCT FROM true THEN
  RAISE invalid_parameter_value USING MESSAGE='Draft review required'; END IF;
 IF nullif(payload->>'start','') IS NULL OR nullif(payload->>'end','') IS NULL OR (payload->>'end')::timestamptz < (payload->>'start')::timestamptz THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid event dates'; END IF;
 IF payload->'ticketDraft' IS NOT NULL AND payload->'ticketDraft'<>'null'::jsonb THEN features := features || jsonb_build_array((payload->'ticketDraft')-'layout'); END IF;
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN features := features || '[{"code":"form","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN features := features || '[{"code":"schedule","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN features := features || '[{"code":"information","is_enabled":true}]'; END IF;
 config := jsonb_build_object('unit',d.unit,'organization',d.organization,
  'title',payload->>'title','link',payload->>'link','description',coalesce(payload->>'description',''),
  'start_time',payload->>'start','end_time',payload->>'end','is_hidden',true,'is_open',false,
  'features',features,'data',jsonb_build_object('client_sync_v1',false) || CASE WHEN event_kind IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('eventKind',event_kind) END || CASE WHEN nullif(btrim(payload->>'replyTo'),'') IS NOT NULL THEN jsonb_build_object('reply_to',btrim(payload->>'replyTo')) ELSE '{}'::jsonb END);
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
 IF event_kind IS NOT NULL THEN
  form_data:=jsonb_set(form_data,'{title}',payload->'title');
 END IF;
 SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f,
  LATERAL jsonb_array_elements(coalesce(f->'product_type_data'->'products',f->'product_type'->'products','[]')) p
  WHERE coalesce((p->>'price')::numeric,0)>0 AND coalesce((p->>'is_hidden')::boolean,false)=false) INTO paid;
 IF NOT paid AND event_kind IS NOT NULL THEN
  form_data:=jsonb_set(form_data,'{data}',coalesce(nullif(form_data->'data','null'::jsonb),'{}')-ARRAY['payments','is_reminder_enabled','reminder_interval_seconds']);
  form_data:=form_data || '{"bank_account":null,"deadline_duration_seconds":null}';
 END IF;

 IF nullif(btrim(payload->>'replyTo'),'') IS NOT NULL AND (length(payload->>'replyTo')>254 OR payload->>'replyTo' !~ '^[^[:space:]<>@]+@[^[:space:]<>@]+[.][^[:space:]<>@]+$') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid reply address'; END IF;
 IF coalesce(payload->>'communicationTone','inherit') NOT IN ('inherit','formal','informal') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid communication tone'; END IF;
 IF payload ? 'communicationTone' THEN
  form_data:=jsonb_set(form_data,'{data}',coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)-'communication_tone' ||
   CASE WHEN payload->>'communicationTone' IN ('formal','informal') THEN jsonb_build_object('communication_tone',payload->>'communicationTone') ELSE '{}'::jsonb END);
 END IF;
 -- A copied source's schedule is never the creation intent of the destination.
 IF payload ? 'saleMode' THEN
  form_data:=jsonb_set(form_data,'{data}',(coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)-'start_time'-'end_time'-'enable_countdown') ||
   jsonb_build_object('schedule',(coalesce(nullif(form_data#>'{data,schedule}','null'::jsonb),'{}'::jsonb)-'start_time'-'end_time') || jsonb_build_object('sale_preparation',payload->>'saleMode'='preparation')));
 END IF;
 IF payload->>'saleMode' NOT IN ('preparation','scheduled','immediate') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid sale mode'; END IF;
 IF payload->>'saleMode' IN ('scheduled','immediate') THEN
  IF coalesce((payload->>'saleEnd')::timestamptz,(payload->>'end')::timestamptz) > (payload->>'end')::timestamptz OR
     coalesce((payload->>'saleEnd')::timestamptz,(payload->>'end')::timestamptz) <= now() OR
     (payload->>'saleMode'='scheduled' AND ((payload->>'saleStart') IS NULL OR (payload->>'saleStart')::timestamptz <= now() OR
       (payload->>'saleStart')::timestamptz >= coalesce((payload->>'saleEnd')::timestamptz,(payload->>'end')::timestamptz))) THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid sale interval'; END IF;
  form_data:=jsonb_set(form_data,'{data}',coalesce(form_data->'data','{}'::jsonb) || jsonb_build_object('schedule',jsonb_build_object(
    'start_time',CASE WHEN payload->>'saleMode'='scheduled' THEN payload->>'saleStart' ELSE now()::text END,
    'end_time',coalesce(payload->>'saleEnd',payload->>'end'))));
 END IF;
 IF form_data IS NOT NULL AND form_data<>'null'::jsonb AND coalesce((payload->>'formEnabled')::boolean,true) THEN
  SELECT id INTO form_id FROM public.forms WHERE occasion=new_id ORDER BY id LIMIT 1;
  IF form_id IS NULL THEN
   result := public.create_form_internal_v1(new_id,NULL,form_data->>'title'); form_id := (result->>'id')::bigint;
  END IF;
  DELETE FROM public.form_fields WHERE form=form_id;
  DELETE FROM eshop.products WHERE occasion=new_id;
  DELETE FROM eshop.product_types WHERE occasion=new_id;
  -- Seat selection belongs to the active plan, never a stale form toggle.
  form_data := jsonb_set(form_data,'{fields}',coalesce((
   SELECT jsonb_agg(f) FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f
   WHERE f->>'type' IS DISTINCT FROM 'spot'),'[]'::jsonb) ||
   CASE WHEN blueprint_mode<>'none' THEN '[{"type":"spot","is_ticket_field":true,"is_hidden":false,"order":-1}]'::jsonb ELSE '[]'::jsonb END);
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
  result := public.update_form_internal_v1((form_data-'id'-'fields'-'blueprint') || jsonb_build_object(
   'id',form_id,'occasion',new_id,'link',coalesce(nullif(form_data->>'link',''),(SELECT link FROM public.forms WHERE id=form_id)),
   'is_open',coalesce(payload->>'saleMode','preparation') IN ('scheduled','immediate'),'form_fields',fields));
  IF result->>'code'<>'200' THEN RAISE EXCEPTION '%',result; END IF;
  -- Validate configured bank routes using the checkout's exact linked-account,
  -- non-cash and supported-currency predicates. Account priority stays checkout-owned.
  IF coalesce(form_data#>'{data,payments,bankEnabled}','true'::jsonb)='true'::jsonb AND EXISTS(
    SELECT 1 FROM eshop.products p WHERE p.occasion=new_id AND p.price>0
      AND NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts u JOIN eshop.bank_accounts b ON b.id=u.bank_account
        WHERE u.unit=d.unit AND b.type IS DISTINCT FROM 'CASH' AND b.supported_currencies @> ARRAY[p.currency_code::text]
          AND (nullif(form_data->>'bank_account','') IS NULL OR b.id=(form_data->>'bank_account')::bigint))) THEN
    RAISE invalid_parameter_value USING MESSAGE='No valid bank route for the selected currencies';
  END IF;
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
   FOR obj IN SELECT value FROM jsonb_array_elements(payload->'blueprintObjects') LOOP
    -- Editor/source models contain read-only occupancy. Only configuration
    -- crosses the create boundary; the general blueprint command stays strict.
    obj := obj-ARRAY['id','state','order_product_ticket','secret','secret_expiration_time'];
    IF obj->>'type'='spot' AND (obj->>'product' IS NULL OR product_map->>(obj->>'product') IS NULL) THEN
     RAISE invalid_parameter_value USING MESSAGE='Every blueprint seat requires a form product'; END IF;
    IF obj->>'product' IS NOT NULL THEN obj := jsonb_set(obj,'{product}',coalesce(product_map->(obj->>'product'),'null'::jsonb)); END IF;
    objects := objects || jsonb_build_array(obj);
   END LOOP;
   result := public.update_blueprint_internal_v1(jsonb_build_object('occasion',new_id,'organization',d.organization,
    'title',payload->>'blueprintTitle','configuration',jsonb_build_object('dimensions',jsonb_build_object(
     'width',coalesce((payload->>'blueprintWidth')::numeric,12),'height',coalesce((payload->>'blueprintHeight')::numeric,8))),
    'groups',coalesce(payload->'blueprintGroups','[]'),'objects',objects,'background_svg',payload->>'blueprintBackground'));
   IF (result->>'code')::int NOT IN (200,201) THEN RAISE EXCEPTION '%',result; END IF;
   blueprint_id := (result->>'blueprint_id')::bigint;
   UPDATE public.forms SET blueprint=blueprint_id WHERE id=form_id;
   features := features || '[{"code":"blueprint","is_enabled":true}]';
  END IF;
 END IF;
 -- Rebind ticket product-type references only after their new IDs exist.
 IF payload->'ticketDraft' ? 'layout' THEN
  pt := payload->'ticketDraft';
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
  INSERT INTO public.events(occasion,title,start_time,end_time,description)
  SELECT new_id,e->>'title',(e->>'start_time')::timestamptz,(e->>'end_time')::timestamptz,e->>'description'
  FROM jsonb_array_elements(coalesce(payload->'sourceProgram','[]')) e;
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
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('occasion','occasion',new_id,new_id::text,1);
 INSERT INTO public.client_commits(unit,actor_id,actor_kind,source,change_class)
 VALUES(d.unit,auth.uid(),'user','occasion.setup.finalize','configuration') RETURNING * INTO v_commit;
 INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
 SELECT v_commit.commit_id,0,'occasion',new_id::text,'insert',left(title,240),ARRAY['aggregate'] FROM public.occasions WHERE id=new_id;
 PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,d.unit);
 receipt := jsonb_build_object('status','applied','code',200,'data',
  jsonb_build_object('occasionId',new_id,'link',(SELECT link FROM public.occasions WHERE id=new_id)));
 receipt := public.finish_client_mutation_v1(p_command_id,receipt,v_commit.commit_id);
 UPDATE public.occasion_setup_drafts SET data=data || jsonb_build_object('finalizedOccasion',new_id,'finalizeResponse',receipt),revision=revision+1 WHERE id=p_id;
 RETURN receipt;
END $$;
REVOKE ALL ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) TO authenticated;
