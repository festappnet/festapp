import importlib.util,io,json,subprocess,sys,tarfile,tempfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('r2_archive',Path(__file__).resolve().parents[1]/'hetzner-supabase/backup/create-r2-image-archive.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
spec2=importlib.util.spec_from_file_location('r2_verify',Path(__file__).resolve().parents[1]/'hetzner-supabase/restore/r2_archive.py')
v=importlib.util.module_from_spec(spec2);spec2.loader.exec_module(v)
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'hetzner-supabase/restore'))
spec3=importlib.util.spec_from_file_location('r2_dump_verify',Path(__file__).resolve().parents[1]/'hetzner-supabase/restore/verify-r2-dump-local.py')
d=importlib.util.module_from_spec(spec3);spec3.loader.exec_module(d)

class R2ArchiveTest(unittest.TestCase):
 def test_new_asset_format_covers_colliding_a_keys_and_service_fonts(self):
  inventories={bucket:[] for bucket in m.ASSET_BUCKETS}
  for key in ['images/same.png','imports/a/images/same.png']:
   inventories['festapp-images'].append({'Path':key,'Size':3,'MimeType':'image/png'})
  font='ticket-fonts/sha256/'+'a'*64+'.ttf'
  inventories['festapp-images-private']=[{'Path':font,'Size':3,'MimeType':'application/octet-stream'}]
  def fetch(bucket,key):
   value=b'old' if key.startswith('imports/a/') else b'new'
   return subprocess.Popen(['python3','-c','import sys;sys.stdout.buffer.write('+repr(value)+')'],stdout=subprocess.PIPE)
  stream=io.BytesIO();result=m.write_archive(inventories,fetch,stream,asset_format=True)
  self.assertEqual(result['archive_version'],2)
  with tempfile.TemporaryDirectory() as temp:
   path=Path(temp)/'fixture.tar';path.write_bytes(stream.getvalue())
   receipt=v.verify_archive(path,['https://img.festapp.net/images/same.png','https://a.img.festapp.net/images/same.png',{'bucket':'festapp-images-private','key':font}])
   self.assertTrue(receipt['consistent']);self.assertEqual(receipt['objects'],3)
   with tarfile.open(path) as archive:
    self.assertEqual(archive.extractfile('festapp-images/images/same.png').read(),b'new')
    self.assertEqual(archive.extractfile('festapp-images/imports/a/images/same.png').read(),b'old')

 def test_old_format_remains_an_explicit_historical_reader(self):
  inventories={bucket:[] for bucket in m.BUCKETS}
  inventories['festapp-images-a']=[{'Path':'images/old.png','Size':3}]
  def fetch(bucket,key):return subprocess.Popen(['python3','-c',"import sys;sys.stdout.buffer.write(b'old')"],stdout=subprocess.PIPE)
  stream=io.BytesIO();m.write_archive(inventories,fetch,stream)
  with tempfile.TemporaryDirectory() as temp:
   path=Path(temp)/'fixture.tar';path.write_bytes(stream.getvalue())
   self.assertTrue(v.verify_archive(path,['https://a.img.festapp.net/images/old.png'])['consistent'])

 def test_worker_path_contract_preserves_percent_escapes_and_private_bucket(self):
  inventories={bucket:[] for bucket in m.BUCKETS}
  inventories['festapp-images']=[{'Path':'images/space%20file.jpg','Size':3}]
  inventories['festapp-images-private']=[{'Path':'private/fixture','Size':3}]
  def fetch(bucket,key):return subprocess.Popen(['python3','-c',"import sys;sys.stdout.buffer.write(b'abc')"],stdout=subprocess.PIPE)
  stream=io.BytesIO();m.write_archive(inventories,fetch,stream)
  with tempfile.TemporaryDirectory() as temp:
   path=Path(temp)/'fixture.tar';path.write_bytes(stream.getvalue())
   result=v.verify_archive(path,['https://img.festapp.net/images/space%20file.jpg','https://img.festapp.net/private/fixture'])
   self.assertTrue(result['consistent']);self.assertEqual(result['database_r2_references_checked'],2)

 def test_dump_reference_extraction_does_not_execute_sql_and_rejects_ambiguous_input(self):
  sql='COPY public.images (id, link, name) FROM stdin;\n1\thttps://img.festapp.net/images/x\tname\n2\t\\N\tname\n\\.\nSELECT dangerous();'
  self.assertEqual(d.image_references(sql),(2,['https://img.festapp.net/images/x']))
  for value in ['SELECT 1;',sql.replace('images/x','images/\\x')]:
   with self.assertRaises(AssertionError):d.image_references(value)

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
