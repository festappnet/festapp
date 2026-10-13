#!/usr/bin/env python3
"""Prepare an owned local Supabase workspace and run the real Flutter app."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT.parent / 'festapp-wizard-local'
PROJECT = 'festapp-wizard-local'
DB_URL = 'postgresql://postgres:postgres@127.0.0.1:56822/postgres'
LOG = BACKEND / 'setup.log'


def run(args, **kwargs):
    with LOG.open('a') as log:
        os.chmod(LOG, 0o600)
        subprocess.run(args, check=True, stdout=log, stderr=log, **kwargs)


def sql(*args):
    run(['psql', DB_URL, '-v', 'ON_ERROR_STOP=1', '-q', *args])


def prepare():
    BACKEND.mkdir(exist_ok=True)
    config = BACKEND / 'supabase/config.toml'
    if not config.exists():
        run(['supabase', 'init', '--workdir', str(BACKEND)])
        text = config.read_text()
        settings = {
            'api': {'port': '56821'},
            'db': {'port': '56822', 'shadow_port': '56820', 'major_version': '15'},
            'db.seed': {'enabled': 'false'},
            'realtime': {'enabled': 'false'},
            'studio': {'enabled': 'false', 'port': '56823'},
            'inbucket': {'enabled': 'false', 'port': '56824'},
            'analytics': {'enabled': 'false'},
            'edge_runtime': {'enabled': 'false'},
        }
        for section, values in settings.items():
            def edit(match):
                body = match.group(2)
                for key, value in values.items():
                    body = re.sub(r'^' + key + r'\s*=.*$', key + ' = ' + value, body, flags=re.M)
                return match.group(1) + body
            text = re.sub(r'(\[' + re.escape(section) + r'\]\n)(.*?)(?=\n\[|\Z)', edit, text, flags=re.S)
        config.write_text(text)
    import tomllib
    cfg = tomllib.loads(config.read_text())
    if cfg['project_id'] != PROJECT or cfg['api']['port'] != 56821 or cfg['db']['port'] != 56822:
        raise RuntimeError('Local workspace identity/ports differ; refusing to reuse it')
    run(['supabase', 'start', '--workdir', str(BACKEND), '--exclude',
         'realtime,imgproxy,postgres-meta,studio,edge-runtime,logflare,vector,supavisor,mailpit'])
    # Verify which named container owns the database before any SQL writes.
    containers = subprocess.check_output(['docker', 'ps', '--format', '{{.Names}} {{.Ports}}'], text=True)
    if not any(line.startswith('supabase_db_' + PROJECT + ' ') and ':56822->5432/' in line for line in containers.splitlines()):
        raise RuntimeError('Owned database container is not listening on the expected port')
    marker = BACKEND / 'bootstrap-complete'
    if not marker.exists():
        existing = subprocess.check_output(['psql', DB_URL, '-Atc', "select to_regclass('public.units') is not null"], text=True).strip()
        if existing == 't':
            raise RuntimeError('Unmarked database already contains app data; refusing to bootstrap over it')
        pre = 'CREATE SCHEMA IF NOT EXISTS eshop;'
        for extension, schema in [('dblink','public'),('http','extensions'),('moddatetime','extensions'),
                                  ('pg_cron','pg_catalog'),('pg_trgm','extensions'),('pgaudit','extensions'),
                                  ('pgjwt','extensions'),('unaccent','extensions')]:
            pre += f'CREATE EXTENSION IF NOT EXISTS {extension} WITH SCHEMA {schema};'
        for schema in ['public', 'eshop']:
            for kind in ['TABLES', 'SEQUENCES', 'FUNCTIONS']:
                pre += f'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA {schema} REVOKE ALL ON {kind} FROM anon, authenticated, service_role;'
        sql('-c', pre)
        sql('-f', str(ROOT / 'supabase/baseline/20260805230000_production_schema.sql'))
        for migration in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
            if migration.name[:14] > '20260805230000':
                sql('-f', str(migration))
        sql('-f', str(ROOT / 'supabase/seed.sql'))
        marker.write_text('Canonical baseline and forward migrations loaded.\n')
    # Draft functions may change while iterating; the canonical file is idempotent.
    sql('-f', str(ROOT / 'database/functions/occasion_setup/drafts.sql'))
    sql('-f', str(ROOT / 'database/functions/occasion_setup/sources.sql'))
    sql('-c', "NOTIFY pgrst, 'reload schema'")
    status = json.loads(subprocess.check_output(['supabase', 'status', '--workdir', str(BACKEND), '--output', 'json'], stderr=subprocess.DEVNULL))
    if status['API_URL'] != 'http://127.0.0.1:56821':
        raise RuntimeError('Unexpected local API identity')
    defines = BACKEND / 'wizard-defines.json'
    descriptor = os.open(defines, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        json.dump({'FESTAPP_SUPABASE_URL': status['API_URL'],
                   'FESTAPP_SUPABASE_ANON_KEY': status['ANON_KEY'],
                   'FESTAPP_OCCASION_SETUP': 'true'}, stream)
    os.chmod(defines, 0o600)
    functions = BACKEND / 'supabase/functions'
    expected = ROOT / 'supabase/functions'
    if functions.is_symlink():
        if functions.resolve() != expected.resolve():
            raise RuntimeError('Local Edge Functions directory points elsewhere')
    elif functions.exists():
        raise RuntimeError('Local Edge Functions directory is not owned by this launcher')
    else:
        functions.symlink_to(expected, target_is_directory=True)
    config = BACKEND / 'supabase/config.toml'
    text = config.read_text()
    if '[functions.preview-ticket-layout]' not in text:
        config.write_text(text + '\n[functions.preview-ticket-layout]\n'
                          'static_files = ["./functions/_shared/ticket-assets/*"]\n')
    return defines


if __name__ == '__main__':
    try:
        defines = prepare()
        print('Local Wizard ready. Login: t@t.com / test. URL: http://127.0.0.1:56880/unit/1/edit', flush=True)
        if '--prepare-only' not in sys.argv:
            edge = subprocess.run(
                ['docker', 'inspect', '--format', '{{.State.Running}}',
                 f'supabase_edge_runtime_{PROJECT}'],
                capture_output=True, text=True)
            if edge.returncode != 0 or edge.stdout.strip() != 'true':
                with LOG.open('a') as log:
                    subprocess.Popen(
                        ['supabase', 'functions', 'serve', 'preview-ticket-layout',
                         '--workdir', str(BACKEND)],
                        stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                        start_new_session=True)
            os.chdir(ROOT)
            os.execvp('fvm', ['fvm', 'flutter', 'run', '-d', 'web-server', '--target',
                'test/browser/occasion_setup_e2e.dart', '--dart-define-from-file', str(defines),
                '--web-hostname', '127.0.0.1', '--web-port', '56880'])
    except Exception as error:
        print(f'Local setup failed: {error}. Details: {LOG}', file=sys.stderr)
        sys.exit(1)
