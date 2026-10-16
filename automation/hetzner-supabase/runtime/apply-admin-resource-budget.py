#!/usr/bin/env python3
"""Apply the reviewed administrative-service budget, without touching app/DB.
Run only from a canonical-main, digest-verified staging directory on the host.
"""
import argparse,fcntl,hashlib,json,os,re,subprocess,time
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--ack',choices=['limit-admin-containers-only'],required=True);p.add_argument('--source-commit',required=True);a=p.parse_args()
 assert re.fullmatch('[a-f0-9]{40}',a.source_commit)
 assert os.geteuid()==0 and os.uname().nodename.split('.')[0]=='festapp-supabase-rehearsal-01'
 os.umask(0o077)
 folder=Path('/opt/festapp-supabase/docker')
 lock=(folder/'.festapp-runtime-upgrade.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 backup_lock=Path('/var/backups/festapp-supabase/.lock').open('w');fcntl.flock(backup_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 envpath=folder/'.env';before=envpath.read_text()
 env=dict(line.split('=',1) for line in before.splitlines() if '=' in line and not line.startswith('#'))
 assert env['FESTAPP_RUNTIME_DATABASE']=='festapp_rehearsal_20260909220601'
 previous=['docker-compose.yml','docker-compose.festapp.yml','docker-compose.database-target.yml','docker-compose.email.yml','docker-compose.pgbackrest.yml']
 assert env['COMPOSE_FILE'].split(':')==previous,'unexpected or already modified Compose configuration'
 source=Path(__file__).with_name('docker-compose.resource-budget.yml');data=source.read_bytes();limits=json.loads(data)['services']
 assert set(limits)=={'studio','meta'} and all(set(v)=={'mem_limit','cpus','pids_limit'} for v in limits.values())
 assert all(0<v['mem_limit']<=1024**3 and 0<float(v['cpus'])<=1 and 0<v['pids_limit']<=512 for v in limits.values())
 evidence=Path('/var/lib/festapp-rehearsal-evidence')/('admin-resource-budget-'+a.source_commit[:12]);evidence.mkdir(mode=0o700,exist_ok=False)
 (evidence/'runtime.env.before').write_text(before)
 def capture(args):return subprocess.check_output(args,cwd=folder,stderr=subprocess.DEVNULL)
 def observed():
  ids=capture(['docker','compose','ps','-aq']).decode().split();assert len(ids)==13
  return {c['Name']:{'id':c['Id'],'memory':c['HostConfig']['Memory'],'cpus':c['HostConfig']['NanoCpus'],'pids':c['HostConfig']['PidsLimit'],'running':c['State']['Running'],'oom':c['State']['OOMKilled'],'health':c['State'].get('Health',{}).get('Status')} for c in json.loads(capture(['docker','inspect',*ids]))}
 state_before=observed()
 identity=capture(['docker','exec','supabase-db','psql','-X','-U','postgres','-d',env['FESTAPP_RUNTIME_DATABASE'],'-Atqv','ON_ERROR_STOP=1','-c',"BEGIN READ ONLY; SELECT current_database()='festapp_rehearsal_20260909220601' AND EXISTS(SELECT 1 FROM public.organizations WHERE id=1); COMMIT;"])
 assert identity.strip()==b't'
 destination=folder/source.name;assert not destination.exists()
 destination.write_bytes(data);os.chmod(destination,0o644)
 after='\n'.join('COMPOSE_FILE='+':'.join(previous+[source.name]) if line.startswith('COMPOSE_FILE=') else line for line in before.splitlines())+'\n'
 assert after!=before
 with (evidence/'apply.log').open('wb') as log:
  def run(args):subprocess.run(args,cwd=folder,stdout=log,stderr=log,check=True)
  def healthy():
   for _ in range(60):
    state=observed()
    if all(c['running'] and not c['oom'] and c['health'] in (None,'healthy') for c in state.values()):return state
    time.sleep(2)
   raise RuntimeError('container health did not recover')
  try:
   envpath.write_text(after);os.chmod(envpath,0o600)
   run(['docker','compose','config','--quiet'])
   run(['docker','compose','up','-d','--no-deps','--force-recreate','studio','meta'])
   final=healthy()
   for name,limit in limits.items():
    actual=final['/supabase-'+name]
    assert actual['memory']==limit['mem_limit'] and actual['cpus']==int(float(limit['cpus'])*1e9) and actual['pids']==limit['pids_limit']
   for name,state in state_before.items():
    if name not in ['/supabase-studio','/supabase-meta']:assert final[name]['id']==state['id'],'unexpected other container recreation'
  except Exception:
   envpath.write_text(before);os.chmod(envpath,0o600)
   run(['docker','compose','up','-d','--no-deps','--force-recreate','studio','meta'])
   healthy()
   raise RuntimeError('admin budget failed; previous configuration restored; protected logs retained') from None
 result={'source_commit':a.source_commit,'at':time.time(),'override_sha256':hashlib.sha256(data).hexdigest(),'limits':limits,'containers':final,'only_admin_recreated':True,'host_resized':False,'critical_service_caps_changed':False}
 (evidence/'result.json').write_text(json.dumps(result,indent=2)+'\n')
 print('Administrative service budget applied; all 13 containers healthy; app/DB container identities preserved')

if __name__=='__main__':main()
