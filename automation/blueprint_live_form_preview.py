#!/usr/bin/env python3
"""Create isolated complete forms from allowlisted live configuration, no customer data."""
import json,copy,pathlib,sys
from blueprint_local_e2e import ROOT,BACKEND,PROJECT,sql,private_json
FOLDER=BACKEND/'live-form-preview'
def literal(value):return "'"+json.dumps(value,ensure_ascii=False).replace("'","''")+"'::jsonb"
def refresh_layouts(forms):
 paths=json.loads((BACKEND/'blueprint-preview-artifacts.json').read_text())
 converted=json.loads((BACKEND/paths['conversion']).read_text())
 resources=json.loads((BACKEND/paths['resources']).read_text())
 cases=[]
 for form in forms:
  request=copy.deepcopy(next(b for b in converted['blueprints'] if b['blueprintId']==form['sourceBlueprint'])['request'])
  request.update(id=form['blueprint'],occasion=form['occasion'],organization=form['request']['organization'])
  cases.append({'form':form,'request':request})
 payload={'cases':cases,'resources':resources}
 command="""BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $refresh$
DECLARE input jsonb:="""+literal(payload)+"""; c jsonb; req jsonb; occ bigint; bp bigint; revision bigint; result jsonb; before_state jsonb; after_state jsonb;
BEGIN
 FOR c IN SELECT * FROM jsonb_array_elements(input->'cases') LOOP
  occ:=(c#>>'{form,occasion}')::bigint;bp:=(c#>>'{form,blueprint}')::bigint;
  IF NOT EXISTS(SELECT 1 FROM public.forms f WHERE f.id=(c#>>'{form,form}')::bigint AND f.blueprint=bp AND f.occasion=occ AND f.link LIKE 'preview-%') THEN RAISE EXCEPTION 'Preview scope mismatch';END IF;
  SELECT jsonb_agg(jsonb_build_array(id,product,title,order_product_ticket,secret,secret_expiration_time) ORDER BY id) INTO before_state FROM eshop.spots WHERE blueprint=bp;
  SELECT layout_revision INTO revision FROM eshop.blueprints WHERE id=bp AND occasion=occ;
  PERFORM set_config('request.jwt.claim.sub',c#>>'{form,actor}',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM public.register_blueprint_text_resources(occ,NULL,input->'resources');
  req:=(c->'request')||jsonb_build_object('expected_layout_revision',revision);
  result:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
  IF result->>'status'<>'applied' THEN RAISE EXCEPTION 'Canonical refresh rejected: %',result;END IF;
  SELECT jsonb_agg(jsonb_build_array(id,product,title,order_product_ticket,secret,secret_expiration_time) ORDER BY id) INTO after_state FROM eshop.spots WHERE blueprint=bp;
  IF before_state IS DISTINCT FROM after_state THEN RAISE EXCEPTION 'Refresh changed commercial state';END IF;
 END LOOP;
END $refresh$;
COMMIT;
"""
 sql(command,capture=True,sensitive=True)
 print('Refreshed canonical preview layouts; all spot identities, products, orders and holds preserved.')

