#!/usr/bin/env python3
"""Keep the platform fee source and disabled Wix journal migration canonical."""
import argparse
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sources = (
    'database/tables/service_fees.sql',
    'database/functions/service_fees/source.sql',
    'database/tables/wix_billing_delivery.sql',
    'database/functions/wix_billing/delivery.sql',
)
target = root / 'supabase/migrations/20261028150000_service_fees_wix_delivery.sql'
content = '-- Canonical service fee source and disabled Wix delivery journal. No business facts seeded.\n'
content += ''.join('\n-- Source: ' + source + '\n' + (root / source).read_text() for source in sources)
content += "\nNOTIFY pgrst, 'reload schema';\n"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
if args.check:
    if not target.exists() or target.read_text() != content:
        raise SystemExit('Service fee migration differs from canonical sources')
else:
    target.write_text(content)
