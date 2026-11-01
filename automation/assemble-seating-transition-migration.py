#!/usr/bin/env python3
"""Assemble/check the local, unapplied seating transition forward migration."""
import argparse
import hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PREDECESSOR='2a2f66af6ce91616810eed35d19c96f728a550f8'
TARGET=ROOT/'supabase/migrations/20261101120000_blueprint_existing_admission_seating.sql'
SOURCES=[
 'blueprint/seating_transition_schema.sql',
 'user_permissions/seating_transition_operations.sql',
 'blueprint/seating_transition_context.sql',
 'blueprint/seating_transition_lifecycle.sql',
 'inventory/lock_spot_assignment_scope_internal_v1.sql',
 'inventory/apply_allocations.sql',
 'blueprint/seating_assignment.sql',
 'blueprint/seating_publication.sql',
 'blueprint/save.sql',
 'eshop/update_product_client_sync_v1.sql',
 'eshop_waitlist/form_capacity.sql',
 'eshop/materialize_ticket_products_internal_v1.sql',
 'others/update_occasion.sql',
 'others/save_occasion_domain_command_internal_v1.sql',
 'eshop_forms/update_form_client_sync_v1.sql',
 'eshop_forms/update_form.sql',
 'eshop_forms/delete_form_internal_v1.sql',
 'eshop_forms/duplicate_form_to_occasion.sql',
 'eshop_forms/duplicate_form_to_occasion_client_sync_v1.sql',
 'others/delete_occasion.sql',
 'eshop/get_blueprint_for_edit.sql',
 'eshop/order_seating.sql',
 'eshop/get_order_history.sql',
 'eshop/get_ticket_details_for_generating.sql',
 'eshop_orders/operator_orders.sql',
 'blueprint/seating_transition_sync.sql',
]
def render():
 out=['-- Forward correction: the superseded uncommitted prototype is retained\n-- because no complete live-ledger absence proof is available. Never release\n-- that migration alone; this source-matched migration owns the final contract.\n']
 for source in SOURCES:
  data=(ROOT/'database/functions'/source).read_text()
  out.append(f'\n-- Source: database/functions/{source}\n-- SHA256: {hashlib.sha256(data.encode()).hexdigest()}\n{data.rstrip()}\n')
 out.append("\nNOTIFY pgrst, 'reload schema';\n")
 return ''.join(out)
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--check',action='store_true')
 args=parser.parse_args()
 expected=render()
 if args.check:
  if not TARGET.exists() or TARGET.read_text()!=expected:raise SystemExit('Seating transition migration/source mismatch')
  print(f'Seating migration matches {len(SOURCES)} canonical SQL sources')
 else:TARGET.write_text(expected)
