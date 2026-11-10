#!/usr/bin/env python3
"""Verify the immutable installed seating migration and current source parity."""
import argparse
import hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
TARGET=ROOT/'supabase/migrations/20261101120000_blueprint_existing_admission_seating.sql'
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--check',action='store_true')
 args=parser.parse_args()
 if args.check:
  if hashlib.sha256(TARGET.read_bytes()).hexdigest()!='b9019892b53a721a582b44801afe5fb274b66b6c83ea975f2fa00e80ef714b88':
   raise SystemExit('Applied seating migration changed')
  from generate_canonical_source_contract import render as current_contract, TARGET as contract_target
  if contract_target.read_text()!=current_contract():raise SystemExit('Current canonical source parity is stale')
  print('Immutable seating migration and current canonical parity verified')
 else:raise SystemExit('Applied seating migration is immutable; author a forward migration')
