BEGIN;
DO $$
DECLARE oc bigint; cfg jsonb; r jsonb;
BEGIN
 SELECT occasion_id,config INTO oc,cfg FROM public.scanner_settings LIMIT 1;
 PERFORM public.scanner_validate_settings_internal(oc,cfg);
 BEGIN PERFORM public.scanner_validate_settings_internal(oc,jsonb_set(cfg,'{products,ids}','[99999999999]'));PERFORM assert_fail('foreign product');EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.scanner_validate_settings_internal(oc,jsonb_set(cfg,'{fields}','[{"source":"ticket_field","form_id":99999999,"field_id":99999999,"key":"ticket:99999999:99999999"}]'));PERFORM assert_fail('foreign field');EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 cfg:=jsonb_set(cfg,'{sensitive,price}','false');cfg:=jsonb_set(cfg,'{sensitive,hidden_note}','false');cfg:=jsonb_set(cfg,'{products,mode}','"none"');
 SELECT dto INTO r FROM public.scanner_ticket_projection_internal(oc,cfg) LIMIT 1;
 PERFORM assert_not_null(r,'projection fixture');PERFORM assert_false(r ? 'remaining_amount','price withheld on server');PERFORM assert_false(r ? 'note_hidden','hidden note withheld');PERFORM assert_eq(r->'products','[]'::jsonb,'none mode actually withholds products');
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE fx jsonb; oc bigint; un bigint; usr uuid:=gen_random_uuid(); cfg jsonb; revision bigint; ff bigint; prod bigint; copy bigint; response jsonb;
BEGIN
 fx:=public.scanner_test_fixture();oc:=(fx->>'occasion')::bigint;
 SELECT unit INTO un FROM public.occasions WHERE id=oc;
 INSERT INTO auth.users(id,email) VALUES(usr,usr||'@scanner.invalid');
 INSERT INTO public.user_info(id,name,organization) SELECT usr,'Scanner editor',organization FROM public.occasions WHERE id=oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES(oc,usr,true);
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,usr,true);
 PERFORM set_config('request.jwt.claim.sub',usr::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',usr,'role','authenticated')::text,true);
 INSERT INTO public.form_fields(form,title,is_ticket_field) VALUES((fx->>'form')::bigint,'Scanner field',false) RETURNING id INTO ff;
 SELECT id INTO prod FROM eshop.products WHERE occasion=oc LIMIT 1;
 response:=public.get_scanner_settings(oc);cfg:=response#>'{data,config}';revision:=(response#>>'{data,revision}')::bigint;
 cfg:=jsonb_set(cfg,'{products}',jsonb_build_object('mode','selected','ids',jsonb_build_array(prod),'order',jsonb_build_array(prod)));
 cfg:=jsonb_set(cfg,'{fields}',jsonb_build_array(jsonb_build_object('key','order:'||(fx->>'form')||':'||ff,'source','order_field','form_id',(fx->>'form')::bigint,'field_id',ff,'label','Scanner field','default_visible',true)));
 response:=public.update_scanner_settings(oc,revision,cfg);PERFORM assert_eq(response->>'code','200','authorized settings roundtrip');
 response:=public.update_scanner_settings(oc,revision,cfg);PERFORM assert_eq(response->>'reason','settings_changed','CAS rejects stale draft');
 response:=public.update_scanner_settings(oc,NULL,cfg);PERFORM assert_eq(response->>'reason','settings_changed','NULL revision cannot overwrite');
 copy:=public.duplicate_occasion_internal_v1(oc,un,'cs');
 PERFORM assert_not_null(copy,'occasion duplicate completed');
 SELECT config INTO cfg FROM public.scanner_settings WHERE occasion_id=copy;
 PERFORM assert_not_null(cfg,'duplicate settings preserved');
 PERFORM public.scanner_validate_settings_internal(copy,cfg);
 PERFORM assert_true((cfg#>>'{products,ids,0}')::bigint<>prod,'copied product remapped');
 PERFORM assert_true((cfg#>>'{fields,0,field_id}')::bigint<>ff,'copied field remapped');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.scanner_sessions WHERE occasion_id=copy),'no sessions copied');
 PERFORM assert_true((SELECT occasion_hidden IS NULL FROM public.occasions WHERE id=copy),'no scan secret copied');
END $$;
ROLLBACK;
BEGIN;
DO $$
DECLARE fx jsonb; oc bigint; tid bigint; ff bigint; cfg jsonb; dto jsonb;
BEGIN
 fx:=public.scanner_test_fixture();oc:=(fx->>'occasion')::bigint;tid:=(fx#>>'{tickets,0}')::bigint;
 INSERT INTO public.form_fields(form,title,type,is_ticket_field) VALUES((fx->>'form')::bigint,'Diet','text',true) RETURNING id INTO ff;
 UPDATE eshop.tickets SET data=jsonb_build_object('fields',jsonb_build_array(jsonb_build_object(ff::text,'THIS TICKET ONLY'))) WHERE id=tid;
 SELECT config INTO cfg FROM public.scanner_settings WHERE occasion_id=oc;
 cfg:=jsonb_set(cfg,'{fields}',jsonb_build_array(jsonb_build_object('source','ticket_field','key','ticket:'||(fx->>'form')||':'||ff,'form_id',(fx->>'form')::bigint,'field_id',ff,'label','Diet')));
 SELECT p.dto INTO dto FROM public.scanner_ticket_projection_internal(oc,cfg,tid) p;
 PERFORM assert_eq(dto#>>'{fields,0,value}','THIS TICKET ONLY','ticket field comes from canonical ticket-owned answers');
 SELECT p.dto INTO dto FROM public.scanner_ticket_projection_internal(oc,cfg,(fx#>>'{tickets,1}')::bigint) p;
 PERFORM assert_true(dto#>>'{fields,0,value}' IS NULL,'another ticket never receives the first holder answer');
END $$;
ROLLBACK;
