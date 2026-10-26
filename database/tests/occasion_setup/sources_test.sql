DO $$
DECLARE actor uuid; org bigint; target bigint; foreign_unit bigint;
  occ bigint; pt bigint; product bigint; form_id bigint; plan bigint; result jsonb; source jsonb; node_id uuid := gen_random_uuid(); spot_id bigint;
BEGIN
  SELECT ui.id,ui.organization INTO actor,org FROM public.user_info ui LIMIT 1;
  SELECT unit INTO target FROM public.unit_users WHERE "user"=actor AND (is_manager OR is_editor) LIMIT 1;
  INSERT INTO public.units(title,organization) VALUES('Inaccessible source unit',org) RETURNING id INTO foreign_unit;
  INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
    VALUES(org,target,'Source configuration test','source-'||gen_random_uuid(),now()-interval '1 year',now()-interval '11 months') RETURNING id INTO occ;
  INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Tickets','spot') RETURNING id INTO pt;
  INSERT INTO eshop.products(occasion,product_type,title,price,currency_code)
    VALUES(occ,pt,'Original ticket',690,'CZK') RETURNING id INTO product;
  INSERT INTO eshop.blueprints(occasion,organization,title,configuration,objects,groups)
    VALUES(occ,org,'Original hall','{"dimensions":{"width":12,"height":8}}',
      '[{"x":1,"y":2,"type":"spot","title":"A1","state":"ordered","secret":"do-not-export"}]','[{"id":1,"title":"A"}]') RETURNING id INTO plan;
  UPDATE eshop.blueprints SET layout='{"schemaVersion":2,"symbolSetVersion":1,"canvas":{"x":0,"y":0,"width":1000,"height":1000,"fill":"#ffffffff"},"styles":{},"seatingDefaults":{},"textPolicy":{"language":"und","direction":"auto"},"nodes":[],"selectionUnits":[],"attachments":[],"sections":[],"presets":[]}'::jsonb,
    layout_revision=1 WHERE id=plan;
  UPDATE eshop.blueprints SET layout=jsonb_set(layout,'{nodes}',jsonb_build_array(jsonb_build_object(
    'id',node_id,'kind','seat','width',40,'height',40,'transform',jsonb_build_object('x',60,'y',60,'rotation',0)))) WHERE id=plan;
  INSERT INTO eshop.spots(occasion,blueprint,product,title,secret) VALUES(occ,plan,product,'A1',gen_random_uuid()) RETURNING id INTO spot_id;
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot) VALUES(plan,node_id,spot_id);
  INSERT INTO public.forms(occasion,title,link,blueprint,is_open)
    VALUES(occ,'Original registration','source-form-'||gen_random_uuid(),plan,true) RETURNING id INTO form_id;
  INSERT INTO public.form_fields(form,title,type,is_required,"order") VALUES(form_id,'Name','name',true,0);
  INSERT INTO public.form_fields(form,title,type,product_type,"order") VALUES(form_id,'Tickets','product_type',pt,1);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  result := public.get_occasion_setup_sources(target);
  SELECT x INTO source FROM jsonb_array_elements(result) x WHERE (x->'occasion'->>'id')::bigint=occ;
  PERFORM assert_true(source IS NOT NULL,'Real source occasion is available');
  PERFORM assert_eq(source->'forms'->0->>'title','Original registration','Source form title');
  PERFORM assert_eq(jsonb_array_length(source->'forms'->0->'fields'),2,'All fields retained');
  PERFORM assert_eq(source->'forms'->0->'fields'->1->'product_type_data'->'products'->0->>'title','Original ticket','Real products retained');
  PERFORM assert_eq((source#>>'{blueprints,0,blueprintLayoutDraft,seatBindings,0,productId}')::bigint,product,'Safe product binding retained');
  PERFORM assert_false((source->'blueprints'->0) ? 'objects','Legacy runtime objects are not exported');
  PERFORM assert_false((source->'blueprints')::text LIKE '%secret%' OR (source->'blueprints')::text LIKE '%spotId%','No reservation secrets or runtime spot IDs');
  PERFORM assert_false(source ? 'orders','No orders exported');
  PERFORM assert_false((source->'forms'->0->>'is_open')::boolean,'Source is a closed draft configuration');
  BEGIN PERFORM public.get_occasion_setup_sources(foreign_unit); RAISE EXCEPTION 'foreign sources accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  EXECUTE 'RESET ROLE';
END $$;
