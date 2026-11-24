#!/usr/bin/env python3
"""Assemble the forward migration for purchase seating metadata."""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    'eshop/seating_labels.sql': None,
    'eshop/order_seating.sql': None,
    'eshop/get_tickets_with_details.sql': None,
    'eshop/get_ticket_details_for_generating.sql': None,
    'eshop_orders/get_order_change_summary_v1.sql': None,
    'eshop_waitlist/order_overview.sql': 'get_customer_order_overview_internal',
    'scanning/projection.sql': None,
}
TARGET = ROOT / 'supabase/migrations/20261124163000_typed_seating_labels.sql'


def render():
    parts = ['-- Carry typed seating metadata through existing authorized readers.']
    for source, name in SOURCES.items():
        text = (ROOT / 'database/functions' / source).read_text()
        if name:
            text = re.search(rf'CREATE OR REPLACE FUNCTION public\.{name}\([\s\S]*?\$\$;', text).group()
        parts.append(f'-- SOURCE: {source}\n{text.rstrip()}')
    return '\n\n'.join(parts) + "\n\nNOTIFY pgrst, 'reload schema';\n"


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    expected = render()
    if args.check:
        if TARGET.read_text() != expected:
            raise SystemExit('Typed seating migration is stale')
    else:
        TARGET.write_text(expected)
