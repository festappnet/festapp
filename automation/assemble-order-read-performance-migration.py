"""Assemble the batched order-reader forward from canonical owners."""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    'eshop_transactions/payment_totals.sql': None,
    'user_permissions/domain_operations.sql': ['can_read_orders'],
    'user_permissions/bank_operations.sql': ['can_manage_bank_account'],
    'user_permissions/get_is_manager_on_unit.sql': ['get_is_manager_on_unit'],
    'user_permissions/payment_operations.sql': None,
    'payment_providers/builtin.sql': ['cash_payment_provider_internal', 'bank_payment_provider_internal'],
    'payment_providers/operation_contexts.sql': None,
    'payment_providers/operations.sql': ['payment_method_context_internal'],
    'eshop/order_seating.sql': ['order_spot_metadata_bulk_internal','order_spot_metadata_internal','order_tickets_with_seating_bulk_internal','order_tickets_with_seating_internal'],
    'eshop_orders/get_orders.sql': ['get_orders'],
    'emails/email_reporting.sql': ['order_email_current_issues_bulk','order_email_current_issues','get_order_email_summaries'],
}
TARGET = ROOT / 'supabase/migrations/20261111120000_order_read_performance.sql'


def render():
    parts = [
        '-- Batch ledger facts and distinct stored-scope policies per read.\n'
        '-- Nothing is cached across reads; money commands still re-authorize.',
        (ROOT / 'database/indexes/order_payment_reads.sql').read_text().rstrip(),
    ]
    for source, names in SOURCES.items():
        text = (ROOT / 'database/functions' / source).read_text()
        if names is None:
            parts.append(f'-- SOURCE: {source}\n{text.rstrip()}')
            continue
        for name in names:
            pattern = rf'CREATE OR REPLACE FUNCTION (?:public\.)?{name}\([\s\S]*?\$\$;'
            match = re.search(pattern, text)
            if match is None:
                raise SystemExit(f'Missing canonical function: {name}')
            # Carry adjacent ACL statements too, especially for new private helpers.
            acl = re.match(r'\s*((?:(?:REVOKE|GRANT)[\s\S]*?;\s*)+)', text[match.end():])
            body = match.group() + ('\n' + acl[1].rstrip() if acl else '')
            parts.append(f'-- SOURCE: {source} ({name})\n{body}')
    parts.append("NOTIFY pgrst, 'reload schema';")
    return '\n\n'.join(parts) + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    content = render()
    if args.check:
        if not TARGET.exists() or TARGET.read_text() != content:
            raise SystemExit('Order read performance migration is stale')
        print('Order read performance migration matches canonical owners')
    else:
        TARGET.write_text(content)
