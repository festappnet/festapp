#!/usr/bin/env python3
"""One-time, recoverable retirement and online compaction on the canonical host."""
import argparse
import datetime as dt
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import uuid


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


maintenance = module('database_retention', 'database-retention.py')
host = module('host_retention', 'host-retention.py')
RUNTIME = maintenance.RUNTIME
OLD = {'festapp_rehearsal_20260828234500': 84190, 'festapp_stage_a': 185319,
       'festapp_stage_default': 185025, 'festapp_stage_slunovrat': 185613}
STATE = maintenance.STATE
COMPACT = [('postgres', 'cron.job_run_details'), (RUNTIME, 'public.information'),
           (RUNTIME, 'public.events'), (RUNTIME, 'public.news'),
           (RUNTIME, 'public.email_messages'), (RUNTIME, 'public.log_app_config'),
           (RUNTIME, 'auth.audit_log_entries')]


def run(args, **kwargs):
    return host.run(args, **kwargs)


def sql(db, text, readonly=True, timeout='20s'):
    return maintenance.sql(db, text, readonly, timeout)


def quote(value):
    return '"' + value.replace('"', '""') + '"'


def retirement_inventory():
    return json.loads(sql('postgres', "SELECT coalesce(json_agg(x),'[]') FROM "
        "(SELECT d.datname,d.oid::bigint AS oid,pg_database_size(d.oid) bytes,s.numbackends,s.xact_commit,s.xact_rollback,"
        "s.tup_inserted,s.tup_updated,s.tup_deleted FROM pg_database d JOIN pg_stat_database s ON s.datid=d.oid "
        "WHERE d.datname IN (" + ','.join("'" + n + "'" for n in OLD) + ")) x"))


def retirement_preflight():
    facts = retirement_inventory()
    for fact in facts:
        if fact['oid'] != OLD[fact['datname']] or fact['xact_commit'] > 250 or fact['xact_rollback'] > 10 or any(fact[k] for k in (
                'numbackends', 'tup_inserted', 'tup_updated', 'tup_deleted')):
            raise RuntimeError('Old database identity or inactivity assertion failed')
    quoted = ','.join("'" + n + "'" for n in OLD)
    if sql('postgres', f'SELECT count(*) FROM cron.job WHERE database IN ({quoted})') != '0':
        raise RuntimeError('Old database still has scheduled jobs')
    if sql('postgres', f'SELECT count(*) FROM pg_replication_slots WHERE database IN ({quoted})') != '0':
        raise RuntimeError('Old database has replication slots')
    if sql('postgres', f'SELECT count(*) FROM pg_prepared_xacts WHERE database IN ({quoted})') != '0':
        raise RuntimeError('Old database has prepared transactions')
    # Imported foreign schemas are archival metadata, not proof of active usage.
    # Refuse database retirement if live functions, views or tracked queries use them.
    for db in [RUNTIME, 'postgres']:
        if sql(db, "SELECT count(*) FROM pg_proc WHERE prosrc LIKE '%festapp_stage_%' "
               "OR prosrc LIKE '%festapp_rehearsal_20260828234500%'") != '0':
            raise RuntimeError('A live stored function references an old database')
        if sql(db, "SELECT count(*) FROM pg_foreign_table f JOIN pg_depend d ON d.refobjid=f.ftrelid "
               "WHERE d.classid='pg_rewrite'::regclass") != '0':
            raise RuntimeError('A live view depends on imported foreign tables')
        if sql(db, "SELECT coalesce(sum(calls),0) FROM pg_stat_statements "
               "WHERE dbid=(SELECT oid FROM pg_database WHERE datname=current_database()) "
               "AND query ~ 'festapp_stage_(a|default|slunovrat)(_|[.]|[^a-z])'") != '0':
            raise RuntimeError('Tracked queries use imported foreign schemas')
    # Exact active container environments, not retained historical .env backups.
    ids = run(['docker', 'ps', '-aq'], text=True).split()
    inventory = json.loads(run(['docker', 'inspect'] + ids, text=True))
    for container in inventory:
        if any(name in value for value in container.get('Config', {}).get('Env', []) for name in OLD):
            raise RuntimeError('A configured container references an old database')
    return facts


