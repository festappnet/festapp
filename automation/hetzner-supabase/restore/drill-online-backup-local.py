#!/usr/bin/env python3
"""Restore an existing encrypted online set to a NEW network-none local container.
No SSH, DB URL, host data mount, integration service or production target accepted.
Actual production backup acquisition/key recovery remains an operational gate.
"""
import argparse,datetime,hashlib,json,os,re,shutil,subprocess,tempfile,time,tarfile,traceback
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
 required={'postgres.dump.age','globals.sql.age','storage.tar.age','runtime.tar.age'}
 assert required<=set(m['artifacts'])<=required|{'r2-images.tar.age'}
 for name in m['artifacts']:
  path=folder/name;a=m['artifacts'][name]
  with path.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
  assert path.stat().st_size==a['bytes'] and digest==a['sha256'],name
 return m

def storage_consistency(objects, files):
 # Canonical file backend: GLOBAL_S3_BUCKET=stub, TENANT_ID=stub.
 # Supabase storage v1.60.4 TenantLocation + withOptionalVersion;
 # support the two upstream version separators, never an arbitrary suffix.
 matched=set();missing=0;size_mismatch=0
 for obj in objects:
  key='stub/stub/'+obj['bucket']+'/'+obj['name']
  version=obj.get('version')
  candidates=[key+'/'+version,key+'-$v-'+version] if version else [key]
  found=next((name for name in candidates if name in files),None)
  if found is None:missing+=1;continue
  matched.add(found)
  size=obj.get('size')
  if size is not None and int(size)!=files[found]:size_mismatch+=1
 return {'referenced_objects':len(objects),'matched_objects':len(objects)-missing,
  'missing_objects':missing,'size_mismatches':size_mismatch,
  'unreferenced_archive_files':len(set(files)-matched),
  'consistent':bool(objects) and missing==0 and size_mismatch==0,
  'scope':'Same online logical backup DB versus Storage archive, not coordinated PITR or external R2 image consistency'}

