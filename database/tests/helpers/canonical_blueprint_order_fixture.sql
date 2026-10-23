CREATE TEMP TABLE IF NOT EXISTS canonical_order_layouts(blueprint bigint PRIMARY KEY);
-- Test-only bridge for older financial fixtures: create the saved canonical
-- document/bindings explicitly before exercising current checkout authority.
CREATE OR REPLACE FUNCTION pg_temp.prepare_order_blueprint_fixture(p_key uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f public.forms; b eshop.blueprints; spot eshop.spots; node uuid; nodes jsonb:='[]'; n integer:=0; previous_role text:=current_setting('request.jwt.claim.role',true);
BEGIN
 IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment WHERE singleton) THEN RAISE EXCEPTION 'disposable fixture database required'; END IF;
 SELECT * INTO STRICT f FROM public.forms WHERE key=p_key;
 SELECT * INTO b FROM eshop.blueprints WHERE occasion=f.occasion AND (f.blueprint IS NULL OR id=f.blueprint) ORDER BY id LIMIT 1;
 IF b.id IS NULL THEN
  IF NOT EXISTS(SELECT 1 FROM eshop.spots WHERE occasion=f.occasion AND product IS NOT NULL) THEN RETURN; END IF;
  INSERT INTO eshop.blueprints(occasion,organization,title) SELECT f.occasion,organization,'Finance test layout' FROM public.occasions WHERE id=f.occasion RETURNING * INTO b;
 END IF;
 IF b.layout IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_temp.canonical_order_layouts WHERE blueprint=b.id) THEN RETURN; END IF;
 INSERT INTO pg_temp.canonical_order_layouts VALUES(b.id) ON CONFLICT DO NOTHING;
 UPDATE eshop.spots SET blueprint=b.id WHERE occasion=f.occasion AND blueprint IS NULL AND product IS NOT NULL;
 nodes:=coalesce(b.layout->'nodes','[]');n:=jsonb_array_length(nodes);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.register_blueprint_text_resources(f.occasion,NULL,public.blueprint_test_number_resources_internal());
 PERFORM set_config('request.jwt.claim.role',coalesce(previous_role,''),true);
 FOR spot IN SELECT * FROM eshop.spots WHERE blueprint=b.id AND NOT EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings bind WHERE bind.spot=eshop.spots.id) ORDER BY id LOOP
  node:=gen_random_uuid();
  nodes:=nodes||jsonb_build_object('id',node,'kind','seat','width',20,'height',20,
   'transform',jsonb_build_object('x',mod(n,10)*30,'y',(n/10)*30,'rotation',0));n:=n+1;
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,blocked,product_assignment_mode) VALUES(b.id,node,spot.id,false,'override');
 END LOOP;
 UPDATE eshop.blueprints SET layout=jsonb_build_object('schemaVersion',2,'symbolSetVersion',1,
  'canvas',jsonb_build_object('x',0,'y',0,'width',1000,'height',greatest(1000,((n+9)/10)*30),'fill','#ffffffff'),
  'styles','{}'::jsonb,'seatingDefaults','{}'::jsonb,'textPolicy',jsonb_build_object('language','und','direction','auto'),
  'nodes',nodes,'selectionUnits','[]'::jsonb,'attachments','[]'::jsonb,'sections','[]'::jsonb,'presets','[]'::jsonb),
  layout_revision=1 WHERE id=b.id;
 UPDATE public.forms SET blueprint=b.id WHERE id=f.id;
END $$;
REVOKE ALL ON FUNCTION pg_temp.prepare_order_blueprint_fixture(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION pg_temp.prepare_order_fixture_input(p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE form_key uuid; f public.forms; selected bigint; secret uuid:=coalesce(nullif(p_input->>'secret','')::uuid,gen_random_uuid()); result jsonb;
BEGIN
 IF nullif(p_input->>'form','') IS NULL THEN RETURN p_input; END IF;
 BEGIN form_key:=(p_input->>'form')::uuid; EXCEPTION WHEN invalid_text_representation THEN RETURN p_input; END;
 SELECT * INTO f FROM public.forms WHERE key=form_key;
 IF f.id IS NULL THEN RETURN p_input; END IF;
 PERFORM pg_temp.prepare_order_blueprint_fixture(form_key);
 IF public.can_write_orders(f.occasion) OR NOT f.is_open THEN RETURN p_input; END IF;
 FOR selected IN SELECT DISTINCT (x->>'spot')::bigint FROM jsonb_array_elements(coalesce(p_input->'ticket','[]')) x WHERE x->>'spot' IS NOT NULL LOOP
  IF NOT EXISTS(SELECT 1 FROM eshop.spots WHERE id=selected AND occasion=f.occasion AND order_product_ticket IS NULL) THEN CONTINUE; END IF;
  -- Old finance fixtures seeded a secret without a lease. Acquire a real hold.
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL
   WHERE id=selected AND (secret_expiration_time IS NULL OR secret_expiration_time<=clock_timestamp());
  result:=public.select_spot(form_key,secret,selected,true);
  IF result->>'code'<>'200' THEN RAISE EXCEPTION 'Canonical financial fixture hold failed: %',result; END IF;
 END LOOP;
 RETURN p_input||jsonb_build_object('secret',secret);
END $$;
REVOKE ALL ON FUNCTION pg_temp.prepare_order_fixture_input(jsonb) FROM PUBLIC;
