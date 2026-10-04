from pathlib import Path
r=Path(__file__).resolve().parents[1]
files=['eshop_bank_sync/schema.sql','eshop_bank_sync/bank_sync_authority.sql','eshop_bank_sync/bank_sync_manage.sql','eshop_transactions/match_bank_transaction.sql','eshop_orders/recalculate_order_payment_status.sql','eshop_transactions/apply_transaction_pairing.sql','eshop_bank_sync/ingest_bank_sync_transaction.sql','eshop_transactions/insert_transactions.sql','eshop_transactions/process_email_transaction.sql','eshop_transactions/get_bank_account_secret.sql','eshop_transactions/get_fetchable_bank_accounts_for_unit.sql','eshop_transactions/get_fetchable_bank_accounts_with_t_count.sql','eshop_bank_accounts/update_bank_account_token.sql','eshop_bank_accounts/regenerate_bank_account_pairing_code.sql','eshop_bank_accounts/update_bank_account.sql','eshop_bank_accounts/get_my_admin_bank_accounts.sql','eshop_bank_accounts/get_bank_accounts_for_unit_management.sql']
(r/'supabase/migrations/20261004193000_bank_sync_canonical_ingress.sql').write_text('-- Canonical sources: database/functions/eshop_bank_sync and listed legacy boundaries.\n'+''.join('\n-- SOURCE: '+f+'\n'+(r/'database/functions'/f).read_text()+'\n' for f in files))
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
