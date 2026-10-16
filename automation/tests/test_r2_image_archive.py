import importlib.util,io,json,subprocess,tarfile,tempfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('r2_archive',Path(__file__).resolve().parents[1]/'hetzner-supabase/backup/create-r2-image-archive.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
spec2=importlib.util.spec_from_file_location('r2_verify',Path(__file__).resolve().parents[1]/'hetzner-supabase/restore/r2_archive.py')
v=importlib.util.module_from_spec(spec2);spec2.loader.exec_module(v)

class R2ArchiveTest(unittest.TestCase):
 def test_streamed_archive_preserves_contents_and_metadata_with_content_hash(self):
  inventories={bucket:[] for bucket in m.BUCKETS}
  inventories[m.BUCKETS[0]]=[{'Path':'images/example.jpg','Size':3,'MimeType':'image/jpeg','Metadata':{'cache-control':'public,max-age=3600'}}]
  def fetch(bucket,key):return subprocess.Popen(['python3','-c',"import sys;sys.stdout.buffer.write(b'abc')"],stdout=subprocess.PIPE)
  stream=io.BytesIO();result=m.write_archive(inventories,fetch,stream)
  self.assertEqual(result['objects'],1);self.assertEqual(result['bytes'],3)
  with tarfile.open(fileobj=io.BytesIO(stream.getvalue())) as archive:
   self.assertEqual(archive.extractfile(m.BUCKETS[0]+'/images/example.jpg').read(),b'abc')
   record=json.load(archive.extractfile('.r2-objects.json'))['objects'][0]
   self.assertEqual(record['sha256'],'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
   self.assertEqual(record['source_metadata']['MimeType'],'image/jpeg')
  with tempfile.TemporaryDirectory() as temp:
   path=Path(temp)/'fixture.tar';path.write_bytes(stream.getvalue())
   result=v.verify_archive(path,['https://img.festapp.net/images/example.jpg'])
   self.assertTrue(result['consistent']);self.assertEqual(result['database_r2_references_checked'],1)
   result=v.verify_archive(path,['https://img.festapp.net/images/missing.jpg'])
   self.assertFalse(result['consistent']);self.assertEqual(result['missing_database_r2_references'],1)
 def test_restore_rejects_tampered_object_bytes(self):
  with tempfile.TemporaryDirectory() as temp:
   path=Path(temp)/'fixture.tar'
   with tarfile.open(path,'w') as archive:
    member=tarfile.TarInfo(m.BUCKETS[0]+'/images/object');member.size=3;archive.addfile(member,io.BytesIO(b'bad'))
    body=json.dumps({'version':1,'objects':[{'bucket':m.BUCKETS[0],'key':'images/object','size':3,'sha256':'0'*64}]}).encode()
    member=tarfile.TarInfo('.r2-objects.json');member.size=len(body);archive.addfile(member,io.BytesIO(body))
   with self.assertRaisesRegex(AssertionError,'hash mismatch'):v.verify_archive(path,[])
 def test_object_growth_during_backup_fails_instead_of_accepting_partial_content(self):
  inventories={bucket:[] for bucket in m.BUCKETS};inventories[m.BUCKETS[0]]=[{'Path':'images/object','Size':2}]
  def fetch(bucket,key):return subprocess.Popen(['python3','-c',"import sys;sys.stdout.buffer.write(b'abc')"],stdout=subprocess.PIPE)
  with self.assertRaisesRegex(AssertionError,'changed size'):m.write_archive(inventories,fetch,io.BytesIO())
 def test_unknown_bucket_and_path_traversal_are_rejected(self):
  for bucket,key in [('unrelated','images/x'),(m.BUCKETS[0],'../escape'),(m.BUCKETS[0],'/absolute'),(m.BUCKETS[0],'')]:
   with self.subTest(bucket=bucket,key=key),self.assertRaises(AssertionError):m.archive_path(bucket,key)

if __name__=='__main__':unittest.main()
