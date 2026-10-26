#!/usr/bin/env python3
"""Fixed root-only observations for the EXISTING host monitoring timer.
Never serializes Docker env, DB query text or backup credentials.
"""
import datetime,json,os,re,stat,subprocess,tempfile,time
from pathlib import Path
COMPOSE=Path('/opt/festapp-supabase/docker')
OUTPUT=Path('/var/lib/festapp-host-monitor/runtime.json')

def resource_sample(containers, proc=Path('/proc'), cgroups=Path('/sys/fs/cgroup')):
 """Read cgroup v2 counters without starting another docker stats process.
 Working set excludes inactive file cache; memory.current still includes it.
 CPU is a cumulative counter, so consumers must compare consecutive samples.
 """
 memory={line.split(':')[0]:int(line.split()[1])*1024 for line in (proc/'meminfo').read_text().splitlines() if line.startswith(('MemTotal:','MemAvailable:','SwapTotal:'))}
 result={'at':int(time.time()),'host':memory,'containers':[]}
 for container in containers:
  pid=container['State'].get('Pid',0)
  if not pid:continue
  try:
   relative=next(line[3:] for line in (proc/str(pid)/'cgroup').read_text().splitlines() if line.startswith('0::'))
   group=(cgroups/relative.lstrip('/')).resolve()
   assert group.is_relative_to(cgroups.resolve())
   values=dict(line.split() for line in (group/'memory.stat').read_text().splitlines())
   current=int((group/'memory.current').read_text())
   cpu=dict(line.split() for line in (group/'cpu.stat').read_text().splitlines())
   result['containers'].append({'name':container['Name'],'memory_bytes':current,'working_set_bytes':max(0,current-int(values.get('inactive_file',0))),'cpu_usage_usec':int(cpu['usage_usec']),'pids':int((group/'pids.current').read_text())})
  except (OSError,ValueError,KeyError,StopIteration,AssertionError):
   result['containers'].append({'name':container['Name'],'unavailable':True})
 return result

def record_resources(sample, folder):
 # Seven daily bounded files, using the existing timer. No credentials or payloads.
 day=datetime.datetime.fromtimestamp(sample['at'],datetime.timezone.utc).strftime('%Y%m%d')
 path=folder/('resources-'+day+'.jsonl')
 fd=os.open(path,os.O_WRONLY|os.O_APPEND|os.O_CREAT|os.O_NOFOLLOW,0o600)
 try:
  info=os.fstat(fd)
  assert stat.S_ISREG(info.st_mode) and info.st_uid==os.geteuid() and info.st_nlink==1
  os.fchmod(fd,0o600)
  # Bound accidental repeated manual invocations, independently of retention.
  if info.st_size<8*1024*1024:os.write(fd,(json.dumps(sample,separators=(',',':'))+'\n').encode())
 finally:os.close(fd)
 cutoff=sample['at']-7*86400
 for old in folder.glob('resources-????????.jsonl'):
  try:
   stamp=datetime.datetime.strptime(old.name[10:18],'%Y%m%d').replace(tzinfo=datetime.timezone.utc).timestamp()
   if stamp<cutoff:old.unlink()
  except (ValueError,OSError):pass

def command(args):
 return subprocess.check_output(args,cwd=COMPOSE,stderr=subprocess.STDOUT if args[:2]==['docker','logs'] else subprocess.DEVNULL,timeout=8).decode()
def latest(pattern):
 dates=[]
 for path in Path('/var/lib/festapp-rehearsal-evidence').glob(pattern):
  try:
   value=json.loads(path.read_text())
   if value.get('off_host_verified') is True:dates.append(datetime.datetime.fromisoformat(value['uploaded_at'].replace('Z','+00:00')).timestamp())
  except (OSError,ValueError,KeyError):pass
 return max(dates,default=None)
def edge_counters(text, now):
 observations=[]
 for line in text.splitlines():
  match=re.fullmatch(r'(?:\[Info\] )?festapp_runtime_resource_metrics (\{.*\})',line.strip())
  if match:
   try:observations.append(json.loads(match[1]))
   except ValueError:pass
 assert observations,'native counters unavailable'
 data=max(observations,key=lambda x:x.get('at',-1) if type(x.get('at')) is int else -1)
 fields=('version','at','activeUserWorkersCount','retiredUserWorkersCount','receivedRequestsCount','handledRequestsCount')
 assert all(type(data[k]) is int and data[k]>=0 for k in fields)
 assert data['version']==1 and 0<=now*1000-data['at']<=180000,'stale or future Edge counters'
 return {k:data[k] for k in fields}

def main():
 assert os.geteuid()==0 and os.uname().nodename.split('.')[0]=='festapp-supabase-rehearsal-01'
 env=dict(line.split('=',1) for line in (COMPOSE/'.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
 assert env.get('FESTAPP_RUNTIME_DATABASE')=='festapp_rehearsal_20260909220601'
 result={'at':time.time()*1000,'ok':False};sample=None
 try:
  ids=command(['docker','compose','ps','-aq']).split()
  assert ids
  containers=json.loads(command(['docker','inspect',*ids]))
  result['containers']=[{'name':c['Name'],'running':c['State']['Running'],'oom':c['State']['OOMKilled'],'restarts':c['RestartCount']} for c in containers]
  try:
   sample=resource_sample(containers)
   result['resourceSampleAt']=sample['at']
   try:
    sample['edge']=edge_counters(command(['docker','logs','--since','180s','--tail','20000','supabase-edge-functions']),time.time())
   except (subprocess.SubprocessError,OSError,ValueError,KeyError,AssertionError):sample['edge_unavailable']=True
  except (OSError,ValueError,AssertionError):result['resourceSampleUnavailable']=True
  # No customer rows, SQL text, connection addresses or capabilities.
  sql="BEGIN READ ONLY; SELECT json_build_object('connections',count(*) FILTER(WHERE backend_type='client backend'),'active',count(*) FILTER(WHERE backend_type='client backend' AND state='active'),'idle_in_transaction',count(*) FILTER(WHERE state LIKE 'idle in transaction%'),'long_transactions',count(*) FILTER(WHERE xact_start<now()-interval '15 minutes'),'max_connections',current_setting('max_connections')::int,'reserved_connections',current_setting('superuser_reserved_connections')::int+current_setting('reserved_connections')::int) FROM pg_stat_activity WHERE pid<>pg_backend_pid(); COMMIT;"
  value=command(['docker','exec','supabase-db','psql','-X','-U','postgres','-d','festapp_rehearsal_20260909220601','-Atqc',sql]).splitlines()
  database=json.loads(next(x for x in value if x.startswith('{')))
  assert set(database)=={'connections','active','idle_in_transaction','long_transactions','max_connections','reserved_connections'}
  assert all(type(v) is int and v>=0 for v in database.values())
  result['longTransactions']=database['long_transactions']
  if sample is not None:sample['database']=database
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
 if sample is not None:
  try:record_resources(sample,OUTPUT.parent)
  except (OSError,ValueError,AssertionError):result['resourceSampleUnavailable']=True
 # Atomic write never follows a user-controlled destination symlink.
 fd,temp=tempfile.mkstemp(prefix='.runtime-',dir=OUTPUT.parent)
 try:
  os.fchmod(fd,0o644)
  with os.fdopen(fd,'w') as stream:json.dump(result,stream)
  os.replace(temp,OUTPUT)
 finally:
  if os.path.exists(temp):os.unlink(temp)
if __name__=='__main__':main()
