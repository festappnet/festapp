#!/usr/bin/env python3
"""Reviewed, bounded migration of two Apple Wallet inputs; email remains paused."""
import argparse
from datetime import datetime, timezone
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import sys

spec = importlib.util.spec_from_file_location('runtime_guard', Path(__file__).with_name('restart-production-functions.py'))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
KEYS = ('APPLE_WALLET_CREDENTIALS', 'APPLE_WALLET_WEB_SERVICE_URL')

def planned_files(env, overlay, credentials):
    required = {'passTypeIdentifier','teamIdentifier','signerCert','signerKey','wwdr'}
    guard.require(required <= credentials.keys() and not (credentials.keys() - required - {'signerKeyPassphrase'}), 'Unexpected Wallet credential fields.')
    guard.require(credentials['passTypeIdentifier']=='pass.net.festapp.tickets' and credentials['teamIdentifier']=='8WKBB6L8LT', 'Unexpected Wallet identity.')
    # JSON is dotenv-single-quoted. Disallow the delimiter and interpolation characters;
    # PEM uses JSON escapes so every environment record remains one physical line.
    serialized = json.dumps(credentials,separators=(',',':'),ensure_ascii=True)
    guard.require("'" not in serialized and '$' not in serialized and '\n' not in serialized, 'Unsafe protected credential encoding.')
    values = (serialized, 'https://api.festapp.net/functions/v1/apple-wallet')
    env = '\n'.join(line for line in env.splitlines() if not any(line.startswith(k + '=') for k in KEYS)) + '\n'
    env += ''.join(f"{k}='{v}'\n" for k, v in zip(KEYS, values))
    lines = ''.join(f'      {k}: ${{{k}:-}}\n' for k in KEYS)
    if not any(k + ':' in overlay for k in KEYS):
        marker = '      EMAIL_PAYLOAD_KEY:'
        guard.require(overlay.count(marker) == 1, 'Email overlay anchor drift.')
        overlay = overlay.replace(marker, lines + marker, 1)
    for k in KEYS:
        guard.require(overlay.count(f'      {k}: ${{{k}:-}}') == 1, 'Apple Wallet overlay contract drift.')
    return env, overlay, dict(zip(KEYS, values))

def assert_bounded_model(before, after, values):
    expected = json.loads(json.dumps(before))
    expected['services']['functions']['environment'].update(values)
    guard.require(expected == after, 'Configuration migration would change unrelated services or inputs.')

def private_write(path, data):
    path.write_text(data)
    path.chmod(0o600)

def run(credentials_path, apply=False):
    root = guard.ROOT
    guard.require(os.geteuid() == 0 and os.uname().nodename.split('.')[0] == guard.HOST, 'Wrong runtime identity.')
    guard.require(credentials_path.stat().st_mode & 0o077 == 0, 'Credential file must be private.')
    with (root / '.festapp-runtime-upgrade.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        env_path, overlay_path = root / '.env', root / 'docker-compose.email.yml'
        metadata = {path: path.stat() for path in (env_path, overlay_path)}
        guard.require(metadata[env_path].st_uid == 0 and metadata[env_path].st_mode & 0o077 == 0, 'Production environment must be root-owned and private.')
        def runtime_write(path, data):
            path.write_text(data)
            os.chown(path, metadata[path].st_uid, metadata[path].st_gid)
            path.chmod(stat.S_IMODE(metadata[path].st_mode))
        original_env, original_overlay = env_path.read_text(), overlay_path.read_text()
        files, environment = guard.compose_inputs(original_env, os.environ)
        args = ['docker', 'compose', '--env-file', str(env_path)]
        for file in files:
            args.extend(['-f', file])
        model = json.loads(guard.command(args + ['config', '--format', 'json'], environment))
        container = json.loads(guard.command(['docker', 'inspect', 'supabase-edge-functions']))[0]
        guard.validate_configuration(model, container)
        guard.require(guard.sql("SELECT current_database()='" + guard.DATABASE + "' AND EXISTS(SELECT 1 FROM public.organizations WHERE id=3)") == 't', 'Database target mismatch.')
        new_env, new_overlay, values = planned_files(original_env, original_overlay, json.loads(credentials_path.read_text()))
        if not apply:
            print('Preflight passed: exact host/database, complete Compose overlays, current container coherent; two inputs planned. No writes.')
            return
        guard.require(guard.sql("SELECT paused AND NOT EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state IN ('preparing','sending')) FROM public.email_capacity") == 't', 'Pause and drain email before changing Functions configuration.')
        backup = root / ('.apple-wallet-env-backup-' + datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S'))
        backup.mkdir(mode=0o700)
        private_write(backup / '.env', original_env)
        private_write(backup / 'docker-compose.email.yml', original_overlay)
        private_write(backup / 'container.json', json.dumps(container))
        try:
            runtime_write(env_path, new_env)
            runtime_write(overlay_path, new_overlay)
            desired = json.loads(guard.command(args + ['config', '--format', 'json'], environment))
            assert_bounded_model(model, desired, values)
            # Deliberate environment migration: use every installed overlay, never a partial -f list.
            guard.command(args + ['up', '-d', '--no-deps', '--force-recreate', 'functions'], environment)
            after = json.loads(guard.command(['docker', 'inspect', 'supabase-edge-functions']))[0]
            guard.require(after['Id'] != container['Id'], 'Functions configuration was not recreated.')
            guard.validate_configuration(desired, after)
            guard.probe(after)
        except Exception:
            runtime_write(env_path, original_env)
            runtime_write(overlay_path, original_overlay)
            try:
                guard.command(args + ['up', '-d', '--no-deps', '--force-recreate', 'functions'], environment)
                restored = json.loads(guard.command(['docker', 'inspect', 'supabase-edge-functions']))[0]
                guard.validate_configuration(model, restored)
                guard.probe(restored)
            except Exception:
                raise RuntimeError('Configuration rollback needs operator recovery; email remains paused. Protected backup: ' + str(backup)) from None
            raise RuntimeError('Configuration migration failed and previous runtime was restored; email remains paused.') from None
        print('Apple Wallet inputs installed; all other configuration preserved; worker authorization probe passed; email remains paused. Backup: ' + str(backup))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--credentials', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    options = parser.parse_args()
    try:
        run(options.credentials, options.apply)
    except Exception as error:
        # Never leak expanded Compose configuration or private JSON on failure.
        if isinstance(error, RuntimeError):
            raise SystemExit(str(error)) from None
        raise SystemExit('Apple Wallet configuration refused; no secret diagnostics printed; check protected runtime state.') from None
