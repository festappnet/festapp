#!/usr/bin/env python3
"""Assemble the forward admin deletion/context correction; leave published history intact."""
import migration_inputs
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    'database/functions/eshop_orders/delete_order.sql',
    'database/functions/eshop_orders/delete_order_client_sync_v1.sql',
    'database/functions/eshop_forms/get_form_by_link.sql',
    'database/functions/eshop_waitlist/capabilities.sql',
]
TARGET = ROOT / 'supabase/migrations/20261014000000_waitlist_admin_delete.sql'
content = '-- Scoped admin deletion of waiting orders and safe active waitlist labels.\n'
for source in SOURCES:
    content += '\n-- Source: ' + source + '\n' + migration_inputs.read_text(ROOT / source) + '\n'
migration_inputs.write_text(TARGET, content.rstrip() + '\n')
print('Waitlist admin-delete forward migration assembled')
