#!/usr/bin/env python3
"""Create task-owned qualification events through the canonical blueprint writer.

No production URL/configuration is accepted. Optional background bytes must already
be registered by the real image worker; the existing trusted copy helper scopes
that processed resource to the synthetic mixed event.
"""
import json
import pathlib
import time
import uuid
from blueprint_local_e2e import ROOT, BACKEND, PROJECT, sql, private_json, run

MANIFEST = BACKEND / 'blueprint-1000-fixtures.json'

def literal(value):
    return "'" + json.dumps(value, ensure_ascii=False).replace("'", "''") + "'::jsonb"

def guard():
    config = (BACKEND / 'supabase/config.toml').read_text()
    if PROJECT != 'festapp-blueprint-1000-e2e-20261020' or f'project_id = "{PROJECT}"' not in config or 'port = 59721' not in config or 'port = 59722' not in config:
        raise RuntimeError('Exact disposable project and ports required')
    if sql('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton', capture=True).strip() != PROJECT:
        raise RuntimeError('Exact owned database marker required')
    defines = json.loads((BACKEND / 'private-defines.json').read_text())
    if defines['FESTAPP_SUPABASE_URL'] != 'http://127.0.0.1:59721':
        raise RuntimeError('Exact local HTTP endpoint required')
    if sql('SELECT count(*) FROM public.email_capacity WHERE NOT paused OR worker_url IS NOT NULL', capture=True).strip() != '0':
        raise RuntimeError('Email fence required')
    if sql('SELECT count(*) FROM cron.job WHERE active', user='supabase_admin', capture=True).strip() != '0':
        raise RuntimeError('Inactive cron required')

def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, PROJECT + ':' + name))

def node(name, kind, x, y, width=40, height=40, **options):
    return dict(id=identifier(name), kind=kind, width=width, height=height,
                transform=dict(x=x, y=y, rotation=options.pop('rotation', 0)), **options)

