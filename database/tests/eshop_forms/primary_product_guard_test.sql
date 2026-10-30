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
END $$;
