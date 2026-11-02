#!/usr/bin/env python3
from pathlib import Path
import subprocess, tempfile, json, time, shutil, hashlib, base64
import argparse
parser=argparse.ArgumentParser(description='Synthetic offline Edge v1.74.0 preview comparison; no production access')
parser.add_argument('--evidence',type=Path,required=True)
parser.add_argument('--baseline',required=True,help='Frozen pre-implementation Git SHA')
args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
work=args.evidence.resolve();work.mkdir(parents=True,exist_ok=False)
npm_cache=Path(json.loads(subprocess.check_output(['deno','info','--json']))['npmCache'])
subprocess.run(['deno','bundle','--frozen','--lock='+str(root/'supabase/functions/deno.lock'),'--platform','deno',str(root/'automation/tickets/preview-runtime-canary.ts'),'-o',str(work/'current.js')],cwd=root,stdout=subprocess.DEVNULL,stderr=(work/'current-bundle.log').open('w'),check=True)
# Frozen baseline source, no environment files or credentials.
base=work/'baseline-source';base.mkdir(exist_ok=True)
archive=subprocess.Popen(['git','archive',args.baseline,'supabase/functions'],cwd=root,stdout=subprocess.PIPE)
subprocess.run(['tar','-xf','-','-C',str(base)],stdin=archive.stdout,check=True);archive.wait()
entry=(root/'automation/tickets/preview-runtime-canary.ts').read_text().replace("../../supabase/functions/",str(base/'supabase/functions')+'/')
(work/'baseline.ts').write_text(entry)
subprocess.run(['deno','bundle','--frozen','--lock='+str(root/'supabase/functions/deno.lock'),'--platform','deno',str(work/'baseline.ts'),'-o',str(work/'baseline.js')],cwd=root,stdout=subprocess.DEVNULL,stderr=(work/'baseline-bundle.log').open('w'),check=True)
# Deno's JS bundler does not carry npm WASM files. Embed the exact pinned
# HarfBuzz bytes, preserving the real engine and every handler dependency.
wasm=(npm_cache/'registry.npmjs.org/harfbuzzjs/1.6.3/dist/harfbuzz.wasm').read_bytes()
for js in [work/'baseline.js',work/'current.js']:
 source='import {Buffer} from "node:buffer"; import process from "node:process"; var global=globalThis; global.Buffer=Buffer; global.process=process;\n'+js.read_text()
 # Only the frozen historical baseline needs a compatibility rewrite. Never
 # patch current dependencies here: it concealed the production Save failure.
 if js.name=='baseline.js':
  trie=(npm_cache/'registry.npmjs.org/unicode-properties/2.0.1/data.trie').read_bytes()
  source=source.replace('readFileSync(new URL("./data.trie", import.meta.url))','Uint8Array.from(atob('+json.dumps(base64.b64encode(trie).decode())+'),c=>c.charCodeAt(0))')
 source=source.replace('harfbuzz_default()', 'harfbuzz_default({wasmBinary:Uint8Array.from(atob('+json.dumps(base64.b64encode(wasm).decode())+'),c=>c.charCodeAt(0))})')
 js.write_text(source)
for flavor,js in [('before',work/'baseline.js'),('after',work/'current.js')]:
 for i in range(3):
  d=work/f'{flavor}{i}';d.mkdir(exist_ok=True);shutil.copy(js,d/'index.js')
  shutil.copytree(root/'supabase/functions/_shared/ticket-assets',d/'ticket-assets',dirs_exist_ok=True)
