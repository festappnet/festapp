#!/usr/bin/env python3
"""Assemble the seat-swap lifecycle forward from canonical SQL owners."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'supabase/migrations/20261112190000_seat_swap_lifecycle.sql'
SOURCES = (
    'eshop_orders/recalculate_order_payment_status.sql',
    'eshop/swap_spot_tickets.sql',
    'blueprint/apply_seat_swap_internal.sql',
    'eshop_orders/get_order_change_summary_v1.sql',
)


def render():
    parts = ['-- Reconcile seat swaps through the shared payment lifecycle and expose seating changes in customer updates.']
    for source in SOURCES:
        parts.append('-- SOURCE: ' + source + '\n' + (ROOT / 'database/functions' / source).read_text().rstrip())
    return '\n\n'.join(parts) + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    expected = render()
    if args.check:
        if not TARGET.is_file() or TARGET.read_text() != expected:
            raise SystemExit('Seat-swap migration differs from canonical owners')
        from generate_canonical_source_contract import render as source_contract
        source_contract(ROOT, additional_sources=SOURCES)
        print('Seat-swap migration and effective canonical owners match')
    else:
        TARGET.write_text(expected)
