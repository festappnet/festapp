import importlib.util,json,os,tempfile,time,types,unittest
from pathlib import Path
from unittest.mock import patch
root=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('runtime_evidence',root/'automation/hetzner-supabase/monitoring/runtime-evidence.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class RuntimeEvidenceTest(unittest.TestCase):
 def test_native_counter_allowlist_and_stale_rejection(self):
  data={'version':1,'at':1000000,'activeUserWorkersCount':3,'retiredUserWorkersCount':1,'receivedRequestsCount':8,'handledRequestsCount':5,'secret':'never-serialize'}
  self.assertNotIn('secret',m.edge_counters('private log ignored\n[Info] festapp_runtime_resource_metrics '+json.dumps(data),1001))
  for change in [{'at':1},{'at':1002000},{'activeUserWorkersCount':'secret'}]:
   with self.assertRaises(AssertionError):m.edge_counters('festapp_runtime_resource_metrics '+json.dumps({**data,**change}),1001)
 def test_router_patch_is_idempotent_and_rejects_unknown_dispatch(self):
  spec=importlib.util.spec_from_file_location('resource_patch',root/'automation/hetzner-supabase/runtime/patch-function-resource-metrics.py')
  p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
  source='Deno.serve(async (req) => new Response("fixture"));'
  result=p.patch(source);self.assertEqual(p.patch(result),result)
  with self.assertRaises(AssertionError):p.patch('serveChanged();')

 def test_cgroup_working_set_and_cpu_counters_without_secrets(self):
  with tempfile.TemporaryDirectory() as tmp:
   folder=Path(tmp);proc=folder/'proc';groups=folder/'cgroups';group=groups/'docker-test'
   (proc/'123').mkdir(parents=True);group.mkdir(parents=True)
   (proc/'meminfo').write_text('MemTotal: 4096 kB\nMemAvailable: 1024 kB\nSwapTotal: 0 kB\n')
   (proc/'123/cgroup').write_text('0::/docker-test\n')
   for name,value in {'memory.current':'1000','memory.stat':'inactive_file 300\n','cpu.stat':'usage_usec 12345\n','pids.current':'9'}.items():(group/name).write_text(value)
   sample=m.resource_sample([{'Name':'/db','State':{'Pid':123},'Config':{'Env':['secret']}}],proc,groups)
   self.assertEqual(sample['host']['MemTotal'],4096*1024)
   self.assertEqual(sample['containers'],[{'name':'/db','memory_bytes':1000,'working_set_bytes':700,'cpu_usage_usec':12345,'pids':9}])
   self.assertNotIn('secret',json.dumps(sample))
 def test_history_retention_and_symlink_rejection(self):
  with tempfile.TemporaryDirectory() as tmp:
   folder=Path(tmp);old=folder/'resources-20200101.jsonl';old.write_text('old')
   m.record_resources({'at':1792159800,'containers':[]},folder)
   self.assertFalse(old.exists())
   history=next(folder.glob('resources-*.jsonl'))
   self.assertEqual(history.stat().st_mode&0o777,0o600)
   self.assertEqual(len(history.read_text().splitlines()),1)
   history.unlink();target=folder/'target';target.write_text('unchanged');history.symlink_to(target)
   with self.assertRaises(OSError):m.record_resources({'at':1792159800},folder)
   self.assertEqual(target.read_text(),'unchanged')
 def test_sanitized_existing_monitor_observations(self):
  with tempfile.TemporaryDirectory() as tmp:
   folder=Path(tmp);(folder/'.env').write_text('FESTAPP_RUNTIME_DATABASE=festapp_rehearsal_20260909220601\nSECRET=fixture-never-serialize\n')
   def command(args):
    if 'compose' in args:return 'owned-container\n'
    if 'inspect' in args:return json.dumps([{'Name':'db','Config':{'Env':['SECRET=fixture-never-serialize']},'State':{'Running':True,'OOMKilled':False},'RestartCount':2}])
    if 'psql' in args:return 'BEGIN\n'+json.dumps({'connections':12,'active':2,'idle_in_transaction':0,'long_transactions':0,'max_connections':100,'reserved_connections':3})+'\nCOMMIT\n'
    raise AssertionError(args)
   with patch.object(m,'COMPOSE',folder),patch.object(m,'OUTPUT',folder/'runtime.json'),patch.object(m.os,'geteuid',return_value=0),patch.object(m.os,'uname',return_value=types.SimpleNamespace(nodename='festapp-supabase-rehearsal-01')),patch.object(m,'command',side_effect=command),patch.object(m,'latest',return_value=time.time()):
    m.main()
   data=(folder/'runtime.json').read_text();self.assertNotIn('fixture-never-serialize',data)
   result=json.loads(data);self.assertTrue(result['ok']);self.assertEqual(result['longTransactions'],0);self.assertEqual(result['containers'][0]['restarts'],2)
 def test_database_failure_still_keeps_host_and_native_edge_capacity_evidence(self):
  with tempfile.TemporaryDirectory() as tmp:
   folder=Path(tmp);(folder/'.env').write_text('FESTAPP_RUNTIME_DATABASE=festapp_rehearsal_20260909220601\n')
   native={'version':1,'at':int(time.time()*1000),'activeUserWorkersCount':3,'retiredUserWorkersCount':1,'receivedRequestsCount':8,'handledRequestsCount':5}
   def command(args):
    if 'compose' in args:return 'owned-container\n'
    if 'inspect' in args:return json.dumps([{'Name':'db','State':{'Running':True,'OOMKilled':False},'RestartCount':0}])
    if 'logs' in args:return 'festapp_runtime_resource_metrics '+json.dumps(native)
    raise RuntimeError('fixture database unavailable')
   with patch.object(m,'COMPOSE',folder),patch.object(m,'OUTPUT',folder/'runtime.json'),patch.object(m.os,'geteuid',return_value=0),patch.object(m.os,'uname',return_value=types.SimpleNamespace(nodename='festapp-supabase-rehearsal-01')),patch.object(m,'command',side_effect=command),patch.object(m,'resource_sample',return_value={'at':int(time.time()),'host':{},'containers':[]}),patch.object(m,'record_resources') as recorded:
    m.main()
   self.assertEqual(recorded.call_args.args[0]['edge']['activeUserWorkersCount'],3)
   self.assertFalse(json.loads((folder/'runtime.json').read_text())['ok'])
 def test_activation_rejects_another_host_before_lock_or_source_reads(self):
  spec=importlib.util.spec_from_file_location('apply_metrics',root/'automation/hetzner-supabase/runtime/apply-runtime-resource-metrics.py')
  installer=importlib.util.module_from_spec(spec);spec.loader.exec_module(installer)
  import sys
  with patch.object(sys,'argv',['installer','--ack','collect-native-runtime-capacity-counters','--source-commit','a'*40,'--previous-main-sha256','b'*64]),patch.object(installer.os,'geteuid',return_value=0),patch.object(installer.os,'uname',return_value=types.SimpleNamespace(nodename='other-host')),patch.object(installer.fcntl,'flock') as lock:
   with self.assertRaises(AssertionError):installer.main()
   lock.assert_not_called()
 def test_wrong_host_stops_before_reading_configuration(self):
  with patch.object(m.os,'geteuid',return_value=0),patch.object(m.os,'uname',return_value=types.SimpleNamespace(nodename='other-host')),patch.object(m,'command') as command:
   with self.assertRaises(AssertionError):m.main()
   command.assert_not_called()
if __name__=='__main__':unittest.main()
