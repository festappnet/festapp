import importlib.util,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('drill_online',Path(__file__).resolve().parents[1]/'hetzner-supabase/restore/drill-online-backup-local.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class StorageConsistencyTest(unittest.TestCase):
 def test_exact_versions_and_sizes_with_orphan_file(self):
  objects=[{'bucket':'photos','name':'nested/pic.jpg','version':'v1','size':'12'},
   {'bucket':'photos','name':'other.jpg','version':'v2','size':'5'}]
  result=m.storage_consistency(objects,{'stub/stub/photos/nested/pic.jpg/v1':12,'stub/stub/photos/other.jpg-$v-v2':5,'old-orphan':3})
  self.assertTrue(result['consistent']);self.assertEqual(result['unreferenced_archive_files'],1)
 def test_wrong_version_does_not_match(self):
  result=m.storage_consistency([{'bucket':'photos','name':'pic','version':'v2','size':'5'}],{'stub/stub/photos/pic/v1':5})
  self.assertFalse(result['consistent']);self.assertEqual(result['missing_objects'],1)
 def test_size_mismatch_fails_consistency(self):
  result=m.storage_consistency([{'bucket':'photos','name':'pic','size':'5'}],{'stub/stub/photos/pic':3})
  self.assertFalse(result['consistent']);self.assertEqual(result['size_mismatches'],1)
 def test_empty_database_is_not_proof(self):
  self.assertFalse(m.storage_consistency([],{})['consistent'])

if __name__=='__main__':unittest.main()
