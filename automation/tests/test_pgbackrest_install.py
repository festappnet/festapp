import importlib.util,os,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
root=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('pgbackrest_install',root/'automation/hetzner-supabase/backup/pgbackrest/install.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class PgBackRestInstallTest(unittest.TestCase):
 def test_mounted_database_config_group_read_survives_root_umask(self):
  with tempfile.TemporaryDirectory() as tmp:
   original=os.umask(0o077)
   try:
    p=Path(tmp)/'config';m.atomic(p,'fixture-secret',0o640)
    self.assertEqual(p.stat().st_mode&0o777,0o640)
    self.assertEqual(p.read_text(),'fixture-secret')
    m.atomic(p,'updated-root-only')
    self.assertEqual(p.stat().st_mode&0o777,0o600)
   finally:os.umask(original)
 def test_exclusive_temporary_file_never_overwrites_an_existing_file(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'config';(Path(tmp)/'.config.new').write_text('existing')
   with self.assertRaises(FileExistsError):m.atomic(p,'replacement')
   self.assertEqual((Path(tmp)/'.config.new').read_text(),'existing')
   self.assertFalse(p.exists())
if __name__=='__main__':unittest.main()
