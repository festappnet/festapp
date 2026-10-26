#!/usr/bin/env python3
"""Build a new, dormant Festapp-owned reference migration from canonical SQL."""
import argparse
from pathlib import Path
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
files = [
 'eshop_payment_references/schema.sql', 'eshop_payment_references/identity.sql',
 'eshop_payment_references/allocation.sql', 'eshop_payment_references/operations.sql',
 'eshop_payment_references/replay.sql', 'eshop/generate_payment_variable_symbol.sql',
 'eshop/finalize_ticket_order.sql', 'eshop/confirm_blueprint_order_change.sql',
 'eshop_orders/replace_blueprint_order_client_sync_v1.sql',
 'eshop_orders/create_ticket_order_client_sync_v1.sql', 'eshop_waitlist/commands.sql',
 'eshop_payment_references/legacy_boundaries.sql', 'eshop/update_payment_info_variable_symbol.sql',
 'eshop_payment_references/manual.sql', 'eshop_bank_accounts/update_bank_account.sql',
 'emails/fakturoid_email_gate.sql',
]
text = '-- Festapp-owned payment references; activation is a separate scoped operation.\n'
for name in files:
    text += '\n-- Source: database/functions/' + name + '\n' + (root / 'database/functions' / name).read_text() + '\n'
text += '''
-- Direct payment writes cannot publish an unreserved symbol. Domain RPC owners
-- keep their internal access. Legacy helper exports are not a second API.
REVOKE INSERT,UPDATE,DELETE ON eshop.payment_info FROM anon,authenticated;
REVOKE UPDATE(variable_symbol,creditor_reference,bank_account) ON eshop.payment_info FROM anon,authenticated;
REVOKE INSERT,UPDATE ON eshop.bank_accounts FROM anon,authenticated;
REVOKE UPDATE(account_number,type) ON eshop.bank_accounts FROM anon,authenticated;
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='generate_variable_symbol' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
 END LOOP;
END $$;
'''
output = Path(args.output)
if args.check:
    if not output.exists() or output.read_text() != text:
        raise SystemExit('Payment-reference migration differs from canonical sources')
else:
    if output.exists():
        raise SystemExit('Refusing to overwrite an existing migration')
    output.write_text(text)
    tables = root / 'database/tables/tables.sql'
    contents = tables.read_text()
    start = '\n-- Festapp-owned payment-reference registry.\n'
    end = '-- End Festapp-owned payment-reference registry.\n'
    block = start + (root / 'database/functions/eshop_payment_references/schema.sql').read_text() + end
    if start in contents:
        head, tail = contents.split(start, 1)
        if end not in tail:
            raise SystemExit('Missing payment-reference schema end marker')
        contents = head + block + tail.split(end, 1)[1]
    else:
        contents += block
    tables.write_text(contents)
