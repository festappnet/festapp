#!/usr/bin/env python3
"""Verify immutable connector migration and its archived exact source inputs."""
from pathlib import Path
import argparse, hashlib, json
ROOT = Path(__file__).resolve().parents[1]
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    if not parser.parse_args().check:
        raise SystemExit('Connector migration is frozen. Use assemble-payment-provider-hardening-migration.py.')
    archive = ROOT / 'docs/plans/payment-provider-hardening'
    for name, digest in json.loads((archive/'frozen-inputs.json').read_text())['files'].items():
        if hashlib.sha256((archive/'history'/name).read_bytes()).hexdigest() != digest:
            raise SystemExit('Changed archived connector input: '+name)
        if name.startswith('supabase/migrations/') and hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != digest:
            raise SystemExit('Changed frozen connector migration: '+name)
    historical = archive/'history'
    manifest = json.loads((historical/'automation/payment-provider-migration.json').read_text())
    parts = ['-- Payment provider connectors. Forward-only; no provider activation or production application.']
    for source in manifest['sources']:
        body = (historical/'database/functions'/source).read_text().rstrip()
        if source.startswith(('payment_providers/','eshop_stripe/')):
            body = 'SET LOCAL ROLE postgres;\n'+body+'\nRESET ROLE;'
        parts.append('-- SOURCE: '+source+'\n'+body)
    if '\n\n'.join(parts)+'\n' != (historical/'supabase/migrations'/manifest['migration']).read_text():
        raise SystemExit('Historical connector inputs do not reproduce the frozen migration')
    print('Connector migration and exact reproducible historical inputs unchanged')
if __name__ == '__main__': main()
