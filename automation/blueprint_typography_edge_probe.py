#!/usr/bin/env python3
"""Disposable, credential-free Edge user-worker proof on exact registered bytes.
Run blueprint_typography_probe.ts first. Never mounts the repository or contacts DB.
"""
import hashlib,json,pathlib,shutil,subprocess,tempfile,time,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/plans/evidence/blueprint-typography-20261020'
IMAGE='public.ecr.aws/supabase/edge-runtime:v1.74.2@sha256:a82676277615aee03c4f288cbbbf68dedb5ba8693073e567ab8dbfdd11ba5d45'
probe=json.loads((OUT/'engine-probe.json').read_text())
CASES=[c for c in probe['results'] if not c['features']]
FACES={f['id']:f for f in probe['fixtureFaces']}
WORKER=r'''
import {LayoutTextFace} from '../_shared/layoutTextShaper.ts';
import {fontMetrics} from '../_shared/ticketFonts.ts';
import bidiFactory from 'npm:bidi-js@1.1.0/dist/bidi.mjs';
import {prepareLayoutText} from '../_shared/layoutTextPreparation.ts';
import LineBreaker from 'npm:linebreak@1.1.0';
import {graphemeSegments} from 'npm:unicode-segmenter@0.17.3/grapheme';
import * as properties from 'npm:unicode-properties@2.0.1';
const cases=__CASES__,assets=__ASSETS__,paragraphs=__PARAGRAPHS__;
const faces=new Map();
async function run(){
 for(const c of cases){
  const asset=assets[c.fontId];let face=faces.get(asset.id);
  if(!face){const bytes=await Deno.readFile(new URL('../_shared/ticket-assets/'+asset.sha256+'.ttf',import.meta.url));
   face=await LayoutTextFace.fromTicketFont({...asset,bytes,metrics:fontMetrics(bytes)});faces.set(asset.id,face);}
  const glyphs=face.shape(c.text,{direction:c.direction,script:c.script,language:c.language});
  const normalized=glyphs.map(g=>({g:g.glyphId,cl:g.cluster,dx:g.xOffset,dy:g.yOffset,ax:g.xAdvance,ay:g.yAdvance}));
  if(JSON.stringify(normalized)!==JSON.stringify(c.oracle))throw Error('Oracle mismatch: '+c.text);
  const vector=face.vector(c.text,{direction:c.direction,script:c.script,language:c.language});
  if(vector.advance.x!==glyphs.reduce((x,g)=>x+g.xAdvance,0))throw Error('Whole-vector advance mismatch');
  if(!vector.path.length)throw Error('Whole-vector path missing');
 }
 for(const p of paragraphs){const prepared=await prepareLayoutText(faces.get(p.fontId),p.result.descriptor.request);if(JSON.stringify(prepared)!==JSON.stringify(p.result))throw Error('Full paragraph mismatch: '+p.text);}
}
Deno.serve(async()=>{
 try {
  const start=performance.now();await run();const coldMs=performance.now()-start,times=[];
  for(let i=0;i<60;i++){const start=performance.now();await run();times.push(performance.now()-start);}
  times.sort((a,b)=>a-b);
  return Response.json({status:'pass',engine:'HarfBuzz 14.6.0',cases:cases.length,paragraphs:paragraphs.length,faces:faces.size,coldBatchMs:coldMs,batchLabels:cases.length,samples:times.length,p50ms:times[29],p95ms:times[56],
   bidi:[...bidiFactory().getEmbeddingLevels('abc سلام 123').levels],graphemes:[...graphemeSegments('á😀')].map(g=>g.segment),lineBreak:new LineBreaker('a b').nextBreak().position,script:properties.getScript(0x627)});
 }catch(error){return Response.json({status:'fail',error:String(error)},{status:500});}
});
'''
MAIN='''Deno.serve(async(req)=>{try{const worker=await EdgeRuntime.userWorkers.create({servicePath:'/home/deno/functions/worker',memoryLimitMb:150,workerTimeoutMs:60000,noModuleCache:false,staticPatterns:['/home/deno/functions/_shared/ticket-assets/*.ttf'],envVars:[]});return await worker.fetch(req);}catch(e){return Response.json({error:String(e)},{status:500});}});'''
name='festapp-blueprint-text-proof-'+str(time.time_ns())
with tempfile.TemporaryDirectory(prefix='festapp-blueprint-text-proof-') as tmp:
 stage=pathlib.Path(tmp)
 for d in ['main','worker','_shared/ticket-assets']:(stage/d).mkdir(parents=True)
 (stage/'main/index.ts').write_text(MAIN)
 (stage/'worker/index.ts').write_text(WORKER.replace('__CASES__',json.dumps(CASES,ensure_ascii=False)).replace('__ASSETS__',json.dumps(FACES)).replace('__PARAGRAPHS__',json.dumps(probe['preparation'],ensure_ascii=False)))
 for filename in ['layoutTextShaper.ts','layoutTextPreparation.ts','layout-text-policy.json','ticketFonts.ts','ticketText.ts','ticketLayout.ts']:
  shutil.copyfile(ROOT/'supabase/functions/_shared'/filename,stage/'_shared'/filename)
 shutil.copyfile(ROOT/'supabase/functions/_shared/ticket-assets/font-catalog.json',stage/'_shared/ticket-assets/font-catalog.json')
 for asset in FACES.values():
  source=pathlib.Path(asset['path'])
  if hashlib.sha256(source.read_bytes()).hexdigest()!=asset['sha256']:raise RuntimeError('Font integrity mismatch')
  shutil.copyfile(source,stage/'_shared/ticket-assets'/source.name)
 stage.chmod(0o755)
 for path in stage.rglob('*'):path.chmod(0o755 if path.is_dir() else 0o644)
 try:
  subprocess.run(['docker','run','-d','--name',name,'--memory','768m','--pids-limit','128','--cap-drop=ALL','--security-opt=no-new-privileges','-p','127.0.0.1::9000','--entrypoint','sh',IMAGE,'-c','sleep 180'],check=True,capture_output=True)
  subprocess.run(['docker','exec',name,'mkdir','-p','/home/deno/functions'],check=True,capture_output=True)
  subprocess.run(['docker','cp',str(stage)+'/.',name+':/home/deno/functions'],check=True,capture_output=True)
  subprocess.run(['docker','exec','-d',name,'sh','-c','exec edge-runtime start --main-service /home/deno/functions/main > /tmp/typography.log 2>&1'],check=True,capture_output=True)
  inspect=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
  port=inspect['NetworkSettings']['Ports']['9000/tcp'][0]['HostPort']
  started=time.monotonic()
  for attempt in range(30):
   try:
    with urllib.request.urlopen('http://127.0.0.1:'+port+'/proof',timeout=45) as response: result=json.load(response)
    break
   except urllib.error.HTTPError as error:raise RuntimeError(error.read().decode()) from error
   except (ConnectionError,urllib.error.URLError):time.sleep(.2)
  else:raise RuntimeError('Edge worker did not become ready')
  result.update({'image':IMAGE,'startupAndFirstRequestMs':(time.monotonic()-started)*1000,'scriptSha256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),'shaperSha256':hashlib.sha256((ROOT/'supabase/functions/_shared/layoutTextShaper.ts').read_bytes()).hexdigest(),'productionCredentials':False,'repositoryMounted':False,'scope':'actual Edge user worker; local loopback transport; no authorization/DB/end-to-end preparation latency claim'})
  if result['status']!='pass':raise RuntimeError(str(result))
  (OUT/'edge-probe.json').write_text(json.dumps(result,indent=2)+'\n')
  print(json.dumps({k:result[k] for k in ['status','cases','faces','coldBatchMs','p50ms','p95ms','startupAndFirstRequestMs']}))
 except Exception:
  log=subprocess.run(['docker','exec',name,'tail','-12','/tmp/typography.log'],capture_output=True,text=True)
  print(log.stdout+log.stderr)
  state=json.loads(subprocess.check_output(['docker','inspect',name]))[0]['State']
  print(json.dumps(state))
  raise
 finally:
  subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
