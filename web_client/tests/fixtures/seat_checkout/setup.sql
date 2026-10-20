DO $$
DECLARE org bigint; un bigint; oc bigint; fid bigint; bank bigint; pt bigint; prod bigint;
 node_id uuid:=gen_random_uuid(); font public.ticket_font_assets;
 bp bigint; seat bigint; email_field bigint; name_field bigint; surname_field bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Browser seat regression') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Browser seat regression',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time,features)
 VALUES('Browser seat regression',un,org,gen_random_uuid()::text,now(),now()+interval '1 day','[{"code":"blueprint","is_enabled":true}]'::jsonb) RETURNING id INTO oc;
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
 VALUES('Regression bank','FIO','123/0100',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 INSERT INTO eshop.blueprints(title,organization,occasion,objects,configuration)
 VALUES('Regression seats',org,oc,'[]','{"dimensions":{"width":5,"height":5}}') RETURNING id INTO bp;
 INSERT INTO public.forms(title,occasion,link,is_open,blueprint,bank_account)
 VALUES('Browser seat regression',oc,'seat-checkout-regression',true,bp,bank) RETURNING id INTO fid;
 -- Direct fixture inserts must participate in the same URL reservation contract.
 PERFORM public.reserve_public_link_internal('occasion',oc,(SELECT link FROM public.occasions WHERE id=oc),true);
 PERFORM public.reserve_public_link_internal('form',fid,'seat-checkout-regression',true);
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,price,currency_code,occasion,is_hidden)
 VALUES('Admission',pt,150,'CZK',oc,false) RETURNING id INTO prod;
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order")
 VALUES(fid,'email','E-mail',true,false,false,0) RETURNING id INTO email_field;
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order")
 VALUES(fid,'name','Jméno',true,false,false,1) RETURNING id INTO name_field;
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order")
 VALUES(fid,'surname','Příjmení',true,false,false,2) RETURNING id INTO surname_field;
 INSERT INTO public.form_fields(form,type,title,product_type,is_required,is_hidden,"order")
 VALUES(fid,'ticket','Vstupenky',pt,true,false,3);
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order")
 VALUES(fid,'spot','Výběr místa',true,false,true,4);
 INSERT INTO eshop.spots(title,product,occasion,blueprint)
 VALUES('A1',prod,oc,bp) RETURNING id INTO seat;
 -- Synthetic outline resources keep this click/checkout fixture self-contained.
 SELECT * INTO STRICT font FROM public.ticket_font_assets WHERE id LIKE 'builtin:%' ORDER BY id LIMIT 1;
 UPDATE public.ticket_font_assets SET layout_outline=jsonb_build_object(
  'id',font.id,'hash',font.metadata->>'sha256','family',font.metadata->>'family',
  'unitsPerEm',1000,'ascent',800,'descent',-200,'glyphs',jsonb_build_object(
    'A',jsonb_build_object('advance',600,'path','[["M",0,0],["L",300,700],["L",600,0],["Z"]]'::jsonb),
    '1',jsonb_build_object('advance',600,'path','[["M",250,0],["L",250,700],["L",350,700],["L",350,0],["Z"]]'::jsonb))) WHERE id=font.id;
 UPDATE eshop.blueprints SET objects='[]',layout_revision=1,layout=jsonb_build_object(
  'schemaVersion',1,'symbolSetVersion',1,
  'canvas',jsonb_build_object('x',0,'y',0,'width',400,'height',400,'fill','#ffffffff'),
  'defaultTextStyle',jsonb_build_object('fontId',font.id,'size',12,'color','#222222FF'),
  'nodes',jsonb_build_array(jsonb_build_object('id',node_id,'kind','seat','label','A1',
    'width',48,'height',48,'shape','roundedRect','fill','#267329FF','cornerRadius',8,
    'transform',jsonb_build_object('x',200,'y',200,'rotation',0))),
  'selectionUnits','[]'::jsonb) WHERE id=bp;
 PERFORM public.validate_blueprint_layout_internal((SELECT layout FROM eshop.blueprints WHERE id=bp));
 INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot) VALUES(bp,node_id,seat);
 PERFORM set_config('festapp.browser_fixture',jsonb_build_object('form',fid,'seat',seat,'node',node_id,'email',email_field,'name',name_field,'surname',surname_field)::text,true);
END $$;
SELECT current_setting('festapp.browser_fixture')::jsonb AS fixture;
