#!/usr/bin/env python3
"""Verify installed foundation bytes and current owners without rewriting history."""
import argparse
import hashlib
from pathlib import Path
from generate_canonical_source_contract import render

ROOT = Path(__file__).resolve().parents[1]
INSTALLED = ROOT / 'supabase/migrations/20261020120000_canonical_operations_foundation.sql'
INSTALLED_SHA256 = '83709f07dadf93094974385d4c2c43605c936ccd79112780c8533454e34f2a60'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.output:
        raise SystemExit('Installed foundation is immutable; author a new forward migration')
    if INSTALLED.is_symlink() or hashlib.sha256(INSTALLED.read_bytes()).hexdigest() != INSTALLED_SHA256:
        raise SystemExit('Installed operations foundation was changed')
    # One source-contract parser owns final-definition comparison, including
    # later corrections and retirement; historical assembly is no longer live.
    render(ROOT)


if __name__ == '__main__':
    main()
