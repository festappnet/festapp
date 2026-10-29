#!/usr/bin/env python3
"""One bounded real PostgREST request. Uses an existing disposable draft only.
Private context JSON: {draft, actor, token}. Never writes or prints credentials.
Legacy mode hard-stops/restarts ONLY the named disposable REST container.
"""
import argparse, atexit, datetime, json, subprocess, time, urllib.error, urllib.parse, urllib.request, uuid
p=argparse.ArgumentParser()
p.add_argument('--context', required=True)
p.add_argument('--project', required=True)
p.add_argument('--url', required=True)
p.add_argument('--legacy-hard-stop', action='store_true')
a=p.parse_args()
assert a.project.startswith('festapp-') and all(c.isalnum() or c=='-' for c in a.project)
assert urllib.parse.urlparse(a.url).hostname in ('localhost','127.0.0.1','::1')
c=json.load(open(a.context));uuid.UUID(c['draft']);uuid.UUID(c['actor']);db='supabase_db_'+a.project;rest='supabase_rest_'+a.project
# Reject a production or non-disposable target before any request.
def sql(query):
 return subprocess.run(['docker','exec','-i',db,'psql','-U','postgres','-d','postgres','-Atq'],input=query,text=True,capture_output=True,check=True)
identity=sql('select project from festapp_test_support.disposable_environment where singleton;').stdout.strip()
assert identity==a.project, 'Disposable project mismatch'
assert sql('select paused and worker_url is null from email_capacity;').stdout.strip()=='t'
assert sql('select count(*) from cron.job where active;').stdout.strip()=='0'
def call(revision, timeout):
 request=urllib.request.Request(a.url+'/rest/v1/rpc/get_occasion_setup_email_preview',data=json.dumps({'p_id':c['draft'],'p_expected_revision':revision}).encode(),headers={'Authorization':'Bearer '+c['token'],'apikey':c['token'],'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(request,timeout=timeout) as r:return r.status,json.load(r)
 except urllib.error.HTTPError as e:return e.code,json.load(e)
 except TimeoutError:return 'timeout',{}
# A two-second log window tolerates host/VM clock skew; subtract its baseline.
start=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).isoformat()
def log_conflicts():
 logs=subprocess.run(['docker','logs','--since',start,db],capture_output=True,text=True,check=True)
 return (logs.stdout+logs.stderr).count('ERROR:  Draft revision conflict')
baseline=log_conflicts();t=time.monotonic()
status,body=call(0,.25 if a.legacy_hard_stop else 2)
elapsed=time.monotonic()-t
if a.legacy_hard_stop:
 subprocess.run(['docker','stop','-t','0',rest],capture_output=True,check=True)
 def restore_rest():
  subprocess.run(['docker','start',rest],capture_output=True,check=True)
 atexit.register(restore_rest)
# Docker's log stream can lag the HTTP response. Observe for at most 1 second.
count=0
for _ in range(20):
 count=log_conflicts()-baseline
 if count: break
 time.sleep(.025)
direct=sql("begin;set local role authenticated;select set_config('request.jwt.claim.sub','"+c['actor']+"',true);select get_occasion_setup_email_preview('"+c['draft']+"',0);rollback;")
assert direct.stderr.count('ERROR:  Draft revision conflict')==1
result={'frontend_invocations':0,'http_stale_requests':1,'db_stale_conflicts':count,'http_status':status,'http_seconds':round(elapsed,3),'direct_sql_calls':1,'direct_sql_conflicts':1}
if a.legacy_hard_stop:
 restore_rest()
 atexit.unregister(restore_rest)
 assert count>1
else:
 assert status==409 and body['code']=='PT409' and count==1,result
 revision=int(sql("select revision from occasion_setup_drafts where id='"+c['draft']+"';").stdout.strip())
 status,_=call(revision,2)
 assert status==200,status
 result['explicit_retry_status']=status
print(json.dumps(result))
