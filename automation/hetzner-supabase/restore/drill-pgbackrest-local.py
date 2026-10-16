#!/usr/bin/env python3
"""Restore an encrypted repository COPY to a new network-none local container.
No production target, bind mount, application process or cutover accepted.
"""
import argparse,datetime,json,os,re,subprocess,tempfile,time,uuid
from pathlib import Path
IMAGE='festapp-postgres-pgbackrest:17.6-2.57.0-r0'
def main():
 p=argparse.ArgumentParser();p.add_argument('--repo-dir',type=Path,required=True);p.add_argument('--recovery',type=Path,required=True);p.add_argument('--identity',type=Path,required=True);p.add_argument('--target',required=True);p.add_argument('--backup-label',required=True);p.add_argument('--evidence',type=Path,required=True);a=p.parse_args()
 target=datetime.datetime.fromisoformat(a.target.replace('Z','+00:00'));assert target.tzinfo
 assert re.fullmatch(r'\d{8}-\d{6}F(?:_\d{8}-\d{6}D)?',a.backup_label), 'restore from an explicit full/differential backup'
 assert a.repo_dir.is_dir() and (a.repo_dir/'backup/festapp/backup.info').is_file()
 assert not any(x.is_symlink() for x in a.repo_dir.rglob('*'))
 assert a.identity.is_file() and a.identity.stat().st_mode&0o077==0
 assert not a.evidence.exists()
 os.umask(0o077);a.evidence.parent.mkdir(parents=True,exist_ok=True)
 recovery=json.loads(subprocess.check_output(['age','-d','-i',str(a.identity),str(a.recovery)],stderr=subprocess.DEVNULL))
 assert recovery['tool']=='pgbackrest' and recovery['stanza']=='festapp' and recovery['repo_path']=='/pgbackrest/festapp-production' and recovery['cipher_type']=='aes-256-cbc'
 assert re.fullmatch('[a-f0-9]{64}',recovery['cipher_pass'])
 name='festapp-pitr-restore-'+uuid.uuid4().hex[:12];started=time.monotonic()
 with tempfile.TemporaryDirectory(prefix='festapp-pitr-') as temp:
  logfile=Path(temp)/'restore.log'
  with logfile.open('wb') as log:
   def run(*args,input=None,capture=False):
    if capture:return subprocess.check_output(args,input=input,stderr=log).decode().strip()
    subprocess.run(args,input=input,stdout=log,stderr=log,check=True)
   def ex(*args,input=None,capture=False):return run('docker','exec','-i',name,*args,input=input,capture=capture)
   try:
    run('docker','run','-d','--name',name,'--network','none','--user','postgres','--entrypoint','sh',IMAGE,'-c','sleep 3600')
    assert ex('pgbackrest','version',capture=True)=='pgBackRest 2.57.0'
    run('docker','cp',str(a.repo_dir),name+':/tmp/offline-repo')
    run('docker','exec','--user','root',name,'chown','-R','100:101','/tmp/offline-repo')
    config='[global]\nrepo1-type=posix\nrepo1-path=/tmp/offline-repo\nrepo1-cipher-type=aes-256-cbc\nrepo1-cipher-pass='+recovery['cipher_pass']+'\nprocess-max=1\nlog-level-file=off\nlog-level-console=warn\nlock-path=/tmp/pgbackrest-lock\nspool-path=/tmp/pgbackrest-spool\n[festapp]\npg1-path=/tmp/restore-data\n'
    ex('sh','-c','umask 077; cat > /tmp/pgbackrest.conf',input=config.encode())
    ex('pgbackrest','--config=/tmp/pgbackrest.conf','--stanza=festapp','--set='+a.backup_label,'--type=time','--target='+a.target,'--target-action=pause','--link-all=n','--tablespace-map-all=/tmp/restore-tablespaces','restore')
    # Replace external server configuration; retain only pgBackRest's recovery
    # settings in postgresql.auto.conf. No app/cron/net preload or TCP listener.
    control=ex('pg_controldata','/tmp/restore-data',capture=True)
    settings={}
    for line in control.splitlines():
     if ':' not in line:continue
     key,value=line.split(':',1);key=key.strip().lower().removesuffix(' setting')
     if key in ['max_connections','max_worker_processes','max_wal_senders','max_prepared_xacts','max_locks_per_xact']:
      settings[{'max_prepared_xacts':'max_prepared_transactions','max_locks_per_xact':'max_locks_per_transaction'}.get(key,key)]=int(value.strip())
    server="data_directory='/tmp/restore-data'\nhba_file='/tmp/safe_hba.conf'\nident_file='/tmp/safe_ident.conf'\nunix_socket_directories='/tmp'\nlisten_addresses=''\nshared_preload_libraries=''\nsession_preload_libraries=''\nlocal_preload_libraries=''\narchive_mode=off\nhot_standby=on\nprimary_conninfo=''\nmax_logical_replication_workers=0\nautovacuum=off\n"
    server+=''.join(k+'='+str(v)+'\n' for k,v in settings.items())
    ex('sh','-c','cat > /tmp/safe-postgresql.conf',input=server.encode())
    ex('sh','-c',"printf 'local all all trust\\n' > /tmp/safe_hba.conf; touch /tmp/safe_ident.conf")
    ex('pg_ctl','-D','/tmp/restore-data','-l','/tmp/server.log','-o','-c config_file=/tmp/safe-postgresql.conf','-w','start')
    def sql(q):return ex('psql','-X','-h','/tmp','-U','supabase_admin','-d','festapp_rehearsal_20260909220601','-Atqv','ON_ERROR_STOP=1','-c',q,capture=True)
    for _ in range(120):
     if sql('BEGIN READ ONLY; SELECT pg_is_in_recovery() AND pg_is_wal_replay_paused(); COMMIT;')=='t':break
     time.sleep(.5)
    else:raise RuntimeError('requested time target was not reached and paused')
    state=json.loads(sql("BEGIN READ ONLY; SELECT json_build_object('replay_at',pg_last_xact_replay_timestamp(),'replay_lsn',pg_last_wal_replay_lsn(),'organization_exists',EXISTS(SELECT 1 FROM public.organizations WHERE id=1),'security_versions',(SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version IN ('20261016170000','20261016171000','20261016172000'))); COMMIT;"))
    assert state['organization_exists'] and state['security_versions']==3
    assert state['replay_at'] and datetime.datetime.fromisoformat(state['replay_at'])<=target
    # Assert isolation from Docker's actual config, not just requested flags.
    actual=json.loads(run('docker','inspect',name,capture=True))[0]
    assert actual['HostConfig']['NetworkMode']=='none' and not actual['HostConfig']['PortBindings']
    assert not any(m['Type']=='bind' for m in actual['Mounts'])
    result={'status':'pass','tool':'pgbackrest 2.57.0','backup_label':a.backup_label,'target':a.target,'paused_at_target':True,'replay_at':state['replay_at'],'replay_lsn':state['replay_lsn'],'catalog_smoke':True,'network':'none','ports':False,'host_mounts':False,'application_preloads_disabled':True,'encrypted_key_escrow_used':True,'isolated_restore_seconds':round(time.monotonic()-started,2),'full_service_rto_proven':False,'storage_r2_consistency_proven':False}
   except Exception:
    subprocess.run(['docker','cp',name+':/tmp/server.log',str(Path(temp)/'server.log')],stdout=log,stderr=log)
    log.flush()
    failure=a.evidence.with_suffix('.failure.log')
    with failure.open('xb') as out:
     out.write(logfile.read_bytes())
     if (Path(temp)/'server.log').exists():out.write((Path(temp)/'server.log').read_bytes())
    raise RuntimeError('Isolated PITR failed; protected diagnostics saved beside evidence') from None
   finally:subprocess.run(['docker','rm','-f','-v',name],stdout=log,stderr=log)
 with a.evidence.open('x') as stream:json.dump(result,stream,indent=2);stream.write('\n')
 print('Isolated real-backup PITR reached requested time and catalog smoke passed')
if __name__=='__main__':main()
