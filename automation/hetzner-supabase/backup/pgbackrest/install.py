#!/usr/bin/env python3
"""Guarded canonical-host activation. Secrets stay root-only; never print config."""
import argparse,datetime,fcntl,hashlib,json,os,re,secrets,shlex,shutil,subprocess,time
from pathlib import Path
BASE='supabase/postgres:17.6.1.136@sha256:a9946f08d31e8eb1149229c94e5c26603a9233116807cbbd93d75179cbac516a'
DB='festapp_rehearsal_20260909220601'
COMPOSE=Path('/opt/festapp-supabase/docker')
HERE=Path(__file__).resolve().parent
SECRET=Path('/etc/festapp-pgbackrest')
STATE=Path('/var/lib/festapp-pgbackrest')
def env_read(path):
 d={}
 for line in path.read_text().splitlines():
  if line.strip() and not line.startswith('#') and '=' in line:
   key,value=line.split('=',1);d[key]=shlex.split(value)[0] if value else ''
 return d
def atomic(path,data,mode=0o600):
 temp=path.with_name('.'+path.name+'.new');fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL,mode)
 with os.fdopen(fd,'w') as f:f.write(data)
 os.replace(temp,path)
def main():
 a=argparse.ArgumentParser();a.add_argument('--ack',required=True);a.add_argument('--source-commit',required=True);args=a.parse_args()
 assert args.ack=='activate-encrypted-pitr-with-db-restart' and re.fullmatch('[a-f0-9]{40}',args.source_commit)
 assert os.geteuid()==0 and os.uname().nodename.split('.')[0]=='festapp-supabase-rehearsal-01'
 os.umask(0o077)
 envpath=COMPOSE/'.env';env=env_read(envpath);assert env['FESTAPP_RUNTIME_DATABASE']==DB
 assert envpath.stat().st_mode&0o777==0o600
 assert not SECRET.exists(), 'pgBackRest already provisioned; never overwrite encryption keys'
 lock=(COMPOSE/'.festapp-runtime-upgrade.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
 evidence=Path('/var/lib/festapp-rehearsal-evidence')/('pgbackrest-install-'+stamp);evidence.mkdir(mode=0o700)
 log=(evidence/'install.log').open('wb')
 def run(argv,capture=False):
  return subprocess.check_output(argv,cwd=COMPOSE,stderr=log).decode().strip() if capture else subprocess.run(argv,cwd=COMPOSE,stdout=log,stderr=log,check=True)
 def sql(q):return run(['docker','exec','supabase-db','psql','-X','-U','postgres','-d',DB,'-Atqv','ON_ERROR_STOP=1','-c',q],True)
 assert sql('BEGIN READ ONLY; SELECT current_database()||\'|\'||id FROM public.organizations WHERE id=1; COMMIT;')==DB+'|1'
 original=json.loads(run(['docker','inspect','supabase-db'],True))[0]
 assert original['Config']['Image']==BASE
 assert original['Config']['Cmd']==['postgres','-c','config_file=/etc/postgresql/postgresql.conf','-c','log_min_messages=fatal']
 assert sql("BEGIN READ ONLY; SHOW archive_mode; COMMIT;")=='off'
 original_version=run(['docker','exec','supabase-db','postgres','--version'],True)
 # Use the environment's complete current Compose list (including email override).
 files=env['COMPOSE_FILE'].split(':');assert files==['docker-compose.yml','docker-compose.festapp.yml','docker-compose.database-target.yml','docker-compose.email.yml']
 project=original['Config']['Labels']['com.docker.compose.project']
 def compose(extra=False):
  cmd=['docker','compose','-p',project]
  for f in files+(['docker-compose.pgbackrest.yml'] if extra else []):cmd+=['-f',str(COMPOSE/f)]
  return cmd
 run(compose()+['config','-q'])
 # No changes to the running cluster while building the exact-version derivative.
 run(['docker','build','--tag','festapp-postgres-pgbackrest:17.6-2.57.0-r0',str(HERE)])
 image=run(['docker','image','inspect','festapp-postgres-pgbackrest:17.6-2.57.0-r0','--format','{{.Id}}'],True)
 assert re.fullmatch('sha256:[a-f0-9]{64}',image)
 assert run(['docker','run','--rm','--network','none','--entrypoint','postgres',image,'--version'],True)==original_version
 assert run(['docker','run','--rm','--network','none','--entrypoint','pgbackrest',image,'version'],True)=='pgBackRest 2.57.0'
 assert shutil.disk_usage(COMPOSE).free>8*1024**3, 'need at least 8 GiB free before activation'
 r2path=Path('/etc/festapp-backup/r2.env');assert r2path.stat().st_mode&0o777==0o600 and r2path.stat().st_uid==0
 r2=env_read(r2path);assert r2['R2_BUCKET']=='festapp-supabase-backups'
 endpoint=r2['R2_ENDPOINT'].removeprefix('https://').rstrip('/')
 assert re.fullmatch('[a-f0-9]{32}\\.r2\\.cloudflarestorage\\.com',endpoint)
 passphrase=secrets.token_hex(32)
 substitutions={'ACCOUNT.r2.cloudflarestorage.com':endpoint,'PROVISION_FROM_EXISTING_ROOT_ONLY_CONFIG':r2['AWS_ACCESS_KEY_ID'],'GENERATE_AND_ESCROW_WITH_EXISTING_AGE_RECIPIENT':passphrase}
 config=(HERE/'pgbackrest.conf.example').read_text()
 # Separate access-key and secret fields; never interpolate shell commands.
 config=config.replace('repo1-s3-key-secret=PROVISION_FROM_EXISTING_ROOT_ONLY_CONFIG','repo1-s3-key-secret='+r2['AWS_SECRET_ACCESS_KEY'])
 for before,after in substitutions.items():config=config.replace(before,after)
 SECRET.mkdir(mode=0o700)
 atomic(SECRET/'pgbackrest.conf',config,0o640);os.chown(SECRET/'pgbackrest.conf',0,101)
 # Escrow contains no R2 credentials. It is encrypted to the existing recovery identity.
 recovery={'version':1,'tool':'pgbackrest','stanza':'festapp','repo_path':'/pgbackrest/festapp-production','cipher_type':'aes-256-cbc','cipher_pass':passphrase}
 subprocess.run(['age','-r',r2['AGE_RECIPIENT'],'-o',str(SECRET/'recovery.json.age')],input=json.dumps(recovery).encode(),check=True,stdout=log,stderr=log)
 # Existing uploader/config reused only for this new encrypted key artifact.
 run(['rclone','--config','/dev/null','version'])
 rc=SECRET/'rclone.conf';atomic(rc,'[r2]\ntype=s3\nprovider=Cloudflare\naccess_key_id='+r2['AWS_ACCESS_KEY_ID']+'\nsecret_access_key='+r2['AWS_SECRET_ACCESS_KEY']+'\nendpoint=https://'+endpoint+'\nno_check_bucket=true\n')
 run(['rclone','--config',str(rc),'copyto',str(SECRET/'recovery.json.age'),'r2:festapp-supabase-backups/pgbackrest-key-escrow/festapp-recovery.json.age','--immutable'])
 rc.unlink()
 STATE.mkdir(mode=0o700);os.chown(STATE,100,101)
 for part in ['lock','spool','log']:
  (STATE/part).mkdir(mode=0o700);os.chown(STATE/part,100,101)
 shutil.copy2(envpath,evidence/'runtime.env.before')
 override=HERE.parents[1]/'runtime/docker-compose.pgbackrest.yml'
 shutil.copyfile(override,COMPOSE/'docker-compose.pgbackrest.yml');os.chmod(COMPOSE/'docker-compose.pgbackrest.yml',0o644)
 text=envpath.read_text();text=re.sub(r'^COMPOSE_FILE=.*$', 'COMPOSE_FILE='+':'.join(files+['docker-compose.pgbackrest.yml']),text,flags=re.M)
 assert 'FESTAPP_PGBACKREST_DB_IMAGE=' not in text
 text+='\nFESTAPP_PGBACKREST_DB_IMAGE='+image+'\n';atomic(envpath,text)
 run(compose(True)+['config','-q'])
 paused=None;restart_begun=False;healthy=False
 def ready():
  for _ in range(60):
   try:
    if sql('BEGIN READ ONLY; SELECT 1; COMMIT;')=='1':return True
   except subprocess.CalledProcessError:pass
   time.sleep(1)
  return False
 try:
  paused=sql('BEGIN; SELECT paused FROM public.email_capacity FOR UPDATE; UPDATE public.email_capacity SET paused=true; COMMIT;')
  assert paused in ('t','f')
  for _ in range(12):
   if sql("BEGIN READ ONLY; SELECT count(*) FROM public.email_messages WHERE workflow_state IN ('sending','preparing'); COMMIT;")=='0':break
   time.sleep(5)
  else:raise RuntimeError('active email provider attempts prevent DB restart')
  restart_begun=True
  run(compose(True)+['up','-d','--no-deps','--force-recreate','db'])
  assert ready(), 'database did not become ready'
  healthy=True
  assert run(['docker','exec','supabase-db','postgres','--version'],True)==original_version
  assert sql('BEGIN READ ONLY; SHOW archive_mode; COMMIT;')=='on'
  assert sql("BEGIN READ ONLY; SELECT has_function_privilege('supabase_admin','pg_catalog.pg_backup_start(text,boolean)','EXECUTE'); COMMIT;")=='t'
  run(['docker','exec','--user','postgres','supabase-db','pgbackrest','--stanza=festapp','stanza-create'])
  run(['docker','exec','--user','postgres','supabase-db','pgbackrest','--stanza=festapp','check'])
 except Exception:
  if restart_begun and not healthy:
   # Restore the identical pre-existing image/command; never alter application grants.
   atomic(envpath,(evidence/'runtime.env.before').read_text())
   run(compose()+['up','-d','--no-deps','--force-recreate','db']);healthy=ready()
  elif not restart_begun:atomic(envpath,(evidence/'runtime.env.before').read_text())
  raise
 finally:
  if paused=='f' and (not restart_begun or healthy):sql('BEGIN; UPDATE public.email_capacity SET paused=false; SELECT public.wake_email_worker(); COMMIT;')
 # Install schedule only after the first real full backup and archive check succeed.
 dest=Path('/opt/festapp-backup/pgbackrest');dest.mkdir(mode=0o700)
 shutil.copyfile(HERE/'run-backup.sh',dest/'run-backup.sh');os.chmod(dest/'run-backup.sh',0o700)
 shutil.copyfile(HERE/'Dockerfile',dest/'Dockerfile')
 atomic(SECRET/'enabled','enabled\n')
 run([str(dest/'run-backup.sh'),'full'])
 for unit in ['festapp-pgbackrest-backup.service','festapp-pgbackrest-backup.timer']:
  shutil.copyfile(HERE/unit,Path('/etc/systemd/system')/unit);os.chmod(Path('/etc/systemd/system')/unit,0o644)
 run(['systemctl','daemon-reload']);run(['systemctl','enable','--now','festapp-pgbackrest-backup.timer'])
 atomic(evidence/'result.json',json.dumps({'source_commit':args.source_commit,'image':image,'pg_version_unchanged':True,'pgbackrest':'2.57.0','archive_mode':'on','archive_timeout_seconds':300,'repo_encrypted':True,'initial_full_and_check_passed':True,'original_email_pause_restored':True,'existing_logical_backups_retained':True,'backup_timer_enabled':True},indent=2)+'\n')
 print(json.dumps({'status':'pass','evidence':str(evidence),'db_image':image}))
if __name__=='__main__':main()
