#!/usr/bin/env python3
"""Forward-only cash reservation contract assembled from its canonical owners."""
import argparse
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def render():
    manifest = json.loads((ROOT / 'automation/cash-reservations-migration.json').read_text())
    parts = ['''-- Cash reservations; no activation, external calls or historical policy backfill.
ALTER TABLE eshop.payment_providers DROP CONSTRAINT payment_providers_check;
ALTER TABLE eshop.payment_providers ADD CONSTRAINT payment_providers_check CHECK(
 (provider_key IN ('bank','cash') AND handler IS NULL AND source_field IS NULL)
 OR (provider_key NOT IN ('bank','cash') AND handler IS NOT NULL AND source_field IS NOT NULL));
INSERT INTO eshop.payment_providers(provider_key) VALUES('cash');
-- Unlinking preserves account facts. No account deletion may cascade away ledger rows.
ALTER TABLE eshop.transactions DROP CONSTRAINT transactions_bank_account_fkey;
ALTER TABLE eshop.transactions ADD CONSTRAINT transactions_bank_account_fkey
 FOREIGN KEY(bank_account_id) REFERENCES eshop.bank_accounts(id) ON DELETE RESTRICT;''']
    for source in manifest['sources']:
        parts.append('-- SOURCE: ' + source + '\n' + (ROOT / 'database/functions' / source).read_text().rstrip())
    return ROOT / 'supabase/migrations' / manifest['migration'], '\n\n'.join(parts) + '\n'

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target, content = render()
    if args.check:
        if not target.exists() or target.read_text() != content:
            raise SystemExit('Cash reservation migration does not match canonical owners')
        print('Cash reservation migration matches canonical owners')
    else:
        target.write_text(content)
