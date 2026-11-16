#!/usr/bin/env python3
"""Apply one sealed, rehearsed runtime package using the installed Compose set.

No image builds, dependency installation, volume replacement or backup deletion.
The package is prepared and reviewed separately; expanded configuration stays
root-only. After service migrations start, failures keep admission closed and
jobs paused for an explicit resume, never an automatic snapshot restore.
"""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path('/opt/festapp-supabase/docker')
HOST = 'festapp-supabase-rehearsal-01'
DATABASE = 'festapp_rehearsal_20260909220601'
TARGET = 'api.festapp.net'
ACK = 'apply-rehearsed-supabase-0.8.4-postgres-17.12'
FILES = {
    'docker-compose.festapp.yml', 'volumes/api/envoy/cds.yaml',
    'volumes/api/envoy/lds.template.yaml', 'volumes/functions/main/index.ts',
    'volumes/functions/main/memory-pressure.ts', 'volumes/functions/deno.jsonc',
    'studio-customization/install-logout.mjs',
}
CLIENTS = ['functions', 'auth', 'rest', 'realtime', 'supavisor', 'studio', 'meta']
MCP = ['festapp-mcp-mcp-1', 'festapp-mcp-global-mcp-1']
STATE = Path('/var/lib/festapp-runtime-update-20261115')
BACKUP_LOCK = Path('/var/backups/festapp-supabase/.lock')
BOOT_ID_PATH = Path('/proc/sys/kernel/random/boot_id')
MEMINFO_PATH = Path('/proc/meminfo')
IMAGE_SERVICES = {'studio':'studio', 'api-gw':'envoy', 'auth':'auth', 'rest':'rest',
    'realtime':'realtime', 'meta':'postgresMeta', 'functions':'edgeRuntime', 'supavisor':'supavisor'}
QUIET_TIMERS = ['festapp-database-retention.timer', 'festapp-host-retention.timer']


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_manifest(m, source):
    require(m['manifest_version'] == 1, 'Unknown runtime package format.')
    require(re.fullmatch('[a-f0-9]{40}', source or '') is not None, 'Exact source SHA required.')
    require(m['source_sha'] == source and m['target'] == TARGET, 'Package source/target mismatch.')
    require(set(m['files']) == FILES, 'Unexpected package file set.')
    require(m['rehearsal']['status'] == 'pass', 'Combined rehearsal has not passed.')
    require(m['rehearsal']['upgrade_seconds'] + m['rehearsal']['rollback_seconds'] <= 900,
            'Rehearsed upgrade and rollback exceed fifteen minutes.')
    require(m['postgres_version_num'] == '170012', 'Unexpected PostgreSQL version.')
    require(re.fullmatch('sha256:[a-f0-9]{64}', m['db_image']) is not None,
            'Derivative must be sealed by local image ID.')
    pins = json.loads(Path(__file__).with_name('pins.json').read_text())
    expected = {service:pins['supabase']['images'][key] for service,key in IMAGE_SERVICES.items()}
    expected['db'] = m['db_image']
    require(m['images'] == expected, 'Package images differ from the canonical selected bundle.')


def require_private_root(path):
    info = path.stat()
    require(info.st_uid == 0 and info.st_mode & 0o077 == 0, 'Package must be root-owned and private.')


def write(path, data):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Preserve bind-mounted file inodes. Renaming a host file can leave Docker
    # reading its previous inode, notably Caddy's single-file bind mount.
    path.write_bytes(data)


def maintenance(source):
    anchor = '\treverse_proxy 127.0.0.1:8000 {\n'
    require(source.count(anchor) == 1, 'Installed Caddy proxy contract changed.')
    start = source.index(anchor)
    end = source.index('\n\t}', start) + len('\n\t}')
    return source[:start] + ('\theader Retry-After "60"\n'
                            '\theader Cache-Control "no-store"\n'
                            '\trespond "Backend maintenance" 503') + source[end:]


