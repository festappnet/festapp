#!/usr/bin/env python3
"""Restore an existing encrypted online set to a NEW network-none local container.
No SSH, DB URL, host data mount, integration service or production target accepted.
Actual production backup acquisition/key recovery remains an operational gate.
"""
import argparse,datetime,hashlib,json,os,re,subprocess,tempfile,time,tarfile
from pathlib import Path

def run(args,**kw):
 return subprocess.run(args,check=True,**kw)

def validate_manifest(folder):
 m=json.loads((folder/'manifest.json').read_text())
 assert m['version']==1 and m['encrypted'] is True
 assert m['consistency']=='online-operational-backup-not-promotion-rpo0'
 assert re.fullmatch(r'\d{8}T\d{6}Z',m['run_id'])
 assert m['source_host']=='festapp-supabase-rehearsal-01'
 assert m['source_database']=='festapp_rehearsal_20260909220601'
 for name in ('postgres.dump.age','globals.sql.age','storage.tar.age','runtime.tar.age'):
  data=(folder/name).read_bytes(); a=m['artifacts'][name]
  assert len(data)==a['bytes'] and hashlib.sha256(data).hexdigest()==a['sha256'],name
 return m

def main():
 p=argparse.ArgumentParser();p.add_argument('--backup-dir',type=Path,required=True);p.add_argument('--identity',type=Path,required=True);p.add_argument('--evidence',type=Path,required=True)
 a=p.parse_args();m=validate_manifest(a.backup_dir)
 assert a.identity.is_file() and not a.evidence.exists()
 # Pin the same supported production major; no untrusted CLI image argument.
 pins=json.loads((Path(__file__).resolve().parents[1]/'runtime/pins.json').read_text())
 image=pins['supabase']['images']['postgres']
 assert image.startswith('supabase/postgres:17.') and '@sha256:' in image
 started=time.monotonic(); name='festapp-local-restore-'+os.urandom(8).hex()
 # No production secrets/SQL in terminal output. Full logs stay in a protected local tempdir.
 with tempfile.TemporaryDirectory(prefix='festapp-local-restore-') as tmp:
  work=Path(tmp);os.chmod(work,0o700)
  for filename in ('postgres.dump','globals.sql','storage.tar','runtime.tar'):
   run(['age','-d','-i',str(a.identity),'-o',str(work/filename),str(a.backup_dir/(filename+'.age'))],stdout=subprocess.DEVNULL)
  # Inspect archive members without extracting or executing runtime config.
  counts={}
  for filename in ('storage.tar','runtime.tar'):
   with tarfile.open(work/filename) as archive:
    members=archive.getmembers()
    assert all(not Path(x.name).is_absolute() and '..' not in Path(x.name).parts and not x.issym() and not x.islnk() and (x.isfile() or x.isdir()) for x in members),'unsafe archive member'
    counts[filename]={'files':sum(x.isfile() for x in members),'bytes':sum(x.size for x in members if x.isfile())}
  with (work/'restore.log').open('wb') as log:
   try:
    run(['docker','run','-d','--name',name,'--network','none','--label','festapp.isolated-restore=true',
      '-e','POSTGRES_PASSWORD=isolated-fixture-only',image],stdout=log,stderr=log)
    for _ in range(90):
     ready=subprocess.run(['docker','exec',name,'psql','-X','-U','supabase_admin','-d','postgres','-Atqc','SELECT 1'],capture_output=True)
     observed=subprocess.run(['docker','logs',name],capture_output=True)
     logs=observed.stdout+observed.stderr
     if ready.returncode==0 and b'PostgreSQL init process complete' in logs:break
     time.sleep(1)
    else:raise RuntimeError('isolated restore database did not become ready')
    inspect=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
    assert inspect['HostConfig']['NetworkMode']=='none' and not inspect['HostConfig']['Binds'] and not inspect['HostConfig']['PortBindings']
    # Restore globals with duplicate standard-role CREATE errors tolerated. No log exposure.
    with (work/'globals.sql').open('rb') as stream, (work/'globals-restore.log').open('wb') as globals_log:
     run(['docker','exec','-i',name,'psql','-X','-U','supabase_admin','-d','postgres'],stdin=stream,stdout=globals_log,stderr=globals_log)
    globals_output=(work/'globals-restore.log').read_text()
    log.write(globals_output.encode()); log.flush()
    # Only pre-existing foundation roles may fail CREATE. All ALTER/GRANT and
    # every other globals statement must succeed, even though psql continued.
    errors=[line for line in globals_output.splitlines() if 'ERROR:' in line]
    assert all(re.fullmatch(r'.*ERROR:\s+role "[^"]+" already exists',line) for line in errors),'globals restore error'
    run(['docker','exec',name,'createdb','-U','supabase_admin','-O','supabase_admin','isolated_restore'],stdout=log,stderr=log)
    # pg_cron background jobs cannot execute: network-none and cron database_name
    # remains postgres, while all restored jobs/data live in isolated_restore.
    # Exclude only pg_cron extension-owned items that cannot install in this DB.
    with (work/'postgres.dump').open('rb') as stream:
     listing=subprocess.check_output(['docker','exec','-i',name,'pg_restore','--list'],stdin=stream).decode()
    listing='\n'.join(';'+line if re.search(r'EXTENSION - pg_cron|COMMENT - EXTENSION pg_cron|TABLE DATA cron |SEQUENCE SET cron |FUNCTION extensions grant_pg_cron_access|EVENT TRIGGER - issue_pg_cron_access|COMMENT extensions FUNCTION grant_pg_cron_access|ACL - SCHEMA cron |ACL cron |ACL extensions FUNCTION grant_pg_cron_access',line) else line for line in listing.splitlines())+'\n'
    run(['docker','exec','-i',name,'sh','-c','cat > /tmp/restore.list'],input=listing.encode(),stdout=log,stderr=log)
    with (work/'postgres.dump').open('rb') as stream:
     run(['docker','exec','-i',name,'pg_restore','-U','supabase_admin','-d','isolated_restore','--exit-on-error','-L','/tmp/restore.list'],stdin=stream,stdout=log,stderr=log)
    smoke="BEGIN READ ONLY; SELECT count(*) FROM public.organizations; SELECT count(*) FROM auth.users; SELECT count(*) FROM storage.objects; COMMIT;"
    run(['docker','exec',name,'psql','-X','-U','postgres','-d','isolated_restore','-v','ON_ERROR_STOP=1','-Atqc',smoke],stdout=log,stderr=log)
    result={'version':1,'status':'pass','backup_run_id':m['run_id'],'backup_manifest_sha256':hashlib.sha256((a.backup_dir/'manifest.json').read_bytes()).hexdigest(),
     'source_backup_consistency':m['consistency'],'isolated':True,'network':'none','ports':False,'host_mounts':False,
     'application_services_started':False,'runtime_executed':False,'archive_inventory':counts,
     'database_read_smoke':True,'globals_errors_checked':True,'rto_seconds':round(time.monotonic()-started,2),
     'rpo_seconds':None,'pitr_proven':False,'note':'Online DB, Storage and R2 are not one coordinated recovery point; key-loss recovery and cross-store consistency require separate evidence.'}
   except Exception as error:
    # Preserve protected diagnostics only, not decrypted data or role passwords.
    # Errors from pg_restore can contain row values, so never print these logs.
    log.flush()
    failure=a.evidence.with_suffix('.failure.log')
    failure.parent.mkdir(parents=True,exist_ok=True)
    fd=os.open(failure,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'wb') as out:
     out.write(type(error).__name__.encode()+b'\n')
     out.write((work/'restore.log').read_bytes())
    raise RuntimeError('Local restore failed; protected diagnostics saved beside requested evidence; no production action performed') from None
   finally:
    # Exact randomly generated task-owned container only; never prune or touch live volumes.
    subprocess.run(['docker','rm','-f','-v',name],stdout=log,stderr=log)
  a.evidence.parent.mkdir(parents=True,exist_ok=True)
  fd=os.open(a.evidence,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
  with os.fdopen(fd,'w') as out:json.dump(result,out,indent=2)
 print('Isolated online-backup restore: pass')
if __name__=='__main__':main()
