#!/usr/bin/env python3
"""Assemble the canonical group-default removal fix for all blueprint saves."""
import argparse
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'supabase/migrations/20261112200000_blueprint_group_default_removal.sql'
SOURCE = 'blueprint/save.sql'
def render():
    return '-- Accept scoped product-default removal when a blueprint group is removed.\n\n-- SOURCE: '+SOURCE+'\n'+(ROOT/'database/functions'/SOURCE).read_text().rstrip()+'\n'
if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args(); expected=render()
    if args.check:
        if not TARGET.is_file() or TARGET.read_text()!=expected:
            raise SystemExit('Blueprint group-default migration differs from canonical source')
        from generate_canonical_source_contract import render as source_contract
        source_contract(ROOT,additional_sources=[SOURCE])
        print('Blueprint group-default migration and canonical source match')
    else: TARGET.write_text(expected)
