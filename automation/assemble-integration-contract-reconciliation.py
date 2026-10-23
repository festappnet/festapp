#!/usr/bin/env python3
"""Verify installed reconciliation history and the effective canonical owners."""
import argparse
import hashlib
from pathlib import Path
from generate_canonical_source_contract import render
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
if not args.check:
    raise SystemExit('Installed reconciliation history is immutable; author a new forward migration')
target = root / 'supabase/migrations/20261018210000_integration_contract_reconciliation.sql'
if hashlib.sha256(target.read_bytes()).hexdigest() != 'face0361c63741d9324254f0cf8647094af8d1f8a7b3c731dc34d54485ad249d':
    raise SystemExit('Installed reconciliation history changed')
# Newer domain releases replace these five owners. Verify their effective
# definitions instead of rebuilding an installed migration from today's source.
render(root)
print('Integration reconciliation history and effective canonical sources: PASS')
