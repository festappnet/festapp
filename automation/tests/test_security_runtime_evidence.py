import importlib.util,json,os,tempfile,time,types,unittest
from pathlib import Path
from unittest.mock import patch
root=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('runtime_evidence',root/'automation/hetzner-supabase/monitoring/runtime-evidence.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class RuntimeEvidenceTest(unittest.TestCase):
 def test_sanitized_existing_monitor_observations(self):
  with tempfile.TemporaryDirectory() as tmp:
   folder=Path(tmp);(folder/'.env').write_text('FESTAPP_RUNTIME_DATABASE=festapp_rehearsal_20260909220601\nSECRET=fixture-never-serialize\n')
   def command(args):
    if 'compose' in args:return 'owned-container\n'
    if 'inspect' in args:return json.dumps([{'Name':'db','Config':{'Env':['SECRET=fixture-never-serialize']},'State':{'Running':True,'OOMKilled':False},'RestartCount':2}])
    if 'psql' in args:return 'BEGIN\n0\nCOMMIT\n'
    raise AssertionError(args)
   with patch.object(m,'COMPOSE',folder),patch.object(m,'OUTPUT',folder/'runtime.json'),patch.object(m.os,'geteuid',return_value=0),patch.object(m.os,'uname',return_value=types.SimpleNamespace(nodename='festapp-supabase-rehearsal-01')),patch.object(m,'command',side_effect=command),patch.object(m,'latest',return_value=time.time()):
    m.main()
   data=(folder/'runtime.json').read_text();self.assertNotIn('fixture-never-serialize',data)
   result=json.loads(data);self.assertTrue(result['ok']);self.assertEqual(result['longTransactions'],0);self.assertEqual(result['containers'][0]['restarts'],2)
 def test_wrong_host_stops_before_reading_configuration(self):
  with patch.object(m.os,'geteuid',return_value=0),patch.object(m.os,'uname',return_value=types.SimpleNamespace(nodename='other-host')),patch.object(m,'command') as command:
   with self.assertRaises(AssertionError):m.main()
   command.assert_not_called()
if __name__=='__main__':unittest.main()
