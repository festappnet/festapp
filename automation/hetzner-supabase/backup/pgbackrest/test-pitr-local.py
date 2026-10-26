#!/usr/bin/env python3
"""Real full/differential/PITR and archive-failure test, no network or host mounts."""
import json,subprocess,tempfile,time,uuid
from pathlib import Path
IMAGE='festapp-postgres-pgbackrest:17.6-2.57.0-r0'
name='festapp-pgbackrest-test-'+uuid.uuid4().hex[:10]
def run(*args,input=None):
 return subprocess.check_output(args,input=input,stderr=subprocess.STDOUT).decode().strip()
def ex(*args,input=None): return run('docker','exec','-i',name,*args,input=input)
def sql(q,port='5432'): return ex('psql','-X','-h','/tmp','-p',port,'-U','postgres','-d','postgres','-Atv','ON_ERROR_STOP=1','-c',q)
def pb(*args): return ex('pgbackrest','--config=/tmp/pitr/pgbackrest.conf','--stanza=test',*args)
try:
 run('docker','run','-d','--name',name,'--network','none','--user','postgres','--entrypoint','sh',IMAGE,'-c','mkdir -p /tmp/pitr; sleep 3600')
 ex('initdb','-D','/tmp/pitr/data','-U','postgres','-A','trust')
 config='''[global]
repo1-path=/tmp/pitr/repo
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=disposable-test-key-not-a-production-credential
repo1-retention-full=4
process-max=1
compress-type=zst
compress-level=1
log-level-console=warn
log-level-file=off
lock-path=/tmp/pitr/lock
spool-path=/tmp/pitr/spool
[test]
pg1-path=/tmp/pitr/data
pg1-socket-path=/tmp
pg1-user=postgres
'''
 ex('sh','-c','cat > /tmp/pitr/pgbackrest.conf',input=config.encode())
 ex('sh','-c','cat >> /tmp/pitr/data/postgresql.conf',input=b"archive_command = 'pgbackrest --config=/tmp/pitr/pgbackrest.conf --stanza=test archive-push %p'\n")
 options="-k /tmp -c listen_addresses='' -c archive_mode=on -c archive_timeout=300"
 ex('pg_ctl','-D','/tmp/pitr/data','-l','/tmp/pitr/server.log','-o',options,'-w','start')
 pb('stanza-create');pb('check')
 sql('CREATE TABLE pitr_marker(id integer PRIMARY KEY);')
 pb('--type=full','backup')
 info=json.loads(pb('--output=json','info'));full=info[0]['backup'][-1]['label']
 sql('INSERT INTO pitr_marker VALUES (1)')
 target=sql('SELECT clock_timestamp()::text')
 time.sleep(1)
 sql('INSERT INTO pitr_marker VALUES (2); SELECT pg_switch_wal();')
 pb('check');pb('--type=diff','backup')
 info=json.loads(pb('--output=json','info'));assert info[0]['backup'][-1]['type']=='diff'
 # Restore a differential backup to a second, isolated data directory.
 pb('--pg1-path=/tmp/pitr/diff','--type=immediate','--target-action=promote','restore')
 ex('pg_ctl','-D','/tmp/pitr/diff','-l','/tmp/pitr/diff.log','-o',"-k /tmp -p 5433 -c listen_addresses='' -c archive_mode=off",'-w','start')
 for _ in range(60):
  if sql('SELECT pg_is_in_recovery()','5433')=='f':break
  time.sleep(.2)
 assert sql('SELECT string_agg(id::text,\',\' ORDER BY id) FROM pitr_marker','5433')=='1,2'
 ex('pg_ctl','-D','/tmp/pitr/diff','-m','fast','-w','stop')
 # Earlier timestamp must recover row 1 and exclude row 2, starting at the full backup.
 pb('--pg1-path=/tmp/pitr/restored','--set='+full,'--type=time','--target='+target,'--target-action=pause','restore')
 ex('pg_ctl','-D','/tmp/pitr/restored','-l','/tmp/pitr/restored.log','-o',"-k /tmp -p 5434 -c listen_addresses='' -c archive_mode=off",'-w','start')
 for _ in range(60):
  if sql('SELECT pg_is_wal_replay_paused()','5434')=='t':break
  time.sleep(.2)
 assert sql('SELECT pg_is_in_recovery() AND pg_is_wal_replay_paused()','5434')=='t'
 assert sql('SELECT string_agg(id::text,\',\' ORDER BY id) FROM pitr_marker','5434')=='1'
 # Simulated unavailable repository must fail closed and leave the WAL .ready.
 sql("ALTER SYSTEM SET archive_command='false'")
 sql("SELECT pg_reload_conf()")
 time.sleep(.5)
 sql('INSERT INTO pitr_marker VALUES (3); SELECT pg_switch_wal();')
 for _ in range(40):
  failed=sql('SELECT failed_count>0 FROM pg_stat_archiver')
  if failed=='t':break
  time.sleep(.25)
 assert failed=='t'
 assert int(sql("SELECT count(*) FROM pg_ls_archive_statusdir() WHERE name LIKE '%.ready'"))>0
 print(json.dumps({'status':'pass','full_backup':True,'differential_restore':True,'time_target_excludes_later_commit':True,'archive_failure_retains_wal':True,'network':'none','host_mounts':False,'pgbackrest':'2.57.0'}))
except subprocess.CalledProcessError as e:
 # Synthetic cluster only; errors contain no production data or keys.
 print(e.output.decode()[-4000:]);raise
finally:
 subprocess.run(['docker','rm','-f','-v',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