main=work/'main';main.mkdir(exist_ok=True)
(main/'index.ts').write_text('''
const loaded=new Set();
/*BUNDLES*/
const readCpu=async()=>Number((await Deno.readTextFile('/sys/fs/cgroup/cpu.stat')).match(/usage_usec (\\d+)/)[1]);
Deno.serve(async(req)=>{const name=new URL(req.url).pathname.slice(1);const worker=await EdgeRuntime.userWorkers.create({servicePath:'/home/deno/functions/'+name,...(loaded.has(name)?{}:{maybeEszip:bundles[name.startsWith('before')?'before':'after'],maybeEntrypoint:'file:///home/deno/functions/'+name.replace(/[12]$/,'0')+'/index.js'}),memoryLimitMb:256,workerTimeoutMs:60000,cpuTimeSoftLimitMs:20000,cpuTimeHardLimitMs:30000,staticPatterns:['/home/deno/functions/'+name+'/ticket-assets/**/*'],envVars:[]});loaded.add(name);return worker.fetch(req)});
setTimeout(async()=>{try{
 const result={};
 for(const flavor of ['before','after']){
  const values=[];
  for(let i=0;i<23;i++){
   const path=flavor+(i<3?i:2);const cpu=await readCpu(),start=performance.now();
   const response=await fetch('http://127.0.0.1:9000/'+path,{method:'POST',headers:{Authorization:'Bearer synthetic'},body:JSON.stringify({occasionId:7,mode:'resolve',type:'named',fontProtocol:2,resourceProtocol:3})});
   const bytes=await response.arrayBuffer();
   values.push({status:response.status,bytes:bytes.byteLength,cpuMs:((await readCpu())-cpu)/1000,wallMs:performance.now()-start,resources:Number(response.headers.get('x-canary-resource-reads'))});
   if(response.status!==200)throw Error(new TextDecoder().decode(bytes));
  }
  result[flavor]=values;
 }
 result.metrics=await EdgeRuntime.getRuntimeMetrics();
 console.log('TICKET_CANARY_RESULT '+JSON.stringify(result));
}catch(e){console.log('TICKET_CANARY_ERROR '+String(e));}},1000);
''')
name='festapp-ticket-preview-'+hashlib.sha256(str(work).encode()).hexdigest()[:12]
image='supabase/edge-runtime:v1.74.0@sha256:2781daf92394db91f7e94129cc3d04ec474ad16a8fe64b3fbeef6e7d557ab120'
log=work/'docker.log'
try:
 subprocess.run(['docker','run','-d','--name',name,'--network','bridge','--memory','1073741824','--pids-limit','128','--cpus','1','--cap-drop=ALL','--security-opt=no-new-privileges','-e','DENO_DIR=/tmp/deno-cache','--entrypoint','sh',image,'-c','sleep 600'],check=True,stdout=subprocess.DEVNULL)
 subprocess.run(['docker','exec',name,'mkdir','-p','/home/deno/functions'],check=True)
 for d in [main,*[work/f'{f}{i}' for f in ['before','after'] for i in range(3)]]:
  subprocess.run(['docker','cp',str(d),name+':/home/deno/functions/'],check=True,stdout=subprocess.DEVNULL)
 for flavor in ['before','after']:
  subprocess.run(['docker','exec','-u','root',name,'edge-runtime','bundle','--entrypoint','/home/deno/functions/'+flavor+'0/index.js','--output','/tmp/'+flavor+'0.eszip','--static','/home/deno/functions/'+flavor+'0/ticket-assets/**/*'],check=True,stdout=subprocess.DEVNULL,stderr=(work/(flavor+'-edge-bundle.log')).open('w'))
  for i in [1,2]: subprocess.run(['docker','exec',name,'cp','/tmp/'+flavor+'0.eszip','/tmp/'+flavor+str(i)+'.eszip'],check=True)
 bundles={}
 for flavor in ['before','after']:
  target=work/(flavor+'.eszip')
  subprocess.run(['docker','cp',name+':/tmp/'+flavor+'0.eszip',str(target)],check=True,stdout=subprocess.DEVNULL)
  bundles[flavor]=base64.b64encode(target.read_bytes()).decode()
 source=(main/'index.ts').read_text().replace('/*BUNDLES*/','const bundles=Object.fromEntries(Object.entries('+json.dumps(bundles)+').map(([k,v])=>[k,Uint8Array.from(atob(v),c=>c.charCodeAt(0))]));')
 (main/'index.ts').write_text(source)
 subprocess.run(['docker','cp',str(main/'index.ts'),name+':/home/deno/functions/main/index.ts'],check=True,stdout=subprocess.DEVNULL)
 subprocess.run(['docker','exec',name,'chmod','-R','a+rX','/tmp/deno-cache'],check=True)
 subprocess.run(['docker','network','disconnect','bridge',name],check=True)
 subprocess.run(['docker','exec','-d',name,'sh','-c','edge-runtime start --main-service /home/deno/functions/main --policy per_worker --max-parallelism 1 > /tmp/canary.log 2>&1'],check=True)
 for _ in range(180):
  out=subprocess.check_output(['docker','exec',name,'cat','/tmp/canary.log']).decode();log.write_text(out)
  if 'TICKET_CANARY_RESULT ' in out:
   result=json.loads(out.split('TICKET_CANARY_RESULT ')[-1].splitlines()[0]);result['evidence']={'baseline':args.baseline,'image':image,'scriptSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'sourceSha256':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in ['supabase/functions/preview-ticket-layout/handler.ts','supabase/functions/_shared/ticketFonts.ts','supabase/functions/_shared/ticketFontStorage.ts','supabase/functions/_shared/ticket-assets/preview-manifest.json']},'networkDuringWorkload':False,'productionCredentials':False,'cpuLimitsMs':{'soft':20000,'hard':30000},'cpuMeasurement':'container cgroup usage_usec including router, worker initialization and synthetic response consumption'};assert all(v['resources']==0 and v['status']==200 for v in result['after']);assert result['metrics']['activeUserWorkersCount']==6 and result['metrics']['handledRequestsCount']==46;(work/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:{'cold':v[:3],'warmMedianCpuMs':sorted(x['cpuMs'] for x in v[3:])[10],'warmMedianWallMs':sorted(x['wallMs'] for x in v[3:])[10],'bytes':v[-1]['bytes'],'resources':v[-1]['resources']} for k,v in result.items() if isinstance(v,list)}));break
  if 'TICKET_CANARY_ERROR ' in out:raise RuntimeError(out[-5000:])
  time.sleep(1)
 else:raise RuntimeError('Runtime timeout: '+out[-3000:])
finally:
 subprocess.run(['docker','rm','-f','-v',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
