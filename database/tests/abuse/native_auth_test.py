#!/usr/bin/env python3
"""Real production-version Auth against ONLY this task's disposable database."""
import json
import subprocess
import time
import urllib.error
import urllib.request
from uuid import uuid4

DB = 'supabase_db_festapp-abuse-20261016'
CONTAINER = 'festapp-abuse-native-auth'
IMAGE = 'supabase/gotrue:v2.189.0@sha256:cce6c1d00352f22ee7634066012830f69636c157017ea166634c48dbb58eefb7'
actor = str(uuid4())

def docker(*args, capture=False, input=None):
    return subprocess.run(['docker', *args], check=True, input=input, text=True,
                          stdout=subprocess.PIPE if capture else subprocess.DEVNULL).stdout

def sql(statement):
    return docker('exec', '-i', DB, 'psql', '-X', '-U', 'postgres', '-d', 'postgres',
                  '-v', 'ON_ERROR_STOP=1', '-Atq', capture=True, input=statement).strip()

assert json.loads(docker('inspect', DB, capture=True))[0]['Config']['Labels']['com.supabase.cli.project'] == 'festapp-abuse-20261016'
if subprocess.run(['docker', 'inspect', CONTAINER], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
    raise RuntimeError('Native Auth test container already exists; refusing reuse')
# A local fixture password, never a production credential. Native Auth owns its SQL hook.
docker('exec', DB, 'sh', '-c', '''PGPASSWORD="$POSTGRES_PASSWORD" psql -X -h 127.0.0.1 -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q -c "ALTER ROLE supabase_auth_admin PASSWORD 'festapp-local-abuse-test-only'"''')
sql(f"""INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change)
VALUES('00000000-0000-0000-0000-000000000000','{actor}','authenticated','authenticated','{actor}@test.invalid',extensions.crypt('123456',extensions.gen_salt('bf')),now(),now()-interval '5 years',now(),'','','','');
INSERT INTO auth.identities(id,user_id,provider_id,identity_data,provider,created_at,updated_at)
VALUES(gen_random_uuid(),'{actor}','{actor}','{{"sub":"{actor}","email":"{actor}@test.invalid","email_verified":true}}','email',now(),now());""")
env = {
    'GOTRUE_API_HOST': '0.0.0.0', 'GOTRUE_API_PORT': '9999',
    'API_EXTERNAL_URL': 'http://127.0.0.1:55780', 'GOTRUE_SITE_URL': 'http://127.0.0.1:55780',
    'GOTRUE_DB_DRIVER': 'postgres',
    'GOTRUE_DB_DATABASE_URL': 'postgres://supabase_auth_admin:festapp-local-abuse-test-only@db:5432/postgres',
    'GOTRUE_JWT_SECRET': 'festapp-isolated-native-auth-proof-only-0123456789',
    'GOTRUE_JWT_AUD': 'authenticated', 'GOTRUE_JWT_DEFAULT_GROUP_NAME': 'authenticated',
    'GOTRUE_JWT_EXP': '3600', 'GOTRUE_EXTERNAL_EMAIL_ENABLED': 'true',
    'GOTRUE_MAILER_AUTOCONFIRM': 'true', 'GOTRUE_HOOK_PASSWORD_VERIFICATION_ATTEMPT_ENABLED': 'true',
    'GOTRUE_HOOK_PASSWORD_VERIFICATION_ATTEMPT_URI': 'pg-functions://postgres/public/password_verification_attempt_v1',
}
args=['run','-d','--name',CONTAINER,'--network','supabase_network_festapp-abuse-20261016','-p','127.0.0.1:55780:9999']
for key,value in env.items(): args += ['-e',f'{key}={value}']
try:
    docker(*args,IMAGE)
    for _ in range(30):
        try:
            urllib.request.urlopen('http://127.0.0.1:55780/health',timeout=2)
            break
        except Exception: time.sleep(.2)
    else: raise RuntimeError('Isolated Auth failed to start')
    def login(password):
        request=urllib.request.Request('http://127.0.0.1:55780/token?grant_type=password',
          data=json.dumps({'email':f'{actor}@test.invalid','password':password}).encode(),headers={'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(request,timeout=5) as response: return response.status,json.load(response)
        except urllib.error.HTTPError as error: return error.code,json.load(error)
    for _ in range(2): assert login('123456')[0] == 200
    assert login('999999')[0] == 400
    for _ in range(7): assert login('123456')[0] == 200
    status,body=login('123456')
    assert status == 400 and 'Too many' in body.get('msg',''),body
    assert sql(f"SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='password.verify.actor.burst' AND scope_id='{actor}';") == '11'
    assert sql(f"SELECT encrypted_password=extensions.crypt('123456',encrypted_password) FROM auth.users WHERE id='{actor}';") == 't'
    print('Native Auth v2.189.0: permanent password replay, shared budget and committed denial PASS')
finally:
    subprocess.run(['docker','rm','-f',CONTAINER],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
