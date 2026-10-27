#!/usr/bin/env python3
"""Check canonical Functions configuration; optionally restart its existing container.

This deliberately cannot recreate a container or change its environment. A
configuration migration needs its own reviewed plan, not a code-reload command.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

ROOT = Path('/opt/festapp-supabase/docker')
DATABASE = 'festapp_rehearsal_20260909220601'
HOST = 'festapp-supabase-rehearsal-01'
REQUIRED_FILES = {
    'docker-compose.yml', 'docker-compose.festapp.yml',
    'docker-compose.database-target.yml', 'docker-compose.email.yml',
    'docker-compose.pgbackrest.yml', 'docker-compose.resource-budget.yml',
}
REQUIRED_ENV = {
    'EMAIL_SES_ACCOUNT_ID', 'EMAIL_SES_REGION', 'EMAIL_SES_ACCESS_KEY_ID',
    'EMAIL_SES_SECRET_ACCESS_KEY', 'EMAIL_SES_TRANSACTIONAL_SET',
    'EMAIL_SES_SECURITY_SET', 'EMAIL_PAYLOAD_KEY', 'EMAIL_SNS_TOPIC_ARN',
    'AUTH_EMAIL_PUBLIC_URL', 'AUTH_EMAIL_HOOK_SECRET',
    'APP_LINKS_ORGANIZATION_ID', 'FESTAPP_MONITORING_URL',
    'FESTAPP_MONITORING_TOKEN', 'DEFAULT_EMAIL', 'SUPABASE_DB_URL',
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def compose_inputs(text, inherited):
    # Docker parses the values; only inspect names and the overlay list here.
    entries = dict(re.findall(r'^([A-Z][A-Z0-9_]*)=(.*)$', text, re.M))
    files = entries.get('COMPOSE_FILE', '').strip().strip('\"\'').split(':')
    require(len(files) == len(set(files)) and set(files) == REQUIRED_FILES,
            'The complete canonical Compose overlay list is required.')
    require(files[:2] == ['docker-compose.yml', 'docker-compose.festapp.yml'],
            'Unexpected Compose base order.')
    require(files.index('docker-compose.database-target.yml') < files.index('docker-compose.email.yml'),
            'Unexpected Compose database/email order.')
    require(not any(k.startswith('COMPOSE_') for k in inherited),
            'Unset inherited COMPOSE_* overrides before checking the runtime.')
    # Shell variables must not override the protected production .env.
    environment = {k: v for k, v in inherited.items() if k not in entries}
    return files, environment


def validate_configuration(model, container):
    desired = model['services']['functions']
    environment = desired.get('environment', {})
    current = dict(item.split('=', 1) for item in container['Config']['Env'])
    require(all(environment.get(k) and current.get(k) for k in REQUIRED_ENV),
            'Required email, monitoring or database environment is missing.')
    require(all(str(value) == current.get(key) for key, value in environment.items()),
            'Running and configured Functions environments differ; use a reviewed configuration migration.')
    require(desired['image'] == container['Config']['Image'], 'Functions image drift.')
    require(desired.get('command') == container['Config']['Cmd'], 'Functions command drift.')
    require(urlparse(environment['SUPABASE_DB_URL']).path == '/' + DATABASE,
            'Functions database target mismatch.')
    # The shared app-links sender has its own provisioned organization; it is
    # independent of the selected ticketing tenant whose database we verify.
    require(str(environment['APP_LINKS_ORGANIZATION_ID']).isdigit()
            and int(environment['APP_LINKS_ORGANIZATION_ID']) > 0,
            'App-links organization is not configured.')
    require(container['State']['Running'], 'Functions container is not running.')


def command(args, environment=None):
    # Docker/Compose errors may contain expanded secrets. Never echo raw output.
    result = subprocess.run(args, cwd=ROOT, env=environment, text=True, capture_output=True)
    require(result.returncode == 0, 'Runtime command failed; raw output withheld to protect credentials.')
    return result.stdout


def sql(query):
    return command(['docker', 'exec', 'supabase-db', 'psql', '-X', '-U', 'postgres',
                    '-d', DATABASE, '-Atqv', 'ON_ERROR_STOP=1', '-c',
                    'BEGIN READ ONLY; ' + query + '; COMMIT;']).strip()


def probe(container):
    networks = container['NetworkSettings']['Networks']
    address = next(value['IPAddress'] for value in networks.values() if value.get('IPAddress'))
    request = urllib.request.Request('http://' + address + ':9000/process-email-queue',
                                     data=b'{}', headers={'Content-Type': 'application/json'})
    # A real JSON request reaches the worker but cannot authorize or send mail.
    deadline = time.monotonic() + 30
    while True:
        try:
            urllib.request.urlopen(request, timeout=5).close()
        except urllib.error.HTTPError as error:
            require(error.code == 401, 'Functions authorization probe failed.')
            return
        except urllib.error.URLError:
            require(time.monotonic() < deadline, 'Functions did not become ready.')
            time.sleep(2)
            continue
        raise RuntimeError('Unauthenticated worker request unexpectedly succeeded.')


def run(restart=False):
    require(os.geteuid() == 0 and os.uname().nodename.split('.')[0] == HOST,
            'Run only as root on the verified canonical host.')
    with (ROOT / '.festapp-runtime-upgrade.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        files, environment = compose_inputs((ROOT / '.env').read_text(), os.environ)
        args = ['docker', 'compose', '--env-file', str(ROOT / '.env')]
        for file in files:
            args.extend(['-f', file])
        model = json.loads(command(args + ['config', '--format', 'json'], environment))
        before = json.loads(command(['docker', 'inspect', 'supabase-edge-functions']))[0]
        validate_configuration(model, before)
        identity = sql("SELECT current_database() = '" + DATABASE + "' AND EXISTS "
                       "(SELECT 1 FROM public.organizations WHERE id=3 AND data->>'DEFAULT_URL'='https://vstupenky.online')")
        require(identity == 't', 'Canonical database or organization identity mismatch.')
        if restart:
            # The operator's release workflow owns pause/resume. Refuse to kill
            # in-flight preparation/sends or silently resume an existing pause.
            drained = sql("SELECT paused AND NOT EXISTS (SELECT 1 FROM public.email_messages "
                          "WHERE workflow_state IN ('preparing','sending')) FROM public.email_capacity")
            require(drained == 't', 'Pause and drain the canonical email queue before restarting.')
            command(['docker', 'restart', '--time', '30', before['Id']])
            after = json.loads(command(['docker', 'inspect', 'supabase-edge-functions']))[0]
            require(after['Id'] == before['Id'], 'Container was unexpectedly recreated.')
            require(after['Config'] == before['Config'], 'Container configuration changed during restart.')
            validate_configuration(model, after)
            probe(after)
        print('Functions configuration verified' + ('; existing container restarted; email remains paused.'
                                                   if restart else '; no runtime changes.'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--restart', action='store_true', help='Restart only after the operator has paused and drained email.')
    options = parser.parse_args()
    try:
        run(options.restart)
    except RuntimeError as error:
        # Our RuntimeError messages contain only fixed, non-secret diagnostics.
        raise SystemExit(str(error)) from None
    except (OSError, KeyError, ValueError, StopIteration):
        # Do not print exceptions from Docker or config decoding: they may carry
        # secrets. Queue remains paused on failure; the operator owns recovery.
        raise SystemExit('Functions restart/check refused. Verify canonical configuration and queue drain; no secrets printed.') from None