def validate_model_change(original, desired, images):
    # Reject any unreviewed change to mounts, keys, environments, networks,
    # capabilities, profile/service membership or other installed overlays.
    normalized = json.loads(json.dumps(desired))
    require(set(original['services']) == set(desired['services']), 'Compose service membership changed.')
    for service, image in images.items():
        require(normalized['services'][service]['image'] == image, 'Wrong candidate service image.')
        normalized['services'][service]['image'] = original['services'][service]['image']
    functions = normalized['services']['functions']
    before = original['services']['functions']
    require(str(functions.get('mem_limit')) == '2147483648', 'Unexpected Functions memory budget.')
    require(functions.get('command') == ['start', '--user-worker-request-idle-timeout', '150000',
        '--main-service', '/home/deno/functions/main'], 'Unexpected Functions command.')
    require(functions['environment'].get('DENO_TLS_CA_STORE') == 'system,mozilla', 'Unexpected TLS trust store.')
    for field in ('mem_limit', 'command'):
        if field in before:
            functions[field] = before[field]
        else:
            functions.pop(field, None)
    if 'DENO_TLS_CA_STORE' in before['environment']:
        functions['environment']['DENO_TLS_CA_STORE'] = before['environment']['DENO_TLS_CA_STORE']
    else:
        functions['environment'].pop('DENO_TLS_CA_STORE')
    require(normalized == original, 'Candidate changes protected Compose configuration or credentials.')


def update_catalog(sql):
    databases = sql('SELECT datname FROM pg_database WHERE datallowconn ORDER BY datname', 'postgres').splitlines()
    require(set(databases) == {DATABASE, 'postgres', '_supabase', 'template1'}, 'Cluster database inventory changed.')
    require(sql('SELECT bool_and(datcollversion IS NULL OR datcollversion=pg_database_collation_actual_version(oid)) FROM pg_database',
                'postgres') == 't', 'Collation changed; stop for the rehearsed REINDEX decision.')
    reindexed = 0
    for database in databases:
        for name, old, new in [('pg_net','0.20.3','0.20.4'), ('supabase_vault','0.3.1','0.3.2')]:
            version = sql("SELECT extversion FROM pg_extension WHERE extname='"+name+"'", database)
            require(version in ('', old, new), 'Unexpected extension version.')
            if version == old:
                sql("BEGIN; SET LOCAL lock_timeout='3s'; SET LOCAL statement_timeout='60s'; ALTER EXTENSION "
                    +name+" UPDATE TO '"+new+"'; COMMIT;", database, False)
        condition = "(a.amname='gin' OR EXISTS (SELECT FROM unnest(i.indclass) op JOIN pg_opclass oc ON oc.oid=op WHERE oc.opcname='gist_trgm_ops') OR EXISTS (SELECT FROM unnest(i.indkey) k JOIN pg_attribute att ON att.attrelid=i.indrelid AND att.attnum=k WHERE att.atttypid=1042 AND att.atttypmod<0))"
        source = ' FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid JOIN pg_am a ON a.oid=c.relam JOIN pg_namespace n ON n.oid=c.relnamespace WHERE '+condition
        require(sql('SELECT coalesce(sum(pg_relation_size(c.oid)),0)<=67108864 AND count(*)<=16'+source, database) == 't',
                'REINDEX inventory exceeds the rehearsed budget.')
        # PostgreSQL quotes catalog identifiers; no caller-provided SQL/names.
        commands = sql("SELECT format('REINDEX INDEX %I.%I;',n.nspname,c.relname)"+source+' ORDER BY n.nspname,c.relname', database)
        for command in commands.splitlines():
            sql("BEGIN; SET LOCAL lock_timeout='3s'; SET LOCAL statement_timeout='60s'; "+command+' COMMIT;', database, False)
            reindexed += 1
    return {'reindexed': reindexed}


