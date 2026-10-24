"""Deterministic independent ZIPs, generated from canonical shared sources."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys,zipfile
root=Path(__file__).resolve().parents[1]
products=json.loads((root/'products.json').read_text())
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--product',choices=[p['slug'] for p in products])
selected=parser.parse_args().product
subprocess.run([sys.executable,str(root/'scripts/build-plugins.py'),*(['--product',selected] if selected else [])],check=True)
products=[p for p in products if selected is None or p['slug']==selected]
out=root/'dist';out.mkdir(exist_ok=True)
for product in products:
 slug=product['slug'];version=product['version'];plugin=root/slug
 files=sorted(p for p in plugin.rglob('*') if p.is_file())
 allowed={'.php','.js','.json','.css','.txt','.pot','.po','.mo'}
 for p in files:
  if p.suffix not in allowed or p.is_symlink():raise SystemExit('Unexpected package input: '+p.name)
 for p in [plugin/(slug+'.php'),plugin/'readme.txt',plugin/'blocks/ticket-form/block.json']:
  if version not in p.read_text():raise SystemExit('Version mismatch: '+str(p))
 archive=out/f'{slug}-{version}.zip'
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for p in files:
   info=zipfile.ZipInfo(slug+'/'+p.relative_to(plugin).as_posix(),(2026,10,23,0,0,0));info.external_attr=0o100644<<16;info.compress_type=zipfile.ZIP_DEFLATED;z.writestr(info,p.read_bytes())
 digest=hashlib.sha256(archive.read_bytes()).hexdigest();(out/(archive.name+'.sha256')).write_text(f'{digest}  {archive.name}\n')
 manifest={p.relative_to(plugin).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
 (root/'evidence'/(slug+'-package-inputs.json')).write_text(json.dumps(manifest,indent=2)+'\n')
 if slug=='vstupenky-online':(root/'evidence/package-inputs.json').write_text(json.dumps(manifest,indent=2)+'\n')
 print(f'{archive.name}: {len(files)} files; SHA-256 {digest}')
