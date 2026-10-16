import hashlib,importlib.util,json,os,subprocess,sys,tarfile,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('service_smoke',Path(__file__).resolve().parents[1]/'hetzner-supabase/restore/service_smoke.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class ServiceIsolationTest(unittest.TestCase):
 def test_unavailable_docker_does_not_consume_downloaded_inputs(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp);backup=root/'backup';backup.mkdir();tools=root/'bin';tools.mkdir()
   docker=tools/'docker';docker.write_text('#!/bin/sh\nexit 1\n');docker.chmod(0o700)
   artifacts={}
   for name in ['postgres.dump.age','globals.sql.age','storage.tar.age','runtime.tar.age']:
    data=('fixture-'+name).encode();(backup/name).write_bytes(data)
    artifacts[name]={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
   manifest={'version':1,'encrypted':True,'consistency':'online-operational-backup-not-promotion-rpo0','run_id':'20261016T150700Z','source_host':'festapp-supabase-rehearsal-01','source_database':'festapp_rehearsal_20260909220601','artifacts':artifacts}
   (backup/'manifest.json').write_text(json.dumps(manifest));identity=root/'identity';identity.write_text('fixture')
   script=Path(__file__).resolve().parents[1]/'hetzner-supabase/restore/drill-online-backup-local.py'
   env=os.environ.copy();env['PATH']=str(tools)+os.pathsep+env['PATH']
   result=subprocess.run([sys.executable,str(script),'--backup-dir',str(backup),'--identity',str(identity),'--evidence',str(root/'result.json'),'--consume-downloaded-artifacts'],env=env,capture_output=True)
   self.assertNotEqual(result.returncode,0)
   for name,meta in artifacts.items():self.assertEqual(hashlib.sha256((backup/name).read_bytes()).hexdigest(),meta['sha256'])

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
