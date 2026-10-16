"""Read-only HTTP checks on a task-owned, restored network-none database.
Never load runtime.env or integration secrets from the backup. Fixtures are
restricted to a private loopback namespace and are removed by this module.
"""
import base64,hashlib,hmac,json,re,subprocess,tarfile,time
from pathlib import Path
from urllib.parse import quote

def storage_metadata(objects, members, rebuild=False):
 """Preserve Storage's real xattrs, or explicitly recover old ones from DB.
 Never apply privileged namespaces, guess MIME/cache values or expose names.
 """
 allowed={'user.supabase.content-type','user.supabase.cache-control','user.supabase.etag'}
 records={}
 for name,member in members.items():
  assert not Path(name).is_absolute() and '..' not in Path(name).parts
  attrs={key.removeprefix('SCHILY.xattr.'):value for key,value in member.pax_headers.items() if key.removeprefix('SCHILY.xattr.') in allowed}
  if attrs:records[name]=attrs
 rebuilt=0
 for obj in objects:
  key='stub/stub/'+obj['bucket']+'/'+obj['name'];version=obj.get('version')
  candidates=[key+'/'+version,key+'-$v-'+version] if version else [key]
  found=next(name for name in candidates if name in members)
  attrs=records.setdefault(found,{})
  for attr,field in [('user.supabase.content-type','mimetype'),('user.supabase.cache-control','cacheControl')]:
   if attr in attrs:continue
   assert rebuild,'Storage archive lacks required xattrs; explicit DB-metadata recovery or a corrected backup is required'
   value=obj['metadata'].get(field);assert isinstance(value,str) and value,'required Storage DB metadata is missing'
   attrs[attr]=value;rebuilt+=1
 return records,rebuilt

