#!/usr/bin/env python3
"""Seed genuine font resources and reproducible synthetic Blueprint business states."""
import json, pathlib, secrets
from blueprint_local_e2e import ROOT, BACKEND, PROJECT, run, sql, file_sql, private_json

def main():
    if sql("SELECT project FROM festapp_test_support.disposable_environment WHERE singleton",capture=True).strip()!=PROJECT:
        raise RuntimeError('Owned disposable project required')
    # Existing private manifest is reusable only if its actual form still exists.
    manifest=BACKEND/'fixture.json'
    if manifest.exists():
        existing=json.loads(manifest.read_text())
        if sql("SELECT count(*) FROM public.forms form JOIN eshop.blueprints blueprint ON blueprint.id=form.blueprint WHERE blueprint.layout->>'schemaVersion'='2' AND form.key='"+existing['formKey']+"'::uuid",capture=True).strip()=='1':
            print('Existing owned fixture preserved');return
    prepared=json.loads(run(['deno','run','--allow-read','--allow-env',str(ROOT/'automation/blueprint_local_e2e_font.ts')],capture=True))
    file_sql(ROOT/'database/tests/blueprint/fixtures.sql')
    file_sql(ROOT/'database/tests/blueprint/e2e_fixture.sql')
    file_sql(ROOT/'database/tests/blueprint/e2e_business_fixture.sql')
    fixture=json.loads(sql("BEGIN; DO $fixture$ BEGIN PERFORM set_config('festapp.fixture_text_resources','"+json.dumps(prepared['resources']).replace("'","''")+"',true); END $fixture$; SELECT public.blueprint_seed_business_e2e_fixture(public.blueprint_seed_e2e_fixture('"+prepared['fontId']+"',(SELECT id FROM public.organizations WHERE title='Test Organization' ORDER BY id LIMIT 1))); COMMIT;",capture=True))
    private_json(manifest,fixture)
    # HMAC registration key is local-only; never log it or reuse service-role keys.
    secret=secrets.token_hex(32)
    sql("SELECT vault.create_secret('"+secret+"','blueprint_image_processing_v1','Disposable local image registration') WHERE NOT EXISTS(SELECT 1 FROM vault.secrets WHERE name='blueprint_image_processing_v1');",user='supabase_admin')
    # Reusing an already initialized environment uses its existing vault value.
    secret=sql("SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='blueprint_image_processing_v1'",user='supabase_admin',capture=True,sensitive=True).strip()
    env=BACKEND/'private-worker.env';env.write_text('IMAGE_PROCESSING_SERVICE_SECRET='+secret+'\nSUPABASE_ANON_KEY='+json.loads((BACKEND/'private-defines.json').read_text())['FESTAPP_SUPABASE_ANON_KEY']+'\nCONTROL_ALLOWED_ORIGINS=http://127.0.0.1:59740,http://127.0.0.1:59741\n');env.chmod(0o600)
    print('Synthetic fixture ready: form '+str(fixture['form'])+', blueprint '+str(fixture['blueprint'])+'; private manifest '+str(manifest))
if __name__=='__main__':main()
