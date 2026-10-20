#!/usr/bin/env python3
"""Build an inspectable tar from the real pub-selected list, proving source bytes."""
import hashlib,json,pathlib,re,sys,tarfile
root=pathlib.Path(sys.argv[1]).resolve();log=pathlib.Path(sys.argv[2]).read_text();output=pathlib.Path(sys.argv[3]);source=pathlib.Path(sys.argv[4]).resolve() if len(sys.argv)>4 else root
output.parent.mkdir(parents=True,exist_ok=True)
marker='FINE: Creating .tar.gz stream containing:'
if marker not in log:raise SystemExit('No pub-generated archive file list in log')
files=[]
for line in log.rsplit(marker,1)[1].splitlines()[1:]:
 match=re.match(r'\s*\| ((?:/|\./).+)$',line)
 if not match:break
 p=pathlib.Path(match.group(1));p=(p if p.is_absolute() else root/p).resolve()
 try:rel=p.relative_to(root)
 except ValueError:raise SystemExit(f'Pub-selected path escapes package: {p}')
 if p.is_dir():continue
 if not p.is_file():raise SystemExit(f'Missing pub-selected file: {rel}')
 if any(s in rel.parts for s in ['node_modules','.dart_tool','.fvm','__pycache__']) or rel.name=='pubspec_overrides.yaml':raise SystemExit(f'Archive contamination: {rel}')
 files.append(rel)
if not files:raise SystemExit('Empty archive file list')
for rel in files:
 if re.search(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/', (root/rel).read_bytes()):raise SystemExit(f'Absolute workstation path in selected artifact: {rel}')
files=sorted(set(files));hashes={str(p):hashlib.sha256((root/p).read_bytes()).hexdigest() for p in files}
for name,digest in hashes.items():
 p=source/name
 if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=digest:raise SystemExit(f'Staged selected source differs from canonical checkout: {name}')
with tarfile.open(output,'w:gz') as tar:
 for rel in files:tar.add(root/rel,arcname=str(rel),recursive=False)
manifest={'archive':output.name,'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'files':hashes,'selection':'actual pub publish --dry-run --verbose archive list','canonicalSource':str(source),'selectionRoot':str(root),'byteEquivalentToCanonicalSource':True,'stagedOutsideGit':root!=source}
output.with_suffix('.manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'{output.name}: {len(files)} pub-selected files, {output.stat().st_size} bytes; source hashes match')
