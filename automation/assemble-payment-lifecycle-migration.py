#!/usr/bin/env python3
"""Assemble the scoped forward migration from frozen canonical payment SQL."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = (
    'database/functions/eshop_orders/recalculate_order_payment_status.sql',
    'database/functions/eshop_orders/update_ticket_products_ws.sql',
    'database/functions/eshop_transactions/apply_transaction_pairing.sql',
)


def migration_sql():
    content = (
        '-- One payment-eligibility owner for bank facts and product edits.\n'
        '-- Definition-only forward migration; no historical recompute or backfill.\n'
        'BEGIN;\n'
    )
    # The reconciliation helper is declared before its legacy and product adapters.
    for source in SOURCES:
        content += '\n-- Source: ' + source + '\n' + (ROOT / source).read_text().rstrip() + '\n'
    content += '''
-- The caller's authorized domain boundary owns execution of this invoker helper.
-- Check effective privileges too, including accidental inherited/public grants.
DO $payment_lifecycle_acl$
BEGIN
    IF has_function_privilege('anon',
        'public.reconcile_order_payment_internal_v1(bigint,text)', 'EXECUTE')
       OR has_function_privilege('authenticated',
        'public.reconcile_order_payment_internal_v1(bigint,text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Payment reconciliation helper must remain private';
    END IF;
END
$payment_lifecycle_acl$;
COMMIT;
'''
    return content


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, help='New migration path; existing files are never overwritten')
    parser.add_argument('--check', action='store_true', help='Verify parity with canonical SQL without writing')
    args = parser.parse_args()
    output = Path(args.output)
    content = migration_sql()
    if args.check:
        if not output.is_file() or output.read_text() != content:
            raise SystemExit('Payment lifecycle migration differs from canonical sources')
        print('Payment lifecycle migration matches canonical sources')
        return
    try:
        with output.open('x') as handle:
            handle.write(content)
    except FileExistsError:
        raise SystemExit('Refusing to overwrite an existing migration') from None
    print('Payment lifecycle migration assembled')


if __name__ == '__main__':
    main()
