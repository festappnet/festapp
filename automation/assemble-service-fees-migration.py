#!/usr/bin/env python3
"""Keep the platform fee source and disabled Wix journal migration canonical."""
import argparse
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
# This migration is already deployed and must never track mutable source bodies.
historical = root / 'supabase/migrations/20261028150000_service_fees_wix_delivery.sql'
if hashlib.sha256(historical.read_bytes()).hexdigest() != 'd6b172eaaa0979594538f3f67507247de5cb530073f0b9e4d36edf9f438d1113':
    raise SystemExit('Deployed service fee migration history changed')
sources = (
    'database/functions/service_fees/refund_sequence_expansion.sql',
    'database/tables/service_fees.sql',
    'database/functions/service_fees/source.sql',
    'database/functions/wix_billing/delivery.sql',
)
target = root / 'supabase/migrations/20261028160000_service_fee_reporting_integrity.sql'
content = '-- Immutable refund sequence, fresh contract locking and validated reporting facts.\n'
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
