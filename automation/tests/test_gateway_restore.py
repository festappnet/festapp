import importlib.util,io,tarfile,tempfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('gateway_smoke',Path(__file__).resolve().parents[1]/'hetzner-supabase/restore/gateway_smoke.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class GatewayArchiveTest(unittest.TestCase):
 def archive(self,root,replace=None):
  path=root/'runtime.tar'
  with tarfile.open(path,'w') as archive:
   for name in [*m.CONFIGS,'docker/.env']:
    body=b'fixture' if name!='docker/.env' else b'FORBIDDEN_RUNTIME_SECRET'
    info=tarfile.TarInfo(name);info.size=len(body)
    if name==replace:info.type=tarfile.SYMTYPE;info.linkname='/private/secret';info.size=0
    archive.addfile(info,io.BytesIO(body))
  return path
 def test_only_public_proxy_files_are_returned(self):
  with tempfile.TemporaryDirectory() as tmp:
   files=m.configuration_files(self.archive(Path(tmp)))
   self.assertEqual(set(files),set(m.CONFIGS));self.assertNotIn(b'FORBIDDEN_RUNTIME_SECRET',files.values())
 def test_symlink_cannot_supply_proxy_configuration(self):
  with tempfile.TemporaryDirectory() as tmp:
   with self.assertRaises(AssertionError):m.configuration_files(self.archive(Path(tmp),'docker/caddy/Caddyfile'))
 def test_missing_proxy_configuration_is_a_failure(self):
  with tempfile.TemporaryDirectory() as tmp:
   path=Path(tmp)/'runtime.tar'
   with tarfile.open(path,'w'):pass
   with self.assertRaises(AssertionError):m.configuration_files(path)
if __name__=='__main__':unittest.main()
