"""Public-source dependency preparation and isolated real Edge recovery reads."""
import hashlib,io,json,re,subprocess,tarfile,time,os
from pathlib import Path
import ipaddress,urllib.request,urllib.error

PREFIX='docker/volumes/functions/'
CACHE_MARKER='/root/.cache/deno/festapp-recovery-public-cache.json'

def function_sources(runtime_archive):
 files={}
 with tarfile.open(runtime_archive) as archive:
  for member in archive.getmembers():
   if not member.name.startswith(PREFIX) or member.isdir():continue
   name=member.name[len(PREFIX):]
   assert member.isfile() and not Path(name).is_absolute() and '..' not in Path(name).parts,'unsafe function source'
   if Path(name).suffix not in {'.ts','.js','.json','.ttf','.lock'}:continue
   assert not re.search(r'(^|/)(\.env|credentials|secrets?)(\.|/|$)',name,re.I),'private file in public function sources'
   assert name not in files and member.size<16*1024*1024
   files[name]=archive.extractfile(member).read()
 assert 'main/index.ts' in files and 'email-confirmation-status/index.ts' in files
 return files

def source_digest(files):
 return hashlib.sha256(json.dumps({n:hashlib.sha256(b).hexdigest() for n,b in sorted(files.items())},sort_keys=True).encode()).hexdigest()

def public_tar(files):
 stream=io.BytesIO()
 with tarfile.open(fileobj=stream,mode='w') as archive:
  for name,data in sorted(files.items()):
   member=tarfile.TarInfo(name);member.mode=0o644;member.size=len(data);archive.addfile(member,io.BytesIO(data))
 return stream.getvalue()

def prepare_cache(source_tar,evidence):
 # This public-only downloader must never allocate memory on the production host.
 assert re.fullmatch(r'lima-festapp-security-recovery-\d{8}',os.uname().nodename),'run only inside the dedicated local recovery VM'
 assert not evidence.exists()
 with tarfile.open(source_tar) as archive:
  files={}
  for m in archive.getmembers():
   assert m.isfile() and not Path(m.name).is_absolute() and '..' not in Path(m.name).parts and m.size<16*1024*1024
   assert Path(m.name).suffix in {'.ts','.js','.json','.ttf','.lock'} and not re.search(r'(^|/)(\.env|credentials|secrets?)(\.|/|$)',m.name,re.I)
   assert m.name not in files;files[m.name]=archive.extractfile(m).read()
 assert 'main/index.ts' in files and 'email-confirmation-status/index.ts' in files
 digest=source_digest(files);suffix=os.urandom(6).hex();name='festapp-edge-public-cache-'+suffix;volume='festapp-recovery-edge-cache-'+suffix
 pins=json.loads((Path(__file__).resolve().parents[1]/'runtime/pins.json').read_text());image=pins['supabase']['images']['edgeRuntime'];assert '@sha256:' in image
 os.umask(0o077);started=time.monotonic();complete=False
 with evidence.with_suffix('.log').open('xb') as log:
  def run(args,**kw):return subprocess.run(args,check=True,stdout=log,stderr=log,**kw)
  def capture(args):return subprocess.check_output(args,stderr=log)
  run(['docker','volume','create','--label','festapp.recovery-public-edge-cache='+digest,volume])
  try:
   run(['docker','run','-d','--name',name,'--network','bridge','--memory','1073741824','--cpus','1','--pids-limit','128','--cap-drop=ALL','--security-opt=no-new-privileges','--mount','type=volume,src='+volume+',dst=/root/.cache/deno','-e','DENO_DIR=/root/.cache/deno','-e','JWT_SECRET=isolated-edge-cache-fixture-only-0000000000','-e','VERIFY_JWT=true','-e','SUPABASE_URL=http://127.0.0.1:1','-e','SUPABASE_SERVICE_ROLE_KEY=fixture-only','--entrypoint','sh',image,'-c','sleep 3600'])
   actual=json.loads(capture(['docker','inspect',name]))[0]
   assert actual['HostConfig']['NetworkMode']=='bridge' and not actual['HostConfig']['PortBindings'] and not any(m['Type']=='bind' for m in actual['Mounts'])
   run(['docker','exec',name,'mkdir','-p','/home/deno/functions'])
   run(['docker','exec','-i',name,'tar','-xf','-','-C','/home/deno/functions'],input=public_tar(files))
   entries=sorted(n for n in files if re.fullmatch(r'[^/]+/index.ts',n))
   for entry in entries:
    run(['docker','exec','-w','/home/deno/functions',name,'edge-runtime','bundle','--entrypoint','/home/deno/functions/'+entry,'--output','/tmp/recovery.eszip','--checksum','sha256','--timeout','90'])
   # The native runtime also resolves npm type metadata at worker startup.
   # Compile-only eszip graphs do not guarantee an offline worker can boot.
   run(['docker','exec','-d',name,'sh','-c','exec edge-runtime start --main-service /home/deno/functions/main > /proc/1/fd/1 2>/proc/1/fd/2'])
   current=json.loads(capture(['docker','inspect',name]))[0]
   address=current['NetworkSettings']['Networks']['bridge']['IPAddress'];assert ipaddress.ip_address(address).is_private
   opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
   for _ in range(90):
    request=urllib.request.Request('http://'+address+':9000/email-confirmation-status',data=json.dumps({'capability':'0'*64}).encode(),headers={'Content-Type':'application/json'})
    try:
     with opener.open(request,timeout=10) as response:status=response.status;body=response.read()
    except urllib.error.HTTPError as error:status=error.code;body=error.read()
    except (urllib.error.URLError,TimeoutError):time.sleep(.5);continue
    if status==503 and json.loads(body)=={'state':'unavailable'}:break
    time.sleep(.5)
   else:raise RuntimeError('public status worker did not load its runtime-only dependency metadata')
   marker={'version':1,'public_source_sha256':digest,'entrypoints':entries,'runtime_type_metadata_warmed':True,'complete':True}
   run(['docker','exec','-i',name,'sh','-c','cat > '+CACHE_MARKER],input=json.dumps(marker).encode())
   state=json.loads(capture(['docker','inspect',name]))[0];assert not state['State']['OOMKilled'] and state['RestartCount']==0
   result={**marker,'cache_volume':volume,'image':image,'public_sources_only':True,'production_credentials_or_data_loaded':False,'javascript_handlers_executed':True,'executed_handler_scope':'read-only confirmation status, unreachable fixture backend only','native_bundler_used':True,'seconds':round(time.monotonic()-started,2)}
   evidence.write_text(json.dumps(result,indent=2)+'\n');complete=True;print(json.dumps(result),flush=True)
  finally:
   run(['docker','rm','-f','-v',name])
   if not complete:run(['docker','volume','rm',volume])