def apply(args):
    require(not args.rollback or args.resume, 'Rollback requires existing recorded state.')
    require(os.geteuid() == 0 and os.uname().nodename.split('.')[0] == HOST,
            'Run only as root on the canonical host.')
    require(args.target == TARGET and args.ack == ACK, 'Explicit canonical target/ack required.')
    os.umask(0o077)
    package = args.package.resolve()
    require_private_root(package)
    manifest = json.loads((package / 'manifest.json').read_text())
    validate_manifest(manifest, args.source_sha)
    for name, expected in manifest['files'].items():
        path = package / name
        require(path.is_file() and not path.is_symlink() and digest(path) == expected,
                'Package file digest mismatch.')
    spec = importlib.util.spec_from_file_location('functions_runtime',
        Path(__file__).with_name('restart-production-functions.py'))
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    with (ROOT / '.festapp-runtime-upgrade.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with BACKUP_LOCK.open('a') as backup_lock:
            fcntl.flock(backup_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            files, environment = helper.compose_inputs((ROOT / '.env').read_text(), os.environ)
            compose = ['docker', 'compose', '--project-directory', str(ROOT), '--env-file', str(ROOT / '.env')]
            for name in files:
                compose += ['-f', str(ROOT / name)]
            STATE.mkdir(mode=0o700, exist_ok=True)
            log = (STATE / 'commands.log').open('a')

            def run(argv, capture=False, timeout=180):
                result = subprocess.run(argv, cwd=ROOT, env=environment, text=True,
                    stdout=subprocess.PIPE if capture else log, stderr=log, timeout=timeout)
                require(result.returncode == 0, 'Runtime command failed; protected diagnostics retained.')
                return result.stdout.strip() if capture else None

            def sql(query, database=DATABASE, readonly=True):
                statement = 'BEGIN READ ONLY; ' + query + '; COMMIT;' if readonly else query
                return run(['docker', 'exec', 'supabase-db', 'psql', '-X', '-U', 'supabase_admin',
                    '-d', database, '-Atqv', 'ON_ERROR_STOP=1', '-c', statement], True)

            def inspect(name):
                return json.loads(run(['docker', 'inspect', name], True))[0]

            def save():
                temporary = STATE / 'state.json.new'
                with temporary.open('wb') as stream:
                    stream.write((json.dumps(state, indent=2) + '\n').encode())
                    stream.flush()
                    os.fsync(stream.fileno())
                temporary.replace(STATE / 'state.json')

            def caddy(data):
                write(ROOT / 'caddy/Caddyfile', data)
                run(['docker', 'exec', 'festapp-caddy', 'caddy', 'validate', '--config', '/etc/caddy/Caddyfile', '--adapter', 'caddyfile'])
                run(['docker', 'exec', 'festapp-caddy', 'caddy', 'reload', '--config', '/etc/caddy/Caddyfile', '--adapter', 'caddyfile'])

            def verify_identity():
                identity = sql("SELECT current_database() = '" + DATABASE + "' AND EXISTS "
                    "(SELECT FROM public.organizations WHERE id=3 AND data->>'DEFAULT_URL'='https://vstupenky.online')")
                require(identity == 't', 'Canonical database/org mismatch.')
            require(not any(n in ('supabase-storage', 'supabase-imgproxy') for n in
                run(['docker', 'ps', '--format', '{{.Names}}'], True).splitlines()), 'Retired file services are running.')
            require(inspect(manifest['db_image'])['Architecture'] == 'arm64', 'Candidate is not ARM64.')
            if not args.resume:
                require(shutil.disk_usage(ROOT).free >= 6*1024**3, 'Insufficient staged-release/recovery disk headroom.')
                available = re.search(r'^MemAvailable:\s+(\d+) kB$', MEMINFO_PATH.read_text(), re.M)
                require(available is not None and int(available[1]) >= 512*1024, 'Insufficient host memory headroom.')
                verify_identity()
                require(sql("SELECT current_setting('archive_mode')='on' AND NOT pg_is_in_recovery() AND "
                    "last_archived_time>clock_timestamp()-interval '10 minutes' FROM pg_stat_archiver") == 't', 'WAL archive health preflight failed.')
                require(not run(['docker','exec','supabase-db','find','/var/lib/postgresql/data/pg_wal/archive_status',
                    '-maxdepth','1','-type','f','-name','*.ready','-mmin','+10'],True), 'Old pending WAL blocks the update.')
                backup = json.loads(run(['docker','exec','--user','postgres','supabase-db','pgbackrest',
                    '--stanza=festapp','--output=json','info'],True))[0]
                require(backup['status']['code'] == 0 and bool(backup['backup']), 'Physical backup repository is unhealthy.')
                latest = max(backup['backup'],key=lambda item:item['timestamp']['stop'])
                require(not latest['error'] and time.time()-latest['timestamp']['stop'] < 26*3600,
                        'Fresh successful physical backup required.')
                require(not (STATE / 'state.json').exists(), 'Existing update state requires --resume.')
                for name, expected in manifest['baseline_files'].items():
                    require(digest(ROOT / name) == expected, 'Installed baseline config drift.')
                caddy_stat = (ROOT / 'caddy/Caddyfile').stat()
                require(run(['docker','exec','festapp-caddy','stat','-Lc','%d:%i',
                             '/etc/caddy/Caddyfile'],True) == str(caddy_stat.st_dev)+':'+str(caddy_stat.st_ino),
                        'Caddy bind mount references a stale inode; repair before opening the window.')
                require(inspect('supabase-db')['Image'] == manifest['baseline_db_image'], 'Baseline DB image drift.')
                model = json.loads(run(compose + ['config', '--format', 'json'], True))
                helper.validate_configuration(model, inspect('supabase-edge-functions'))
                original_images = {}
                for service in manifest['images']:
                    container_id = run(compose + ['ps', '-q', service], True)
                    require(bool(container_id) and '\n' not in container_id, 'Expected one active service container.')
                    current = inspect(container_id)
                    wanted = model['services'][service]
                    actual_env = dict(entry.split('=',1) for entry in current['Config']['Env'])
                    require(current['State']['Running'] and all(str(value) == actual_env.get(key)
                        for key,value in wanted.get('environment',{}).items()), 'Installed service environment drift.')
                    if 'command' in wanted:
                        # Compose null inherits image CMD; its JSON output keeps
                        # $$ escaping while Docker receives one literal dollar.
                        expected_command = wanted['command']
                        if expected_command is None:
                            # Explicit entrypoint clears the inherited image CMD.
                            if wanted.get('entrypoint') is None:
                                expected_command = inspect(current['Image'])['Config']['Cmd']
                        else:
                            expected_command = [arg.replace('$$', '$') for arg in expected_command]
                        require(expected_command == current['Config']['Cmd'],
                                'Installed service command drift: ' + service)
                    original_images[service] = current['Image']
                # Exact selected bundle images must already exist locally.
                for image in manifest['images'].values():
                    require(inspect(image)['Architecture'] == 'arm64', 'Prepared image missing or wrong platform.')
                env_text, count = re.subn(r'^FESTAPP_PGBACKREST_DB_IMAGE=.*$',
                    'FESTAPP_PGBACKREST_DB_IMAGE=' + manifest['db_image'], (ROOT / '.env').read_text(), flags=re.M)
                require(count == 1, 'Sealed pgBackRest image setting missing/duplicated.')
                write(STATE / 'candidate.env', env_text.encode())
                desired_args = list(compose)
                desired_args[desired_args.index('--env-file') + 1] = str(STATE / 'candidate.env')
                for index, value in enumerate(desired_args):
                    if value == '-f' and Path(desired_args[index + 1]).name == 'docker-compose.festapp.yml':
                        desired_args[index + 1] = str(package / 'docker-compose.festapp.yml')
                desired = json.loads(run(desired_args + ['config', '--format', 'json'], True))
                validate_model_change(model, desired, manifest['images'])
                if args.dry_run:
                    print('Runtime update preflight passed; no restarts or SQL writes.')
                    return
                state = {'source_sha': args.source_sha, 'phase': 'prepared', 'migration_point': False,
                    'started_at': time.time(), 'started_monotonic': time.monotonic(),
                    'boot_id': BOOT_ID_PATH.read_text().strip(),
                    'done': [], 'email_paused': sql('SELECT paused FROM public.email_capacity'),
                    'original_images': original_images,
                    'pre_window_backup': latest['label'],
                    'timers_active': {unit:run(['systemctl','show','--property=ActiveState','--value',unit],True)=='active'
                                      for unit in QUIET_TIMERS},
                    'cron': json.loads(sql('SELECT coalesce(json_agg(json_build_object(\'id\',jobid,\'active\',active)),\'[]\'::json) FROM cron.job', 'postgres')),
                    'mcp_running': [n for n in MCP if inspect(n)['State']['Running']],
                    'db_mounts': inspect('supabase-db')['Mounts']}
                state['original_files'] = []
                state['original_file_hashes'] = {}
                for name in set(files) | FILES | {'.env', 'caddy/Caddyfile'}:
                    source = ROOT / name
                    if source.exists():
                        write(STATE / 'original' / name, source.read_bytes())
                        state['original_files'].append(name)
                        state['original_file_hashes'][name] = digest(source)
                save()
            else:
                state = json.loads((STATE / 'state.json').read_text())
                require(state['source_sha'] == args.source_sha, 'Resume source changed.')
                require(state['boot_id'] == BOOT_ID_PATH.read_text().strip(), 'Host reboot requires recovery-state review.')
                require(not args.dry_run, 'Resume cannot be a dry-run.')
                require(all(digest(STATE / 'original' / name) == expected
                    for name,expected in state['original_file_hashes'].items()), 'Rollback snapshot digest mismatch.')
                if state['phase'] in ('runtime_applied', 'rolled_back'):
                    print('Recorded update already finished: ' + state['phase'])
                    return

            def step(name, action):
                if name in state['done']:
                    return
                require(time.monotonic() - state['started_monotonic'] < 720, 'Stop point reached; retain maintenance for recovery.')
                state['phase'] = name
                save()
                action()
                state['done'].append(name)
                save()

            def pause():
                for unit, active in state['timers_active'].items():
                    if active:
                        run(['systemctl','stop',unit])
                for unit in QUIET_TIMERS:
                    require(run(['systemctl','show','--property=ActiveState','--value',unit.replace('.timer','.service')],True)
                            not in ('active','activating'), 'Direct maintenance writer is still running.')
                sql('UPDATE public.email_capacity SET paused=true', readonly=False)
                sql('UPDATE cron.job SET active=false WHERE active', 'postgres', readonly=False)
                deadline = time.monotonic() + 150
                while sql("SELECT NOT EXISTS (SELECT FROM public.email_messages WHERE workflow_state IN ('preparing','sending'))") != 't':
                    require(time.monotonic() < deadline, 'Email drain timed out.')
                    time.sleep(1)

            def fence():
                caddy(maintenance((STATE / 'original/caddy/Caddyfile').read_text()).encode())
                response = run(['curl', '--silent', '--show-error', '--max-time', '10', '-i',
                    'https://' + TARGET + '/rest/v1/'], True).lower()
                require(re.search(r'http/[^ ]+ 503', response) and 'retry-after: 60' in response
                    and 'cache-control: no-store' in response, 'Public maintenance fence did not pass.')
                state['fenced_at'] = time.time()
                save()

            def stop_clients():
                deadline = time.monotonic() + 150
                while True:
                    lines = run(['docker', 'logs', '--since', str(int(state['fenced_at'])),
                                 '--tail', '100', 'supabase-edge-functions'], True)
                    metrics = [json.loads(line.split('festapp_runtime_resource_metrics ',1)[1])
                               for line in lines.splitlines() if 'festapp_runtime_resource_metrics {' in line]
                    if any(m.get('at',0) >= state['fenced_at']*1000
                           and m['receivedRequestsCount'] == m['handledRequestsCount'] for m in metrics):
                        break
                    require(time.monotonic() < deadline, 'Functions requests did not drain after admission closed.')
                    time.sleep(2)
                if state['mcp_running']:
                    run(['docker', 'stop', '--time', '150'] + state['mcp_running'])
                run(compose + ['stop', '--timeout', '150'] + CLIENTS)
                require(sql("SELECT count(*)=0 FROM pg_stat_activity WHERE backend_type='client backend' AND pid<>pg_backend_pid()") == 't',
                    'Unfenced database clients remain.')
                state['fencing_lsn'] = sql('SELECT pg_current_wal_lsn()')
                save()

            def install():
                for name in FILES:
                    write(ROOT / name, (package / name).read_bytes())
                env = (ROOT / '.env').read_text()
                env, count = re.subn(r'^FESTAPP_PGBACKREST_DB_IMAGE=.*$',
                    'FESTAPP_PGBACKREST_DB_IMAGE=' + manifest['db_image'], env, flags=re.M)
                require(count == 1, 'Sealed pgBackRest image setting missing/duplicated.')
                write(ROOT / '.env', env.encode())
                run(compose + ['config', '--quiet'])

            def database():
                run(compose + ['up', '-d', '--no-deps', '--wait', '--wait-timeout', '90', 'db'])
                require(sorted(inspect('supabase-db')['Mounts'], key=lambda item:item['Destination'])
                        == sorted(state['db_mounts'], key=lambda item:item['Destination']),
                        'Database mount identity changed.')
                require(sql("SELECT current_setting('server_version_num')") == manifest['postgres_version_num'], 'Wrong live SQL version.')
                verify_identity()
                run(['docker', 'exec', '--user', 'postgres', 'supabase-db', 'pgbackrest', '--stanza=festapp', 'check'])

            def services():
                # Auth/Realtime/Supavisor may migrate on first start. Never label
                # a binary/config rollback as safe after this persistent marker.
                state['migration_point'] = True
                save()
                state['catalog_update'] = update_catalog(sql)
                save()
                run(compose + ['up', '-d', '--no-deps', '--wait', '--wait-timeout', '150'] + CLIENTS + ['api-gw'])
                model = json.loads(run(compose + ['config', '--format', 'json'], True))
                current = inspect('supabase-edge-functions')
                helper.validate_configuration(model, current)
                helper.probe(current)
                anon = model['services']['functions']['environment']['SUPABASE_ANON_KEY']
                require(run(['curl', '--silent', '--show-error', '--max-time', '10',
                    '--output', '/dev/null', '--write-out', '%{http_code}', '-H', 'apikey: ' + anon,
                    'http://127.0.0.1:8000/auth/v1/health'], True) == '200', 'Auth health failed.')
                # The OpenAPI root is intentionally admin-only; use the same
                # bounded read-only service-role probe as the native rehearsal.
                service = model['services']['functions']['environment']['SUPABASE_SERVICE_ROLE_KEY']
                require(run(['curl', '--silent', '--show-error', '--max-time', '10',
                    '--output', '/dev/null', '--write-out', '%{http_code}', '-H', 'apikey: ' + service,
                    '-H', 'Authorization: Bearer ' + service,
                    'http://127.0.0.1:8000/rest/v1/organizations?select=id&id=eq.3'], True) == '200', 'REST health failed.')

            def retain_images():
                guards = []
                for service, image in state['original_images'].items():
                    name = 'festapp-runtime-rollback-20261115-' + service
                    existing = run(['docker','ps','-aq','--filter','name=^/'+name+'$'],True)
                    if existing:
                        current = inspect(name)
                        require(current['Image'] == image and not current['State']['Running'], 'Rollback image guard drift.')
                    else:
                        # Stopped, network-none references survive existing
                        # host-retention image pruning. These cannot start PG.
                        run(['docker','create','--name',name,'--network','none',
                            '--label','net.festapp.rollback-retain-until=2026-11-22',
                            '--entrypoint','/bin/false',image])
                    guards.append(name)
                state['rollback_image_guards'] = guards
                save()

            def resume():
                for job in state['cron']:
                    sql('UPDATE cron.job SET active=' + ('true' if job['active'] else 'false')
                        + ' WHERE jobid=' + str(int(job['id'])), 'postgres', readonly=False)
                sql('UPDATE public.email_capacity SET paused=' + ('true' if state['email_paused'] == 't' else 'false'), readonly=False)
                if state['mcp_running']:
                    run(['docker', 'start'] + state['mcp_running'])
                caddy((STATE / 'original/caddy/Caddyfile').read_bytes())
                for unit, active in state['timers_active'].items():
                    if active:
                        run(['systemctl','start',unit])

            if args.rollback:
                require(args.resume and not state['migration_point'],
                    'Binary/config rollback is allowed only before service migrations.')
                # Only configuration/images are restored. PGDATA and confirmed
                # writes remain in place; backups are never recovery inputs here.
                if 'clients_stopped' in state['done']:
                    run(compose + ['stop', '--timeout', '150'] + CLIENTS)
                    for name in state['original_files']:
                        write(ROOT / name, (STATE / 'original' / name).read_bytes())
                    for name in FILES - set(state['original_files']):
                        (ROOT / name).unlink(missing_ok=True)
                    run(compose + ['up', '-d', '--no-deps', '--wait', '--wait-timeout', '90', 'db'])
                    require(inspect('supabase-db')['Image'] == manifest['baseline_db_image'], 'Old DB image did not return.')
                    verify_identity()
                    run(['docker', 'exec', '--user', 'postgres', 'supabase-db', 'pgbackrest', '--stanza=festapp', 'check'])
                    run(compose + ['up', '-d', '--no-deps', '--wait', '--wait-timeout', '150'] + CLIENTS + ['api-gw'])
                    helper.probe(inspect('supabase-edge-functions'))
                resume()
                state['phase'] = 'rolled_back'
                save()
                print('Rehearsed pre-migration rollback restored original runtime/jobs; PGDATA retained.')
                return

            try:
                step('rollback_images_retained', retain_images)
                step('pause', pause)
                step('fence', fence)
                step('clients_stopped', stop_clients)
                step('configuration_installed', install)
                step('database_updated', database)
                step('services_updated', services)
                step('admission_restored', resume)
                state['phase'] = 'runtime_applied'
                state['elapsed_seconds'] = round(time.monotonic() - state['started_monotonic'], 3)
                save()
                print('Runtime applied; admission/jobs restored. Live monitoring and new backup restore remain required.')
            except Exception:
                # No speculative data/binary rollback. Root-only state captures
                # the last completed action for the rehearsed recovery runbook.
                state['failed_phase'] = state['phase']
                save()
                raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--source-sha', required=True)
    parser.add_argument('--target', required=True)
    parser.add_argument('--ack', required=True)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--resume', action='store_true')
    parser.add_argument('--rollback', action='store_true')
    try:
        apply(parser.parse_args())
    except RuntimeError as error:
        # These invariant/transport errors contain static messages, never env.
        raise SystemExit('Runtime update stopped: ' + str(error) +
                         ' Inspect protected state/log; preserve admission and job state until recovery.') from None
    except Exception:
        raise SystemExit('Runtime update stopped. Inspect protected state/log; preserve admission and job state until recovery.') from None
