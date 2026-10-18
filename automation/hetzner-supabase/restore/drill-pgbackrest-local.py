#!/usr/bin/env python3
"""Restore an encrypted repository COPY to a new network-none local container.
No production target, bind mount or cutover accepted. Optional REST read smoke
shares only the network-none container's private loopback, with fixture auth.
"""
import argparse,datetime,json,os,re,subprocess,tempfile,time,uuid
from pathlib import Path
IMAGE='festapp-postgres-pgbackrest:17.6-2.57.0-r0'
def postgres_recovery_target(value):
 target=datetime.datetime.fromisoformat(value.replace('Z','+00:00'))
 if target.tzinfo is None:raise ValueError('Recovery target requires an explicit timezone')
 # PostgreSQL's recovery GUC rejects the otherwise valid ISO UTC suffix Z.
 return target.astimezone(datetime.timezone.utc).isoformat(sep=' ')

def main():
 p=argparse.ArgumentParser();p.add_argument('--repo-dir',type=Path,required=True);p.add_argument('--recovery',type=Path,required=True);p.add_argument('--identity',type=Path,required=True);p.add_argument('--target',required=True);p.add_argument('--backup-label',required=True);p.add_argument('--evidence',type=Path,required=True);p.add_argument('--rest-smoke',action='store_true');a=p.parse_args()
 target=postgres_recovery_target(a.target)
 assert re.fullmatch(r'\d{8}-\d{6}F(?:_\d{8}-\d{6}D)?',a.backup_label), 'restore from an explicit full/differential backup'
 assert a.repo_dir.is_dir() and (a.repo_dir/'backup/festapp/backup.info').is_file()
 assert not any(x.is_symlink() for x in a.repo_dir.rglob('*'))
 assert a.identity.is_file() and a.identity.stat().st_mode&0o077==0
 assert not a.evidence.exists()
 os.umask(0o077);a.evidence.parent.mkdir(parents=True,exist_ok=True)
 recovery=json.loads(subprocess.check_output(['age','-d','-i',str(a.identity),str(a.recovery)],stderr=subprocess.DEVNULL))
 assert recovery['tool']=='pgbackrest' and recovery['stanza']=='festapp' and recovery['repo_path']=='/pgbackrest/festapp-production' and recovery['cipher_type']=='aes-256-cbc'
 assert re.fullmatch('[a-f0-9]{64}',recovery['cipher_pass'])
 name='festapp-pitr-restore-'+uuid.uuid4().hex[:12];rest_name=name+'-rest';started=time.monotonic()
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
    ex('pgbackrest','--config=/tmp/pgbackrest.conf','--stanza=festapp','--set='+a.backup_label,'--type=time','--target='+target,'--target-action=pause','--link-all=n','--tablespace-map-all=/tmp/restore-tablespaces','restore')
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
    if a.rest_smoke:server=server.replace("listen_addresses=''","listen_addresses='127.0.0.1'")
    ex('sh','-c','cat > /tmp/safe-postgresql.conf',input=server.encode())
    ex('sh','-c',"printf 'local all all trust\\n' > /tmp/safe_hba.conf; touch /tmp/safe_ident.conf")
    if a.rest_smoke:ex('sh','-c',"printf 'host all supabase_admin 127.0.0.1/32 trust\\n' >> /tmp/safe_hba.conf")
    # Command-line settings override restored postgresql.auto.conf as well.
    options='-c config_file=/tmp/safe-postgresql.conf -c data_directory=/tmp/restore-data -c hba_file=/tmp/safe_hba.conf -c ident_file=/tmp/safe_ident.conf -c unix_socket_directories=/tmp -c port=5432 -c shared_preload_libraries= -c session_preload_libraries= -c local_preload_libraries= -c archive_mode=off -c listen_addresses= -c primary_conninfo= -c max_logical_replication_workers=0 -c autovacuum=off -c ssl=off'
    if a.rest_smoke:options=options.replace('-c listen_addresses= ', '-c listen_addresses=127.0.0.1 ')
    ex('pg_ctl','-D','/tmp/restore-data','-l','/tmp/server.log','-o',options,'-w','start')
    def sql(q):return ex('env','PGOPTIONS=-c session_preload_libraries= -c local_preload_libraries=','psql','-X','-h','/tmp','-U','supabase_admin','-d','festapp_rehearsal_20260909220601','-Atqv','ON_ERROR_STOP=1','-c',q,capture=True)
    for _ in range(120):
     if sql('BEGIN READ ONLY; SELECT pg_is_in_recovery() AND pg_is_wal_replay_paused(); COMMIT;')=='t':break
     time.sleep(.5)
    else:raise RuntimeError('requested time target was not reached and paused')
    state=json.loads(sql("BEGIN READ ONLY; SELECT json_build_object('preloads_disabled',current_setting('shared_preload_libraries')='' AND current_setting('session_preload_libraries')='' AND current_setting('local_preload_libraries')='','network_disabled',current_setting('listen_addresses')='' AND current_setting('primary_conninfo')='' AND current_setting('max_logical_replication_workers')='0','archiving_disabled',current_setting('archive_mode')='off','replay_at',pg_last_xact_replay_timestamp(),'replay_lsn',pg_last_wal_replay_lsn(),'organization_exists',EXISTS(SELECT 1 FROM public.organizations WHERE id=1),'security_versions',(SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version IN ('20261016170000','20261016171000','20261016172000'))); COMMIT;"))
    assert state['organization_exists'] and state['security_versions']==3
    if a.rest_smoke:
     state['network_disabled']=sql("BEGIN READ ONLY; SELECT current_setting('listen_addresses')='127.0.0.1' AND current_setting('primary_conninfo')='' AND current_setting('max_logical_replication_workers')='0'; COMMIT;")=='t'
    assert state['preloads_disabled'] and state['network_disabled'] and state['archiving_disabled']
    assert state['replay_at'] and datetime.datetime.fromisoformat(state['replay_at'])<=target
    # Assert isolation from Docker's actual config, not just requested flags.
    actual=json.loads(run('docker','inspect',name,capture=True))[0]
    assert actual['HostConfig']['NetworkMode']=='none' and not actual['HostConfig']['PortBindings']
    assert not any(m['Type']=='bind' for m in actual['Mounts'])
    rest_smoke=False
    if a.rest_smoke:
     pins=json.loads((Path(__file__).resolve().parents[1]/'runtime/pins.json').read_text())
     image=pins['supabase']['images']['rest'];assert image.startswith('postgrest/postgrest:') and '@sha256:' in image
     # Paused read-only clone: admin connection can clear preload GUCs; HTTP
     # requests run as service_role. No production JWT/password or DB config.
     uri='postgresql://supabase_admin@127.0.0.1:5432/festapp_rehearsal_20260909220601?options=-c%20session_preload_libraries%3D%20-c%20local_preload_libraries%3D'
     run('docker','run','-d','--name',rest_name,'--network','container:'+name,'--read-only','--cap-drop=ALL','--security-opt=no-new-privileges',
      '-e','PGRST_DB_URI='+uri,'-e','PGRST_DB_ANON_ROLE=service_role','-e','PGRST_DB_SCHEMAS=public','-e','PGRST_DB_CONFIG=false',
      '-e','PGRST_JWT_SECRET=isolated-restore-fixture-only-secret-000000000000','-e','PGRST_SERVER_HOST=127.0.0.1',image)
     for _ in range(60):
      try:
       response=ex('curl','--fail','--silent','--max-time','2','http://127.0.0.1:3000/organizations?select=id&id=eq.1',capture=True)
       assert json.loads(response)==[{'id':1}];break
      except (subprocess.CalledProcessError,ValueError,AssertionError):time.sleep(.5)
     else:raise RuntimeError('isolated REST organization read failed')
     # Exercise a real application read with an empty projection, retaining no payload.
     assert isinstance(json.loads(ex('curl','--fail','--silent','--max-time','5','http://127.0.0.1:3000/occasions?select=id&limit=1',capture=True)),list)
     rest_actual=json.loads(run('docker','inspect',rest_name,capture=True))[0]
     assert rest_actual['HostConfig']['NetworkMode']=='container:'+actual['Id'] or rest_actual['HostConfig']['NetworkMode']=='container:'+name
     assert not rest_actual['HostConfig']['PortBindings'] and not any(m['Type']=='bind' for m in rest_actual['Mounts'])
     rest_smoke=True
    result={'status':'pass','tool':'pgbackrest 2.57.0','backup_label':a.backup_label,'target':a.target,'postgres_recovery_target':target,'paused_at_target':True,'replay_at':state['replay_at'],'replay_lsn':state['replay_lsn'],'catalog_smoke':True,'application_rest_read_smoke':rest_smoke,'production_integrations_started':False,'network':'none','ports':False,'host_mounts':False,'application_preloads_disabled':True,'encrypted_key_escrow_used':True,'isolated_restore_seconds':round(time.monotonic()-started,2),'full_service_rto_proven':False,'storage_r2_consistency_proven':False}
   except Exception:
    subprocess.run(['docker','logs',rest_name],stdout=log,stderr=log)
    subprocess.run(['docker','cp',name+':/tmp/server.log',str(Path(temp)/'server.log')],stdout=log,stderr=log)
    log.flush()
    failure=a.evidence.with_suffix('.failure.log')
    with failure.open('xb') as out:
     out.write(logfile.read_bytes())
     if (Path(temp)/'server.log').exists():out.write((Path(temp)/'server.log').read_bytes())
    raise RuntimeError('Isolated PITR failed; protected diagnostics saved beside evidence') from None
   finally:
    subprocess.run(['docker','rm','-f','-v',rest_name],stdout=log,stderr=log)
    subprocess.run(['docker','rm','-f','-v',name],stdout=log,stderr=log)
 with a.evidence.open('x') as stream:json.dump(result,stream,indent=2);stream.write('\n')
 print('Isolated real-backup PITR reached requested time and catalog smoke passed')
if __name__=='__main__':main()
