exec(open('/tmp/festapp-setup-20261021/measure.py').read().split('measurements=[]')[0])
mode=sys.argv[1]; measurements=[]
def measured(stage,name,data,i):
 r,t,n=rpc(name,data); measurements.append(dict(run=i,stage=stage,rpc=name,ms=t,bytes=n));Path('/tmp/festapp-setup-20261021/full-'+mode+'.json').write_text(json.dumps(measurements,indent=2));return r
for i in range(4):
 measured('overview','get_unit_edit_data',{'p_unit_id':1},i)
 d=measured('create','create_occasion_setup_draft',{'p_unit':1,'p_id':str(uuid.uuid4())},i)
 if mode=='after':
  rows=measured('sources','get_occasion_setup_source_list',{'p_unit':1},i)
  source=measured('detail','get_occasion_setup_source',{'p_unit':1,'p_occasion':rows[0]['occasion']['id']},i)
 else:
  rows=measured('sources','get_occasion_setup_sources',{'p_unit':1},i);source=rows[0]
 data=d['data']; data.update(title='Synthetic measured event',link='',sourceId=source['occasion']['id'],start='2027-10-01T16:00:00Z',end='2027-10-02T00:00:00Z',reviewConfirmed=True,formEnabled=True,step=5,blueprintMode='copy' if mode=='after' else 'Převzít',formDraft={**source['forms'][0],'link':''},blueprintLayoutDraft=source['blueprints'][0]['blueprintLayoutDraft'],blueprintTitle='Synthetic hall',saleMode='preparation')
 bank=rpc('get_occasion_setup_bank_accounts',{'p_id':d['id']})[0]['accounts'][0]
 data.update(bankAccountId=bank['id'],bankAccountFingerprint=bank['fingerprint'])
 if mode!='after':data['bankAccountConfirmed']=True
 d=measured('saveBlueprint','save_occasion_setup_draft',{'p_id':d['id'],'p_expected_revision':d['revision'],'p_data':data,'p_step':5},i)
 measured('editorResources','get_occasion_setup_blueprint_resources',{'p_draft':d['id']},i)
 data['title']='Synthetic measured event edited'
 d=measured('save','save_occasion_setup_draft',{'p_id':d['id'],'p_expected_revision':d['revision'],'p_data':data,'p_step':5},i)
 response=measured('finalize','finalize_occasion_setup_draft',{'p_id':d['id'],'p_expected_revision':d['revision'],'p_command_id':str(uuid.uuid4())},i)
 import subprocess
 subprocess.run(['psql','postgresql://supabase_admin:postgres@127.0.0.1:56822/postgres','-q','-v','ON_ERROR_STOP=1','-c',f"DELETE FROM eshop.blueprint_seat_bindings WHERE blueprint IN(SELECT b.id FROM eshop.blueprints b JOIN public.occasions o ON o.id=b.occasion WHERE o.id={int(response['data']['occasionId'])} AND o.title='Synthetic measured event edited');"],check=True,capture_output=True)
 rpc('delete_occasion_client_sync_v1',{'p_occasion':response['data']['occasionId'],'p_command_id':str(uuid.uuid4())})
 # Terminal receipts can be deleted from the private local fixture after measurement.
 current=rpc('get_occasion_setup_draft',{'p_id':d['id']})[0]
 rpc('delete_occasion_setup_draft',{'p_id':d['id'],'p_unit':1,'p_expected_revision':current['revision']})
Path('/tmp/festapp-setup-20261021/full-'+mode+'.json').write_text(json.dumps(measurements,indent=2))
print(json.dumps(measurements))