def main():
 p=argparse.ArgumentParser();p.add_argument('--backup-dir',type=Path,required=True);p.add_argument('--identity',type=Path,required=True);p.add_argument('--evidence',type=Path,required=True)
 p.add_argument('--storage-consistency',action='store_true')
 p.add_argument('--service-smoke',action='store_true')
 p.add_argument('--admin-resources',action='store_true')
 p.add_argument('--rebuild-storage-metadata',action='store_true')
 p.add_argument('--consume-downloaded-artifacts',action='store_true',help='Delete each local encrypted input only after successful decryption; retain manifest and off-host backups')
 a=p.parse_args();m=validate_manifest(a.backup_dir)
 assert not a.admin_resources or a.service_smoke,'admin resource drill requires service smoke'
 assert not a.rebuild_storage_metadata or a.service_smoke,'metadata recovery requires service smoke'
 assert a.identity.is_file() and not a.evidence.exists()
 # Pin the same supported production major; no untrusted CLI image argument.
 pins=json.loads((Path(__file__).resolve().parents[1]/'runtime/pins.json').read_text())
 image=pins['supabase']['images']['postgres']
 assert image.startswith('supabase/postgres:17.') and '@sha256:' in image
 # Check Docker before decrypting or consuming any downloaded input.
 image_info=json.loads(subprocess.check_output(['docker','image','inspect',image],stderr=subprocess.DEVNULL))[0]
 started=time.monotonic(); name='festapp-local-restore-'+os.urandom(8).hex()
 # No production secrets/SQL in terminal output. Full logs stay in a protected local tempdir.
 with tempfile.TemporaryDirectory(prefix='festapp-local-restore-') as tmp:
  work=Path(tmp);os.chmod(work,0o700)
  filenames=['postgres.dump','globals.sql','storage.tar','runtime.tar']
  if 'r2-images.tar.age' in m['artifacts']:filenames.append('r2-images.tar')
  # Avoid exhausting the workstation disk and causing Docker WAL fsync failures.
  # Consumption is opt-in and only happens after the complete set passed hashes.
  sizes=[m['artifacts'][filename+'.age']['bytes'] for filename in filenames]
  required_free=(max(sizes) if a.consume_downloaded_artifacts else sum(sizes))+512*1024*1024
  assert shutil.disk_usage(work).free>required_free,'Insufficient local disk space: free disk space or use --consume-downloaded-artifacts for this downloaded copy'
  for filename in filenames:
   source=a.backup_dir/(filename+'.age')
   run(['age','-d','-i',str(a.identity),'-o',str(work/filename),str(source)],stdout=subprocess.DEVNULL)
   if a.consume_downloaded_artifacts:source.unlink()
  # Inspect archive members without extracting or executing runtime config.
  counts={};storage_files={}
  for filename in ('storage.tar','runtime.tar'):
   with tarfile.open(work/filename) as archive:
    members=archive.getmembers()
    assert all(not Path(x.name).is_absolute() and '..' not in Path(x.name).parts and not x.issym() and not x.islnk() and (x.isfile() or x.isdir()) for x in members),'unsafe archive member'
    counts[filename]={'files':sum(x.isfile() for x in members),'bytes':sum(x.size for x in members if x.isfile())}
    if filename=='storage.tar' and (a.storage_consistency or a.service_smoke):
     storage_files={str(Path(x.name)):x.size for x in members if x.isfile()}
     assert len(storage_files)==counts[filename]['files'],'duplicate Storage archive paths'
  with (work/'restore.log').open('wb') as log:
   try:
    if a.service_smoke:
     command=image_info['Config']['Cmd']
     assert command==['postgres','-D','/etc/postgresql']
     # Keep PID 1 alive across the post-restore PostgreSQL restart. pg_net
     # requires its normal preload for CREATE EXTENSION during pg_restore;
     # all workers are disabled before any application services start.
     run(['docker','run','-d','--name',name,'--network','none','--label','festapp.isolated-restore=true',
       '-e','POSTGRES_PASSWORD=isolated-fixture-only','--entrypoint','sh',image,'-c','sleep 7200'],stdout=log,stderr=log)
     run(['docker','exec','-d',name,'sh','-c','docker-entrypoint.sh postgres -D /etc/postgresql > /tmp/restore-init.log 2>&1'],stdout=log,stderr=log)
    else:
     run(['docker','run','-d','--name',name,'--network','none','--label','festapp.isolated-restore=true',
       '-e','POSTGRES_PASSWORD=isolated-fixture-only',image],stdout=log,stderr=log)
    for _ in range(90):
     ready=subprocess.run(['docker','exec',name,'psql','-X','-U','supabase_admin','-d','postgres','-Atqc','SELECT 1'],capture_output=True)
     observed=subprocess.run(['docker','exec',name,'cat','/tmp/restore-init.log'] if a.service_smoke else ['docker','logs',name],capture_output=True)
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
    consistency=None
    if a.storage_consistency or a.service_smoke:
     query="BEGIN READ ONLY; SELECT coalesce(json_agg(json_build_object('bucket',bucket_id,'name',name,'version',version,'size',metadata->>'size')),'[]'::json) FROM storage.objects; COMMIT;"
     # Object names remain in memory only, never stdout/evidence/logs.
     rows=subprocess.check_output(['docker','exec',name,'psql','-X','-U','postgres','-d','isolated_restore','-v','ON_ERROR_STOP=1','-Atq','-c',query],stderr=log)
     consistency=storage_consistency(json.loads(rows),storage_files)
    r2_consistency=None
    if 'r2-images.tar.age' in m['artifacts']:
     from r2_archive import verify_archive
     query="BEGIN READ ONLY; SELECT coalesce(json_agg(link),'[]'::json) FROM public.images WHERE link LIKE 'https://img.festapp.net/%' OR link LIKE 'https://a.img.festapp.net/%'; COMMIT;"
     references=json.loads(subprocess.check_output(['docker','exec',name,'psql','-X','-U','postgres','-d','isolated_restore','-v','ON_ERROR_STOP=1','-Atq','-c',query],stderr=log))
     r2_consistency=verify_archive(work/'r2-images.tar',references)
    application=None
    if a.service_smoke:
     assert consistency['consistent'],'inconsistent Storage prevents application recovery proof'
     from service_smoke import application_reads
     application=application_reads(name,pins,work/'storage.tar',log,admin_resources=a.admin_resources,rebuild_metadata=a.rebuild_storage_metadata)
    result={'version':1,'status':'pass' if r2_consistency is None or r2_consistency['consistent'] else 'inconsistent-r2-references','backup_run_id':m['run_id'],'backup_manifest_sha256':hashlib.sha256((a.backup_dir/'manifest.json').read_bytes()).hexdigest(),
     'source_backup_consistency':m['consistency'],'isolated':True,'network':'none','ports':False,'host_mounts':False,
     'application_services_started':bool(application),'application_reads':application,'runtime_executed':False,'local_encrypted_downloads_consumed':a.consume_downloaded_artifacts,'archive_inventory':counts,'storage_consistency':consistency,'r2_consistency':r2_consistency,
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
     out.write(traceback.format_exc().encode())
     out.write((work/'restore.log').read_bytes())
    raise RuntimeError('Local restore failed; protected diagnostics saved beside requested evidence; no production action performed') from None
   finally:
    # Exact randomly generated task-owned container only; never prune or touch live volumes.
    subprocess.run(['docker','rm','-f','-v',name],stdout=log,stderr=log)
  a.evidence.parent.mkdir(parents=True,exist_ok=True)
  fd=os.open(a.evidence,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
  with os.fdopen(fd,'w') as out:json.dump(result,out,indent=2)
 assert result['status']=='pass','R2 references are inconsistent; application recovery and bounded gap evidence saved'
 print('Isolated online-backup restore: pass')
if __name__=='__main__':main()
