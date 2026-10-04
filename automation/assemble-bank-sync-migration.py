from pathlib import Path
import argparse
r=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--output',required=True,help='New migration path; existing files are never overwritten')
args=parser.parse_args()
output=Path(args.output)
if output.exists(): raise SystemExit('Refusing to overwrite an existing migration')
files=['eshop_bank_sync/schema.sql','eshop_bank_sync/bank_sync_authority.sql','eshop_bank_sync/bank_sync_manage.sql','eshop_transactions/match_bank_transaction.sql','eshop_orders/recalculate_order_payment_status.sql','eshop_transactions/apply_transaction_pairing.sql','eshop_bank_sync/bank_sync_existing_facts_match.sql','eshop_bank_sync/ingest_bank_sync_transaction.sql','eshop_bank_accounts/update_bank_account.sql','eshop_bank_accounts/get_my_admin_bank_accounts.sql','eshop_bank_accounts/get_bank_accounts_for_unit_management.sql']
output.write_text('-- Canonical sources: database/functions/eshop_bank_sync.\n'+''.join('\n-- SOURCE: '+f+'\n'+(r/'database/functions'/f).read_text()+'\n' for f in files))
p=r/'database/tables/tables.sql';s=p.read_text()
start='\n-- BankSync canonical import authority and audit.\n'
end='-- End BankSync canonical import authority and audit.\n'
block=start+(r/'database/functions/eshop_bank_sync/schema.sql').read_text()+end
if start in s:
    before,tail=s.split(start,1)
    if end not in tail: raise ValueError('BankSync schema block end marker is missing')
    s=before+block+tail.split(end,1)[1]
else: s+=block
p.write_text(s)
