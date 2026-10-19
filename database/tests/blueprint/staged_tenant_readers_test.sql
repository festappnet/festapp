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

BEGIN;
DO $$
DECLARE f jsonb; selected jsonb; r jsonb; sid bigint; admin_r jsonb;
BEGIN
 f:=public.blueprint_test_fixture_internal();
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 INSERT INTO eshop.spots(occasion,blueprint,title,product) VALUES((f->>'occasion')::bigint,(f->>'blueprint')::bigint,'Legacy chair',(f->>'product')::bigint) RETURNING id INTO sid;
 UPDATE eshop.blueprints SET objects=jsonb_build_array(jsonb_build_object('type','spot','id',sid,'x',0,'y',0)) WHERE id=(f->>'blueprint')::bigint;
 r:=public.get_blueprint(gen_random_uuid(),(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 PERFORM public.assert_eq((r->>'code')::int,200,'unreleased tenant public reader works');
 PERFORM public.assert_eq((r->'data') ? 'objects',true,'unreleased tenant retains geometry');
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,spots}'),1,'unreleased tenant retains seats');
 r:=public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=(f->>'occasion')::bigint));
 PERFORM public.assert_eq((r->'data') ? 'objects',true,'unreleased admin reader retains geometry');
 DELETE FROM eshop.spots WHERE id=sid;
 r:=public.update_blueprint_client_sync_v1(f->'request',gen_random_uuid());
 PERFORM public.assert_eq((r->>'code')::int,200,'canonical aggregate saved');
 UPDATE eshop.blueprints SET objects='[{"type":"spot","id":-999}]' WHERE id=(f->>'blueprint')::bigint;
 r:=public.get_blueprint(gen_random_uuid(),(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 PERFORM public.assert_eq((r->>'code')::int,200,'converted public reader works');
 PERFORM public.assert_eq((r->'data') ? 'objects',false,'converted reader omits legacy geometry');
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,spots}'),4,'converted reader uses bindings');
 admin_r:=public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=(f->>'occasion')::bigint));
 PERFORM public.assert_eq((admin_r->'data') ? 'objects',false,'converted admin omits legacy geometry');
 INSERT INTO public.organizations(id,title) VALUES(3,'Selected rollout tenant') ON CONFLICT(id) DO NOTHING;
 selected:=public.blueprint_test_fixture_internal(3);
 r:=public.get_blueprint(gen_random_uuid(),(selected->>'formKey')::uuid,(selected->>'blueprint')::bigint);
 PERFORM public.assert_eq(r->>'reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED','selected tenant cannot fall back');
 PERFORM public.assert_eq(has_function_privilege('anon','public.get_blueprint_legacy_rollout_internal(uuid,uuid,bigint)','execute'),false,'legacy helper not callable publicly');
 PERFORM public.assert_eq(has_function_privilege('authenticated','public.get_blueprint_for_edit_legacy_rollout_internal(text)','execute'),false,'admin helper not callable directly');
END $$;
ROLLBACK;
