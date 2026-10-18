#!/usr/bin/env python3
"""Seal the forward reconciliation of existing domain owners, never old migrations."""
from pathlib import Path
import argparse, re
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
owners = [
 ('database/functions/users/reception_qr_login.sql', 'create_reception_user_v1'),
 ('database/functions/users/reception_qr_login.sql', 'cancel_reception_registration_v1'),
 ('database/functions/eshop_orders/delete_order.sql', 'delete_order_internal_v1'),
 ('database/functions/eshop_orders/delete_order_client_sync_v1.sql', 'delete_order_client_sync_v1'),
 ('database/functions/emails/email_queue.sql', 'email_intent_valid'),
]
content = '-- Restore scoped owners overwritten by older assembled migrations.\n'
for source, name in owners:
 text = (root / source).read_text()
 pattern = rf'CREATE OR REPLACE FUNCTION public\.{name}\([\s\S]*?\bAS\s+(\$\w*\$)[\s\S]*?\1\s*;'
 match = re.search(pattern, text, re.I)
 if not match:
  raise SystemExit('Missing canonical owner: ' + name)
 content += '\n-- Source: ' + source + '\n' + match[0] + '\n'
content += """
REVOKE ALL ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.email_intent_valid(public.email_messages) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.email_intent_valid(public.email_messages) TO service_role;
"""
target = root / 'supabase/migrations/20261018210000_integration_contract_reconciliation.sql'
if args.check:
 if target.read_text() != content:
  raise SystemExit('Integration reconciliation differs from canonical owners')
else:
 target.write_text(content)
print('Integration reconciliation: canonical (5 owners)')
