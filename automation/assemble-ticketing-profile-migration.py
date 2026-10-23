#!/usr/bin/env python3
"""Assemble the forward ticketing profile contract without rewriting old migrations."""
from pathlib import Path
import argparse
import subprocess
ROOT = Path(__file__).resolve().parents[1]
# Already deployed: preserve the exact original source contract. Later changes
# belong in forward migrations, never a rewritten 2300 ledger entry.
SOURCE_REVISION = '044796108b9de89c7820f65d7fa24ec4780b5046'
def source_text(source):
    return subprocess.check_output(['git', '-C', str(ROOT), 'show',
        SOURCE_REVISION + ':database/functions/' + source], text=True)

SOURCES = ['catalog/source_policy.sql', 'others/get_available_occasions.sql',
           'others/get_public_occasions.sql', 'others/get_occasion_seo_data.sql',
           'eshop_stripe/checkout_locale.sql', 'eshop_forms/form_creation_domain.sql',
           'eshop_stripe/form_availability.sql', 'eshop_forms/duplicate_form_to_occasion.sql',
           'occasion_setup/drafts.sql', 'occasion_setup/finalize.sql', 'eshop_orders/update_scan_code.sql', 'eshop/seating_worker_access.sql', 'eshop/get_ticket_details_for_generating.sql', 'eshop/get_order_details_for_email.sql', 'emails/email_queue.sql', 'emails/fakturoid_email_gate.sql',
           'eshop_stripe/order_creation.sql', 'eshop_stripe/checkout.sql']
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
target = ROOT / 'supabase/migrations/20261023230000_ticketing_profiles.sql'
body = '-- Shared ticketing profiles. No production provisioning or Stripe activation.\n\n'
feature = source_text('eshop_stripe/feature_settings.sql')
feature = feature[feature.index('CREATE OR REPLACE FUNCTION public.stripe_unit_feature_enabled_internal'):feature.index('CREATE OR REPLACE FUNCTION public.set_stripe_unit_feature')]
body += '-- SOURCE: eshop_stripe/feature_settings.sql (discovery function only)\n' + feature + '\n'
body += '\n\n'.join('-- SOURCE: ' + source + '\n' + source_text(source).rstrip() for source in SOURCES) + '\n'
if args.check:
    if not target.exists() or target.read_text() != body: raise SystemExit('Ticketing profile migration is stale')
else: target.write_text(body)
print('Ticketing profile migration matches sources' if args.check else 'Assembled ticketing profile migration')