def application_reads(database_container, pins, storage_archive, log, admin_resources=False, rebuild_metadata=False, gateway_archive=None):
 assert re.fullmatch(r'festapp-local-restore-[a-f0-9]{16}',database_container)
 def run(args,**kwargs):return subprocess.run(args,check=True,stdout=log,stderr=log,**kwargs)
 def capture(args):return subprocess.check_output(args,stderr=log)
 def sql(query):return capture(['docker','exec',database_container,'psql','-X','-U','supabase_admin','-d','isolated_restore','-Atqv','ON_ERROR_STOP=1','-c',query])
 actual=json.loads(capture(['docker','inspect',database_container]))[0]
 assert actual['HostConfig']['NetworkMode']=='none' and not actual['HostConfig']['PortBindings']
 assert not any(m['Type']=='bind' for m in actual['Mounts'])
 # Changes are allowed ONLY after Docker's actual clone isolation is proven.
 paths=json.loads(sql("SELECT json_build_object('data',current_setting('data_directory'),'config',current_setting('config_file'),'hba',current_setting('hba_file'));"))
 assert all(re.fullmatch(r'/[A-Za-z0-9_./-]+',value) for value in paths.values())
 # Trust only this private loopback and this clone role. No published port.
 run(['docker','exec','-u','root',database_container,'sh','-c',
  'p="$1"; t="${p}.restore-test"; { printf "host all supabase_admin 127.0.0.1/32 trust\\n"; cat "$p"; } > "$t"; cat "$t" > "$p"; rm "$t"','sh',paths['hba']])
 options='-c config_file='+paths['config']+' -c hba_file='+paths['hba']+' -c shared_preload_libraries= -c session_preload_libraries= -c local_preload_libraries= -c archive_mode=off -c autovacuum=off -c max_logical_replication_workers=0 -c listen_addresses=127.0.0.1 -c ssl=off'
 run(['docker','exec','-u','postgres',database_container,'pg_ctl','-D',paths['data'],'-m','fast','-w','-o',options,'restart'])
 disabled=sql("SELECT current_setting('shared_preload_libraries')='' AND current_setting('archive_mode')='off' AND current_setting('listen_addresses')='127.0.0.1' AND current_setting('max_logical_replication_workers')='0';").strip()
 assert disabled==b't'
 secret='isolated-recovery-fixture-only-00000000000000000000'
 def jwt(role):
  def enc(value):return base64.urlsafe_b64encode(json.dumps(value,separators=(',',':')).encode()).rstrip(b'=')
  body=enc({'alg':'HS256','typ':'JWT'})+b'.'+enc({'role':role,'iss':'supabase','iat':int(time.time()),'exp':int(time.time())+3600})
  return (body+b'.'+base64.urlsafe_b64encode(hmac.new(secret.encode(),body,hashlib.sha256).digest()).rstrip(b'=')).decode()
 service=jwt('service_role');anon=jwt('anon')
 uri='postgresql://supabase_admin@127.0.0.1:5432/isolated_restore?options=-c%20session_preload_libraries%3D%20-c%20local_preload_libraries%3D'
 names=[]
 def start(kind,environment,limits=None,prepare=False):
  image=pins['supabase']['images'][kind];assert '@sha256:' in image
  name=database_container+'-'+kind;names.append(name)
  args=['docker','run','-d','--name',name,'--network','container:'+database_container,'--cap-drop=ALL','--security-opt=no-new-privileges']
  # The pinned Caddy binary has a file capability; exec fails EPERM if its
  # bounding set omits NET_BIND_SERVICE, even with a high-port test listener.
  if kind=='caddy':args+=['--cap-add=NET_BIND_SERVICE']
  if limits:args+=['--memory',str(limits['mem_limit']),'--cpus',limits['cpus'],'--pids-limit',str(limits['pids_limit'])]
  for key,value in environment.items():args+=['-e',key+'='+value]
  if prepare:args+=['--entrypoint','sh']
  run(args+[image]+(['-c','sleep 7200'] if prepare else []))
  info=json.loads(capture(['docker','inspect',name]))[0]
  assert info['HostConfig']['NetworkMode'] in ['container:'+actual['Id'],'container:'+database_container]
  assert not info['HostConfig']['PortBindings'] and not any(m['Type']=='bind' for m in info['Mounts'])
  if kind=='caddy':assert info['HostConfig']['CapAdd'] in [['NET_BIND_SERVICE'],['CAP_NET_BIND_SERVICE']]
  if limits:
   assert info['HostConfig']['Memory']==limits['mem_limit'] and info['HostConfig']['NanoCpus']==int(float(limits['cpus'])*1e9) and info['HostConfig']['PidsLimit']==limits['pids_limit']
  return name
 def http(port,path,token=None):
  args=['docker','exec',database_container,'curl','--fail','--silent','--max-time','5']
  if token:args+=['-H','Authorization: Bearer '+token]
  return capture(args+['http://127.0.0.1:'+str(port)+path])
 def wait(port,path):
  for _ in range(90):
   try:return http(port,path)
   except subprocess.CalledProcessError:time.sleep(.5)
  raise RuntimeError('isolated service did not become healthy')
 try:
  start('rest',{'PGRST_DB_URI':uri,'PGRST_DB_ANON_ROLE':'anon','PGRST_DB_SCHEMAS':'public','PGRST_DB_CONFIG':'false','PGRST_JWT_SECRET':secret,'PGRST_SERVER_HOST':'127.0.0.1'})
  start('auth',{'GOTRUE_API_HOST':'127.0.0.1','GOTRUE_API_PORT':'9999','API_EXTERNAL_URL':'http://127.0.0.1:9999','GOTRUE_SITE_URL':'http://127.0.0.1','GOTRUE_DB_DRIVER':'postgres','GOTRUE_DB_DATABASE_URL':uri,'GOTRUE_JWT_SECRET':secret,'GOTRUE_JWT_ADMIN_ROLES':'service_role','GOTRUE_JWT_AUD':'authenticated','GOTRUE_JWT_DEFAULT_GROUP_NAME':'authenticated','GOTRUE_DISABLE_SIGNUP':'true','GOTRUE_EXTERNAL_EMAIL_ENABLED':'true','GOTRUE_MAILER_AUTOCONFIRM':'false'})
  storage=start('storage',{'DATABASE_URL':uri,'ANON_KEY':anon,'SERVICE_KEY':service,'POSTGREST_URL':'http://127.0.0.1:3000','AUTH_JWT_SECRET':secret,'STORAGE_BACKEND':'file','FILE_STORAGE_BACKEND_PATH':'/var/lib/storage','GLOBAL_S3_BUCKET':'stub','TENANT_ID':'stub','REGION':'stub','ENABLE_IMAGE_TRANSFORMATION':'false','FILE_SIZE_LIMIT':'52428800'},prepare=True)
  # Stream the private host archive: docker cp can preserve a workstation UID
  # that a cap-dropped root process cannot read. Never hide tar failure behind rm.
  with storage_archive.open('rb') as stream:
   run(['docker','exec','-i','-u','root',storage,'sh','-c','mkdir -p /var/lib/storage && tar -xof - -C /var/lib/storage'],stdin=stream)
  objects=json.loads(sql("SELECT json_agg(json_build_object('bucket',bucket_id,'name',name,'version',version,'metadata',metadata)) FROM storage.objects;"))
  with tarfile.open(storage_archive) as archive:
   members={str(Path(x.name)):x for x in archive.getmembers() if x.isfile()}
   attributes,rebuilt=storage_metadata(objects,members,rebuild_metadata)
  # BusyBox tar does not restore GNU/PAX xattrs. Use the exact Storage image's
  # existing fs-xattr library; values are data on stdin, never executable code.
  program="const x=require('fs-xattr'),fs=require('fs'),path=require('path');(async()=>{const records=JSON.parse(fs.readFileSync(0,'utf8'));for(const [name,attrs] of Object.entries(records)){const p=path.resolve('/var/lib/storage',name);if(!p.startsWith('/var/lib/storage/'))throw Error('path');for(const [k,v] of Object.entries(attrs)){if(!['user.supabase.content-type','user.supabase.cache-control','user.supabase.etag'].includes(k))throw Error('attribute');await x.set(p,k,v);}}})().catch(e=>{console.error(JSON.stringify({operation:'restore-storage-xattr',code:e.code||e.name}));process.exit(1)});"
  run(['docker','exec','-i','-u','root',storage,'node','-e',program],input=json.dumps(attributes).encode())
  # Restore all files and xattrs before Storage starts background jobs.
  config=json.loads(capture(['docker','image','inspect',pins['supabase']['images']['storage']]))[0]['Config']
  assert config['Entrypoint']==['docker-entrypoint.sh'] and config['Cmd']==['node','dist/start/server.js']
  run(['docker','exec','-d',storage,*config['Entrypoint'],*config['Cmd']])
  wait(9999,'/health');wait(5000,'/status')
  for _ in range(90):
   try:
    assert json.loads(http(3000,'/organizations?select=id&id=eq.1',service))==[{'id':1}];break
   except (subprocess.CalledProcessError,AssertionError):time.sleep(.5)
  else:raise RuntimeError('isolated REST organization read failed')
  users=json.loads(http(9999,'/admin/users?page=1&per_page=1',service));assert users.get('users'),'restored Auth user read returned no users'
  buckets=json.loads(http(5000,'/bucket',service));assert isinstance(buckets,list) and buckets,'restored Storage bucket read returned no buckets'
  obj=json.loads(sql("SELECT row_to_json(o) FROM (SELECT bucket_id,name,version FROM storage.objects WHERE (metadata->>'size')::bigint BETWEEN 1 AND 1048576 ORDER BY id LIMIT 1) o;"))
  key='stub/stub/'+obj['bucket_id']+'/'+obj['name'];version=obj.get('version')
  candidates=[key+'/'+version,key+'-$v-'+version] if version else [key]
  with tarfile.open(storage_archive) as archive:
   members={str(Path(x.name)):x for x in archive.getmembers() if x.isfile()}
   member=next(members[key] for key in candidates if key in members)
   expected=hashlib.sha256(archive.extractfile(member).read()).digest()
  downloaded=http(5000,'/object/'+quote(obj['bucket_id'],safe='')+'/'+quote(obj['name'],safe='/'),service)
  assert hashlib.sha256(downloaded).digest()==expected,'restored Storage object content mismatch'
  admin=None
  if admin_resources:
   limits=json.loads((Path(__file__).resolve().parents[1]/'runtime/docker-compose.resource-budget.yml').read_text())['services']
   meta=start('postgresMeta',{'PG_META_PORT':'8080','PG_META_DB_HOST':'127.0.0.1','PG_META_DB_PORT':'5432','PG_META_DB_NAME':'isolated_restore','PG_META_DB_USER':'supabase_admin','PG_META_DB_PASSWORD':'isolated-fixture-only','CRYPTO_KEY':'isolated-fixture-only-32-byte-key'},limits['meta'])
   studio=start('studio',{'HOSTNAME':'127.0.0.1','PORT':'3001','STUDIO_PG_META_URL':'http://127.0.0.1:8080','POSTGRES_HOST':'127.0.0.1','POSTGRES_PORT':'5432','POSTGRES_DB':'isolated_restore','POSTGRES_PASSWORD':'isolated-fixture-only','SUPABASE_URL':'http://127.0.0.1:3000','SUPABASE_PUBLIC_URL':'http://127.0.0.1:3000','SUPABASE_ANON_KEY':anon,'SUPABASE_SERVICE_KEY':service,'AUTH_JWT_SECRET':secret,'DEFAULT_ORGANIZATION_NAME':'Isolated Recovery','DEFAULT_PROJECT_NAME':'Recovery','ENABLED_FEATURES_LOGS_ALL':'false'},limits['studio'])
   wait(8080,'/health');wait(3001,'/api/platform/profile')
   admin={}
   for kind,container,url in [('meta',meta,'http://127.0.0.1:8080/tables?include_columns=false'),('studio',studio,'http://127.0.0.1:3001/api/platform/profile')]:
    # Bounded burst stays inside each capped disposable service; no host ports.
    program="const fs=require('fs');(async()=>{let completed=0;const started=Date.now();await Promise.all(Array.from({length:8},async()=>{for(let i=0;i<10;i++){const r=await fetch("+json.dumps(url)+");if(r.status!==200)throw Error('health failed');await r.arrayBuffer();completed++;}}));const counters={};for(const name of ['memory.peak','pids.current','cpu.stat'])counters[name]=fs.readFileSync('/sys/fs/cgroup/'+name,'utf8').trim();console.log(JSON.stringify({completed,elapsed_ms:Date.now()-started,counters}));})().catch(()=>process.exit(1))"
    burst=json.loads(capture(['docker','exec',container,'node','-e',program]));assert burst['completed']==80
    assert int(burst['counters']['memory.peak'])<=limits[kind]['mem_limit'] and int(burst['counters']['pids.current'])<limits[kind]['pids_limit']
    info=json.loads(capture(['docker','inspect',container]))[0];assert not info['State']['OOMKilled'] and info['RestartCount']==0
    admin[kind]={'limits':limits[kind],'burst':burst,'oom':False,'restarts':0,'recovered_health':True}
   assert http(8080,'/health') and http(3001,'/api/platform/profile')
  gateway=None
  if gateway_archive is not None:
   from gateway_smoke import gateway_reads
   gateway=gateway_reads(database_container,gateway_archive,start,run,capture,http,wait,service,anon)
  return {'auth_health':True,'auth_restored_user_read':True,'rest_organization_read':True,'storage_bucket_read':True,'storage_object_bytes_match_archive':True,'storage_data_prepared_before_api_start':True,'storage_metadata_files':len(attributes),'storage_metadata_attributes_rebuilt_from_db':rebuilt,'network':'private loopback of network-none clone','production_credentials_loaded':False,'background_preloads_disabled':True,'production_integrations_started':False,'admin_resource_burst':admin,'gateway_reads':gateway,'source_images':{key:pins['supabase']['images'][key] for key in ['rest','auth','storage']}}
 finally:
  for name in reversed(names):
   subprocess.run(['docker','logs',name],stdout=log,stderr=log)
   subprocess.run(['docker','rm','-f','-v',name],stdout=log,stderr=log)
