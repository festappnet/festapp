#!/usr/bin/env python3
"""Verify staged immutable ticket assets and emit their manifest proof."""
import hashlib
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
catalog_bytes = (root / 'font-catalog.json').read_bytes()
catalog = json.loads(catalog_bytes)
proof = {'font-catalog.json': {'sha256': hashlib.sha256(catalog_bytes).hexdigest(), 'bytes': len(catalog_bytes)}}
for asset in catalog['fonts']:
    if asset['source'] != 'bundled':
        continue
    name = asset['file']
    if pathlib.Path(name).name != name:
        raise ValueError('Unbounded font asset path')
    data = (root / name).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != asset['sha256'] or len(data) != asset['byteLength']:
        raise ValueError('Ticket asset integrity: ' + name)
    proof[name] = {'sha256': digest, 'bytes': len(data)}
manifest_bytes = (root / 'preview-manifest.json').read_bytes()
manifest = json.loads(manifest_bytes)
payload = manifest_bytes.decode().strip().rsplit(',"sha256":', 1)[0] + '}'
if hashlib.sha256(payload.encode()).hexdigest() != manifest['sha256']:
    raise ValueError('Preview manifest integrity')
proof['preview-manifest.json'] = {'sha256': hashlib.sha256(manifest_bytes).hexdigest(), 'bytes': len(manifest_bytes)}
for asset in [*manifest['fonts'].values(), *manifest['artwork'].values()]:
    name = asset['file']
    if '..' in pathlib.PurePosixPath(name).parts or pathlib.PurePosixPath(name).is_absolute():
        raise ValueError('Unbounded preview asset path')
    data = (root / name).read_bytes()
    if hashlib.sha256(data).hexdigest() != asset['sha256'] or len(data) != asset['byteLength']:
        raise ValueError('Preview asset integrity: ' + name)
    proof[name] = {'sha256': asset['sha256'], 'bytes': len(data)}
print(json.dumps(proof, sort_keys=True))
