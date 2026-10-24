import json,subprocess,urllib.parse
conf=subprocess.check_output(['git','show','origin/prod/festapp:automation/project.conf'],text=True)
c=dict(l.split('=',1) for l in conf.splitlines() if l and not l.startswith('#') and '=' in l)
url=c['BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL'].strip('"')
key=c['BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY'].strip('"')
assert url=='https://api.festapp.net'
probes=[('hidden_occasions','occasions',{'select':'id','organization':'eq.1','is_hidden':'eq.true','limit':'1'}),('news_read_markers','user_news',{'select':'occasions!inner(organization)','occasions.organization':'eq.1','limit':'1'}),('anonymous_group_memberships','user_groups',{'select':'user_group_info!inner(occasions!inner(organization))','user_group_info.occasions.organization':'eq.1','limit':'1'})]
for label,table,query in probes:
 result=subprocess.check_output(['curl','-sS','--max-time','15','-w','\n%{http_code}','-H','apikey: '+key,'-H','Authorization: Bearer '+key,url+'/rest/v1/'+table+'?'+urllib.parse.urlencode(query)],text=True)
 body,status=result.rsplit('\n',1)
 try: data=json.loads(body)
 except ValueError: data=None
 print(json.dumps({'probe':label,'status':int(status),'row_returned':isinstance(data,list) and len(data)>0,'error_code':data.get('code') if isinstance(data,dict) else None}))
for name,payload in [('set_user_password',{'usr':'audit-invalid-uuid','oc':1,'password':'audit-never-executed'}),('create_user_in_organization_with_data',{'org':'audit-invalid-bigint','email':'audit@example.invalid','password':'audit-never-executed','data':{}})]:
 result=subprocess.check_output(['curl','-sS','--max-time','15','-w','\n%{http_code}','-H','apikey: '+key,'-H','Authorization: Bearer '+key,'-H','Content-Type: application/json','--data-binary',json.dumps(payload),url+'/rest/v1/rpc/'+name],text=True)
 body,status=result.rsplit('\n',1)
 try:data=json.loads(body)
 except ValueError:data={}
 print(json.dumps({'probe':'invalid_type_'+name,'status':int(status),'error_code':data.get('code')}))
