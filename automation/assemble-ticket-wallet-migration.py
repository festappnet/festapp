#!/usr/bin/env python3
"""Assemble the additive Google Wallet migration from its canonical SQL owners."""
import migration_inputs
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [(f'ticket_wallet/{name}.sql', None) for name in
           ('schema', 'settings', 'projection', 'capabilities', 'sync', 'worker')] + [
    ('others/ticket_layout.sql', ('merge_ticket_layout_features', 'merge_ticket_appearance_internal_v1')),
    ('occasion_setup/drafts.sql', ('save_occasion_setup_draft',)),
    ('occasion_setup/appearance.sql', None),
    ('occasion_setup/email_preview.sql', None),
    ('occasion_setup/communication.sql', None),
    ('emails/email_queue.sql', ('begin_email_send',)),
    ('others/get_ticket_layout_write_contract_v1.sql', None),
    ('eshop/get_order_details_for_email.sql', None),
]
parts = ['-- Google Wallet: additive capability and provider metadata; no tenant activation.\n']
for path, names in SOURCES:
    source = ROOT / 'database/functions' / path
    text = migration_inputs.read_text(source)
    if names:
        matches = [re.search(r'CREATE OR REPLACE FUNCTION public\.' + name + r'\([\s\S]*?\$\$;', text)
                   for name in names]
        if not all(matches):
            raise SystemExit(f'Missing canonical function in {path}')
        text = '\n'.join(match.group(0) for match in matches) + '\n'
    parts.extend(['\n-- Source: database/functions/' + path + '\n', text])
result = ''.join(parts)
target = ROOT / 'supabase/migrations/20261110230000_ticket_wallet.sql'
if '--check' in sys.argv:
    if migration_inputs.read_text(target) != result:
        raise SystemExit('Ticket Wallet migration differs from canonical SQL')
else:
    migration_inputs.write_text(target, result)
