#!/usr/bin/env python3
"""Assemble the forward cutover from separate plan publication to ordinary save."""
import argparse
import hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
TARGET=ROOT/'supabase/migrations/20261110220000_automatic_form_blueprints.sql'
SOURCES=[
 'eshop_waitlist/form_capacity.sql',
 'blueprint/form_binding.sql',
 'blueprint/seating_context.sql',
 'blueprint/seating_assignment.sql',
 'blueprint/admission_seating.sql',
 'blueprint/save.sql',
 'eshop_forms/update_form.sql',
 'eshop_forms/form_creation_domain.sql',
 'others/update_occasion.sql',
 'eshop_forms/delete_form_internal_v1.sql',
 'others/delete_occasion.sql',
 'eshop/order_seating.sql',
 'eshop_orders/get_order_admin_detail.sql',
 'eshop/materialize_ticket_products_internal_v1.sql',
 'blueprint/retire_publication.sql',
 'blueprint/seating_sync.sql',
 'others/get_ticket_layout_write_contract_v1.sql',
]
def render():
 out=['-- Saved plans are immediately available to enabled form seat selectors.\n-- The existing form availability window remains the only public sales gate.\n']
 for source in SOURCES:
  data=(ROOT/'database/functions'/source).read_text()
  out.append(f'\n-- Source: database/functions/{source}\n-- SHA256: {hashlib.sha256(data.encode()).hexdigest()}\n{data.rstrip()}\n')
 out.append("\nNOTIFY pgrst, 'reload schema';\n")
 return ''.join(out)
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--check',action='store_true')
 args=parser.parse_args();expected=render()
 if args.check:
  if not TARGET.exists() or TARGET.read_text()!=expected:raise SystemExit('Automatic seating migration is stale')
  print('Automatic seating migration matches canonical sources')
 else:TARGET.write_text(expected)
