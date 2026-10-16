"""Verify decrypted R2 archive content and chosen restored DB references.
Reads local data only; never writes or contacts an object store.
"""
import hashlib,json,tarfile
from pathlib import Path
from urllib.parse import urlparse
BUCKETS={'festapp-images','festapp-images-a','festapp-images-private','festapp-images-a-private'}
HOSTS={'img.festapp.net':'festapp-images','a.img.festapp.net':'festapp-images-a'}

def verify_archive(path,references):
 with tarfile.open(path) as archive:
  members=archive.getmembers()
  assert all(m.isfile() and not Path(m.name).is_absolute() and '..' not in Path(m.name).parts for m in members),'unsafe R2 archive member'
  names={m.name:m for m in members};assert len(names)==len(members),'duplicate R2 archive path'
  index=names['.r2-objects.json'];assert index.size<=16*1024*1024
  manifest=json.load(archive.extractfile(index));assert manifest['version']==1
  keys=set();total=0
  for obj in manifest['objects']:
   assert obj['bucket'] in BUCKETS and obj['key'] and not obj['key'].startswith('/') and '..' not in obj['key'].split('/')
   name=obj['bucket']+'/'+obj['key'];assert name not in keys;keys.add(name)
   member=names[name];assert member.size==obj['size']
   with archive.extractfile(member) as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
   assert digest==obj['sha256'],'R2 archive content hash mismatch'
   total+=member.size
  assert set(names)==keys|{'.r2-objects.json'},'unindexed R2 archive object'
  checked=0;missing=0
  for value in references:
   uri=urlparse(value)
   if uri.hostname not in HOSTS:continue
   checked+=1
   bucket=HOSTS[uri.hostname]
   if uri.path.startswith('/private/'):bucket+='-private'
   # Worker passes URL.pathname directly to R2; percent escapes stay literal.
   if bucket+'/'+uri.path.lstrip('/') not in keys:missing+=1
 return {'objects':len(keys),'bytes':total,'content_hashes_verified':True,'database_r2_references_checked':checked,'missing_database_r2_references':missing,'consistent':checked>0 and missing==0,'scope':'Selected online DB snapshot against selected R2 archive; not arbitrary-time R2 version history'}
