#!/usr/bin/env python3
"""Verify installed sandbox history and its effective forward-owned definitions."""
from pathlib import Path
import argparse, hashlib, json
from generate_canonical_source_contract import render as source_contract
ROOT=Path(__file__).resolve().parents[1]
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true')
 if not parser.parse_args().check: raise SystemExit('Installed Barion migration is immutable; author a new forward migration')
 manifest=json.loads((ROOT/'automation/barion-sandbox-migration.json').read_text())
 target=ROOT/'supabase/migrations'/manifest['migration']
 if target.is_symlink() or hashlib.sha256(target.read_bytes()).hexdigest()!='9c5dbacf7997544ac5224391c02053d5b861fdec65278d77a76fa24d2187cb9e':
  raise SystemExit('Installed Barion migration bytes changed')
 source_contract(ROOT,additional_sources=manifest['sources'])
 print('Immutable Barion history and effective forward owners match')
if __name__=='__main__':main()
