#!/usr/bin/env python3
"""Deliberate one-key Functions environment migration with full Compose inputs.

This is not the code-reload/restart command. Email pause/drain and release gates
are mandatory; neither success nor rollback resumes the operator's email pause.
"""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import time

spec = importlib.util.spec_from_file_location('function_restart', Path(__file__).with_name('restart-production-functions.py'))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
require = runtime.require


def environment(container):
    values = container['Config']['Env']
    result = dict(value.split('=', 1) for value in values)
    require(len(result) == len(values), 'Duplicate container environment keys.')
    return result


def validate_change(before, after, key, value):
    before = deepcopy(before)
    after = deepcopy(after)
    require(key in before['services']['functions']['environment'], 'Key is absent from canonical Functions configuration.')
    require(after['services']['functions']['environment'].pop(key) == value, 'Proposed environment value did not resolve exactly.')
    before['services']['functions']['environment'].pop(key)
    require(before == after, 'Configuration migration would change more than the selected Functions key.')


def validate_recreated(before, after, key, value):
    expected = environment(before)
    expected[key] = value
    require(environment(after) == expected, 'Recreated Functions environment differs from the exact one-key change.')
    for field in ['Image', 'HostConfig']:
        require(before[field] == after[field], 'Functions image or host configuration changed.')
    for field in ['Image', 'Cmd', 'Entrypoint', 'User', 'WorkingDir', 'Healthcheck']:
        require(before['Config'].get(field) == after['Config'].get(field), 'Functions execution configuration changed.')
    normalized = lambda container: sorted(container['Mounts'], key=lambda item: item['Destination'])
    require(normalized(before) == normalized(after), 'Functions mounts changed.')
    require(after['Id'] != before['Id'] and after['State']['Running'], 'Functions recreation did not produce a running replacement.')


def write_private(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as file:
        file.write(data)
        file.flush()
        os.fsync(file.fileno())


def run(key, value_file, apply):
    require(os.geteuid() == 0 and os.uname().nodename.split('.')[0] == runtime.HOST, 'Run only as root on the verified canonical host.')
    require(re.fullmatch(r'[A-Z][A-Z0-9_]+', key) and not key.startswith('COMPOSE_'), 'Invalid environment key.')
    info = value_file.lstat()
    require(stat.S_ISREG(info.st_mode) and not info.st_mode & 0o077 and info.st_uid == 0, 'Value input must be a protected root-owned regular file.')
    value = value_file.read_text().strip()
    require(value and not any(c in value for c in "\r\n'"), 'Value input must be a nonempty single-line value without single quotes.')
    with (runtime.ROOT / '.festapp-runtime-upgrade.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        env_path = runtime.ROOT / '.env'
        original = env_path.read_text()
        pattern = re.compile(r'^' + re.escape(key) + r'=.*$', re.M)
        require(len(pattern.findall(original)) == 1, 'Environment key must already exist exactly once.')
        proposed = pattern.sub(lambda _: key + "='" + value + "'", original)
        files, inherited = runtime.compose_inputs(original, os.environ)
        args = ['docker', 'compose', '--env-file', str(env_path)]
        for file in files:
            args.extend(['-f', file])
        before_model = json.loads(runtime.command(args + ['config', '--format', 'json'], inherited))
        before = json.loads(runtime.command(['docker', 'inspect', 'supabase-edge-functions']))[0]
        runtime.validate_configuration(before_model, before)
        # Baseline service drift must not be silently adopted during recreation.
        configured_hash = runtime.command(args + ['config', '--hash', 'functions'], inherited).strip().split()[-1]
        require(configured_hash == before['Config']['Labels']['com.docker.compose.config-hash'], 'Installed Compose service hash differs; resolve baseline drift first.')
        identity = runtime.sql("SELECT current_database() = '" + runtime.DATABASE + "' AND EXISTS (SELECT 1 FROM public.organizations WHERE id=3 AND data->>'DEFAULT_URL'='https://vstupenky.online')")
        require(identity == 't', 'Canonical database or organization identity mismatch.')
        candidate = runtime.ROOT / ('.env.function-candidate-' + str(os.getpid()))
        write_private(candidate, proposed)
        try:
            proposed_args = args.copy()
            proposed_args[3] = str(candidate)
            proposed_model = json.loads(runtime.command(proposed_args + ['config', '--format', 'json'], inherited))
            validate_change(before_model, proposed_model, key, value)
            if not apply:
                print('Functions one-key environment migration verified; no runtime changes.')
                return
            drained = runtime.sql("SELECT paused AND NOT EXISTS (SELECT 1 FROM public.email_messages WHERE workflow_state IN ('preparing','sending')) FROM public.email_capacity")
            require(drained == 't', 'Pause and drain the canonical email queue before environment migration.')
            backup = runtime.ROOT / ('.env.before-functions-' + time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()))
            write_private(backup, original)
            os.replace(candidate, env_path)
            try:
                runtime.command(args + ['up', '-d', '--no-deps', '--force-recreate', '--pull', 'never', 'functions'], inherited)
                after = json.loads(runtime.command(['docker', 'inspect', 'supabase-edge-functions']))[0]
                validate_recreated(before, after, key, value)
                runtime.validate_configuration(proposed_model, after)
                runtime.probe(after)
            except Exception:
                # Restore only the exact pre-migration environment. Never resume
                # email, change other services, or substitute a different image.
                rollback = runtime.ROOT / ('.env.function-rollback-' + str(os.getpid()))
                write_private(rollback, original)
                os.replace(rollback, env_path)
                runtime.command(args + ['up', '-d', '--no-deps', '--force-recreate', '--pull', 'never', 'functions'], inherited)
                restored = json.loads(runtime.command(['docker', 'inspect', 'supabase-edge-functions']))[0]
                runtime.validate_configuration(before_model, restored)
                runtime.probe(restored)
                raise RuntimeError('Functions environment migration failed and its environment was restored; email remains paused.') from None
            print(json.dumps({'ok': True, 'key': key, 'valueSha256': hashlib.sha256(value.encode()).hexdigest(),
                              'containerId': after['Id'], 'backup': str(backup), 'emailResumed': False}))
        finally:
            candidate.unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--key', required=True)
    parser.add_argument('--value-file', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    options = parser.parse_args()
    try:
        run(options.key, options.value_file, options.apply)
    except RuntimeError as error:
        raise SystemExit(str(error)) from None
    except (OSError, KeyError, ValueError, IndexError):
        raise SystemExit('Functions environment migration refused; raw configuration and credentials withheld. Email remains paused if a migration began.') from None
