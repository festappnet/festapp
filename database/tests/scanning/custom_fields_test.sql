BEGIN;
DO $$
DECLARE fx jsonb; oc bigint; fm bigint; tid bigint; oid bigint; ofield bigint; tfield bigint; cfg jsonb; dto jsonb; session jsonb; snap jsonb; page jsonb; offline_dto jsonb;
BEGIN
 fx:=public.scanner_test_fixture();oc:=(fx->>'occasion')::bigint;fm:=(fx->>'form')::bigint;tid:=(fx#>>'{tickets,0}')::bigint;
 INSERT INTO public.form_fields(form,title,type,is_ticket_field) VALUES(fm,'Skupina','text',false) RETURNING id INTO ofield;
 INSERT INTO public.form_fields(form,title,type,is_ticket_field) VALUES(fm,'Menu','text',true) RETURNING id INTO tfield;
 SELECT "order" INTO oid FROM eshop.order_product_ticket WHERE ticket=tid LIMIT 1;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[oid]);
 UPDATE eshop.orders SET data=data||jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(ofield::text,'Orion'))) WHERE id=oid;
 UPDATE eshop.tickets SET data=jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(tfield::text,'Bez lepku'))) WHERE id=tid;
 SELECT config INTO cfg FROM public.scanner_settings WHERE occasion_id=oc;
 cfg:=jsonb_set(cfg,'{fields}',jsonb_build_array(
 jsonb_build_object('key','order:'||fm||':'||ofield,'source','order_field','form_id',fm,'field_id',ofield,'label','Skupina','default_visible',true,'hide_empty',true),
 jsonb_build_object('key','ticket:'||fm||':'||tfield,'source','ticket_field','form_id',fm,'field_id',tfield,'label','Menu','default_visible',true,'hide_empty',true)));
 PERFORM public.scanner_validate_settings_internal(oc,cfg);
 UPDATE public.scanner_settings SET config=cfg WHERE occasion_id=oc;
 session:=(public.open_scanner_session(fx->>'scan_code'))->'data';
 dto:=(public.lookup_scanner_ticket((session->>'session_id')::uuid,session->>'token',(SELECT ticket_symbol FROM eshop.tickets WHERE id=tid)))->'data';
 PERFORM assert_eq((dto->>'order_id')::bigint,oid,'server provides canonical order identity for grouping');
 PERFORM assert_eq(dto#>>'{fields,0,value}','Orion','order answer projected');
 PERFORM assert_eq(dto#>>'{fields,1,value}','Bez lepku','individual ticket answer projected');
 PERFORM assert_true((dto#>>'{fields,0,default_visible}')::boolean,'configured field visible by default');
 SELECT p.dto INTO offline_dto FROM public.scanner_ticket_projection_internal(oc,cfg,(fx#>>'{tickets,1}')::bigint) p;
 PERFORM assert_true(offline_dto#>>'{fields,0,value}' IS NULL,'order answers never leak to another order');
 PERFORM assert_true(offline_dto#>>'{fields,1,value}' IS NULL,'ticket answers never leak to another guest');
 snap:=(public.prepare_scanner_snapshot((session->>'session_id')::uuid,session->>'token'))->'data';
 page:=public.get_scanner_snapshot_page((session->>'session_id')::uuid,session->>'token',(snap->>'snapshot_id')::uuid,0);
 SELECT value INTO offline_dto FROM jsonb_array_elements((page#>>'{data,payload_text}')::jsonb) WHERE (value->>'ticket_id')::bigint=tid;
 PERFORM assert_eq(offline_dto->'fields',dto->'fields','offline snapshot preserves configured custom field values');
END $$;
ROLLBACK;
