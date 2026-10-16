#!/usr/bin/env python3
"""Stream the shared backend's R2 objects through tar -> existing age encryption.
Uses standard rclone, never changes a source object or writes plaintext files.
"""
import argparse,hashlib,io,json,os,shlex,subprocess,tarfile,time
from pathlib import Path
BUCKETS=('festapp-images','festapp-images-a','festapp-images-private','festapp-images-a-private')
CONFIG=Path('/etc/festapp-backup/images.env')

def archive_path(bucket,key):
 assert bucket in BUCKETS and key and not key.startswith('/') and '..' not in key.split('/') and '\\' not in key
 return bucket+'/'+key

def write_archive(inventories,fetch,stream):
 """All object paths/hashes stay inside the encrypted archive, not logs."""
 count=0;total=0;index=[]
 with tarfile.open(fileobj=stream,mode='w|',format=tarfile.PAX_FORMAT) as archive:
  for bucket in BUCKETS:
   seen=set()
   for obj in inventories[bucket]:
    key=obj['Path'];name=archive_path(bucket,key);assert name not in seen;seen.add(name)
    size=int(obj['Size']);assert size>=0
    member=tarfile.TarInfo(name);member.size=size;member.mode=0o600;member.mtime=int(time.time())
    source=fetch(bucket,key)
    class Reader:
     def __init__(self):self.digest=hashlib.sha256();self.read_bytes=0
     def read(self,n):
      data=source.stdout.read(n);self.digest.update(data);self.read_bytes+=len(data);return data
    reader=Reader()
    try:
     archive.addfile(member,reader)
     assert not source.stdout.read(1),'R2 object changed size during backup'
     assert source.wait()==0 and reader.read_bytes==size,'R2 object read did not complete'
    finally:
     source.stdout.close()
     if source.poll() is None:source.terminate();source.wait()
    index.append({'bucket':bucket,'key':key,'size':size,'sha256':reader.digest.hexdigest(),'source_metadata':obj})
    count+=1;total+=size
  body=json.dumps({'version':1,'objects':index},separators=(',',':')).encode()
  member=tarfile.TarInfo('.r2-objects.json');member.size=len(body);member.mode=0o600
  archive.addfile(member,io.BytesIO(body))
 return {'objects':count,'bytes':total,'buckets':list(BUCKETS)}

def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 assert os.geteuid()==0 and os.uname().nodename.split('.')[0]=='festapp-supabase-rehearsal-01'
 assert CONFIG.stat().st_uid==0 and CONFIG.stat().st_mode&0o777==0o600
 assert not a.output.exists() and a.output.name=='r2-images.tar.age'
 recipient=os.environ['AGE_RECIPIENT'];assert recipient.startswith('age1')
 values={line.split('=',1)[0]:shlex.split(line.split('=',1)[1])[0] for line in CONFIG.read_text().splitlines() if line and not line.startswith('#') and '=' in line}
 assert set(values)=={'R2_SOURCE_ACCESS_KEY_ID','R2_SOURCE_SECRET_ACCESS_KEY','R2_SOURCE_ENDPOINT'}
 assert values['R2_SOURCE_ENDPOINT']=='https://84b32318ac235bf6738bdf1c8caa0795.r2.cloudflarestorage.com'
 env=os.environ.copy()
 for key,value in {'TYPE':'s3','PROVIDER':'Cloudflare','ACCESS_KEY_ID':values['R2_SOURCE_ACCESS_KEY_ID'],'SECRET_ACCESS_KEY':values['R2_SOURCE_SECRET_ACCESS_KEY'],'ENDPOINT':values['R2_SOURCE_ENDPOINT'],'NO_CHECK_BUCKET':'true'}.items():env['RCLONE_CONFIG_IMAGES_'+key]=value
 os.umask(0o077);inventories={}
 for bucket in BUCKETS:
  inventories[bucket]=json.loads(subprocess.check_output(['rclone','--config','/dev/null','lsjson','--recursive','--files-only','--metadata','images:'+bucket],env=env,stderr=subprocess.DEVNULL))
 def fetch(bucket,key):return subprocess.Popen(['rclone','--config','/dev/null','cat','images:'+bucket+'/'+key],env=env,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
 with subprocess.Popen(['age','-r',recipient,'-o',str(a.output)],stdin=subprocess.PIPE,stderr=subprocess.DEVNULL) as age:
  try:
   result=write_archive(inventories,fetch,age.stdin);age.stdin.close();assert age.wait()==0
  except Exception:
   age.stdin.close();age.terminate();age.wait();raise RuntimeError('R2 archive failed; no source changes or plaintext files') from None
 print(json.dumps({'encrypted_r2_image_archive':True,**result}))

if __name__=='__main__':main()
