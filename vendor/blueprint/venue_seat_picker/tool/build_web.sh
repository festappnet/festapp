#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
fvm dart tool/export_contract.dart
fvm dart tool/export_demo_seed.dart
mkdir -p web/dist web/assets/layout_fonts
cp assets/layout_fonts/* web/assets/layout_fonts/
fvm dart compile js --no-source-maps -O2 web/kernel/main.dart -o web/dist/venue_layout_kernel.js
web/node_modules/.bin/esbuild web/demo/demo.js --bundle --format=iife --target=es2020 --outfile=web/dist/demo.js
python3 - <<'PY'
import gzip,hashlib,json,pathlib,subprocess
root=pathlib.Path.cwd(); files={}
for base in ['packages/venue_layout_core/lib','web/src','web/kernel','assets/layout_fonts']:
 for p in sorted((root/base).rglob('*')):
  if p.is_file(): files[str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
code=(root/'web/dist/venue_layout_kernel.js').read_bytes()
manifest={'protocol':1,'symbolSetVersion':1,'documentVersion':2,'resourceProtocol':2,'sourceRevision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'sourceDigest':hashlib.sha256(json.dumps(files,sort_keys=True).encode()).hexdigest(),'files':files,'kernelSha256':hashlib.sha256(code).hexdigest(),'kernelBytes':len(code),'kernelGzipBytes':len(gzip.compress(code,mtime=0)),'toolchain':{k:v for k,v in json.loads(subprocess.check_output(['fvm','flutter','--version','--machine'],text=True)).items() if k in ['frameworkVersion','channel','frameworkRevision','engineRevision','dartSdkVersion']}}
(root/'web/dist/manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Kernel gzip: %d bytes'%manifest['kernelGzipBytes'])
PY
