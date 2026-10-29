-- Run ONLY in a fresh owned disposable backend after canonical baseline/migrations/seed.
DO $$
DECLARE oc bigint; frm bigint; pt bigint; bank bigint;
BEGIN
 IF (SELECT count(*) FROM public.organizations)<>1 OR
    (SELECT title FROM public.organizations WHERE id=1)<>'Test Organization' OR
    EXISTS(SELECT 1 FROM public.forms) THEN RAISE EXCEPTION 'Fresh synthetic backend required'; END IF;
 UPDATE public.organizations SET data=jsonb_set(coalesce(data,'{}'),'{DEFAULT_URL}','"http://127.0.0.1:59801"') WHERE id=1;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,features)
 VALUES(1,1,'Synthetic embedded checkout','embedded-event',now(),now()+interval '1 year','[{"code":"form","is_enabled":true},{"code":"ticket","is_enabled":true}]') RETURNING id INTO oc;
 INSERT INTO eshop.bank_accounts(title,account_number,type,supported_currencies,is_fetch_enabled)
 VALUES('Synthetic bank','123456/0100','FIO',ARRAY['CZK'],false) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(1,bank,1);
 INSERT INTO public.forms(occasion,title,link,is_open,header,data)
 VALUES(oc,'Synthetic checkout','embedded-synthetic',true,
 '<h1>Synthetic checkout</h1>'||repeat('<p>Long form: synthetic event information.</p>',18),
 '{"is_card_design":true}') RETURNING id INTO frm;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(oc,'Admission','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(product_type,title,price,currency_code,is_hidden) VALUES(pt,'Synthetic admission',120,'CZK',false);
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order",product_type) VALUES
 (frm,'email','Email',true,false,false,1,null),
 (frm,'ticket','Tickets',true,false,false,2,null),
 (frm,'product_type','Admission',true,false,true,3,pt),
 (frm,'name','Name',true,false,true,4,null),
 (frm,'surname','Surname',true,false,true,5,null);
 UPDATE public.forms SET link=public.reserve_public_link_internal('form',frm,'embedded-synthetic',true) WHERE id=frm;
END $$;
NOTIFY pgrst,'reload schema';
-- Reuse the canonical prepared number-symbol resources used by blueprint tests.
\ir ../../../../database/tests/blueprint/fixtures.sql
-- No email queue worker is started. No external provider credentials are supplied.
SELECT cron.unschedule(jobid) FROM cron.job;
DO $$
DECLARE f bigint; seat_form bigint; oc bigint; bp bigint; pr bigint; sid bigint;
 node uuid; nodes jsonb:='[]'; previous_role text:=current_setting('request.jwt.claim.role',true);
BEGIN
 SELECT id,occasion INTO f,oc FROM public.forms WHERE link='embedded-synthetic';
 SELECT id INTO pr FROM eshop.products LIMIT 1;
 INSERT INTO eshop.blueprints(organization,occasion,title)
 VALUES(1,oc,'Synthetic seats') RETURNING id INTO bp;
 FOR i IN 1..12 LOOP
  node:=gen_random_uuid();
  INSERT INTO eshop.spots(occasion,blueprint,product,title) VALUES(oc,bp,pr,'A'||i) RETURNING id INTO sid;
  nodes:=nodes||jsonb_build_array(jsonb_build_object('id',node,'kind','seat','width',40,'height',40,
   'transform',jsonb_build_object('x',40+((i-1)%6)*64,'y',40+((i-1)/6)*64,'rotation',0)));
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,blocked,product_assignment_mode)
   VALUES(bp,node,sid,false,'override');
 END LOOP;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.register_blueprint_text_resources(oc,NULL,public.blueprint_test_number_resources_internal());
 PERFORM set_config('request.jwt.claim.role',coalesce(previous_role,''),true);
 UPDATE eshop.blueprints SET layout=jsonb_build_object('schemaVersion',2,'symbolSetVersion',1,
  'canvas',jsonb_build_object('x',0,'y',0,'width',440,'height',190,'fill','#ffffffff'),
  'styles','{}'::jsonb,'seatingDefaults','{}'::jsonb,
  'textPolicy',jsonb_build_object('language','und','direction','auto'),
  'nodes',nodes,'selectionUnits','[]'::jsonb,'attachments','[]'::jsonb,'sections','[]'::jsonb,'presets','[]'::jsonb),
  layout_revision=1 WHERE id=bp;
 UPDATE public.occasions SET features=features||'[{"code":"blueprint","is_enabled":true}]'::jsonb WHERE id=oc;
 INSERT INTO public.forms(occasion,title,link,is_open,header,data,blueprint)
 SELECT occasion,'Synthetic seats','embedded-seats',true,'<h1>Synthetic seats</h1>',data,bp FROM public.forms WHERE id=f RETURNING id INTO seat_form;
 UPDATE public.forms SET link=public.reserve_public_link_internal('form',seat_form,'embedded-seats',true) WHERE id=seat_form;
 INSERT INTO public.form_fields(form,title,type,is_required,is_hidden,is_ticket_field,"order",data,product_type)
 SELECT seat_form,title,type,is_required,is_hidden,is_ticket_field,"order",data,product_type FROM public.form_fields WHERE form=f;
 INSERT INTO public.form_fields(form,title,type,is_required,is_ticket_field,"order") VALUES(seat_form,'Seat','spot',true,true,0);
 INSERT INTO public.forms(occasion,title,link,is_open,header_off) VALUES(oc,'Closed','embedded-closed',false,'<p>Synthetic sales closed</p>') RETURNING id INTO seat_form;
 UPDATE public.forms SET link=public.reserve_public_link_internal('form',seat_form,'embedded-closed',true) WHERE id=seat_form;
 INSERT INTO public.forms(occasion,title,link,is_open,header,data,participant_capacity,waitlist_enabled,waitlist_offer_duration_seconds)
 SELECT occasion,'Synthetic waitlist','embedded-waitlist',true,'<h1>Synthetic waitlist</h1>',data,1,true,86400 FROM public.forms WHERE id=f RETURNING id INTO seat_form;
 UPDATE public.forms SET link=public.reserve_public_link_internal('form',seat_form,'embedded-waitlist',true) WHERE id=seat_form;
 INSERT INTO public.form_fields(form,title,type,is_required,is_hidden,is_ticket_field,"order",data,product_type)
 SELECT seat_form,title,type,is_required,is_hidden,is_ticket_field,"order",data,product_type FROM public.form_fields WHERE form=f;
END $$;
NOTIFY pgrst,'reload schema';
INSERT INTO public.unit_legal_profiles(unit_id,revision,status,legal_name,country_code,registration_number,street,city,postal_code,contact_email,reviewed_organization_id,reviewed_at)
VALUES(1,1,'verified','Synthetic Organizer','CZ','00000000','Test street','Test city','00000','organizer@example.invalid',1,now());
INSERT INTO public.form_fields(form,title,type,is_required,is_hidden,is_ticket_field,"order",data)
SELECT id,'Birth date','birth_date',false,false,false,8,'{}' FROM public.forms WHERE link='embedded-synthetic';
