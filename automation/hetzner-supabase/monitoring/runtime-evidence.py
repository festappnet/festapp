#!/usr/bin/env python3
"""Fixed root-only observations for the EXISTING host monitoring timer.
Never serializes Docker env, DB query text or backup credentials.
"""
import datetime,json,os,subprocess,tempfile,time
from pathlib import Path
COMPOSE=Path('/opt/festapp-supabase/docker')
OUTPUT=Path('/var/lib/festapp-host-monitor/runtime.json')

def command(args):
 return subprocess.check_output(args,cwd=COMPOSE,stderr=subprocess.DEVNULL,timeout=8).decode()
def latest(pattern):
 dates=[]
 for path in Path('/var/lib/festapp-rehearsal-evidence').glob(pattern):
  try:
   value=json.loads(path.read_text())
   if value.get('off_host_verified') is True:dates.append(datetime.datetime.fromisoformat(value['uploaded_at'].replace('Z','+00:00')).timestamp())
  except (OSError,ValueError,KeyError):pass
 return max(dates,default=None)
def main():
 assert os.geteuid()==0 and os.uname().nodename.split('.')[0]=='festapp-supabase-rehearsal-01'
 env=dict(line.split('=',1) for line in (COMPOSE/'.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
 assert env.get('FESTAPP_RUNTIME_DATABASE')=='festapp_rehearsal_20260909220601'
 result={'at':time.time()*1000,'ok':False}
 try:
  ids=command(['docker','compose','ps','-aq']).split()
  assert ids
  containers=json.loads(command(['docker','inspect',*ids]))
  result['containers']=[{'name':c['Name'],'running':c['State']['Running'],'oom':c['State']['OOMKilled'],'restarts':c['RestartCount']} for c in containers]
  # No customer rows, SQL text, connection addresses or capabilities.
  sql="BEGIN READ ONLY; SELECT count(*) FROM pg_stat_activity WHERE xact_start<now()-interval '15 minutes' AND pid<>pg_backend_pid(); COMMIT;"
  value=command(['docker','exec','supabase-db','psql','-X','-U','postgres','-d','festapp_rehearsal_20260909220601','-Atqc',sql]).splitlines()
  result['longTransactions']=int(next(x for x in value if x.isdigit()))
  result['backupAt']=latest('scheduled-backup-*/result.json')
  result['logUploadAt']=latest('runtime-log-upload-*/result.json')
  if Path('/etc/festapp-pgbackrest/enabled').exists():
   # Fixed metadata only. Never query repository credentials or customer rows.
   pitr_sql="BEGIN READ ONLY; SELECT json_build_object('enabled',current_setting('archive_mode')='on','failed',coalesce(last_failed_time>coalesce(last_archived_time,'epoch'::timestamptz),false),'oldestPendingSeconds',(SELECT coalesce(extract(epoch FROM now()-min(modification)),0) FROM pg_ls_archive_statusdir() WHERE name LIKE '%.ready')) FROM pg_stat_archiver; COMMIT;"
   observation=command(['docker','exec','supabase-db','psql','-X','-U','supabase_admin','-d','postgres','-Atqc',pitr_sql]).splitlines()
   result['pitr']=json.loads(next(x for x in observation if x.startswith('{')))
   try:result['pitr']['backupAt']=json.loads(Path('/var/lib/festapp-pgbackrest/last-backup.json').read_text())['backup_stop']
   except (OSError,ValueError,KeyError):result['pitr']['backupAt']=None
  result['ok']=True
 except Exception:result['reason']='runtime_collection_unavailable'
 # Atomic write never follows a user-controlled destination symlink.
 fd,temp=tempfile.mkstemp(prefix='.runtime-',dir=OUTPUT.parent)
 try:
  os.fchmod(fd,0o644)
  with os.fdopen(fd,'w') as stream:json.dump(result,stream)
  os.replace(temp,OUTPUT)
 finally:
  if os.path.exists(temp):os.unlink(temp)
if __name__=='__main__':main()
