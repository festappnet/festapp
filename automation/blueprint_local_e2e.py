#!/usr/bin/env python3
"""Restore ONLY the owned disposable Blueprint B full backend; never production."""
import json, os, pathlib, re, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parent.parent
BACKEND = pathlib.Path('/Users/miakh/source/festapp-blueprint-1000-e2e-20261020')
PROJECT = 'festapp-blueprint-1000-e2e-20261020'
LOG = pathlib.Path('/tmp/blueprint-1000-rebootstrap.log')
ENV = dict(os.environ, PGPASSWORD='postgres')
LOG.touch(mode=0o600, exist_ok=True); LOG.chmod(0o600)
def run(args, *, text=None, capture=False, sensitive=False):
    result = subprocess.run(args, input=text, text=True, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with LOG.open('a') as log: log.write(('[private output omitted]\n' if sensitive else result.stdout) + result.stderr)
    if result.returncode:
        raise RuntimeError('Command failed: '+str(args[0])+'; inspect private log '+str(LOG))
    return result.stdout if capture else None
def sql(query, user='postgres', capture=False, sensitive=False):
    return run(['psql','-h','127.0.0.1','-p','59722','-U',user,'-d','postgres','-X','-qAt','-v','ON_ERROR_STOP=1'],text=query,capture=capture,sensitive=sensitive)
def file_sql(path,user='postgres'):
    run(['psql','-h','127.0.0.1','-p','59722','-U',user,'-d','postgres','-X','-q','-v','ON_ERROR_STOP=1','-f',str(path)])
def private_json(path,value):
    with os.fdopen(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600),'w') as target: target.write(json.dumps(value))
    path.chmod(0o600)
def main():
    if pathlib.Path.cwd().resolve()!=ROOT: raise RuntimeError('Run from the isolated source checkout')
    config=(BACKEND/'supabase/config.toml').read_text()
    if f'project_id = "{PROJECT}"' not in config or 'port = 59721' not in config or 'port = 59722' not in config:
        raise RuntimeError('Owned disposable project identity/ports mismatch')
    print('Starting owned Blueprint disposable backend',flush=True)
    run(['supabase','start','--workdir',str(BACKEND),'--exclude','realtime,imgproxy,postgres-meta,studio,edge-runtime,logflare,vector,supavisor,mailpit'])
    exists=sql("select to_regclass('public.organizations') is not null",capture=True).strip()=='t'
    if exists:
        marker=sql("select project from festapp_test_support.disposable_environment where singleton",capture=True).strip()
        if marker!=PROJECT: raise RuntimeError('Database is not owned by this task')
        print('Owned schema already present; preserving data',flush=True)
    else:
        sql('''CREATE SCHEMA IF NOT EXISTS eshop;
CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS moddatetime WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgaudit WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;
'''+'\n'.join(f'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA {schema} REVOKE ALL ON {kind} FROM anon, authenticated, service_role;' for schema in ['public','eshop'] for kind in ['TABLES','SEQUENCES','FUNCTIONS']))
        baseline=sorted((ROOT/'supabase/baseline').glob('*_production_schema.sql'))[-1]
        version=baseline.name.split('_')[0]
        print('Restoring canonical baseline '+version,flush=True); file_sql(baseline)
        file_sql(ROOT/'automation/local_db/reference_tenants.sql')
        sql("CREATE SCHEMA IF NOT EXISTS festapp_test_support; CREATE TABLE IF NOT EXISTS festapp_test_support.disposable_environment(singleton boolean PRIMARY KEY CHECK(singleton),project text NOT NULL); INSERT INTO festapp_test_support.disposable_environment VALUES(true,'"+PROJECT+"') ON CONFLICT(singleton) DO UPDATE SET project=EXCLUDED.project;")
    sql("CREATE TABLE IF NOT EXISTS festapp_test_support.applied_migrations(version text PRIMARY KEY)")
    baseline=sorted((ROOT/'supabase/baseline').glob('*_production_schema.sql'))[-1]
    version=baseline.name.split('_')[0]
    applied=set(sql("SELECT version FROM festapp_test_support.applied_migrations",capture=True).splitlines())
    migrations=[p for p in sorted((ROOT/'supabase/migrations').glob('*.sql')) if p.name.split('_')[0]>version and p.name.split('_')[0] not in applied]
    for migration in migrations:
        # A few canonical demo maintenance migrations explicitly require postgres.
        # Preserve those guards instead of bypassing their role checks.
        user='postgres' if re.search(r"current_user\s*<>\s*'postgres'",migration.read_text(),re.I) else 'supabase_admin'
        file_sql(migration,user)
        sql("INSERT INTO festapp_test_support.applied_migrations VALUES('"+migration.name.split('_')[0]+"')")
    print('Applied '+str(len(migrations))+' pending forward migrations',flush=True)
    # Local supabase_admin can update extension-owned helpers, but application
    # definers must retain the canonical postgres owner used by trusted domains.
    sql("""DO $$ DECLARE item record; BEGIN FOR item IN
      SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND pg_get_userbyid(p.proowner)='supabase_admin'
      AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')
      LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',item.signature); END LOOP; END $$;""",user='supabase_admin')

    # The replacement finalizer reads this private waitlist table as its
    # canonical postgres definer. Local admin-applied forwards must retain
    # the production migration owner, without adding runtime grants.
    sql("ALTER TABLE eshop.waitlist_offer_slots OWNER TO postgres",user='supabase_admin')

    # Fence all scheduler/provider delivery before synthetic seed or orders.
    sql("UPDATE cron.job SET active=false",user="supabase_admin")
    sql("UPDATE public.email_capacity SET paused=true,worker_url=NULL;")
    file_sql(ROOT/'supabase/seed.sql')
    sql("UPDATE cron.job SET active=false",user="supabase_admin")
    sql("UPDATE public.email_capacity SET paused=true,worker_url=NULL; NOTIFY pgrst, 'reload schema';")
    status=json.loads(run(['supabase','status','--workdir',str(BACKEND),'--output','json'],capture=True,sensitive=True))
    if status.get('API_URL')!='http://127.0.0.1:59721':raise RuntimeError('Unexpected API target')
    private_json(BACKEND/'private-defines.json',{'FESTAPP_SUPABASE_URL':status['API_URL'],'FESTAPP_SUPABASE_ANON_KEY':status['ANON_KEY'],'FESTAPP_E2E_BACKEND_PORT':'59721','FESTAPP_E2E_IMAGE_PORT':'59725','FESTAPP_OCCASION_SETUP':'true'})
    print('Owned backend ready; email delivery paused and every cron job inactive',flush=True)
if __name__=='__main__':
    try:main()
    except Exception as error:print(str(error),file=sys.stderr);sys.exit(1)
