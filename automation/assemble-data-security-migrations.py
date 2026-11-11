#!/usr/bin/env python3
"""Verify immutable installed release artifacts and the current canonical catalog."""
import migration_inputs
import argparse
import hashlib
import json
from pathlib import Path
from generate_canonical_source_contract import render
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');p.add_argument('--output');args=p.parse_args()
if args.output or not args.check:raise SystemExit('Installed security history is immutable; author a new forward migration')
release=json.loads(migration_inputs.read_text(root/'automation/hetzner-supabase/runtime/data-security-release.json'))
for phase in release['phases']:
    payload=migration_inputs.read_bytes(root/phase['file'])
    if hashlib.sha256(payload).hexdigest()!=phase['sha256']:raise SystemExit('Installed migration changed: '+phase['file'])
    driver=migration_inputs.read_bytes(root/phase['driver'])
    if payload not in driver:raise SystemExit('Historical driver lost its exact migration')
    if 'driver_sha256' in phase and hashlib.sha256(driver).hexdigest()!=phase['driver_sha256']:raise SystemExit('Historical driver changed')
render(root)
print('Security history and effective canonical sources: PASS')
