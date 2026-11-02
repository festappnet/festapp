DO $$
DECLARE org bigint; un bigint; oc bigint; bp bigint; invalid jsonb; col text;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Canonical blueprint storage') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Canonical storage unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,un,'Canonical storage',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO eshop.blueprints(occasion,organization,title) VALUES(oc,org,'New plan') RETURNING id INTO bp;
 PERFORM assert_eq((SELECT layout->'schemaVersion' FROM eshop.blueprints WHERE id=bp),'2'::jsonb,'Implicit creation is canonical');
 PERFORM assert_true((SELECT layout->'nodes'='[]'::jsonb AND objects IS NULL AND groups IS NULL AND configuration IS NULL AND background_svg IS NULL FROM eshop.blueprints WHERE id=bp),'No second stored geometry');
 FOR invalid IN SELECT v FROM jsonb_array_elements('[null,{}, {"schemaVersion":1,"nodes":[]},{"schemaVersion":"2","nodes":[]}]') v LOOP
  BEGIN
   UPDATE eshop.blueprints SET layout=nullif(invalid,'null'::jsonb) WHERE id=bp;
   RAISE EXCEPTION 'Retired or malformed layout accepted';
  EXCEPTION WHEN check_violation OR not_null_violation THEN NULL; END;
 END LOOP;
 FOREACH col IN ARRAY ARRAY['objects','groups','configuration'] LOOP
  BEGIN
   EXECUTE format('UPDATE eshop.blueprints SET %I=$1 WHERE id=$2',col) USING '[]'::jsonb,bp;
   RAISE EXCEPTION 'Retired geometry column accepted: %',col;
  EXCEPTION WHEN check_violation THEN NULL; END;
 END LOOP;
 BEGIN
  UPDATE eshop.blueprints SET background_svg='<svg/>' WHERE id=bp;
  RAISE EXCEPTION 'Retired background accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM assert_true(to_regprocedure('public.get_blueprint_editor(text)') IS NULL,'Retired editor RPC absent');
 PERFORM assert_true(to_regprocedure('public.migrate_blueprint_layout_reviewed_internal(text,text,jsonb,uuid)') IS NULL,'Runtime legacy migration API absent');
END $$;
