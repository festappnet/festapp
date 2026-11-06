#!/usr/bin/env python3
"""Reconcile provider support with canonical measurement, presale and email owners."""
from pathlib import Path
import argparse
import json

ROOT = Path(__file__).resolve().parents[1]

def render():
    manifest = json.loads((ROOT / 'automation/payment-provider-integration-migration.json').read_text())
    parts = ['-- Payment provider canonical integration. No provider activation or network jobs.']
    for source in manifest['sources']:
        parts.append('-- SOURCE: ' + source + '\n' + (ROOT / 'database/functions' / source).read_text().rstrip())
    return ROOT / 'supabase/migrations' / manifest['migration'], '\n\n'.join(parts) + '\n'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target, content = render()
    if args.check:
        if target.read_text() != content:
            raise SystemExit('Payment provider integration migration is stale')
        print('Payment provider integration sources match')
    else:
        target.write_text(content)

if __name__ == '__main__':
    main()
