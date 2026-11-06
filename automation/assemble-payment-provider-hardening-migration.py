#!/usr/bin/env python3
"""Check immutable hardening history and owners evolved by the integration forward."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    if not parser.parse_args().check:
        raise SystemExit('Payment hardening migration is immutable; use the integration forward assembler')
    manifest = json.loads((ROOT / 'automation/payment-provider-hardening-migration.json').read_text())
    historical = ROOT / 'supabase/migrations' / manifest['migration']
    if hashlib.sha256(historical.read_bytes()).hexdigest() != '95176f853212158111d5829e6bfb2ea005d7790e03f9d32eb1e9aef03d7da979':
        raise SystemExit('Installed payment hardening migration bytes changed')
    integration = json.loads((ROOT / 'automation/payment-provider-integration-migration.json').read_text())
    text = historical.read_text()
    for source in manifest['sources']:
        if source not in integration['sources'] and (ROOT / 'database/functions' / source).read_text().rstrip() not in text:
            raise SystemExit('Hardening owner needs an explicit integration forward: ' + source)
    spec = importlib.util.spec_from_file_location('payment_integration', ROOT / 'automation/assemble-payment-provider-integration-migration.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    target, expected = module.render()
    if target.read_text() != expected:
        raise SystemExit('Payment integration forward does not match current owners')
    print('Immutable hardening history and current integration owners match')

if __name__ == '__main__':
    main()
