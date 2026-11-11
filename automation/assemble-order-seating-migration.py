#!/usr/bin/env python3
"""Verify the immutable order-seating migration and shared current SQL parity."""
import migration_inputs
import argparse
import hashlib
from pathlib import Path
from generate_canonical_source_contract import render, TARGET
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check',action='store_true')
args=parser.parse_args()
if not args.check:
    raise SystemExit('Applied migration is immutable; author a new forward migration. Current parity: automation/generate_canonical_source_contract.py')
if hashlib.sha256(migration_inputs.read_bytes(ROOT/'supabase/migrations/20261021040000_order_seating.sql')).hexdigest()!='201564ec915bcd996e6523418df373504484e646612f6644bbcf5a1b778f239b':
    raise SystemExit('Immutable order-seating migration changed')
if migration_inputs.read_text(TARGET)!=render():
    raise SystemExit('Current canonical SQL parity is stale')
print('Immutable order-seating migration and current canonical parity verified')
