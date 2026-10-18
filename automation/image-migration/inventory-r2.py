#!/usr/bin/env python3
"""Read-only streaming R2 inventory, run inside the protected backend context.

Uses existing read-only backup credentials, never exports them or downloads
objects to disk. Two streams bound memory and source-provider concurrency.
"""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess

BUCKETS = ('festapp-images','festapp-images-a','festapp-images-private','festapp-images-a-private')


def main():
    assert os.geteuid()==0 and os.uname().nodename.split('.')[0]=='festapp-supabase-rehearsal-01'
    config=Path('/etc/festapp-backup/images.env')
    assert config.stat().st_uid==0 and config.stat().st_mode & 0o777 == 0o600
    values={line.split('=',1)[0]:shlex.split(line.split('=',1)[1])[0] for line in config.read_text().splitlines() if line and not line.startswith('#') and '=' in line}
    assert set(values)=={'R2_SOURCE_ACCESS_KEY_ID','R2_SOURCE_SECRET_ACCESS_KEY','R2_SOURCE_ENDPOINT'}
    assert values['R2_SOURCE_ENDPOINT']=='https://84b32318ac235bf6738bdf1c8caa0795.r2.cloudflarestorage.com'
    env=os.environ.copy()
    for key,value in {'TYPE':'s3','PROVIDER':'Cloudflare','ACCESS_KEY_ID':values['R2_SOURCE_ACCESS_KEY_ID'],'SECRET_ACCESS_KEY':values['R2_SOURCE_SECRET_ACCESS_KEY'],'ENDPOINT':values['R2_SOURCE_ENDPOINT'],'NO_CHECK_BUCKET':'true'}.items():
        env['RCLONE_CONFIG_IMAGES_'+key]=value
    def listing(bucket):
        return json.loads(subprocess.check_output(['rclone','--config','/dev/null','lsjson','--recursive','--files-only','--metadata','images:'+bucket],env=env,stderr=subprocess.DEVNULL))
    inventories={bucket:listing(bucket) for bucket in BUCKETS}
    def hash_object(item):
        bucket,obj=item
        with subprocess.Popen(['rclone','--config','/dev/null','cat','images:'+bucket+'/'+obj['Path']],env=env,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL) as source:
            digest=hashlib.sha256();size=0
            while True:
                data=source.stdout.read(1024*1024)
                if not data:break
                digest.update(data);size+=len(data)
            assert source.wait()==0 and size==obj['Size'],'R2 source read failed or changed size'
        return {'source_bucket':bucket,'key':obj['Path'],'size':size,'sha256':digest.hexdigest(),'source_metadata':obj,
                'destination_bucket':('festapp-images-private' if bucket.endswith('-private') else 'festapp-images'),
                'destination_key':('imports/a/'+obj['Path'] if bucket in ('festapp-images-a','festapp-images-a-private') else obj['Path'])}
    with ThreadPoolExecutor(max_workers=2) as pool:
        objects=list(pool.map(hash_object,[(bucket,obj) for bucket,items in inventories.items() for obj in items]))
    for bucket,before in inventories.items():
        after=listing(bucket)
        fingerprint=lambda rows: sorted((o['Path'],o['Size'],o.get('ModTime'),o.get('Metadata')) for o in rows)
        assert fingerprint(before)==fingerprint(after),'R2 changed during inventory; refresh required'
    print(json.dumps({'version':1,'read_only':True,'objects':objects}))


if __name__=='__main__':main()