def main():
 assert sql('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton',capture=True).strip()==PROJECT
 assert sql('SELECT count(*) FROM public.email_capacity WHERE NOT paused OR worker_url IS NOT NULL',capture=True).strip()=='0'
 assert sql('SELECT count(*) FROM cron.job WHERE active',user='supabase_admin',capture=True).strip()=='0'
 assert sql('SELECT count(*) FROM eshop.external_services',capture=True).strip()=='0'
 manifest=FOLDER/'private-local-forms.json'
 if manifest.exists():
  if '--refresh-layouts' in sys.argv:refresh_layouts(json.loads(manifest.read_text()));return
  print('Existing preview forms preserved:',manifest);return
 source=json.loads((FOLDER/'private-source.json').read_text())
 paths=json.loads((BACKEND/'blueprint-preview-artifacts.json').read_text())
 converted=json.loads((BACKEND/paths['conversion']).read_text())
 resources=json.loads((BACKEND/paths['resources']).read_text())
 cases=[]
 for id,link in [(44,'preview-country-bal-2026'),(87,'preview-ples-akh-2026')]:
  snapshot=json.loads((FOLDER/f'private-plan-{id}.json').read_text());original=next(b for b in source['blueprints'] if b['id']==id)
  form=next(f for f in source['forms'] if f['blueprint']==id)
  record=next(b for b in converted['blueprints'] if b['blueprintId']==id)
  request=copy.deepcopy(record['request'])
  fields=copy.deepcopy([f for f in source['fields'] if f['form']==form['id']])
  cases.append({'id':id,'link':link,'source':original,'form':form,'occasion':next(o for o in source['occasions'] if o['id']==original['occasion']),
   'fields':fields, 'productTypes':[p for p in source['productTypes'] if p['occasion']==original['occasion']],
   'products':[p for p in source['products'] if p['occasion']==original['occasion']], 'request':request,'spots':snapshot['data']['spots'],'parity':snapshot['parity']})
 payload={'cases':cases,'resources':resources}
 script='''BEGIN;
CREATE TEMP TABLE preview_input(value jsonb);
INSERT INTO preview_input VALUES ('''+literal(payload)+''');
CREATE TEMP TABLE preview_result(value jsonb);
DO $seed$
DECLARE input jsonb; c jsonb; f jsonb; row jsonb; req jsonb; product_type bigint; occ bigint; fid bigint; bp bigint; bank bigint; un bigint; order_id bigint; ticket_id bigint; opt bigint; result jsonb;
BEGIN
 SELECT value INTO input FROM preview_input;
 FOR c IN SELECT * FROM jsonb_array_elements(input->'cases') LOOP
  f:=public.blueprint_test_fixture_internal((SELECT id FROM public.organizations WHERE title='Test Organization' ORDER BY id LIMIT 1));
  occ:=(f->>'occasion')::bigint;fid:=(f->>'form')::bigint;bp:=(f->>'blueprint')::bigint;
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SELECT unit INTO un FROM public.occasions WHERE id=occ;
  UPDATE public.occasions SET title='[TEST] '||(c#>>'{occasion,title}'),features=c#>'{occasion,features}',start_time=(c#>>'{occasion,start_time}')::timestamptz,end_time=(c#>>'{occasion,end_time}')::timestamptz WHERE id=occ;
  INSERT INTO public.unit_users(unit,"user",is_manager,is_editor,is_editor_view) VALUES(un,(f->>'actor')::uuid,true,true,true);
  INSERT INTO eshop.bank_accounts(title,account_number,account_number_human_readable,type,is_fetch_enabled,supported_currencies) VALUES('TEST - neplatit','123456/0100','123456/0100','FIO',false,ARRAY['CZK']) RETURNING id INTO bank;
  INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,(f->>'actor')::uuid,true);
  INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(un,bank,1);
  UPDATE public.forms SET title=c#>>'{form,title}',header=c#>>'{form,header}',header_off=c#>>'{form,header_off}',data=(c#>'{form,data}'),type=c#>>'{form,type}',is_open=true,bank_account=bank,link=c->>'link',deadline_duration_seconds=(c#>>'{form,deadline_duration_seconds}')::bigint,participant_capacity=(c#>>'{form,participant_capacity}')::int,waitlist_enabled=coalesce((c#>>'{form,waitlist_enabled}')::boolean,false),show_remaining_capacity=coalesce((c#>>'{form,show_remaining_capacity}')::boolean,false) WHERE id=fid;
  UPDATE public.forms SET link=public.reserve_public_link_internal('form',fid,link,true) WHERE id=fid;
  DELETE FROM public.form_fields WHERE form=fid;
  UPDATE eshop.products SET is_hidden=true WHERE id=(f->>'product')::bigint;
  FOR row IN SELECT * FROM jsonb_array_elements(c->'productTypes') LOOP
   INSERT INTO eshop.product_types(id,occasion,title,type) VALUES((row->>'id')::bigint,occ,row->>'title',row->>'type');
  END LOOP;
  FOR row IN SELECT * FROM jsonb_array_elements(c->'products') LOOP
   INSERT INTO eshop.products(id,occasion,product_type,title,description,price,currency_code,is_hidden,maximum,"order",data)
    VALUES((row->>'id')::bigint,occ,(row->>'product_type')::bigint,row->>'title',row->>'description',(row->>'price')::numeric,row->>'currency_code',(row->>'is_hidden')::boolean,(row->>'maximum')::bigint,(row->>'order')::bigint,row->'data');
  END LOOP;
  FOR row IN SELECT * FROM jsonb_array_elements(c->'fields') LOOP
   INSERT INTO public.form_fields(id,form,title,description,data,type,product_type,is_required,is_hidden,is_ticket_field,"order")
    VALUES((row->>'id')::bigint,fid,row->>'title',row->>'description',row->'data',row->>'type',(row->>'product_type')::bigint,(row->>'is_required')::boolean,(row->>'is_hidden')::boolean,(row->>'is_ticket_field')::boolean,(row->>'order')::bigint);
  END LOOP;
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM public.register_blueprint_text_resources(occ,NULL,input->'resources');
  req:=(c->'request')||jsonb_build_object('id',bp,'occasion',occ,'organization',(f#>'{request,organization}'),'expected_layout_revision',0);
  FOR row IN SELECT * FROM jsonb_array_elements(c->'spots') LOOP
   INSERT INTO eshop.spots(id,occasion,blueprint,title,product) VALUES((row->>'id')::bigint,occ,bp,row->>'title',(row->>'product')::bigint);
  END LOOP;
  result:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
  IF result->>'status'<>'applied' THEN RAISE EXCEPTION 'Canonical save rejected: %',result;END IF;
  order_id:=public.allocate_ticket_order_identity_internal(fid);
  UPDATE eshop.orders SET state='paid',data='{"email":"occupied-preview@example.invalid","name":"Testovací","surname":"Obsazenost"}'::jsonb WHERE id=order_id;
  FOR row IN SELECT * FROM jsonb_array_elements(c->'spots') LOOP
   IF row->>'state' IN ('ordered','used','taken') THEN
    INSERT INTO eshop.tickets(occasion,state) VALUES(occ,CASE WHEN row->>'state' IN('used','taken') THEN 'used' ELSE 'paid' END) RETURNING id INTO ticket_id;
    INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(order_id,ticket_id,(row->>'product')::bigint) RETURNING id INTO opt;
    UPDATE eshop.spots SET order_product_ticket=opt WHERE id=(row->>'id')::bigint;
   ELSIF row->>'state'='selected' THEN
    UPDATE eshop.spots SET secret=gen_random_uuid(),secret_expiration_time=now()+interval '1 day' WHERE id=(row->>'id')::bigint;
   ELSIF row->>'state'<>'available' THEN RAISE EXCEPTION 'Unsupported source state %',row->>'state'; END IF;
  END LOOP;
  INSERT INTO preview_result VALUES(f||jsonb_build_object('sourceBlueprint',c->'id','sourceParity',c->'parity','localFormLink',c->>'link','url','http://127.0.0.1:59601/form/'||(c->>'link')));
 END LOOP;
 PERFORM setval(pg_get_serial_sequence('eshop.spots','id'),(SELECT max(id) FROM eshop.spots));
 PERFORM setval(pg_get_serial_sequence('eshop.products','id'),(SELECT max(id) FROM eshop.products));
 PERFORM setval(pg_get_serial_sequence('eshop.product_types','id'),(SELECT max(id) FROM eshop.product_types));
 PERFORM setval(pg_get_serial_sequence('public.form_fields','id'),(SELECT max(id) FROM public.form_fields));
END $seed$;
SELECT jsonb_agg(value) FROM preview_result;
COMMIT;
'''
 private_json(FOLDER/'private-seed-input.json',payload)
 result=json.loads(sql(script,capture=True,sensitive=True));private_json(manifest,result)
 print('Created complete local forms:',*[f['url'] for f in result])
if __name__=='__main__':main()
