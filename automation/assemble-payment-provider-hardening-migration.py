#!/usr/bin/env python3
"""Verify immutable payment history and effective forward-owned definitions."""
import migration_inputs
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
from generate_canonical_source_contract import render as source_contract

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    if not parser.parse_args().check:
        raise SystemExit('Payment hardening migration is immutable; author a new forward migration')
    manifest = json.loads(migration_inputs.read_text(ROOT / 'automation/payment-provider-hardening-migration.json'))
    historical = ROOT / 'supabase/migrations' / manifest['migration']
    reset = ROOT / 'supabase/migrations/20261106210000_restore_payment_configuration_null_resets.sql'
    for target, expected in [
        (historical, '95176f853212158111d5829e6bfb2ea005d7790e03f9d32eb1e9aef03d7da979'),
        (reset, 'fc477ea3e8b7043dba1902bc67dd65385173411ea1a228a5d5a5cfc29689a46b'),
    ]:
        if target.is_symlink() or hashlib.sha256(migration_inputs.read_bytes(target)).hexdigest() != expected:
            raise SystemExit('Installed payment migration bytes changed: ' + target.name)
    # Later cash policy forwards supersede the nullable-settings snapshot too.
    # Validate current owners at the effective release head, not in old files.
    source_contract(ROOT, additional_sources=manifest['sources'])
    spec = importlib.util.spec_from_file_location('payment_integration', ROOT / 'automation/assemble-payment-provider-integration-migration.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.render()
    print('Immutable payment history and effective forward owners match')


if __name__ == '__main__':
    main()
