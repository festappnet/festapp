-- test-setup: database/tests/blueprint/fixtures.sql
DO $$
DECLARE actor uuid; org bigint; un bigint; oc bigint; fm bigint; parent bigint;
 pt bigint; prod bigint; second bigint; field_id bigint; optional_type bigint; optional_field bigint;
 payload jsonb; result jsonb; bundle jsonb; link text:='primary-guard-'||gen_random_uuid();
BEGIN
 PERFORM create_user_for_test('primary-guard-editor','primary-guard@example.invalid');
 actor:=get_user_id('primary-guard-editor');
 INSERT INTO public.organizations(title) VALUES('Primary product guard') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Primary product guard',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time)
 VALUES('Primary product guard',un,org,link,now(),now()+interval '1 day') RETURNING id INTO oc;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_order,is_editor_order_view,is_editor_view)
 VALUES(oc,actor,true,true,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 INSERT INTO public.forms(occasion,title,link) VALUES(oc,'Original',link) RETURNING id INTO fm;
 PERFORM public.reserve_public_link_internal('form',fm,link,true);
 INSERT INTO public.form_fields(form,type,is_hidden) VALUES(fm,'ticket',true) RETURNING id INTO parent;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(oc,'Participation','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden)
 VALUES(oc,pt,'Standard',2650,'CZK',false) RETURNING id INTO prod;
 INSERT INTO public.form_fields(form,type,product_type,is_ticket_field,is_required,is_hidden)
 VALUES(fm,'product_type',pt,true,true,false) RETURNING id INTO field_id;
 bundle:=public.get_form_for_edit(link);
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(bundle#>'{data,form_fields}') f
   WHERE (f->>'id')::bigint=field_id AND NOT (f->>'can_delete')::boolean AND f->>'delete_blocked_reason'='primary_product'),
   'Unused primary group must already be protected in editor projection');
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(bundle#>'{data,products}') p
   WHERE (p->>'id')::bigint=prod AND NOT (p->>'can_delete')::boolean),'Last primary option protected before any orders exist');
 payload:=jsonb_build_object('id',fm,'occasion',oc,'link',link);
 result:=public.update_form_internal_v1(payload||jsonb_build_object('title','Broken','deleted_field_ids',jsonb_build_array(field_id)));
 PERFORM assert_eq(result->>'message','FORM_DELETE_primary_product','Cannot delete primary group through form save');
 PERFORM assert_eq((SELECT title FROM public.forms WHERE id=fm),'Original','Rejected save rolls back all changes');
 result:=public.update_form_internal_v1(payload||jsonb_build_object('deleted_field_ids',jsonb_build_array(parent)));
 PERFORM assert_eq(result->>'message','FORM_DELETE_primary_product','Cannot remove primary group by deleting its parent');
 result:=public.update_form_internal_v1(payload||jsonb_build_object('deleted_product_ids',jsonb_build_array(prod)));
 PERFORM assert_eq(result->>'message','FORM_DELETE_primary_product','Cannot delete last option in form save');
 result:=public.update_form_internal_v1(payload||jsonb_build_object('form_fields',jsonb_build_array(
   jsonb_build_object('id',field_id,'type','product_type','product_type_id',pt,'is_hidden',true,'is_ticket_field',true))));
 PERFORM assert_eq(result->>'message','FORM_DELETE_primary_product','Cannot hide primary group');
 result:=public.update_form_internal_v1(payload||jsonb_build_object('form_fields',jsonb_build_array(
   jsonb_build_object('id',field_id,'type','product_type','is_ticket_field',true,'is_hidden',false,
     'product_type',jsonb_build_object('id',pt,'title','Participation','type',NULL)))));
 PERFORM assert_eq(result->>'message','FORM_DELETE_primary_product','Cannot demote primary group to an ordinary group');
 BEGIN
   PERFORM public.delete_product_client_sync_v1(prod,gen_random_uuid(),0);
   RAISE EXCEPTION 'Last primary option deletion accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'FORM_DELETE_primary_product' THEN RAISE; END IF; END;
 BEGIN
   PERFORM public.update_product_client_sync_v1(jsonb_build_object('id',prod,'is_hidden',true),gen_random_uuid());
   RAISE EXCEPTION 'Last primary option hiding accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'FORM_DELETE_primary_product' THEN RAISE; END IF; END;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden)
 VALUES(oc,pt,'Another price',2800,'CZK',false) RETURNING id INTO second;
 result:=public.delete_product_client_sync_v1(prod,gen_random_uuid(),0);
 PERFORM assert_eq((result->>'code')::integer,200,'An unused variant can be deleted while another visible variant remains');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.products WHERE id=second),'Primary group retains a usable option');
 PERFORM assert_true(public.primary_product_delete_blocked_internal(second),'Remaining variant is protected immediately');
 result:=public.update_product_client_sync_v1(jsonb_build_object('id',second,'title','Renamed','price',2900),gen_random_uuid());
 PERFORM assert_eq((result->>'code')::integer,200,'Primary option name and price remain editable');
 INSERT INTO eshop.product_types(occasion,title) VALUES(oc,'Optional dinner') RETURNING id INTO optional_type;
 INSERT INTO public.form_fields(form,type,product_type,is_ticket_field) VALUES(fm,'product_type',optional_type,true) RETURNING id INTO optional_field;
 result:=public.update_form_internal_v1(payload||jsonb_build_object('deleted_field_ids',jsonb_build_array(optional_field)));
 PERFORM assert_eq((result->>'code')::integer,200,'Unused optional group can still be deleted');

 -- Duplicated seated forms can attach the primary catalog to the ticket
 -- container itself, with separate food/transport groups beneath it.
 DELETE FROM public.form_fields WHERE id=field_id;
 UPDATE public.form_fields SET product_type=pt,is_hidden=false WHERE id=parent;
 INSERT INTO public.form_fields(form,type,product_type,is_ticket_field)
 VALUES(fm,'product_type',optional_type,true) RETURNING id INTO optional_field;
 result:=public.update_form_internal_v1(payload||jsonb_build_object('is_open',true,
   'form_fields',jsonb_build_array(
     jsonb_build_object('id',parent,'type','ticket','product_type_id',pt,'is_hidden',false),
     jsonb_build_object('id',optional_field,'type','product_type','product_type_id',optional_type,
       'is_ticket_field',true,'is_hidden',false))));
 PERFORM assert_eq((result->>'code')::integer,200,
   'Opening a form whose ticket container owns the primary group must succeed');
 PERFORM assert_true((SELECT is_open FROM public.forms WHERE id=fm),'Opening is persisted');
 result:=public.update_form_internal_v1(payload||jsonb_build_object('form_fields',jsonb_build_array(
   jsonb_build_object('id',parent,'type','ticket','product_type_id',pt,'is_hidden',true))));
 PERFORM assert_eq(result->>'message','FORM_DELETE_primary_product','Cannot hide ticket-owned primary group');
 result:=public.update_form_internal_v1(payload||jsonb_build_object('deleted_field_ids',jsonb_build_array(parent)));
 PERFORM assert_eq(result->>'message','FORM_DELETE_primary_product','Cannot delete ticket-owned primary group');
 BEGIN
   PERFORM public.update_product_client_sync_v1(jsonb_build_object('id',second,'is_hidden',true),gen_random_uuid());
   RAISE EXCEPTION 'Last ticket-owned primary option hiding accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'FORM_DELETE_primary_product' THEN RAISE; END IF; END;
