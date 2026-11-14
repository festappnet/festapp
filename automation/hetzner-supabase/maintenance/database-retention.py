#!/usr/bin/env python3
"""Explicit operational retention; no application contracts or roles are changed."""
import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import socket
import subprocess
import time

HOST = 'festapp-supabase-rehearsal-01'
RUNTIME = 'festapp_rehearsal_20260909220601'
DB_USER = 'supabase_admin'
STATE = Path('/var/lib/festapp-database-maintenance')
# Relation, expiry expression, batch limit. In-flight cron records stay intact.
POLICIES = [
    ('postgres', 'cron.job_run_details', "status='succeeded' AND end_time < statement_timestamp()-interval '7 days'"),
    ('postgres', 'cron.job_run_details', "status='failed' AND end_time < statement_timestamp()-interval '90 days'"),
    (RUNTIME, 'public.log_app_config', "created_at < statement_timestamp()-interval '90 days'"),
    (RUNTIME, 'auth.audit_log_entries', "created_at < statement_timestamp()-interval '365 days'"),
]


def sql(database, statement, readonly=False, timeout='15s'):
    options = f'-c statement_timeout={timeout} -c lock_timeout=250ms -c application_name=festapp-db-maintenance'
    if readonly:
        statement = 'BEGIN READ ONLY; ' + statement + '; COMMIT;'
    p = subprocess.run(['docker', 'exec', '-i', '-e', 'PGOPTIONS=' + options, 'supabase-db',
                        'psql', '-X', '-U', DB_USER, '-d', database, '-Atq',
                        '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate'],
                       input=statement, text=True, capture_output=True)
    if p.returncode:
        # SQLSTATE-only psql errors do not serialize row contents or query text.
        raise RuntimeError('Maintenance SQL failed: ' + p.stderr.strip()[-160:])
    return p.stdout.strip()


def guard():
    if os.geteuid() != 0 or socket.gethostname().split('.')[0] != HOST:
        raise RuntimeError('Canonical host required')
    if 'FESTAPP_RUNTIME_DATABASE=' + RUNTIME not in Path('/opt/festapp-supabase/docker/.env').read_text().splitlines():
        raise RuntimeError('Canonical runtime mismatch')
    if sql(RUNTIME, "SELECT current_database()='" + RUNTIME + "' AND EXISTS(SELECT 1 FROM public.organizations WHERE id=3)", True) != 't':
        raise RuntimeError('Canonical database/organization mismatch')
    if sql(RUNTIME, 'SELECT rolsuper FROM pg_roles WHERE rolname=current_user', True) != 't':
        raise RuntimeError('The existing local maintenance superuser is required')


def backup_guard():
    p = subprocess.run(['docker', 'exec', '-u', 'postgres', 'supabase-db', 'pgbackrest',
                        '--stanza=festapp', '--output=json', 'info'], capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError('Backup inventory unavailable')
    data = json.loads(p.stdout)[0]
    backup = data['backup'][-1] if data.get('backup') else {}
    if (data['name'] != 'festapp' or data['status']['code'] != 0 or backup.get('error', False)
            or time.time() - backup.get('timestamp', {}).get('stop', 0) > 26 * 3600):
        raise RuntimeError('A healthy cluster backup younger than 26 hours is required')
    archiver = sql(RUNTIME, "SELECT archive_mode='on' AND NOT failed AND pending<600 FROM "
                   "(SELECT current_setting('archive_mode') archive_mode, "
                   "coalesce(last_failed_time>coalesce(last_archived_time,'epoch'::timestamptz),false) failed, "
                   "coalesce((SELECT max(extract(epoch FROM now()-modification)) FROM pg_ls_archive_statusdir() WHERE name LIKE '%.ready'),0) pending "
                   "FROM pg_stat_archiver) s", True)
    if archiver != 't':
        raise RuntimeError('Healthy WAL archiving is required')
    return backup['label']


def delete_sql(relation, predicate, batch=5000):
    # Relations and predicates are fixed policy constants, never CLI input.
    return (f'WITH selected AS (SELECT ctid FROM {relation} WHERE {predicate} LIMIT {batch} FOR UPDATE SKIP LOCKED), '
            f'removed AS (DELETE FROM {relation} t USING selected s WHERE t.ctid=s.ctid RETURNING 1) '
            'SELECT count(*) FROM removed;')


def prune(execute=sql, max_batches=400):
    result = []
    for database, relation, predicate in POLICIES:
        total = 0
        for _ in range(max_batches):
            count = int(execute(database, delete_sql(relation, predicate)))
            total += count
            if count < 5000:
                break
            time.sleep(.05)
        result.append({'database': database, 'relation': relation, 'predicate': predicate, 'removed': total})
        print(json.dumps(result[-1]), flush=True)
    # Ordinary VACUUM keeps pages reusable. Disable truncation's stronger lock.
    targets = sorted({(d, r) for d, r, _ in POLICIES} | {
        (RUNTIME, 'public.events'), (RUNTIME, 'public.information'), (RUNTIME, 'public.news'),
        (RUNTIME, 'public.email_messages'), (RUNTIME, 'auth.refresh_tokens'),
        (RUNTIME, 'public.client_commit_components'), (RUNTIME, 'public.client_sync_private_scopes')})
    for database, relation in targets:
        execute(database, f'VACUUM (ANALYZE, TRUNCATE FALSE) {relation};', timeout='120s')
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    os.umask(0o077)
    guard()
    STATE.mkdir(mode=0o700, exist_ok=True)
    with (STATE / '.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        if not args.apply:
            for database, relation, predicate in POLICIES:
                print(json.dumps({'database': database, 'relation': relation, 'expired_rows': int(sql(
                    database, f'SELECT count(*) FROM {relation} WHERE {predicate}', True))}), flush=True)
            return
        label = backup_guard()
        result = {'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'backup': label, 'policies': prune()}
        (STATE / 'latest-retention.json').write_text(json.dumps(result, indent=2) + '\n')
        print('Database retention and ordinary vacuum completed', flush=True)


if __name__ == '__main__':
    main()
