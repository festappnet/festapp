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
print(json.dumps(proof, sort_keys=True))