END $$;

-- The actual Copy occasion command must produce an independently editable form,
-- not merely a hand-built field representation accepted by the guard.
DO $$
DECLARE actor uuid; fixture jsonb; org bigint; un bigint; source bigint; target bigint;
 source_form bigint; target_form bigint; source_primary bigint; addon bigint; bank bigint;
 result jsonb; bundle jsonb; fields jsonb; payload jsonb; target_plan bigint; seat bigint;
 input jsonb; quote jsonb; copied_primary bigint; source_layout jsonb;
BEGIN
 PERFORM create_user_for_test('copied-ball-editor','copied-ball-'||gen_random_uuid()||'@example.invalid');
 actor:=get_user_id('copied-ball-editor');
 fixture:=public.blueprint_test_fixture_internal();
 source:=(fixture->>'occasion')::bigint; source_form:=(fixture->>'form')::bigint;
 SELECT organization,unit INTO org,un FROM public.occasions WHERE id=source;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor,is_editor_view) VALUES(un,actor,true,true,true);
 DELETE FROM public.occasion_users WHERE occasion=source;
 INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor,is_editor_view,is_editor_order,is_editor_order_view)
 VALUES(source,actor,true,true,true,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 result:=public.update_blueprint_client_sync_v1(fixture->'request',gen_random_uuid());
 PERFORM assert_eq(result->>'status','applied','Source plan saved through canonical command');
 UPDATE public.occasions SET title='Skautský ples 2026',features=
 '[{"code":"form","is_enabled":true},{"code":"ticket","is_enabled":true},{"code":"blueprint","is_enabled":true}]'
 WHERE id=source;
 SELECT product_type INTO source_primary FROM eshop.products WHERE id=(fixture->>'product')::bigint;
 UPDATE eshop.products SET title='Místo u stolu',price=200 WHERE id=(fixture->>'product')::bigint;
 UPDATE public.form_fields SET type='ticket',title='Vstupenky',is_ticket_field=false WHERE form=source_form;
 INSERT INTO public.form_fields(form,type,title,is_ticket_field) VALUES(source_form,'spot','Místo',true),
 (source_form,'email','E-mail',false),(source_form,'name','Jméno',false),(source_form,'surname','Příjmení',false);
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(source,'Večeře','food') RETURNING id INTO addon;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden)
 VALUES(source,addon,'Večeře',170,'CZK',false);
 INSERT INTO public.form_fields(form,type,title,product_type,is_ticket_field)
 VALUES(source_form,'product_type','Večeře',addon,true);
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(source,'Odvoz','taxi') RETURNING id INTO addon;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden)
 VALUES(source,addon,'Domoradovice',0,'CZK',false);
 INSERT INTO public.form_fields(form,type,title,product_type,is_ticket_field)
 VALUES(source_form,'product_type','Odvoz',addon,true);
 INSERT INTO eshop.bank_accounts(title,account_number,type,is_fetch_enabled,supported_currencies)
 VALUES('Účet pořadatele','123456/0100','FIO',false,ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(un,bank,1);
 UPDATE public.forms SET title='Skautský ples 2026',is_open=false,bank_account=bank WHERE id=source_form;
 SELECT layout INTO source_layout FROM eshop.blueprints WHERE id=(fixture->>'blueprint')::bigint;
 SET LOCAL ROLE authenticated;
 PERFORM assert_true(public.can_read_unit_administration(un),'Fixture organizer can enter the unit administration UI');
 result:=public.start_occasion_lifecycle(NULL,NULL,source,'copy',gen_random_uuid(),NULL,'cs');
 PERFORM assert_eq(result->>'code','200','Actual UI occasion-copy command succeeds');
 target:=(result#>>'{data,occasionId}')::bigint;
 RESET ROLE;
 PERFORM assert_true(target IS NOT NULL AND target<>source,'Copied occasion has a fresh identity');
 SELECT id,blueprint INTO target_form,target_plan FROM public.forms WHERE occasion=target;
 SELECT product_type INTO copied_primary FROM public.form_fields WHERE form=target_form AND type='ticket';
 PERFORM assert_true(copied_primary<>source_primary,'Primary group belongs to copied occasion');
 PERFORM assert_true(target_plan<>(fixture->>'blueprint')::bigint,'Copied plan has an independent identity');
 PERFORM assert_eq((SELECT count(*)::integer FROM eshop.spots WHERE blueprint=target_plan),4,'All source seats copied');
 PERFORM assert_eq((SELECT count(*)::integer FROM eshop.orders WHERE occasion=target),0,'Copy creates no orders');
 PERFORM assert_true(NOT (SELECT is_open FROM public.forms WHERE id=target_form),'Copied form starts closed');
 bundle:=public.get_form_for_edit((SELECT link FROM public.forms WHERE id=target_form));
 PERFORM assert_eq(bundle->>'code','200','Copied form loads through real editor reader');
 SELECT jsonb_agg(field||jsonb_build_object('product_type',(
   SELECT kind||jsonb_build_object('products',(SELECT jsonb_agg(product)
     FROM jsonb_array_elements(bundle#>'{data,products}') product WHERE product->>'product_type'=kind->>'id'))
   FROM jsonb_array_elements(bundle#>'{data,product_types}') kind WHERE kind->>'id'=field->>'product_type')))
 INTO fields FROM jsonb_array_elements(bundle#>'{data,form_fields}') field;
 payload:=jsonb_build_object('id',target_form,'occasion',target,'link',bundle#>>'{data,form,link}',
   'title','Skautský ples 2027','is_open',true,'form_fields',fields,
   'expected_aggregate_version',bundle#>'{data,form,aggregate_version}',
   'expected_product_versions',(SELECT jsonb_object_agg(p->>'id',p->'aggregate_version') FROM jsonb_array_elements(bundle#>'{data,products}') p),
   'expected_product_type_versions',(SELECT jsonb_object_agg(p->>'id',p->'aggregate_version') FROM jsonb_array_elements(bundle#>'{data,product_types}') p));
 SET LOCAL ROLE authenticated;
 result:=public.update_form_client_sync_v1(payload,gen_random_uuid());
 PERFORM assert_eq(result->>'status','applied','Actual editor command saves and opens copied form: '||result::text);
 RESET ROLE;
 PERFORM assert_true((SELECT is_open FROM public.forms WHERE id=target_form),'Copied form opening persisted');
 PERFORM assert_eq((SELECT title FROM public.forms WHERE id=source_form),'Skautský ples 2026','Copy save does not edit source form');
 PERFORM assert_true(NOT (SELECT is_open FROM public.forms WHERE id=source_form),'Source form stays closed');
 UPDATE public.forms SET is_open=false WHERE id=target_form;
 SELECT min(id) INTO seat FROM eshop.spots WHERE blueprint=target_plan;
 input:=jsonb_build_object('email','objednavka@example.invalid','form_key',(SELECT key FROM public.forms WHERE id=target_form));
 SET LOCAL ROLE authenticated;
 quote:=public.preview_blueprint_seat_order(target,org,un,target_plan,ARRAY[seat],input,true);
 PERFORM assert_eq(quote->>'code','200','Real plan-order quote accepts closed copied form');
 result:=public.create_blueprint_seat_order(target,org,un,target_plan,ARRAY[seat],input,
   ARRAY[seat],ARRAY[seat],quote#>'{quote,blueprints}',quote->>'confirmationHash',gen_random_uuid(),true,actor);
 PERFORM assert_eq(result->>'status','applied','Real plan-editor command creates order with copied form closed');
 RESET ROLE;
 PERFORM assert_eq((SELECT count(*)::integer FROM eshop.orders WHERE occasion=target),1,'Order is actually persisted in copy');
 PERFORM assert_eq((SELECT count(*)::integer FROM eshop.tickets WHERE occasion=target),1,'Admission is actually persisted in copy');
 PERFORM assert_true(NOT (SELECT is_open FROM public.forms WHERE id=target_form),'Plan order leaves copied form closed');
 PERFORM assert_eq((SELECT count(*)::integer FROM eshop.orders WHERE occasion=source),0,'Source has no new order');
 PERFORM assert_eq((SELECT layout FROM eshop.blueprints WHERE id=(fixture->>'blueprint')::bigint),source_layout,'Source plan unchanged');
END $$;
