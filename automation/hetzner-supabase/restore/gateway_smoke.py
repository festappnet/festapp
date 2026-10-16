"""Exercise backed-up public proxy configuration in the clone's private loopback.
Only five public configuration files are read. Runtime env/secrets are forbidden.
"""
import json,re,tarfile

CONFIGS={
 'docker/volumes/api/envoy/envoy.yaml':'/etc/envoy/envoy.yaml',
 'docker/volumes/api/envoy/cds.yaml':'/etc/envoy/cds.yaml',
 'docker/volumes/api/envoy/lds.template.yaml':'/etc/envoy/lds.template.yaml',
 'docker/volumes/api/envoy/docker-entrypoint.sh':'/tmp/recovery-envoy-entrypoint.sh',
 'docker/caddy/Caddyfile':'/etc/caddy/Caddyfile',
}

def configuration_files(runtime_archive):
 with tarfile.open(runtime_archive) as archive:
  files={}
  for path in CONFIGS:
   matches=[m for m in archive.getmembers() if m.name==path]
   assert len(matches)==1 and matches[0].isfile() and matches[0].size<1024*1024,'missing, duplicate or unsafe proxy configuration'
   files[path]=archive.extractfile(matches[0]).read()
 return files

def gateway_reads(database_container,runtime_archive,start,run,capture,http,wait,service,anon):
 files=configuration_files(runtime_archive)
 # Same namespace as the network-none DB: names become private loopback only.
 cds='docker/volumes/api/envoy/cds.yaml'
 text=files[cds].decode()
 text=re.sub(r'(?m)^(\s*address:) (auth|rest|realtime-dev\.supabase-realtime|storage|functions|meta|studio)\s*$',r'\1 127.0.0.1',text)
 assert not re.search(r'(?m)^\s*address: (?!127\.0\.0\.1\s*$|0\.0\.0\.0\s*$)[A-Za-z0-9]',text),'unexpected upstream address'
 files[cds]=text.encode()
 envoy=start('envoy',{'ANON_KEY':anon,'SERVICE_ROLE_KEY':service,'DASHBOARD_USERNAME':'recovery','DASHBOARD_PASSWORD':'fixture-only'},prepare=True)
 for source,destination in CONFIGS.items():
  if source.endswith('/Caddyfile'):continue
  # Stream bytes, preserving no workstation UID and executing no archive text.
  run(['docker','exec','-i',envoy,'sh','-c','mkdir -p /etc/envoy && cat > "$1"','sh',destination],input=files[source])
 run(['docker','exec','-d',envoy,'sh','-c','exec "$@" > /proc/1/fd/1 2>/proc/1/fd/2','sh','sh','/tmp/recovery-envoy-entrypoint.sh','--concurrency','1'])
 wait(9901,'/ready')
 caddy=start('caddy',{'FESTAPP_SUPABASE_SITE_ADDRESSES':'http://127.0.0.1:8081','FESTAPP_SUPABASE_ADMIN_HOSTNAME':'127.0.0.1','FESTAPP_SUPABASE_ADMIN_BASIC_AUTH':'cmVjb3Zlcnk6Zml4dHVyZS1vbmx5'},prepare=True)
 run(['docker','exec','-i',caddy,'sh','-c','mkdir -p /etc/caddy && cat > /etc/caddy/Caddyfile'],input=files['docker/caddy/Caddyfile'])
 run(['docker','exec','-d',caddy,'sh','-c','exec "$@" > /proc/1/fd/1 2>/proc/1/fd/2','sh','caddy','run','--config','/etc/caddy/Caddyfile','--adapter','caddyfile'])
 # Readiness must not bypass the actual API-key gate on /auth/v1/health.
 wait(2019,'/config/')
 def api(port,path):
  return capture(['docker','exec',database_container,'curl','--fail','--silent','--max-time','5','-H','apikey: '+service,'-H','Authorization: Bearer '+service,'http://127.0.0.1:'+str(port)+path])
 denied=capture(['docker','exec',database_container,'curl','--silent','--max-time','5','-o','/dev/null','-w','%{http_code}','http://127.0.0.1:8081/auth/v1/health'])
 assert denied==b'401','restored gateway must reject an unauthenticated request'
 for port in [8000,8081]:
  assert json.loads(api(port,'/rest/v1/organizations?select=id&id=eq.1'))==[{'id':1}]
  api(port,'/auth/v1/health')
  api(port,'/storage/v1/status')
 counters={}
 for kind,name in [('envoy',envoy),('caddy',caddy)]:
  state=json.loads(capture(['docker','inspect',name]))[0]
  assert state['State']['Running'] and not state['State']['OOMKilled'] and state['RestartCount']==0
  counters[kind]={'running':True,'oom':False,'restarts':0}
 return {'backed_up_configuration_used':True,'public_configuration_files':len(CONFIGS),'runtime_env_or_credentials_loaded':False,'only_upstream_dns_replaced_with_private_loopback':True,'envoy_auth_storage_and_rest_reads':True,'unauthenticated_auth_request_denied':True,'caddy_to_envoy_to_restored_database_read':True,'caddy_auth_and_storage_reads':True,'provider_tls_or_external_access_tested':False,'caddy_only_additional_capability':'NET_BIND_SERVICE','services':counters}
