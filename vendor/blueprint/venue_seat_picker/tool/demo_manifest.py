#!/usr/bin/env python3
import hashlib,json,pathlib,subprocess,sys
root,kit=map(pathlib.Path,sys.argv[1:])
def run(args): return subprocess.check_output(args,cwd=root,text=True).strip()
assets=[]
for file in sorted(kit.rglob('*')):
    if file.is_file() and file!=kit/'manifest.json' and 'report' not in file.relative_to(kit).parts and not file.name.startswith('.demo-server'):
        data=file.read_bytes(); assets.append({'path':str(file.relative_to(kit)),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
sources={}
for folder in ['lib','example/lib','packages/venue_layout_core/lib','web/src','web/demo','tool']:
    for file in sorted((root/folder).rglob('*')):
        if file.is_file() and '__pycache__' not in file.parts:
            sources[str(file.relative_to(root))]=hashlib.sha256(file.read_bytes()).hexdigest()
manifest={'sourceFiles':sources,'sourceDigest':hashlib.sha256(json.dumps(sources,sort_keys=True).encode()).hexdigest(),'format':'venue-layout-demo-kit','version':1,'protocol':1,'source':run(['git','rev-parse','HEAD']),
    'sourceDirty':bool(run(['git','status','--porcelain'])),'sdk':json.loads(run(['fvm','flutter','--version','--machine'])),
    'runtime':'loopback required by Flutter loader; JS viewer can use file://','assets':assets}
(kit/'manifest.json').write_text(json.dumps(manifest,indent=2))
