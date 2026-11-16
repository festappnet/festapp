#!/usr/bin/env python3
"""Own a complete isolated CMS/backend/browser matrix; no production credentials.

The database, CMS and public form are real. CMP APIs and Wix Site viewMode are
modeled at their documented public boundary. Default Joomla COOP is retained
for installed tests; positive-path proxy routing explicitly removes that header.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import sys
import time
import uuid

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'automation/ci'))
from telemetry import phase as timed_phase, emit
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base-port',type=int,default=int(os.environ.get('FESTAPP_CMS_FIXTURE_BASE_PORT','61000')))
parser.add_argument('--keep',action='store_true',help='Keep only this owned environment after verification for diagnosis')
args=parser.parse_args()
base=args.base_port
if base<1024 or base>65480:raise SystemExit('Invalid loopback port block')
for offset in [1,11,12,15,16,20,21,22,23,24,27,29,31,32,33,34,35,36,37,38]:
 with socket.socket() as s:
  try:s.bind(('127.0.0.1',base+offset))
  except OSError:raise SystemExit(f'Port {base+offset} is in use; choose a different --base-port, never stop another task')
project='festapp-cms-consent-'+uuid.uuid4().hex[:12]
fixture=ROOT/'.private'/project
fixture.mkdir(parents=True,mode=0o700)
log=fixture/'owner.log'
log.touch(mode=0o600)
env={**os.environ,'FESTAPP_CMS_TEST_PROJECT':project,'FESTAPP_CMS_TEST_BASE_PORT':str(base+20),'FESTAPP_CMS_TEST_SERVICE':f'https://127.0.0.1:{base+32}',
 'FESTAPP_JOOMLA_TEST_PREFIX':project+'-joomla','FESTAPP_JOOMLA_TEST_PORT5':str(base+15),'FESTAPP_JOOMLA_TEST_PORT6':str(base+16)}
def input_digests():
 paths=set()
 for directory in ['integrations/wordpress/shared','integrations/joomla/shared','integrations/wix/src','web_client/src']:
  paths.update(p for p in (ROOT/directory).rglob('*') if p.is_file())
 for name in ['automation/testing/cms_consent_fixture.py','web_client/scripts/cms_consent_fixture_server.mjs','web_client/scripts/cms_consent_fixture_prepare.mjs','web_client/scripts/test_cms_managed_consent_browser.mjs','web_client/scripts/native_browser.mjs','supabase/migrations/20261114170000_website_consent_bindings.sql','automation/release/help/help.js','automation/release/help/en/embed-generator.html']:
  paths.add(ROOT/name)
 return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}
source_inputs=input_digests()
processes=[]
started={'backend':False,'wordpress':False,'joomla':False}

def run(command,cwd=ROOT,extra=None,capture=False,label='command'):
 with timed_phase('cms.'+label), log.open('a') as output:
  result=subprocess.run([str(v) for v in command],cwd=cwd,env={**env,**(extra or {})},stdout=subprocess.PIPE if capture else output,stderr=output,text=True)
  if result.returncode:raise RuntimeError(f'{Path(str(command[0])).name} failed ({result.returncode}); private log: {log}')
 return result.stdout if capture else ''

def start(command,cwd=ROOT):
 with log.open('a') as output:
  p=subprocess.Popen([str(v) for v in command],cwd=cwd,env=env,stdout=output,stderr=output,start_new_session=True)
 processes.append(p)
 return p

def phase(message):print(message,flush=True)

def sql(query):
 return run(['psql',f'postgresql://supabase_admin:postgres@127.0.0.1:{base+22}/postgres','-X','-qAt','-v','ON_ERROR_STOP=1','-c',query],capture=True).strip()

def cleanup_partial_wordpress():
 # wp-env destroy may refuse an interrupted startup. Compose labels bind any
 # fallback strictly to this copied environment, never another running project.
 raw=run(['docker','ps','-a','--format','{{.ID}}|{{.Label "com.docker.compose.project.working_dir"}}|{{.Label "com.docker.compose.project"}}'],capture=True)
 records=[line.split('|') for line in raw.splitlines() if len(line.split('|'))==3]
 boundary=(fixture/'integrations/wordpress/.private/wp-env').resolve()
 owned={project_name for _,working,project_name in records if working and Path(working).resolve().is_relative_to(boundary) and re.fullmatch(r'[a-zA-Z0-9_-]+',project_name)}
 for project_name in owned:
  group=[row for row in records if row[2]==project_name]
  if any(not working or not Path(working).resolve().is_relative_to(boundary) for _,working,_ in group):
   raise RuntimeError('Compose identity collision; foreign resources preserved')
  working=Path(group[0][1]);compose=working/'docker-compose.yml'
  if compose.is_file():
   run(['docker','compose','--project-name',project_name,'--project-directory',working,'-f',compose,'down','--volumes','--remove-orphans'])
  else:
   run(['docker','rm','-fv',*[row[0] for row in group]])
   for kind in ['volume','network']:
    names=run(['docker',kind,'ls','--filter','label=com.docker.compose.project='+project_name,'--format','{{.Name}}'],capture=True).splitlines()
    if names:run(['docker',kind,'rm',*names])

wp=fixture/'integrations/wordpress';joomla=fixture/'integrations/joomla'
try:
 phase('Preparing owned CMS package copies and frozen dependencies')
 for cms in ['wordpress','joomla']:
  target=fixture/'integrations'/cms;target.mkdir(parents=True)
  for name in ['scripts','shared','tests']:
   shutil.copytree(ROOT/'integrations'/cms/name,target/name,ignore=shutil.ignore_patterns('__pycache__','node_modules'))
  for name in ['products.json','translations.json','package.json','pnpm-lock.yaml','pnpm-workspace.yaml','.wp-env.json','docker-images.json']:
   source=ROOT/'integrations'/cms/name
   if source.is_file():shutil.copy2(source,target/name)
  (target/'evidence').mkdir()
 # Canonical SQL is read through source paths; no node_modules is copied/shared.
 for name in ['automation','database','supabase']:(fixture/name).symlink_to(ROOT/name,target_is_directory=True)
 (fixture/'web_client/tests/fixtures').mkdir(parents=True)
 (fixture/'web_client/tests/fixtures/embedded-checkout').symlink_to(ROOT/'web_client/tests/fixtures/embedded-checkout',target_is_directory=True)
 (fixture/'integrations/measurement').mkdir()
 shutil.copy2(ROOT/'integrations/measurement/consent-export.php',fixture/'integrations/measurement/consent-export.php')
 service=f'https://127.0.0.1:{base+32}'
 for cms in ['wordpress','joomla']:
  p=fixture/'integrations'/cms/'products.json';products=json.loads(p.read_text())
  for product in products:product['origin']=service
  p.write_text(json.dumps(products,indent=2)+'\n')
 # Test product origin has a loopback port; renderer/parser/runtime stay unchanged.
 build=wp/'scripts/build-plugins.py';text=build.read_text();old="r'https://[a-z0-9.-]+'";assert old in text
 build.write_text(text.replace(old,"r'https://[a-z0-9.-]+(?::[0-9]+)?'"))
 config=json.loads((wp/'.wp-env.json').read_text());config['port']=base+11;config['testsPort']=base+12
 config['config'].update({'WP_HOME':f'https://127.0.0.1:{base+31}','WP_SITEURL':f'https://127.0.0.1:{base+31}'})
 config['env']['tests']['config']={'WP_HOME':f'https://127.0.0.1:{base+36}','WP_SITEURL':f'https://127.0.0.1:{base+36}'}
 (wp/'.wp-env.json').write_text(json.dumps(config,indent=2)+'\n')
 # One verified frozen installation in the source package, reused by the
 # copied environment's CLI. No node_modules copy and no shared CMS state.
 run(['python3','automation/ci/run.py','install','integrations/wordpress'],label='dependencies')
 env['FESTAPP_WP_ENV_CLI']=str(ROOT/'integrations/wordpress/node_modules/.bin/wp-env')
 run(['python3','scripts/package.py'],wp);run(['python3','scripts/package.py'],joomla)
 run(['node','scripts/setup-backend.mjs'],wp)
 phase('Starting independent owned services and browser dependencies concurrently')
 jprefix=project+'-joomla'
 def prepare_backend():
  started['backend']=True
  run(['supabase','start','--workdir','.private/backend','--exclude','realtime,imgproxy,postgres-meta,studio,edge-runtime,logflare,vector,supavisor,mailpit'],wp,label='backend.start')
  run(['bash','scripts/bootstrap-backend.sh'],wp,label='backend.bootstrap')
  sql("CREATE SCHEMA IF NOT EXISTS festapp_test_support; CREATE TABLE IF NOT EXISTS festapp_test_support.disposable_environment(singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),project text NOT NULL); INSERT INTO festapp_test_support.disposable_environment VALUES(true,'"+project+"') ON CONFLICT(singleton) DO UPDATE SET project=EXCLUDED.project; GRANT USAGE ON SCHEMA festapp_test_support TO postgres; GRANT SELECT ON festapp_test_support.disposable_environment TO postgres")
 def prepare_wordpress():
  run([sys.executable,ROOT/'automation/ci/docker_cache.py','prefetch-wordpress'],label='wordpress.images')
  started['wordpress']=True;run(['node','scripts/environment.mjs','start'],wp,label='wordpress.start')
  products=json.loads((wp/'products.json').read_text())
  for cli in ['cli','tests-cli']:
   for p in products:run(['node','scripts/environment.mjs','run',cli,'wp','plugin','install',f'/var/www/html/wp-content/vo-artifacts/{p["slug"]}-{p["version"]}.zip','--activate','--force'],wp)
   run(['node','scripts/environment.mjs','run',cli,'wp','eval-file','/var/www/html/wp-content/plugins/vstupenky-online-tests/consent-installed.php'],wp)
 def prepare_joomla():
  started['joomla']=True;run(['python3','scripts/environment.py','start'],joomla,label='joomla.start')
  for major in [5,6]:
   for p in json.loads((joomla/'products.json').read_text()):
    archive=f'{p["element"]}-{p["version"]}.zip'
    run(['docker','cp',joomla/'artifacts'/archive,jprefix+'-'+str(major)+':/tmp/'+archive])
    # docker cp retains a private ZIP's 0600 mode but assigns root ownership.
    # Give only the installer user access; keep the host artifact private.
    run(['docker','exec','--user','root',jprefix+'-'+str(major),'chown','www-data:www-data','/tmp/'+archive])
    run(['docker','exec','--user','www-data',jprefix+'-'+str(major),'php','cli/joomla.php','extension:install','--path','/tmp/'+archive])
  run(['python3','tests/consent-installed.py'],joomla)
 def prepare_browsers():
  browser_cache=Path(os.environ.get('PLAYWRIGHT_BROWSERS_PATH',Path.home()/('Library/Caches/ms-playwright' if sys.platform=='darwin' else '.cache/ms-playwright')))
  def cache_bytes():return sum(p.stat().st_size for p in browser_cache.rglob('*') if p.is_file()) if browser_cache.exists() else 0
  cache_before=cache_bytes();browser_started=time.monotonic()
  run(['pnpm','--dir',ROOT/'web_client','exec','playwright','install','--with-deps','chromium','firefox','webkit'],label='browsers.install')
  emit('cms.browsers.cache',browser_started,bytesBefore=cache_before,bytesAfter=cache_bytes(),binaryCache='cold' if cache_before==0 else 'warm',networkTransferBytes=None)
 with ThreadPoolExecutor(max_workers=4) as workers:
  pending=[(name,workers.submit(prepare)) for name,prepare in [('backend',prepare_backend),('wordpress',prepare_wordpress),('joomla',prepare_joomla),('browsers',prepare_browsers)]]
  failures=[]
  for name,future in pending:
   try:future.result()
   except Exception as error:failures.append((name,error))
  if failures:raise RuntimeError('Owned CMS preparation failed: '+', '.join(name for name,_ in failures)) from failures[0][1]
 phase('Starting explicit local HTTPS transports (modeled CMP; Joomla positive proxy excludes COOP)')
 (fixture/'tls').mkdir()
 run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',fixture/'tls/key.pem','-out',fixture/'tls/cert.pem','-subj','/CN=127.0.0.1','-addext','subjectAltName=IP:127.0.0.1','-days','1'])
 (fixture/'tls/key.pem').chmod(0o600)
 (fixture/'fixture-state.json').write_text(json.dumps({'exports':{},'coop':False}))
 server=start(['node','web_client/scripts/cms_consent_fixture_server.mjs',fixture,str(base)])
 for _ in range(120):
  if (fixture/'transport-ready').exists():break
  if server.poll() is not None:raise RuntimeError('Fixture transport exited; inspect private owner log')
  time.sleep(.5)
 else:raise RuntimeError('Fixture transport readiness timeout')
 cases=[('wordpress',31,'cli','chromium'),('wordpress',31,'cli','firefox'),('wordpress',31,'cli','webkit'),
        ('wordpress',36,'tests-cli','chromium'),('joomla',34,'5','chromium'),('joomla',35,'6','chromium'),
        ('wix',37,None,'chromium'),('html',38,None,'chromium'),('joomla',34,'5','chromium')]
 results=[]
 for case_index,(platform,offset,variant,engine) in enumerate(cases):
  coop=case_index==len(cases)-1
  state_file=fixture/'fixture-state.json';state=json.loads(state_file.read_text());state['coop']=coop;state_file.write_text(json.dumps(state))
  phase(f'Verifying {platform} {variant or "generated"} with {engine}')
  prepared=json.loads(run(['node','web_client/scripts/cms_consent_fixture_prepare.mjs',fixture,str(base),str(offset),platform],capture=True))
  if platform=='wordpress':run(['node','scripts/environment.mjs','run',variant,'wp','eval-file','/var/www/html/wp-content/plugins/vstupenky-online-tests/consent-journey.php'],wp)
  elif platform=='joomla':
   container=jprefix+'-'+variant
   run(['docker','exec',container,'php','/tests/consent-journey.php']);run(['docker','exec',container,'php','/tests/clear-cache.php'])
   # Test installation trusts only its loopback reverse proxy; production source is unchanged.
   run(['docker','exec',container,'php','-r',"$f='configuration.php';$s=file_get_contents($f);if(!str_contains($s,'HTTP_X_FORWARDED_PROTO')){$s=str_replace('<?php',\"<?php if ((\\$_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https') { \\$_SERVER['HTTPS']='on'; }\",$s);file_put_contents($f,$s);}"])
  extra={'FESTAPP_CMS_TEST_SITE':f'https://127.0.0.1:{base+offset}','FESTAPP_CMS_TEST_SERVICE':service,'FESTAPP_CMS_TEST_API':f'https://127.0.0.1:{base+33}',
   'FESTAPP_CMS_TEST_DATABASE':f'postgresql://postgres:postgres@127.0.0.1:{base+22}/postgres','FESTAPP_CMS_TEST_MARKER':project,'FESTAPP_CMS_TEST_ACTOR':prepared['actor'],
   'FESTAPP_CMS_TEST_PATH':'/managed-consent-test/' if platform=='wordpress' else '/','FESTAPP_CMS_TEST_ENGINE':engine}
  if platform=='wix':extra['FESTAPP_CMS_TEST_IFRAME']='1'
  if coop:extra['FESTAPP_CMS_EXPECT_COOP']='1'
  else:extra['FESTAPP_CMS_TEST_WITHDRAWAL']='1'
  output=run(['node','web_client/scripts/test_cms_managed_consent_browser.mjs'],extra=extra,capture=True,label=f'case.{case_index}.{platform}.{engine}')
  lines=[line for line in output.splitlines() if line.startswith('PASS ')];assert lines,output
  for line in lines:phase(line)
  results.append({'platform':platform,'variant':variant,'engine':engine,'result':'passed','scenario':'blocked COOP fallback' if coop else 'grant/refusal/withdrawal/disable/stale export','boundary':'modeled CMP; modeled Wix Site mode'})
 if input_digests()!=source_inputs:raise RuntimeError('Fixture source changed during verification; repeat affected checks')
 (fixture/'result.json').write_text(json.dumps({'sourceInputs':source_inputs,'project':project,'basePort':base,'cases':results,'state':'passed','productionWrites':False},indent=2)+'\n')
 phase(f'PASS complete owned CMS/backend matrix: {len(results)} cases; receipt {fixture}/result.json')
finally:
 if not args.keep:
  for p in reversed(processes):
   if p.poll() is None:
    os.killpg(p.pid,signal.SIGTERM)
    try:p.wait(timeout=10)
    except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
  cleanup=[(['python3','scripts/environment.py','stop'],joomla,'joomla'),(['node','scripts/environment.mjs','cleanup','--force'],wp,'wordpress'),(['supabase','stop','--workdir','.private/backend','--no-backup'],wp,'backend')]
  with ThreadPoolExecutor(max_workers=3) as workers:
   pending=[(key,workers.submit(run,command,cwd,label='cleanup.'+key)) for command,cwd,key in cleanup if started[key]]
   for key,future in pending:
    try:future.result()
    except Exception as error:print(f'Owned {key} cleanup failed: {error}',file=sys.stderr)
  if started['wordpress']:
   try:cleanup_partial_wordpress()
   except Exception as error:print(f'Owned partial WordPress cleanup failed: {error}',file=sys.stderr)
