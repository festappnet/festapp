#!/usr/bin/env python3
"""Read-only off-server recovery. Requires Python 3, age and rclone."""
import argparse,json,os,subprocess,re,hashlib
from pathlib import Path
from backup_manifest import validate_artifacts
p=argparse.ArgumentParser();p.add_argument('--run');p.add_argument('--output',type=Path);p.add_argument('--pgbackrest',action='store_true');a=p.parse_args()
os.umask(0o077);kit=Path(__file__).resolve().parent
c=json.loads(subprocess.check_output(['age','-d','-i',str(kit/'age-identity.txt'),str(kit/'backup-reader.json.age')]))
assert c['buckets']==['festapp-supabase-backups']
env=os.environ.copy()
for k,v in {'TYPE':'s3','PROVIDER':'Cloudflare','ACCESS_KEY_ID':c['access_key_id'],'SECRET_ACCESS_KEY':c['secret_access_key'],'ENDPOINT':c['endpoint'],'NO_CHECK_BUCKET':'true'}.items():env['RCLONE_CONFIG_RECOVERY_'+k]=v
prefix='recovery:festapp-supabase-backups/'
def call(*args,**kw):return subprocess.run(['rclone','--config','/dev/null',*args],env=env,check=True,**kw)
if a.pgbackrest:
 assert a.output and not a.output.exists();a.output.mkdir(mode=0o700)
 call('copy',prefix+'pgbackrest/festapp-production',str(a.output));print('Encrypted pgBackRest repository downloaded')
elif not a.run:
 call('lsf','--dirs-only',prefix+'backups/festapp-supabase-rehearsal-01')
else:
 assert re.fullmatch(r'\d{8}T\d{6}Z',a.run) and a.output and not a.output.exists()
 a.output.mkdir(mode=0o700);source=prefix+'backups/festapp-supabase-rehearsal-01/'+a.run+'/'
 call('copyto',source+'manifest.json',str(a.output/'manifest.json'))
 m=json.loads((a.output/'manifest.json').read_text());assert m['run_id']==a.run and m['encrypted'] is True
 validate_artifacts(m)
 for name,meta in m['artifacts'].items():
  target=a.output/name;call('copyto',source+name,str(target))
  with target.open('rb') as f:assert hashlib.file_digest(f,'sha256').hexdigest()==meta['sha256']
  assert target.stat().st_size==meta['bytes']
 print('Downloaded and verified encrypted backup: '+a.run)
