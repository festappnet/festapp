-- Current-schema, task-owned local Wix backend only. Preserve existing purchases.
DO $$
DECLARE org bigint; un bigint; oc bigint; fid bigint; bank bigint; pt bigint;
 prod bigint; bp bigint; seat bigint; node_id uuid := gen_random_uuid();
BEGIN
 IF NOT EXISTS (SELECT 1 FROM festapp_test_support.disposable_environment
                WHERE singleton AND project='festapp-wix-qa-20261025') OR
    (SELECT title FROM public.organizations WHERE id=1) IS DISTINCT FROM 'Test Organization' THEN
   RAISE EXCEPTION 'Dedicated canonical Wix fixture required';
 END IF;
 IF EXISTS (SELECT 1 FROM public.forms WHERE link='wix-qa-safari-hold-20261026') THEN
   RETURN; -- Never reset a purchased seat or replay fixture creation.
 END IF;
 org := 1;
 INSERT INTO public.units(title,organization) VALUES('Wix Safari hold QA 20261026',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time,features)
 VALUES('Wix - ukázkový ples',un,org,'wix-qa-safari-hold-20261026',now(),now()+interval '30 days',
   '[{"code":"blueprint","is_enabled":true}]') RETURNING id INTO oc;
 INSERT INTO eshop.bank_accounts(title,type,account_number,account_number_human_readable,creditor_name,supported_currencies)
 VALUES('Wix synthetic bank','FIO','CZ7001000000000000123457','123457/0100','Synthetic Organizer',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 INSERT INTO eshop.blueprints(title,organization,occasion,objects,configuration)
 VALUES('Wix QA seats',org,oc,'[]','{"dimensions":{"width":5,"height":5}}') RETURNING id INTO bp;
 INSERT INTO public.forms(title,header,occasion,link,is_open,blueprint,bank_account,participant_capacity)
 VALUES('Wix - ukázkový ples','<p>Izolovaný test sedadel a bankovních instrukcí. Žádná skutečná platba.</p>',
   oc,'wix-qa-safari-hold-20261026',true,bp,bank,10) RETURNING id INTO fid;
 PERFORM public.reserve_public_link_internal('occasion',oc,'wix-qa-safari-hold-20261026',true);
 PERFORM public.reserve_public_link_internal('form',fid,'wix-qa-safari-hold-20261026',true);
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Vstupenka','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,price,currency_code,occasion,is_hidden)
 VALUES('Základní vstupenka',pt,150,'CZK',oc,false) RETURNING id INTO prod;
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order") VALUES
 (fid,'email','E-mail',true,false,false,0),
 (fid,'name','Jméno',true,false,false,1),
 (fid,'surname','Příjmení',true,false,false,2);
 INSERT INTO public.form_fields(form,type,title,product_type,is_required,is_hidden,"order")
 VALUES(fid,'ticket','Vstupenky',pt,true,false,3);
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order")
 VALUES(fid,'spot','Výběr místa',true,false,true,4);
 INSERT INTO eshop.spots(title,product,occasion,blueprint) VALUES('A1',prod,oc,bp) RETURNING id INTO seat;
 UPDATE eshop.blueprints SET layout_revision=1,layout=jsonb_build_object(
   'schemaVersion',2,'symbolSetVersion',1,
   'canvas',jsonb_build_object('x',0,'y',0,'width',400,'height',400,'fill','#FFFFFFFF'),
   'styles','{}'::jsonb,'seatingDefaults','{}'::jsonb,
   'textPolicy',jsonb_build_object('language','und','direction','auto'),
   'nodes',jsonb_build_array(jsonb_build_object('id',node_id,'kind','seat','width',48,'height',48,
     'transform',jsonb_build_object('x',200,'y',200,'rotation',0))),
   'selectionUnits','[]'::jsonb) WHERE id=bp;
 PERFORM public.validate_blueprint_layout_internal((SELECT layout FROM eshop.blueprints WHERE id=bp));
 INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot) VALUES(bp,node_id,seat);
-- The supported duration policy is scoped only to this new disposable unit.
 -- Existing units and the ordinary 900-second policy remain unchanged.
 INSERT INTO public.abuse_policy_overrides(rule_key,target_kind,target_id,base_limit,expires_at,reason,author)
 VALUES('hold.duration.seconds','unit',un,15,clock_timestamp()+interval '1 day','Disposable native Safari expiry qualification',(SELECT id FROM auth.users ORDER BY created_at LIMIT 1));
END $$;
NOTIFY pgrst, 'reload schema';
