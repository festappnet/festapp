-- Synthetic authoring-only fixtures for the isolated loopback wizard workspace.
DO $$
DECLARE org bigint; u bigint; oc bigint; pt bigint; pr bigint; form_id bigint; plan bigint; bank_id bigint;
 i integer; n integer; nodes jsonb; node_id uuid; spot_id bigint;
BEGIN
 SELECT id INTO org FROM public.organizations WHERE title='Test Organization';
 IF org IS NULL THEN RAISE EXCEPTION 'Synthetic local organization required'; END IF;
 SELECT id INTO u FROM public.units WHERE organization=org ORDER BY id LIMIT 1;
 IF EXISTS(SELECT 1 FROM public.occasions WHERE external_source='setup-usability-synthetic') THEN RETURN; END IF;
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
 VALUES('Synthetic CZK account','FIO','123456/2010',ARRAY['CZK']) RETURNING id INTO bank_id;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(u,bank_id,0);
 FOR i IN 1..6 LOOP
  INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,is_hidden,is_open,external_source)
  VALUES(CASE WHEN i IN (1,2) THEN 'Synthetic repeated title' ELSE 'Synthetic source '||i END,org,u,'synthetic-source-'||i,
   now()+((i-3)*interval '1 month'),now()+((i-3)*interval '1 month')+interval '1 day',true,false,'setup-usability-synthetic') RETURNING id INTO oc;
  INSERT INTO eshop.product_types(occasion,title,type) VALUES(oc,'Admission','spot') RETURNING id INTO pt;
  INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) VALUES(oc,pt,'Synthetic admission',100,'CZK') RETURNING id INTO pr;
  INSERT INTO eshop.blueprints(occasion,organization,title,configuration,objects,groups)
  VALUES(oc,org,'Synthetic hall '||i,'{"dimensions":{"width":20,"height":10}}','[]','[]') RETURNING id INTO plan;
  nodes:='[]';
  FOR n IN 1..180 LOOP
   node_id:=gen_random_uuid();
   nodes:=nodes||jsonb_build_array(jsonb_build_object('id',node_id,'kind','seat','width',40,'height',40,
      'transform',jsonb_build_object('x',((n-1)%20)*50+50,'y',((n-1)/20)*50+50,'rotation',0)));
   INSERT INTO eshop.spots(occasion,blueprint,product,title) VALUES(oc,plan,pr,'Seat '||n) RETURNING id INTO spot_id;
   INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot) VALUES(plan,node_id,spot_id);
  END LOOP;
  UPDATE eshop.blueprints SET layout='{"schemaVersion":2,"symbolSetVersion":1,"canvas":{"x":0,"y":0,"width":1200,"height":800,"fill":"#ffffffff"},"styles":{},"seatingDefaults":{},"textPolicy":{"language":"und","direction":"auto"},"nodes":[],"selectionUnits":[],"attachments":[],"sections":[],"presets":[]}'::jsonb || jsonb_build_object('nodes',nodes),layout_revision=1 WHERE id=plan;
  INSERT INTO public.forms(occasion,title,link,blueprint,is_open,deadline_duration_seconds)
  VALUES(oc,'Synthetic form '||i,'synthetic-form-'||i,plan,false,NULL) RETURNING id INTO form_id;
  INSERT INTO public.form_fields(form,title,type,is_required,"order") VALUES(form_id,'E-mail','email',true,0);
  INSERT INTO public.form_fields(form,title,type,"order") VALUES(form_id,'Admission','ticket',1);
  INSERT INTO public.form_fields(form,title,type,is_ticket_field,is_required,product_type,"order") VALUES(form_id,'Admission product','product_type',true,true,pt,2);
  INSERT INTO public.form_fields(form,title,type,is_ticket_field,is_required,"order") VALUES(form_id,'Seat','spot',true,true,3);
 END LOOP;
END $$;
