#!/usr/bin/env python3
"""Pinned runtime fixture only: no network, production functions or credentials."""
import argparse,hashlib,importlib.util,os,json,time,subprocess,tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--evidence',type=Path,required=True);a=p.parse_args();assert not a.evidence.exists()
os.umask(0o077);root=Path(__file__).resolve().parents[3];a.evidence.parent.mkdir(mode=0o700,parents=True,exist_ok=True);name='festapp-edge-resource-drill-'+os.urandom(6).hex();image='supabase/edge-runtime:v1.74.0@sha256:ac5a8314e0c45b0f65d091643c1d6f5293e3a38f31fd3d15186e04a9d5c91cb7'
with tempfile.TemporaryDirectory(prefix='festapp-edge-metrics-') as tmp:
 work=Path(tmp);work.chmod(0o755)
 for folder in ['main','a','b','_shared']:(work/folder).mkdir(mode=0o755)
 (work/'_shared/runtime_resource_metrics.ts').write_bytes((root/'supabase/functions/_shared/runtime_resource_metrics.ts').read_bytes())
 main='''import {sampleRuntimeResources} from "../_shared/runtime_resource_metrics.ts";
setTimeout(async()=>{try {
const responses=await Promise.all(Array.from({length:16},async(_,i)=>{const r=await fetch("http://127.0.0.1:9000/"+(i%2?"a":"b"));if(r.status!==200||await r.text()!=="fixture")throw Error("request failed");return r.status;}));
await new Promise(r=>setTimeout(r,100));const started=performance.now();const data=await sampleRuntimeResources();console.log("festapp_runtime_resource_metrics "+JSON.stringify(data));
console.log("FESTAPP_FIXTURE_RESULT "+JSON.stringify({status:"pass",responses:responses.length,samplingElapsedMs:performance.now()-started,metrics:data}));
}catch(e){console.log("FESTAPP_FIXTURE_RESULT "+JSON.stringify({status:"fail",error:String(e)}));}},1000);
Deno.serve(async(req)=>{const name=new URL(req.url).pathname.slice(1);const worker=await EdgeRuntime.userWorkers.create({servicePath:"/home/deno/functions/"+name,memoryLimitMb:64,workerTimeoutMs:60000,envVars:[]});return await worker.fetch(req)});
'''
 (work/'main/index.ts').write_text(main)
 for x in ['a','b']:(work/x/'index.ts').write_text('Deno.serve(async()=>{await new Promise(r=>setTimeout(r,40));return new Response("fixture")});')
 # Public fixture code only; unlike private recovery archives it is world-readable.
 for p in work.rglob('*'):
  p.chmod(0o755 if p.is_dir() else 0o644)
 with a.evidence.with_suffix('.log').open('xb') as log:
  def run(*args):return subprocess.run(args,stdout=log,stderr=log,check=True)
  try:
   run('docker','run','-d','--name',name,'--network','none','--memory','805306368','--pids-limit','128','--cpus','1','--cap-drop=ALL','--security-opt=no-new-privileges','--entrypoint','sh',image,'-c','sleep 600')
   actual=json.loads(subprocess.check_output(['docker','inspect',name]))[0];assert actual['HostConfig']['NetworkMode']=='none' and not actual['HostConfig']['PortBindings'] and not any(m['Type']=='bind' for m in actual['Mounts'])
   run('docker','exec',name,'mkdir','-p','/home/deno/functions')
   run('docker','cp',str(work)+ '/.',name+':/home/deno/functions')
   run('docker','exec','-d',name,'sh','-c','exec edge-runtime start --main-service /home/deno/functions/main --policy per_request --max-parallelism 1 > /tmp/fixture.log 2>&1')
   for _ in range(90):
    r=subprocess.run(['docker','exec',name,'cat','/tmp/fixture.log'],capture_output=True)
    lines=[line.partition('FESTAPP_FIXTURE_RESULT ')[2] for line in r.stdout.decode().splitlines() if 'FESTAPP_FIXTURE_RESULT ' in line]
    if lines:result=json.loads(lines[-1]);break
    time.sleep(1)
   else:raise RuntimeError('native Edge fixture did not finish')
   assert result['status']=='pass',result
   assert result['metrics']['receivedRequestsCount']==16 and result['metrics']['handledRequestsCount']==16
   assert result['metrics']['activeUserWorkersCount']==2,'per-service cap was incorrectly treated as global'
   final=json.loads(subprocess.check_output(['docker','inspect',name]))[0];assert not final['State']['OOMKilled'] and final['RestartCount']==0
   result['memory_peak_bytes']=int(subprocess.check_output(['docker','exec',name,'cat','/sys/fs/cgroup/memory.peak']))
   result['oom']=False;result['restarts']=0
   result.update({'network':'none','host_binds':False,'host_ports':False,'production_credentials':False,'production_functions':False,'max_parallelism':1,'max_parallelism_scope':'per service_path, not process-wide'})
   log.flush()
   spec=importlib.util.spec_from_file_location('observer',root/'automation/hetzner-supabase/monitoring/runtime-evidence.py');observer=importlib.util.module_from_spec(spec);spec.loader.exec_module(observer)
   output=subprocess.check_output(['docker','exec',name,'cat','/tmp/fixture.log']).decode()
   assert observer.edge_counters(output,time.time())['activeUserWorkersCount']==2
   result['native_log_parsed_by_production_collector']=True;result['script_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
   a.evidence.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
  finally:
   subprocess.run(['docker','exec',name,'cat','/tmp/fixture.log'],stdout=log,stderr=log)
   subprocess.run(['docker','rm','-f','-v',name],stdout=log,stderr=log)