def geometry(kind, product, font):
    nodes, changes, groups, units = [], [], [], []
    count = 950 if kind == 'mixed' else 1000
    for index in range(count):
        group = None
        if kind == 'tables':
            table_index, offset = divmod(index, 10)
            group = identifier(kind + ':table:' + str(table_index))
            if offset == 0:
                nodes.append(node(kind + ':table:' + str(table_index), 'table', 180 + table_index % 10 * 460,
                                  170 + table_index // 10 * 300, 220, 100, label='Mixed table', surface={'type':'rect'}, style={'material':'simple'}))
                groups.append(dict(groupNodeId=group, productId=product))
            x, y = (offset % 5 - 2) * 64, (-110 if offset < 5 else 110)
        else:
            x, y = 70 + index % 40 * 64, 70 + index // 40 * 72
        item = node(kind + ':seat:' + str(index), 'seat', x, y, label=str(index + 1),
                    rotation=15 if kind == 'mixed' and index % 20 == 0 else 0)
        if group:
            item['parentId'] = group
        if index % 37 == 0:
            item.update(style={'seatStyle':'wood','fill':'#B58B57FF'})
        selection_unit = identifier('mixed:couch-unit') if kind == 'mixed' and index >= 948 else None
        if selection_unit:
            item['parentId'] = identifier('mixed:couch')
            item['transform'].update(x=-40 if index == 948 else 40, y=0)
            group = identifier('mixed:couch')
        nodes.append(item)
        changes.append(dict(nodeId=item['id'], spotId=None, productId=product, title=str(index + 1),
                            groupNodeId=group, selectionUnitId=selection_unit, blocked=index == 30, operation='upsert',productAssignmentMode='override'))
    if kind == 'mixed':
        nodes.append(node('mixed:couch', 'furniture', 2350, 1900, 180, 80, label='', furniture='couch', assembly={'kind':'couch','seats':2,'minSeatWidth':40,'minSeatHeight':40}, shape='roundedRect',rotation=20))
        nodes.append(node('mixed:standing', 'capacityArea', 500, 1950, 260, 160, label='Standing', capacity=50, shape='rect'))
        groups.append(dict(groupNodeId=identifier('mixed:couch'), productId=product))
        units.append(dict(id=identifier('mixed:couch-unit'), kind='atomic', nodeIds=[identifier('mixed:seat:948'),identifier('mixed:seat:949')]))
    document = dict(schemaVersion=2, symbolSetVersion=1,
                    canvas=dict(x=0,y=0,width=4700 if kind == 'tables' else 2800,height=3200 if kind == 'tables' else 2200,fill='#FFFFFFFF'),
                    nodes=nodes, selectionUnits=units,
                    attachments=[dict(seatId=n['id'],targetId=n['parentId'],placement={'mode':'free'},rotationMode='manual') for n in nodes if n['kind']=='seat' and n.get('parentId')],
                    styles={'label':{'fontFamilyId':font}},seatingDefaults={},textPolicy={'language':'und','direction':'auto'},sections=[],presets=[])
    return document, changes, groups

def seed(kind, font, prepared, asset):
    f = json.loads(sql("SELECT public.blueprint_test_fixture_internal((SELECT id FROM public.organizations WHERE title='Test Organization' ORDER BY id LIMIT 1))", capture=True))
    sql("BEGIN; DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',true); END $$; SELECT public.register_blueprint_text_resources(%d,NULL,%s); COMMIT;" % (f['occasion'],literal(prepared)))
    request = f['request']
    document, changes, groups = geometry(kind, f['product'], font)
    request.update(title='Qualification 1000 ' + kind, layout=document, seatChanges=changes,groupProductChanges=groups)
    if kind == 'mixed':
        standing = json.loads(sql("""WITH p AS (INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES(%d,'Qualification standing','generic',50) RETURNING id),
        c AS (INSERT INTO public.inventory_contexts(inventory_pool,title) SELECT id,'Qualification standing' FROM p RETURNING id,inventory_pool),
        r AS (INSERT INTO public.resources(inventory_pool,occasion,title,capacity) SELECT inventory_pool,%d,'Standing capacity',50 FROM c)
        SELECT jsonb_build_object('context',id,'pool',inventory_pool) FROM c;""" % (f['occasion'],f['occasion']), capture=True))
        sql("INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES(%d,%d,1); SELECT public.adjust_spot_capacity_for_pool(%d);" % (f['product'],standing['context'],standing['pool']))
        # Standing and addressed seats need distinct products/PIC mappings.
        extra = int(sql("INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) SELECT occasion,product_type,'Standing',80,'CZK' FROM eshop.products WHERE id=%d RETURNING id" % f['product'],capture=True).strip())
        sql("UPDATE eshop.product_inventory_contexts SET product=%d WHERE product=%d AND inventory_context=%d" % (extra,f['product'],standing['context']))
        request['areaBindingChanges'] = [dict(nodeId=identifier('mixed:standing'),productId=extra,inventoryContextId=standing['context'],operation='upsert')]
        if asset:
            document['background'] = dict(assetRef=asset['asset_ref'],hash=asset['hash'],width=asset['width'],height=asset['height'],x=0,y=0,rotation=0,scale=1,opacity=0.15,crop={'x':0,'y':0,'width':1,'height':1})
            sql('SELECT public.copy_blueprint_image_resources_internal(%d,%d,%s)' % (asset['occasion'],f['occasion'],literal(document)))
    fields = "INSERT INTO public.form_fields(form,title,type,is_required,is_hidden,is_ticket_field,\"order\",data) VALUES (%d,'Email','email',true,false,false,0,'{}'),(%d,'Tickets','ticket',true,false,false,10,'{\"max_tickets\":20}'),(%d,'Seat','spot',false,false,true,20,'{}');" % (f['form'],f['form'],f['form'])
    sql(fields + "UPDATE public.occasions SET features='[{\"code\":\"blueprint\",\"is_enabled\":true},{\"code\":\"form\",\"is_enabled\":true}]' WHERE id=%d; INSERT INTO public.unit_users(unit,\"user\",is_manager,is_editor,is_editor_view) SELECT unit,'%s'::uuid,true,true,true FROM public.occasions WHERE id=%d;" % (f['occasion'],f['actor'],f['occasion']))
    request['textResourceIds']=json.loads(sql('SELECT to_jsonb(public.blueprint_text_resource_ids_internal(%s,%d))' % (literal(document),f['occasion']),capture=True))
    def save(req):
        start=time.perf_counter()
        response=json.loads(sql("BEGIN; SELECT set_config('request.jwt.claim.sub','%s',true) AS actor \\gset\nSELECT public.update_blueprint_client_sync_v1(%s,'%s'::uuid); COMMIT;" % (f['actor'],literal(req),uuid.uuid4()),capture=True))
        if response.get('status') != 'applied':
            raise RuntimeError('Canonical fixture save rejected: ' + json.dumps(response))
        return response, round((time.perf_counter()-start)*1000,3)
    first, create_ms = save(request)
    bindings = first['data']['seatBindings']
    request.update(expected_layout_revision=first['data']['layout_revision'],seatChanges=[],groupProductChanges=[],areaBindingChanges=[])
    second, reopen_ms = save(request)
    if {b['nodeId']:b['spotId'] for b in bindings} != {b['nodeId']:b['spotId'] for b in second['data']['seatBindings']}:
        raise RuntimeError('Canonical save changed spot identity')
    return dict(kind=kind,**{k:f[k] for k in ('actor','occasion','form','formKey','blueprint','product')},
                layoutRevision=second['data']['layout_revision'],seatCount=len(changes),eventCapacity=1000,
                formLink=sql('SELECT link FROM public.forms WHERE id=%d' % f['form'],capture=True).strip(),
                occasionLink=sql('SELECT link FROM public.occasions WHERE id=%d' % f['occasion'],capture=True).strip(),
                bindings=bindings,background=bool(document.get('background')),fontId=font,
                createCommandPsqlMs=create_ms,saveReopenCommandPsqlMs=reopen_ms)

def configure_checkout(fixtures):
    base=json.loads((BACKEND/'fixture.json').read_text())
    bank=int(base['business']['bankAccount'])
    for fixture in fixtures:
        occasion=int(fixture['occasion']); form=int(fixture['form'])
        sql("INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) SELECT o.unit,%d,1 FROM public.occasions o WHERE o.id=%d AND NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba WHERE uba.unit=o.unit AND uba.bank_account=%d); UPDATE public.forms SET bank_account=%d,data=coalesce(data,'{}')||'{\"schedule\":{\"start_time\":\"2020-01-01T00:00:00Z\",\"end_time\":\"2099-01-01T00:00:00Z\"}}'::jsonb WHERE id=%d; UPDATE public.occasions SET features=features||'[{\"code\":\"ticket\",\"is_enabled\":true,\"ticket_type\":\"wide\"}]'::jsonb WHERE id=%d AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(features) feature WHERE feature->>'code'='ticket');" % (bank,occasion,bank,bank,form,occasion))
        fixture['bankAccount']=bank

def main():
    guard()
    previous=json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {'fixtures':[]}
    if previous.get('complete'):
        print('Existing 1000 fixtures preserved: ' + str(MANIFEST));return
    if previous.get('project',PROJECT)!=PROJECT: raise RuntimeError('Fixture manifest project mismatch')
    version=sql("SELECT public.blueprint_contract_metadata_internal()->>'documentVersion'",capture=True).strip()
    if version!='2': raise RuntimeError('Canonical2 SQL migration must be installed before fixtures')
    prepared=json.loads(run(['deno','run','--allow-read','--allow-env',str(ROOT/'automation/blueprint_local_e2e_font.ts')],capture=True))
    resources=prepared['resources']
    font=next(key for key,value in resources['fontFamilies'].items() if value['faces'].get('400:normal')==prepared['fontId'])
    raw=sql("SELECT row_to_json(a) FROM public.blueprint_image_assets a WHERE occasion IS NOT NULL AND organization=(SELECT id FROM public.organizations WHERE title='Test Organization' ORDER BY id LIMIT 1) ORDER BY created_at DESC LIMIT 1",capture=True).strip()
    asset=json.loads(raw) if raw else None
    fixtures=previous['fixtures']
    for kind in ('chairs','tables','mixed'):
        if any(f['kind']==kind for f in fixtures): continue
        if kind=='mixed' and asset is None: raise RuntimeError('First two fixtures ready; register a genuine occasion-scoped raster asset then resume mixed fixture')
        fixtures.append(seed(kind,font,resources,asset))
        private_json(MANIFEST,dict(project=PROJECT,schemaVersion=2,resourceBoundary='actual immutable font bytes through canonical2 whole-text preparer',fixtures=fixtures,complete=False))
    configure_checkout(fixtures)
    private_json(MANIFEST,dict(project=PROJECT,schemaVersion=2,resourceBoundary='actual immutable font bytes through canonical2 whole-text preparer',fixtures=fixtures,complete=True))
    print(json.dumps(dict(manifest=str(MANIFEST),fixtures=[dict(kind=f['kind'],blueprint=f['blueprint'],seats=f['seatCount'],background=f['background']) for f in fixtures])))
if __name__ == '__main__': main()
