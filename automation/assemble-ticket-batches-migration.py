#!/usr/bin/env python3
"""Assemble the one new batch feature migration; installed history is immutable."""
import migration_inputs
import argparse
import hashlib
from generate_canonical_source_contract import render
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    manifest = json.loads(migration_inputs.read_text(ROOT/'automation/ticket-batches-sources.json'))
    target = ROOT/manifest['migration']
    if target.name != '20261024020000_pregenerated_ticket_batches.sql' or target.is_symlink():
        raise SystemExit('Refusing another migration target')
    sources = manifest['sources']
    if len(sources) != len(set(sources)): raise SystemExit('Duplicate source')
    expected_sha256 = 'dad0ef111e05a7154ceaee99fc97e0d5b5c83badf24077cacea54155c5b4630c'
    if not migration_inputs.exists(target) or hashlib.sha256(migration_inputs.read_bytes(target)).hexdigest() != expected_sha256:
        raise SystemExit('Installed ticket-batch migration bytes changed')
    if not args.check:
        raise SystemExit('Installed ticket-batch migration is immutable; author a new forward migration')
    # Later forwards may intentionally deepen these same canonical owners.
    # Compare their final definitions using the one source-contract parser.
    render(ROOT)
if __name__ == '__main__': main()