def edge_reads(database_container,runtime_archive,cache_volume,start,run,capture,service,anon,jwt_secret):
 assert re.fullmatch(r'festapp-recovery-edge-cache-[a-f0-9]{12}',cache_volume)
 files=function_sources(runtime_archive);digest=source_digest(files)
 volume=json.loads(capture(['docker','volume','inspect',cache_volume]))[0]
 assert volume.get('Labels',{}).get('festapp.recovery-public-edge-cache')==digest,'cache does not match backed-up public sources'
 edge=start('edgeRuntime',{'JWT_SECRET':jwt_secret,'VERIFY_JWT':'true','SUPABASE_URL':'http://127.0.0.1:8000','SUPABASE_ANON_KEY':anon,'SUPABASE_SERVICE_ROLE_KEY':service,'DENO_DIR':'/root/.cache/deno'},prepare=True,cache_volume=cache_volume)
 marker=json.loads(capture(['docker','exec',edge,'cat',CACHE_MARKER]));assert marker['complete'] and marker.get('runtime_type_metadata_warmed') and marker['public_source_sha256']==digest
 run(['docker','exec',edge,'mkdir','-p','/home/deno/functions'])
 run(['docker','exec','-i',edge,'tar','-xf','-','-C','/home/deno/functions'],input=public_tar(files))
 run(['docker','exec','-d',edge,'sh','-c','exec edge-runtime start --main-service /home/deno/functions/main > /proc/1/fd/1 2>/proc/1/fd/2'])
 parts=service.split('.');parts[2]=('A' if parts[2][0]!='A' else 'B')+parts[2][1:];invalid_token='.'.join(parts)
 def request(path,method='GET',body=None,invalid_jwt=False):
  args=['docker','exec',database_container,'curl','--silent','--max-time','10','-w','\n%{http_code}','-X',method,'-H','apikey: '+anon]
  if invalid_jwt:args+=['-H','Authorization: Bearer '+invalid_token]
  if body is not None:args+=['-H','Content-Type: application/json','--data',json.dumps(body)]
  out=capture(args+['http://127.0.0.1:18081/functions/v1/'+path]);payload,status=out.rsplit(b'\n',1);return int(status),payload
 for _ in range(90):
  try:
   status,payload=request('download-ticket',invalid_jwt=True)
   if status==401 and json.loads(payload).get('msg')=='Invalid JWT':break
  except (subprocess.CalledProcessError,ValueError):pass
  time.sleep(.5)
 else:raise RuntimeError('restored actual Edge router did not become ready')
 status,payload=request('email-confirmation-status','POST',{'capability':'0'*64})
 assert status==403 and json.loads(payload)=={'state':'unavailable'},'actual status worker did not read the restored database safely'
 state=json.loads(capture(['docker','inspect',edge]))[0];assert state['State']['Running'] and not state['State']['OOMKilled'] and state['RestartCount']==0
 return {'actual_backed_up_router_and_worker':True,'public_source_sha256':digest,'dependency_cache_matches_sources':True,'cached_entrypoints':len(marker['entrypoints']),'offline_network_none_runtime':True,'fixture_credentials_only':True,'actual_router_jwt_gate_denied_wrong_signature':True,'actual_confirmation_status_worker_read_restored_db':True,'provider_requests_or_emails_sent':False,'oom':False,'restarts':0}

if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser();p.add_argument('--public-source-tar',type=Path,required=True);p.add_argument('--evidence',type=Path,required=True);a=p.parse_args();prepare_cache(a.public_source_tar,a.evidence)
