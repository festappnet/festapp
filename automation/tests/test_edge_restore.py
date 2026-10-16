import importlib.util,io,json,tarfile,tempfile,types,unittest
from pathlib import Path
from unittest.mock import Mock,patch
spec=importlib.util.spec_from_file_location('edge_smoke',Path(__file__).resolve().parents[1]/'hetzner-supabase/restore/edge_smoke.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class EdgeArchiveTest(unittest.TestCase):
 def fixture(self,path,extra=None):
  with tarfile.open(path,'w') as tar:
   for n,b in {m.PREFIX+'main/index.ts':b'public main',m.PREFIX+'email-confirmation-status/index.ts':b'public worker','docker/.env':b'PRIVATE_RUNTIME_ENV',m.PREFIX+'.env':b'PRIVATE_FUNCTION_ENV',**(extra or {})}.items():
    info=tarfile.TarInfo(n);info.size=len(b);tar.addfile(info,io.BytesIO(b))
 def test_export_does_not_include_runtime_or_function_environment(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'runtime.tar';self.fixture(p);files=m.function_sources(p)
   self.assertEqual(set(files),{'main/index.ts','email-confirmation-status/index.ts'})
   self.assertNotIn(b'PRIVATE_RUNTIME_ENV',m.public_tar(files));self.assertNotIn(b'PRIVATE_FUNCTION_ENV',m.public_tar(files))
 def test_path_traversal_source_is_rejected(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'runtime.tar';self.fixture(p,{m.PREFIX+'../escape.ts':b'bad'})
   with self.assertRaises(AssertionError):m.function_sources(p)
 def test_credential_json_cannot_be_exported_as_source(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'runtime.tar';self.fixture(p,{m.PREFIX+'main/secrets.json':b'private'})
   with self.assertRaises(AssertionError):m.function_sources(p)
 def test_source_digest_is_order_independent_but_content_sensitive(self):
  self.assertEqual(m.source_digest({'b':b'2','a':b'1'}),m.source_digest({'a':b'1','b':b'2'}))
  self.assertNotEqual(m.source_digest({'a':b'1'}),m.source_digest({'a':b'2'}))
 def test_downloader_refuses_production_before_any_docker_call(self):
  with patch.object(m.os,'uname',return_value=types.SimpleNamespace(nodename='festapp-supabase-rehearsal-01')),patch.object(m.subprocess,'run') as call:
   with self.assertRaisesRegex(AssertionError,'dedicated local recovery VM'):m.prepare_cache(Path('/unused'),Path('/unused-result'))
   call.assert_not_called()
 def test_mismatched_cache_is_rejected_before_service_creation(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'runtime.tar';self.fixture(p);start=Mock();capture=Mock(return_value=json.dumps([{'Labels':{'festapp.recovery-public-edge-cache':'wrong'}}]).encode())
   with self.assertRaisesRegex(AssertionError,'does not match'):m.edge_reads('festapp-local-restore-'+'a'*16,p,'festapp-recovery-edge-cache-'+'b'*12,start,Mock(),capture,'fixture-service','fixture-anon','fixture-secret')
   start.assert_not_called()
if __name__=='__main__':unittest.main()
