import importlib.util,json,tarfile,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('service_smoke',Path(__file__).resolve().parents[1]/'hetzner-supabase/restore/service_smoke.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class ServiceIsolationTest(unittest.TestCase):
 def test_missing_xattrs_require_explicit_recovery_from_database_metadata(self):
  member=tarfile.TarInfo('stub/stub/photos/pic/v1')
  objects=[{'bucket':'photos','name':'pic','version':'v1','metadata':{'mimetype':'image/jpeg','cacheControl':'max-age=3600'}}]
  with self.assertRaisesRegex(AssertionError,'lacks required xattrs'):m.storage_metadata(objects,{member.name:member})
  attrs,count=m.storage_metadata(objects,{member.name:member},True)
  self.assertEqual(count,2);self.assertEqual(attrs[member.name]['user.supabase.content-type'],'image/jpeg')
 def test_archived_metadata_is_preserved_and_other_namespaces_are_ignored(self):
  member=tarfile.TarInfo('stub/stub/photos/pic')
  member.pax_headers={'SCHILY.xattr.user.supabase.content-type':'image/png','SCHILY.xattr.user.supabase.cache-control':'max-age=7','SCHILY.xattr.security.capability':'unsafe'}
  obj={'bucket':'photos','name':'pic','metadata':{'mimetype':'image/jpeg','cacheControl':'max-age=3600'}}
  attrs,count=m.storage_metadata([obj],{member.name:member})
  self.assertEqual(count,0);self.assertEqual(len(attrs[member.name]),2);self.assertEqual(attrs[member.name]['user.supabase.content-type'],'image/png')
 def test_metadata_restore_rejects_archive_path_escape(self):
  with self.assertRaises(AssertionError):m.storage_metadata([],{'../escape':tarfile.TarInfo('../escape')})
 def test_production_container_name_is_rejected_before_docker(self):
  with patch.object(m.subprocess,'check_output') as read,patch.object(m.subprocess,'run') as write:
   with self.assertRaises(AssertionError):m.application_reads('supabase-db',{},None,None)
   read.assert_not_called();write.assert_not_called()
 def test_nonisolated_clone_is_rejected_before_mutation(self):
  for mode,bindings,mounts in [('bridge',{},[]),('none',{'5432/tcp':[{}]},[]),('none',{},[{'Type':'bind'}])]:
   actual=[{'HostConfig':{'NetworkMode':mode,'PortBindings':bindings},'Mounts':mounts}]
   with self.subTest(mode=mode,bindings=bindings,mounts=mounts),patch.object(m.subprocess,'check_output',return_value=json.dumps(actual).encode()),patch.object(m.subprocess,'run') as write:
    with self.assertRaises(AssertionError):m.application_reads('festapp-local-restore-'+'a'*16,{},None,None)
    write.assert_not_called()

if __name__=='__main__':unittest.main()
