#!/usr/bin/env python3
"""Vendor pinned harfbuzzjs with embedded WASM loading for Edge workers."""
import base64
import hashlib
import json
from pathlib import Path
import sys

source = Path(sys.argv[1])
if json.loads((source / 'package.json').read_text())['version'] != '1.6.3':
    raise SystemExit('Expected harfbuzzjs 1.6.3')
target = Path(__file__).resolve().parents[1] / 'supabase/functions/_shared/vendor/harfbuzzjs'
target.mkdir(parents=True, exist_ok=True)
files = ['dist/index.mjs', 'dist/index.d.mts', 'dist/harfbuzz.js', 'dist/harfbuzz.wasm', 'LICENSE']
manifest = {name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in files}
proof = target / 'upstream-sha256.json'
if proof.exists() and json.loads(proof.read_text()) != manifest:
    raise SystemExit('Pinned upstream content changed')
for name in files:
    data = (source / name).read_bytes()
    if name == 'dist/index.mjs':
        original = b'init(await createHarfBuzz());'
        if data.count(original) != 1:
            raise SystemExit('Upstream initialization changed')
        data = b'import wasmBase64 from "./harfbuzz.wasm.json" with {type: "json"};\n' + data.replace(original, b'init(await createHarfBuzz({wasmBinary: Uint8Array.from(atob(wasmBase64), c => c.charCodeAt(0))}));')
    if name == 'dist/harfbuzz.wasm':
        (target / 'harfbuzz.wasm.json').write_text(json.dumps(base64.b64encode(data).decode()) + '\n')
        (target / 'harfbuzz.wasm').unlink(missing_ok=True)
        continue
    if name == 'dist/index.d.mts':
        data = b'// The Edge build passes only wasmBinary to the private module factory.\ninterface EmscriptenModule {}\n' + data
    (target / Path(name).name).write_bytes(data)
proof.write_text(json.dumps(manifest, indent=2) + '\n')
