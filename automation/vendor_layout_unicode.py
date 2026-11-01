#!/usr/bin/env python3
"""Vendor pinned Unicode properties with the upstream in-memory trie loader."""
import hashlib
import json
from pathlib import Path
import sys

source = Path(sys.argv[1])
if json.loads((source / 'package.json').read_text())['version'] != '2.0.1':
    raise SystemExit('Expected unicode-properties 2.0.1')
target = Path(__file__).resolve().parents[1] / 'supabase/functions/_shared/vendor/unicode-properties'
files = ['index.js', 'data.js', 'data.base64.trie.js', 'binaryTrie.browser.js', 'LICENSE']
manifest = {name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in files}
proof = target / 'upstream-sha256.json'
if proof.exists() and json.loads(proof.read_text()) != manifest:
    raise SystemExit('Pinned upstream content changed')
target.mkdir(parents=True, exist_ok=True)
for name in files:
    data = (source / name).read_bytes()
    if name == 'index.js':
        trie = b"from 'unicode-trie'"
        loader = b"from '#binary-trie'"
        if data.count(trie) != 1 or data.count(loader) != 1:
            raise SystemExit('Upstream initialization changed')
        data = data.replace(trie, b"from 'npm:unicode-trie@3.0.0'")
        data = data.replace(loader, b"from './binaryTrie.browser.js'")
    (target / name).write_bytes(data)
proof.write_text(json.dumps(manifest, indent=2) + '\n')
