CREATE OR REPLACE FUNCTION public.blueprint_test_fixture_internal(p_organization bigint)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE actor uuid; org bigint; un bigint; occ bigint; bp bigint; prod bigint; pt bigint; fid bigint; fkey uuid; d jsonb; seats jsonb; node uuid; i integer; font public.ticket_font_assets;
BEGIN
 SELECT id INTO actor FROM auth.users LIMIT 1;
 IF p_organization IS NULL THEN INSERT INTO public.organizations(title) VALUES('Blueprint integration fixture') RETURNING id INTO org;
 ELSE SELECT id INTO org FROM public.organizations WHERE id=p_organization;IF org IS NULL THEN RAISE EXCEPTION 'fixture organization not found';END IF;END IF;
 INSERT INTO public.units(title,organization) VALUES('Blueprint fixture',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Blueprint fixture',org,un,'bp-fixture-'||gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO occ;
 UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',occ,link,true) WHERE id=occ;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_editor) VALUES(occ,actor,true,true,true);
 INSERT INTO eshop.blueprints(occasion,organization,title,objects) VALUES(occ,org,'Blueprint fixture','[]') RETURNING id INTO bp;
 INSERT INTO public.forms(occasion,blueprint,title,link,is_open,type) VALUES(occ,bp,'Fixture','bp-form-'||gen_random_uuid(),true,'ticket') RETURNING id,key INTO fid,fkey;
 UPDATE public.forms SET link=public.reserve_public_link_internal('form',fid,link,true) WHERE id=fid;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Seats','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden) VALUES(occ,pt,'Seat',100,'CZK',false) RETURNING id INTO prod;
 INSERT INTO public.form_fields(form,product_type,type,is_ticket_field,is_hidden) VALUES(fid,pt,'product_type',true,false);
 SELECT * INTO font FROM public.ticket_font_assets WHERE id LIKE 'builtin:%' ORDER BY id LIMIT 1;
 UPDATE public.ticket_font_assets SET layout_outline=coalesce(layout_outline,jsonb_build_object('id',font.id,'hash',font.metadata->>'sha256','family',font.metadata->>'family','unitsPerEm',1000,'ascent',800,'descent',-200,'glyphs','{}'::jsonb)) WHERE id=font.id;
 d:='{"schemaVersion":1,"symbolSetVersion":1,"canvas":{"x":0,"y":0,"width":1000,"height":1000,"fill":"#ffffffff"},"nodes":[],"selectionUnits":[]}'::jsonb; d:=jsonb_set(d,'{defaultTextStyle}',jsonb_build_object('fontId',font.id,'size',24,'color','#222222FF')); seats:='[]';
 FOR i IN 1..4 LOOP
  node:=gen_random_uuid();
  d:=jsonb_set(d,'{nodes}',d->'nodes'||jsonb_build_array(jsonb_build_object('id',node,'kind','seat','width',40,'height',40,'transform',jsonb_build_object('x',i*60,'y',60,'rotation',0))));
  seats:=seats||jsonb_build_array(jsonb_build_object('nodeId',node,'spotId',NULL,'productId',prod,'title','S'||i,'groupNodeId',NULL,'selectionUnitId',NULL,'blocked',false,'operation','upsert'));
 END LOOP;
 RETURN jsonb_build_object('actor',actor,'occasion',occ,'form',fid,'formKey',fkey,'blueprint',bp,'product',prod,
  'request',jsonb_build_object('id',bp,'occasion',occ,'organization',org,'title','Fixture','expected_layout_revision',0,'layout',d,'seatChanges',seats,'groupProductChanges','[]'::jsonb,'areaBindingChanges','[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.blueprint_test_fixture_internal()
RETURNS jsonb LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.blueprint_test_fixture_internal(NULL::bigint)
$$;
DO $$
DECLARE f jsonb; r jsonb; command uuid:=gen_random_uuid(); request jsonb;
BEGIN
 f:=public.blueprint_test_fixture_internal();request:=f->'request';
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 UPDATE public.occasion_users SET is_editor=false,is_manager=false,is_editor_order=true WHERE occasion=(f->>'occasion')::bigint AND "user"=(f->>'actor')::uuid;
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.update_blueprint_client_sync_v1(request,command);RAISE EXCEPTION 'order-only geometry save accepted';
 EXCEPTION WHEN insufficient_privilege THEN PERFORM public.assert_eq(SQLERRM,'blueprint editor required','order-only geometry write denied'); END;
 RESET ROLE;
 BEGIN PERFORM public.save_blueprint_layout_internal_v1(request);RAISE EXCEPTION 'order-only internal geometry save accepted';
 EXCEPTION WHEN insufficient_privilege THEN PERFORM public.assert_eq(SQLERRM,'blueprint editor required','internal owner enforces same geometry permission'); END;
 PERFORM public.assert_eq((SELECT layout_revision::int FROM eshop.blueprints WHERE id=(f->>'blueprint')::bigint),0,'forbidden geometry leaves revision');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.blueprint_seat_bindings WHERE blueprint=(f->>'blueprint')::bigint),0,'forbidden geometry leaves bindings');
 PERFORM public.assert_eq((SELECT count(*)::int FROM public.client_mutation_receipts WHERE command_id=command),0,'forbidden geometry creates no receipt');
 UPDATE public.occasion_users SET is_editor=true,is_editor_order=false WHERE occasion=(f->>'occasion')::bigint AND "user"=(f->>'actor')::uuid;
 SET LOCAL ROLE authenticated;
 r:=public.update_blueprint_client_sync_v1(request,command);
 RESET ROLE;
 PERFORM public.assert_eq(r->>'status','applied','geometry editor succeeds independently of order permission');
 PERFORM public.assert_eq((r#>>'{data,layout_revision}')::int,1,'editor save accepted revision');
 UPDATE public.occasion_users SET is_editor=false,is_manager=true WHERE occasion=(f->>'occasion')::bigint AND "user"=(f->>'actor')::uuid;
 request:=jsonb_set(request,'{expected_layout_revision}','1');request:=jsonb_set(request,'{seatChanges}','[]');
 SET LOCAL ROLE authenticated;
 r:=public.update_blueprint_client_sync_v1(request,gen_random_uuid());
 RESET ROLE;
 PERFORM public.assert_eq(r->>'status','applied','occasion manager can edit geometry');
 PERFORM public.assert_eq((r#>>'{data,layout_revision}')::int,2,'manager save accepted revision');
END $$;