def table_counts(container, database, user=maintenance.DB_USER, port=None):
    args = ['docker', 'exec', '-i', container, 'psql', '-X', '-U', user, '-d', database,
            '-Atq', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate']
    if port:
        args += ['-h', '/tmp', '-p', str(port)]
    query = "BEGIN READ ONLY; SET LOCAL statement_timeout='30s'; "
    tables = run(args, input=query + "SELECT quote_ident(n.nspname)||'.'||quote_ident(c.relname) "
        "FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' "
        "AND c.relpersistence='p' AND n.nspname NOT IN ('pg_catalog','information_schema') "
        "AND n.nspname NOT LIKE 'pg_toast%' ORDER BY 1; COMMIT;", text=True).splitlines()
    if not tables:
        return {}
    statement = ' UNION ALL '.join("SELECT '" + name.replace("'", "''") + "',count(*) FROM " + name
                                    for name in tables)
    lines = run(args, input=query + statement + '; COMMIT;', text=True).splitlines()
    return dict(line.rsplit('|', 1) for line in lines)


def save(path, value):
    temporary = path.with_suffix('.tmp')
    with temporary.open('w') as handle:
        json.dump(value, handle, indent=2)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def upload(path, remote, env):
    with path.open('rb') as handle:
        checksum = host.digest_stream(handle)
    run(['rclone', '--config', '/dev/null', 'copyto', str(path), remote, '--immutable', '--retries', '3'], env=env)
    with tempfile.TemporaryFile() as errors:
        process = subprocess.Popen(['rclone', '--config', '/dev/null', 'cat', remote], env=env,
                                   stdout=subprocess.PIPE, stderr=errors)
        try:
            actual = host.digest_stream(process.stdout)
            status = process.wait()
        finally:
            process.stdout.close()
            if process.poll() is None:
                process.kill()
                process.wait()
    if status or actual != checksum:
        raise RuntimeError('Retirement archive readback mismatch; database preserved')
    return {'remote': remote, 'sha256': checksum, 'bytes': path.stat().st_size, 'readback_verified': True}


def clone_roles(roles):
    # Ownership restoration needs role names, not production memberships, login
    # permissions or role GUCs. Full original definitions remain age-encrypted.
    return b'\n'.join(line for line in roles.splitlines() if line.startswith(b'CREATE ROLE ')) + b'\n'


def dump_and_restore(database, verifier, target, recipient, source_container="supabase-db", source_user=maintenance.DB_USER):
    """Fan out identical custom-dump bytes into encryption and a real isolated restore."""
    with target.open('xb') as encrypted, tempfile.TemporaryFile() as errors:
        dump = subprocess.Popen(['docker', 'exec', source_container, 'pg_dump', '-U', source_user, '-Fc', database],
                                stdout=subprocess.PIPE, stderr=errors)
        age = subprocess.Popen(['age', '-r', recipient], stdin=subprocess.PIPE, stdout=encrypted, stderr=errors)
        restore = subprocess.Popen(['docker', 'exec', '-i', verifier, 'pg_restore', '-h', '/tmp', '-p', '55439',
            '-U', 'retirement_restore_admin', '--exit-on-error', '--no-subscriptions', '-d', 'verify_retired'],
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=errors)
        children = [dump, age, restore]
        try:
            for block in iter(lambda: dump.stdout.read(65536), b''):
                age.stdin.write(block)
                restore.stdin.write(block)
            age.stdin.close()
            restore.stdin.close()
            status = [p.wait() for p in children]
            if any(status):
                raise RuntimeError('Dump/encryption/isolated restore failed; source preserved')
        except Exception:
            # Protected diagnostics only; never print raw database restore errors.
            errors.seek(0)
            with (STATE / 'restore-failure.log').open('wb') as log:
                shutil.copyfileobj(errors, log)
            raise
        finally:
            dump.stdout.close()
            for process in children:
                if process.poll() is None:
                    process.terminate()
            for process in children:
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def archive_databases(facts, env, recipient, run_id):
    image = run(['docker', 'inspect', '--format', '{{.Image}}', 'supabase-db'], text=True).strip()
    verifier = 'festapp-retirement-verify-' + uuid.uuid4().hex[:12]
    prefix = f'r2:festapp-supabase-backups/retired-databases/{host.HOST}/{run_id}'
    results = []
    try:
        run(['docker', 'run', '-d', '--name', verifier, '--network', 'none', '--memory', '512m',
             '--memory-swap', '512m', '--cpus', '1', '--pids-limit', '256', '--user', 'postgres',
             '--entrypoint', 'sh', image, '-c', 'sleep 7200'])
        actual = json.loads(run(['docker', 'inspect', verifier], text=True))[0]
        if actual['HostConfig']['NetworkMode'] != 'none' or actual['HostConfig'].get('PortBindings') or any(
                m['Type'] == 'bind' for m in actual['Mounts']):
            raise RuntimeError('Restore container isolation assertion failed')
        run(['docker', 'exec', verifier, 'initdb', '-D', '/tmp/retire-pg', '-U', 'retirement_restore_admin',
             '--auth=trust', '--no-locale', '--encoding=UTF8'])
        run(['docker', 'exec', verifier, 'pg_ctl', '-D', '/tmp/retire-pg', '-l', '/tmp/retire-pg.log', '-w',
             '-o', "-c listen_addresses='' -c unix_socket_directories=/tmp -c port=55439 "
             "-c shared_preload_libraries=pg_net,pgaudit,pg_stat_statements,supabase_vault "
             "-c pg_net.database_name=retirement_network_disabled "
             "-c session_preload_libraries='' -c local_preload_libraries='' "
             "-c max_connections=20 -c maintenance_work_mem=32MB -c work_mem=4MB -c archive_mode=off", 'start'])
        fence = run(['docker','exec',verifier,'psql','-X','-h','/tmp','-p','55439',
            '-U','retirement_restore_admin','-d','postgres','-Atqc',
            "SELECT current_setting('pg_net.database_name')='retirement_network_disabled' "
            "AND current_setting('listen_addresses')='' AND current_setting('archive_mode')='off' "
            "AND NOT EXISTS(SELECT 1 FROM pg_database WHERE datname='retirement_network_disabled')"], text=True).strip()
        if fence != 't':
            raise RuntimeError('Restore integration fence is not active')
        roles = run(['docker', 'exec', 'supabase-db', 'pg_dumpall', '-U', maintenance.DB_USER, '--roles-only', '--no-role-passwords'])
        run(['docker', 'exec', '-i', verifier, 'psql', '-X', '-h', '/tmp', '-p', '55439', '-U',
             'retirement_restore_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], input=clone_roles(roles))
        with tempfile.TemporaryDirectory(prefix='retirement-', dir=STATE) as temporary:
            temp = Path(temporary)
            roles_file = temp / 'roles.sql.age'
            run(['age', '-r', recipient, '-o', str(roles_file)], input=roles)
            role_archive = upload(roles_file, prefix + '/roles.sql.age', env)
            for database in [RUNTIME] + [f['datname'] for f in facts]:
                run(['docker', 'exec', verifier, 'createdb', '-h', '/tmp', '-p', '55439',
                     '-U', 'retirement_restore_admin', '-T', 'template0', 'verify_retired'])
                target = temp / (database + '.dump.age')
                print(json.dumps({'phase': 'backup_and_isolated_restore', 'database': database}), flush=True)
                dump_and_restore(database, verifier, target, recipient)
                restored = table_counts(verifier, 'verify_retired', 'retirement_restore_admin', 55439)
                if database != RUNTIME:
                    source = table_counts('supabase-db', database)
                    if restored != source:
                        raise RuntimeError('Isolated restore row counts differ; source preserved')
                else:
                    # Live writes continue during backup. Verify canonical identity in the restored snapshot.
                    identity = run(['docker', 'exec', verifier, 'psql', '-X', '-h', '/tmp', '-p', '55439',
                        '-U', 'retirement_restore_admin', '-d', 'verify_retired', '-Atqc',
                        'SELECT count(*) FROM public.organizations WHERE id=3'], text=True).strip()
                    if identity != '1':
                        raise RuntimeError('Restored runtime identity mismatch')
                    # Exercise the exact extension/client pair on the isolated
                    # restored snapshot before enabling it against live tables.
                    def clone_sql(statement):
                        return run(['docker','exec',verifier,'psql','-X','-h','/tmp','-p','55439',
                            '-U','retirement_restore_admin','-d','verify_retired','-Atqv','ON_ERROR_STOP=1',
                            '-c',statement], text=True).strip()
                    clone_sql("CREATE EXTENSION pg_repack VERSION '1.5.2';")
                    run(['docker','exec',verifier,'pg_repack','-h','/tmp','-p','55439',
                         '-U','retirement_restore_admin','-d','verify_retired','-n','-t',
                         'public.information','--wait-timeout=1','--no-kill-backend'])
                    clone_sql('DROP EXTENSION pg_repack;')
                    if clone_sql("SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'repack_trigger%'") != '0':
                        raise RuntimeError('Isolated compaction left a technical trigger')
                result = {'database': database, 'archive': upload(target, prefix + '/' + target.name, env),
                          'roles_archive': role_archive, 'isolated_restore_passed': True,
                          'restored_tables': len(restored), 'restored_rows': sum(map(int, restored.values())),
                          'source_counts_equal': database != RUNTIME, 'isolated_compaction_passed': database == RUNTIME, 'dropped': False}
                # Persist remote locator and actual restore evidence before any drop.
                save(STATE / (run_id + '-' + database + '.json'), result)
                target.unlink()
                run(['docker', 'exec', verifier, 'dropdb', '-h', '/tmp', '-p', '55439',
                     '-U', 'retirement_restore_admin', 'verify_retired'])
                if database in OLD:
                    if sql('postgres', f"SELECT oid FROM pg_database WHERE datname='{database}'") != str(OLD[database]):
                        raise RuntimeError('Database identity changed before retirement')
                    if sql('postgres', f"SELECT count(*) FROM pg_stat_activity WHERE datname='{database}'") != '0':
                        raise RuntimeError('Database became active; preserving it')
                    # No FORCE: another session is never terminated by retirement.
                    sql('postgres', 'ALTER DATABASE ' + quote(database) + ' ALLOW_CONNECTIONS false;', False)
                    try:
                        sql('postgres', 'DROP DATABASE ' + quote(database) + ';', False, timeout='30s')
                    except Exception:
                        sql('postgres', 'ALTER DATABASE ' + quote(database) + ' ALLOW_CONNECTIONS true;', False)
                        raise
                    if sql('postgres', f"SELECT count(*) FROM pg_database WHERE datname='{database}'") != '0':
                        raise RuntimeError('Retired database still exists')
                    result['dropped'] = True
                    save(STATE / (run_id + '-' + database + '.json'), result)
                results.append(result)
                print(json.dumps({'database': database, 'restore_verified': True, 'dropped': result['dropped']}), flush=True)
            manifest = temp / 'manifest.json'
            save(manifest, {'version': 1, 'run_id': run_id, 'databases': results})
            upload(manifest, prefix + '/manifest.json', env)
    finally:
        # Remove only this newly-created isolated verifier and its anonymous volumes.
        run(['docker', 'rm', '-f', '-v', verifier])
    return results


def compact():
    results = []
    for db in sorted({db for db, _ in COMPACT}):
        version = sql(db, "SELECT extversion FROM pg_extension WHERE extname='pg_repack'")
        if version:
            raise RuntimeError('Existing pg_repack installation needs ownership review')
        sql(db, "CREATE EXTENSION pg_repack VERSION '1.5.2';", False)
        try:
            if sql(db, "SELECT extversion FROM pg_extension WHERE extname='pg_repack'") != '1.5.2':
                raise RuntimeError('Repack extension version mismatch')
            for database, relation in COMPACT:
                if database != db:
                    continue
                before = int(sql(db, f"SELECT pg_total_relation_size('{relation}')"))
                print(json.dumps({'phase': 'online_repack', 'database': db, 'relation': relation}), flush=True)
                run(['docker', 'exec', '-e', 'PGOPTIONS=-c statement_timeout=120s -c application_name=festapp-online-maintenance',
                     'supabase-db', 'pg_repack', '-U', maintenance.DB_USER, '-d', db, '-n', '-t', relation,
                     '--wait-timeout=1', '--no-kill-backend'])
                after = int(sql(db, f"SELECT pg_total_relation_size('{relation}')"))
                results.append({'database': db, 'relation': relation, 'before_bytes': before, 'after_bytes': after})
        finally:
            # RESTRICT is intentional. Never cascade through unexpected dependencies.
            sql(db, 'DROP EXTENSION pg_repack;', False)
        if sql(db, "SELECT count(*) FROM pg_extension WHERE extname='pg_repack'") != '0':
            raise RuntimeError('Temporary repack extension remains')
        if sql(db, "SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'repack_trigger%'") != '0':
            raise RuntimeError('Temporary repack trigger remains')
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    os.umask(0o077)
    maintenance.guard()
    STATE.mkdir(mode=0o700, exist_ok=True)
    with (STATE / '.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        facts = retirement_preflight()
        print(json.dumps({'retirement_plan': facts, 'compaction': COMPACT}), flush=True)
        if not args.apply:
            return
        backup = maintenance.backup_guard()
        env, recipient = host.remote_env()
        run_id = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        before = shutil.disk_usage('/').free
        archives = archive_databases(facts, env, recipient, run_id)
        retention = maintenance.prune()
        repack = compact()
        result = {'run_id': run_id, 'backup_guard': backup, 'archives': archives,
                  'retention': retention, 'compaction': repack, 'free_before': before,
                  'free_after': shutil.disk_usage('/').free, 'status': 'completed'}
        save(STATE / ('cleanup-' + run_id + '.json'), result)
        print(json.dumps({'status': 'completed', 'free_before': before, 'free_after': result['free_after']}), flush=True)


if __name__ == '__main__':
    main()
