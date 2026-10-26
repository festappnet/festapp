#!/usr/bin/env python3
"""Activate numeric capacity evidence in the existing router and host collector.
Canonical source staging only; no other function source, limits or image changes.
"""
import argparse,fcntl,hashlib,importlib.util,json,os,re,subprocess,time
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--ack',choices=['collect-native-runtime-capacity-counters'],required=True);p.add_argument('--source-commit',required=True);p.add_argument('--previous-main-sha256',required=True);a=p.parse_args()
 assert re.fullmatch('[a-f0-9]{40}',a.source_commit) and re.fullmatch('[a-f0-9]{64}',a.previous_main_sha256)
 assert os.geteuid()==0 and os.uname().nodename.split('.')[0]=='festapp-supabase-rehearsal-01'
 os.umask(0o077);here=Path(__file__).resolve().parent;source_root=here.parents[2];folder=Path('/opt/festapp-supabase/docker')
 lock=(folder/'.festapp-runtime-upgrade.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 backup_lock=Path('/var/backups/festapp-supabase/.lock').open('w');fcntl.flock(backup_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 env=dict(line.split('=',1) for line in (folder/'.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
 assert env['FESTAPP_RUNTIME_DATABASE']=='festapp_rehearsal_20260909220601'
 main_path=folder/'volumes/functions/main/index.ts';previous=main_path.read_bytes()
 assert hashlib.sha256(previous).hexdigest()==a.previous_main_sha256
 spec=importlib.util.spec_from_file_location('resource_patch',here/'patch-function-resource-metrics.py');patch=importlib.util.module_from_spec(spec);spec.loader.exec_module(patch)
 candidate=patch.patch(previous.decode()).encode();assert candidate!=previous,'already instrumented; inspect existing receipt rather than replay'
 module_path=folder/'volumes/functions/_shared/runtime_resource_metrics.ts';assert not module_path.exists()
 module_source=source_root/'supabase/functions/_shared/runtime_resource_metrics.ts';assert module_source.is_file()
 evidence=Path('/var/lib/festapp-rehearsal-evidence')/('runtime-resource-metrics-'+a.source_commit[:12]);evidence.mkdir(mode=0o700,exist_ok=False)
 (evidence/'main.before.ts').write_bytes(previous)
 collector=Path('/opt/festapp-host-monitor/runtime-evidence.py');old_collector=collector.read_bytes();(evidence/'collector.before.py').write_bytes(old_collector)
 log=(evidence/'apply.log').open('wb')
 def capture(args):return subprocess.check_output(args,cwd=folder,stderr=log)
 def run(args):subprocess.run(args,cwd=folder,stdout=log,stderr=log,check=True)
 def sql(query):return capture(['docker','exec','supabase-db','psql','-X','-U','postgres','-d',env['FESTAPP_RUNTIME_DATABASE'],'-Atqv','ON_ERROR_STOP=1','-c',query]).decode().strip()
 assert sql("BEGIN READ ONLY; SELECT current_database()='festapp_rehearsal_20260909220601' AND EXISTS(SELECT 1 FROM public.organizations WHERE id=1); COMMIT;")=='t'
 def observed():
  ids=capture(['docker','compose','ps','-aq']).decode().split();assert len(ids)==13
  return {x['Name']:{'id':x['Id'],'running':x['State']['Running'],'oom':x['State']['OOMKilled'],'health':x['State'].get('Health',{}).get('Status')} for x in json.loads(capture(['docker','inspect',*ids]))}
 before=observed();unknown_before=int(sql("BEGIN READ ONLY; SELECT count(*) FROM public.email_messages WHERE workflow_state='unknown'; COMMIT;"))
 def ready():
  for _ in range(60):
   state=observed()
   if all(x['running'] and not x['oom'] and x['health'] in (None,'healthy') for x in state.values()):return state
   time.sleep(2)
  raise RuntimeError('runtime health did not recover')
 def write(path,data,mode=0o644):
  temporary=path.with_name(path.name+'.resource-stage');assert not temporary.exists()
  temporary.write_bytes(data);temporary.chmod(mode);os.replace(temporary,path)
 paused=None;changed=False;healthy=False
 try:
  paused=sql('BEGIN; SELECT paused FROM public.email_capacity FOR UPDATE; UPDATE public.email_capacity SET paused=true; COMMIT;');assert paused in ('t','f')
  for _ in range(12):
   if sql("BEGIN READ ONLY; SELECT count(*) FROM public.email_messages WHERE workflow_state IN ('sending','preparing'); COMMIT;")=='0':break
   time.sleep(5)
  else:raise RuntimeError('active email attempts prevent functions recreation')
  changed=True;write(module_path,module_source.read_bytes());write(main_path,candidate)
  run(['docker','compose','up','-d','--no-deps','--force-recreate','functions']);final=ready();healthy=True
  native=None
  for _ in range(90):
   try:
    spec=importlib.util.spec_from_file_location('observer',here.parent/'monitoring/runtime-evidence.py');observer=importlib.util.module_from_spec(spec);spec.loader.exec_module(observer)
    lines=subprocess.check_output(['docker','logs','--since','180s','--tail','20000','supabase-edge-functions'],stderr=subprocess.STDOUT).decode()
    native=observer.edge_counters(lines,time.time());break
   except (subprocess.SubprocessError,ValueError,KeyError,AssertionError):time.sleep(1)
  else:raise RuntimeError('native Edge counters unavailable')
  write(collector,(here.parent/'monitoring/runtime-evidence.py').read_bytes())
  run(['python3',str(collector)])
  runtime=json.loads(Path('/var/lib/festapp-host-monitor/runtime.json').read_text());assert runtime['ok'] and not runtime.get('resourceSampleUnavailable')
  history=Path('/var/lib/festapp-host-monitor')/('resources-'+time.strftime('%Y%m%d',time.gmtime())+'.jsonl')
  sample=json.loads(history.read_text().splitlines()[-1]);assert 'database' in sample and 'edge' in sample
  for name,state in before.items():
   if name!='/supabase-edge-functions':assert final[name]['id']==state['id'],'unexpected container recreation'
  assert int(sql("BEGIN READ ONLY; SELECT count(*) FROM public.email_messages WHERE workflow_state='unknown'; COMMIT;"))==unknown_before
  # Preserve the same instrumentation on subsequent canonical bundle installs.
  for name in ['patch-function-resource-metrics.py','install-production-function-bundle.sh']:
   target=folder/name;(evidence/(name+'.before')).write_bytes(target.read_bytes() if target.exists() else b'');write(target,(here/name).read_bytes(),0o700)
 except Exception:
  if changed:
   healthy=False
   write(main_path,previous);write(collector,old_collector)
   module_path.unlink(missing_ok=True)
   run(['docker','compose','up','-d','--no-deps','--force-recreate','functions']);ready();healthy=True
  raise RuntimeError('resource instrumentation failed; previous router restored; protected diagnostics retained') from None
 finally:
  if paused=='f' and (not changed or healthy):sql('BEGIN; UPDATE public.email_capacity SET paused=false; SELECT public.wake_email_worker(); COMMIT;')
  log.close()
 result={'source_commit':a.source_commit,'at':time.time(),'main_before_sha256':a.previous_main_sha256,'main_after_sha256':hashlib.sha256(candidate).hexdigest(),'collector_sha256':hashlib.sha256(collector.read_bytes()).hexdigest(),'only_functions_recreated':True,'all_containers_healthy':True,'original_email_pause_restored':True,'unknown_email_outcomes_unchanged':unknown_before,'new_public_endpoint':False,'new_daemon':False,'sample':sample}
 (evidence/'result.json').write_text(json.dumps(result,indent=2)+'\n');print('Native Edge and database counters recorded by the existing host monitor; other container identities preserved')
if __name__=='__main__':main()
