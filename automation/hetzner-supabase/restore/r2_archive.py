"""Verify decrypted R2 archive content and chosen restored DB references.
Reads local data only; never writes or contacts an object store.
"""
import hashlib,json,sys,tarfile
from pathlib import Path
from urllib.parse import urlparse
LEGACY_BUCKETS={'festapp-images','festapp-images-a','festapp-images-private','festapp-images-a-private'}
BUCKETS={'festapp-images','festapp-images-private'}
HOSTS={'img.festapp.net':'festapp-images','a.img.festapp.net':'festapp-images-a'}

def application_references(value,owned_hosts):
 # Reuse the exact structural HTML/CSS/JSON parser used for migration. Pack it
 # alongside the recovery sources; a missing parser is an error, never a skip.
 sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'image-migration'))
 from storage_references import URL,decoded_spans,inspect_value
 assert not list(inspect_value(value,owned_hosts)),'Current application field still contains owned Storage references'
 def walk(item):
  if isinstance(item,dict):
   for key,child in item.items():yield from walk(key);yield from walk(child)
  elif isinstance(item,list):
   for child in item:yield from walk(child)
  elif isinstance(item,str):
   try:nested=json.loads(item)
   except (ValueError,TypeError):nested=None
   if isinstance(nested,(dict,list,str)):
    yield from walk(nested);return
   decoded,_=decoded_spans(item)
   for match in URL.finditer(decoded):
    url=match[0];uri=urlparse('https:'+url if url.startswith('//') else url)
    if uri.hostname in HOSTS or uri.hostname=='image-api.festapp.net':
     assert uri.scheme=='https' and not uri.port and not uri.username and not uri.password,'Unsafe owned R2 origin'
     yield uri.geturl()
 return list(walk(value))

def verify_archive(path,references):
 with tarfile.open(path) as archive:
  members=archive.getmembers()
  assert all(m.isfile() and not Path(m.name).is_absolute() and '..' not in Path(m.name).parts for m in members),'unsafe R2 archive member'
  names={m.name:m for m in members};assert len(names)==len(members),'duplicate R2 archive path'
  index=names['.r2-objects.json'];assert index.size<=16*1024*1024
  manifest=json.load(archive.extractfile(index));assert manifest['version'] in (1,2)
  # v1 is a retained historical backup boundary, never an application fallback.
  legacy=manifest['version']==1
  allowed=LEGACY_BUCKETS if legacy else BUCKETS
  if not legacy:
   assert manifest['format']=='festapp-assets' and set(manifest['buckets'])==BUCKETS
  keys=set();objects={};total=0
  for obj in manifest['objects']:
   assert obj['bucket'] in allowed and obj['key'] and not obj['key'].startswith('/') and '..' not in obj['key'].split('/')
   name=obj['bucket']+'/'+obj['key'];assert name not in keys;keys.add(name);objects[name]=obj
   member=names[name];assert member.size==obj['size']
   with archive.extractfile(member) as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
   assert digest==obj['sha256'],'R2 archive content hash mismatch'
   total+=member.size
  assert set(names)==keys|{'.r2-objects.json'},'unindexed R2 archive object'
  checked=0;missing=0;mismatch=0
  for value in references:
   if isinstance(value,dict):
    assert set(value) in ({'bucket','key'},{'bucket','key','sha256','bytes','content_type'}) and value['bucket'] in allowed
    checked+=1
    obj=objects.get(value['bucket']+'/'+value['key'])
    if obj is None:missing+=1
    elif 'sha256' in value:
     metadata=obj['source_metadata']
     content_type=metadata.get('Metadata',{}).get('content-type') or metadata.get('MimeType')
     if value['sha256']!=obj['sha256'] or value['bytes']!=obj['size'] or value['content_type']!=content_type:mismatch+=1
    continue
   uri=urlparse(value)
   if uri.hostname not in HOSTS and uri.hostname!='image-api.festapp.net':continue
   checked+=1
   if uri.hostname=='image-api.festapp.net':
    assert uri.path.startswith('/private/'),'unsupported control reference'
    bucket='festapp-images-private'
    from urllib.parse import parse_qs
    project=parse_qs(uri.query).get('projectId',['default'])[0]
    assert project in ('default','a','slunovrat')
    is_a=project=='a'
    if legacy and is_a:bucket='festapp-images-a-private'
   else:
    bucket=HOSTS[uri.hostname]
    is_a=uri.hostname=='a.img.festapp.net'
    if uri.path.startswith('/private/'):bucket+='-private'
    if not legacy and is_a:bucket='festapp-images-private' if uri.path.startswith('/private/') else 'festapp-images'
   # Worker passes URL.pathname directly to R2; percent escapes stay literal.
   key=uri.path.lstrip('/')
   if not legacy and is_a:key='imports/a/'+key
   if bucket+'/'+key not in keys:missing+=1
 return {'objects':len(keys),'bytes':total,'content_hashes_verified':True,'database_r2_references_checked':checked,'missing_database_r2_references':missing,'mismatched_database_r2_references':mismatch,'consistent':checked>0 and missing==0 and mismatch==0,'scope':'Selected online DB snapshot against selected R2 archive; not arbitrary-time R2 version history'}
