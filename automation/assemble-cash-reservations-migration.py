#!/usr/bin/env python3
"""Verify immutable cash reservation history against effective forward-owned sources."""
import migration_inputs
from pathlib import Path
import argparse
import hashlib
import json
from generate_canonical_source_contract import render as source_contract

ROOT = Path(__file__).resolve().parents[1]
INSTALLED_SHA256 = 'faca691eb97680b060d4bedda89fedb7d3c2ba5ab4b29212fd4871d9f14791f0'


def render(root=ROOT):
    manifest = json.loads(migration_inputs.read_text(root / 'automation/cash-reservations-migration.json'))
    target = root / 'supabase/migrations' / manifest['migration']
    if target.is_symlink() or hashlib.sha256(migration_inputs.read_bytes(target)).hexdigest() != INSTALLED_SHA256:
        raise ValueError('Installed cash reservation migration bytes changed')
    # Later forward migrations legitimately supersede some
    # installed cash reservation bodies. Compare their final effective definitions using the
    # same parser as the canonical catalog contract, never rewrite old SQL.
    source_contract(root, additional_sources=manifest['sources'])
    return target, migration_inputs.read_text(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    if not parser.parse_args().check:
        raise SystemExit('Installed cash reservation is immutable; author a new forward migration')
    render()
    print('Immutable cash reservation history and effective owners match')


if __name__ == '__main__':
    main()
