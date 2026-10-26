#!/usr/bin/env python3
"""Verify the immutable Blueprint migration; current parity has one generator.

New source changes belong in forward migrations. The former domain-only parity
artifact is superseded by generate_canonical_source_contract.py, which now
includes all of this migration's canonical sources and effective later owners.
"""
import argparse
import hashlib
from pathlib import Path
from generate_canonical_source_contract import render, TARGET as PARITY_TARGET
ROOT=Path(__file__).resolve().parents[1]
TARGET=ROOT/'supabase/migrations/20261021010000_blueprint_reservation_integrity.sql'
FROZEN_SHA256='f5e137f068223398e0cb4705c732aaf1f7d9f473d5448da31dbae3437eaa3019'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check',action='store_true')
args=parser.parse_args()
if not args.check:
    raise SystemExit('Applied migration is immutable; author a new forward migration. Current parity: automation/generate_canonical_source_contract.py')
if hashlib.sha256(TARGET.read_bytes()).hexdigest()!=FROZEN_SHA256:
    raise SystemExit('Immutable Blueprint migration changed')
if hashlib.sha256((ROOT/'supabase/migrations/20261021020000_blueprint_release_integration.sql').read_bytes()).hexdigest()!='98da54019793ebe446323b69d2a273544c788c4cff0753a9a82f8225b6348918':
    raise SystemExit('Immutable Blueprint release integration migration changed')
if PARITY_TARGET.read_text()!=render():
    raise SystemExit('Current canonical SQL source parity is stale')
print('Immutable Blueprint migration and current canonical parity verified')
