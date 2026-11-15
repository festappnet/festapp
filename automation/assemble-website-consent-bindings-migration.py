#!/usr/bin/env python3
"""Verify immutable website consent migration and current source parity."""
import argparse
import hashlib
from pathlib import Path
from generate_canonical_source_contract import render, TARGET
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check',action='store_true')
if not parser.parse_args().check:
 raise SystemExit('Applied migration is immutable; author a forward migration')
if hashlib.sha256((ROOT/'supabase/migrations/20261114170000_website_consent_bindings.sql').read_bytes()).hexdigest()!='2e1b565e386b3b2fd85cff7bfa82ea9dba22eb867a7121dc382738f163a7fecd':
 raise SystemExit('Immutable website consent migration changed')
if TARGET.read_text()!=render(): raise SystemExit('Current canonical source parity is stale')
print('Immutable website consent migration and current source parity verified')
