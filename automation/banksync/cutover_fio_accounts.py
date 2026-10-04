#!/usr/bin/env python3
"""Reviewed one-way rollout: credentials never enter argv, logs, or manifests.

The operator directory supplies an authenticated api(path,method,body) function.
It must be outside this repository. The caller verifies backend activation and
SSH/database identity first. Account IDs are explicit; no global auto-selection.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--operator-directory', required=True)
parser.add_argument('--database', required=True)
parser.add_argument('--ssh-host', required=True)
parser.add_argument('--instance', required=True)
parser.add_argument('--accounts', required=True)
parser.add_argument('--evidence', required=True)
args = parser.parse_args()
ids = [int(value) for value in args.accounts.split(',')]
assert ids and all(value > 0 for value in ids)
sys.path.insert(0, args.operator_directory)
from bs_operator import api
out = Path(args.evidence)
out.mkdir(mode=0o700, parents=True, exist_ok=True)
os.chmod(out, 0o700)
assert all(c.isalnum() or c == '_' for c in args.database)

def sql(query):
    result = subprocess.run(['ssh', args.ssh_host,
        f'docker exec -i supabase-db psql -X -qAt -U postgres -d {args.database} -v ON_ERROR_STOP=1'],
        input=query, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError('Cutover SQL failed; no credentials logged. ' + result.stderr[-500:])
    return result.stdout.strip()

def literal(value):
    return 'NULL' if value is None else "'" + str(value).replace("'", "''") + "'"

for local_id in ids:
    account = json.loads(sql(f"""BEGIN READ ONLY;
      SELECT json_build_object('id',b.id,'iban',upper(regexp_replace(b.account_number,'\\s','','g')),
        'title',b.title,'token',s.secret,'expiry',s.expiry_date,
        'enabled',b.is_fetch_enabled,'valid',s.expiry_date IS NULL OR s.expiry_date>now(),
        'ledger_count',(SELECT count(*) FROM eshop.transactions WHERE bank_account_id=b.id),
        'ledger_high_water',(SELECT coalesce(max(id),0) FROM eshop.transactions WHERE bank_account_id=b.id),
        'connection',c.id,'remote',c.remote_bank_account_id)
      FROM eshop.bank_accounts b JOIN eshop.secrets s ON s.id=b.secret
      LEFT JOIN eshop.bank_sync_connections c ON c.bank_account_id=b.id
      WHERE b.id={local_id} AND b.type='FIO'; COMMIT;"""))
    # The bank API and canonical credential endpoint trim surrounding whitespace.
    account['token'] = account['token'].strip()
    assert account['token'] and account['iban']
    assert account['enabled'] or account['connection'] is not None, 'Do not activate an intentionally disabled account'
    remote_accounts = api('/bank-accounts')
    matches = [a for a in remote_accounts if a.get('account_number', '').replace(' ', '').upper() == account['iban']]
    if matches:
        assert len(matches) == 1 and matches[0]['owner_app_id'] == 'festapp', 'Physical account ownership conflict'
        remote = matches[0]
    else:
        remote = api('/bank-accounts', 'POST', {'account_number':account['iban'],'account_type':'FIO',
            'label':account['title'],'owner_app_id':'festapp','ingest_mode':'api','ingest_enabled':False})
    remote_id = str(remote['id'])
    assert remote_id.isdigit()
    if account['remote'] is not None:
        assert str(account['remote']) == remote_id, 'Mapping changed'
    subs = api('/subscriptions?bank_account_id=' + remote_id)
    assert any(s['consumer_app_id'] == 'festapp' for s in subs), 'Missing canonical subscriber'
    # Idempotent retry must not pause a successfully activated account again.
    proof = api('/bank-accounts/' + remote_id + '/ingest-state')
    digest = hashlib.sha256(account['token'].encode()).hexdigest()
    if proof.get('api_token_hash') != digest:
        assert account['connection'] is None, 'Credential changed after activation; use canonical management'
        api('/bank-accounts/' + remote_id + '/fio-token','PUT',
            {'fio_api_token':account['token'],'fetch_enabled':False,'ingest_mode':'api'})
    assert api('/bank-accounts/' + remote_id + '/ingest-state')['api_token_hash'] == digest
    manifest = {k: account[k] for k in ('id','iban','title','expiry','valid','ledger_count','ledger_high_water')}
    manifest.update(remote=remote_id, instance=args.instance, database=args.database, aliases=[], provider='FIO')
    raw = json.dumps(manifest,sort_keys=True)
    manifest_hash = hashlib.sha256(raw.encode()).hexdigest()
    manifest_path = out / f'account-{local_id}.json'
    if not manifest_path.exists():
        manifest_path.write_text(raw+'\n'); os.chmod(manifest_path,0o600)
    else:
        old = json.loads(manifest_path.read_text())
        assert old['remote'] == remote_id and old['iban'] == account['iban']
        manifest_hash = hashlib.sha256(json.dumps(old,sort_keys=True).encode()).hexdigest()
    if account['connection'] is None:
        sql(f"""BEGIN;
          SELECT set_config('request.jwt.claim.role','service_role',true);
          SELECT id FROM eshop.bank_accounts WHERE id={local_id} FOR UPDATE;
          INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,
            physical_account,provider,mode,state,pairing_code,manifest_sha256,token_expiry_at)
          VALUES({literal(args.instance)},'festapp',{literal(remote_id)},{local_id},{literal(account['iban'])},'FIO','api',
            'provisioning',{literal(remote['pairing_code'])},{literal(manifest_hash)},{literal(account['expiry'])});
          SELECT public.activate_bank_sync_connection(id,{literal(manifest_hash)}) FROM eshop.bank_sync_connections WHERE bank_account_id={local_id};
          {'UPDATE eshop.bank_sync_connections SET state=\'suspended\',last_error=\'fio_token_invalid_or_inactive\' WHERE bank_account_id='+str(local_id)+';' if not account['valid'] else ''}
          COMMIT;""")
    if account['valid']:
        api('/bank-accounts/' + remote_id + '/ingest-state','PUT',{'enabled':True})
        api('/bank-accounts/' + remote_id + '/fio-token','PUT',{'fetch_enabled':True,'ingest_mode':'api'})
    print(json.dumps({'account':local_id,'remote':remote_id,'status':'polling' if account['valid'] else 'suspended_expired_token'}),flush=True)
