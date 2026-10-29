#!/usr/bin/env python3
"""Own loopback-only disposable Joomla instances; never touches other containers."""
import json
import secrets
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / '.private'
PREFIX = 'festapp-joomla-20261026'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout


def wait_ready(container, port, expected_version, credentials, timeout=90):
    """Wait for image extraction, CLI installation and a working frontend."""
    deadline = time.monotonic() + timeout
    php_ready = (
        "if (!is_file('configuration.php') || !is_file('cli/joomla.php') "
        "|| is_dir('installation')) { exit(1); } "
        "require 'configuration.php'; $config = new JConfig; "
        "if (!$config->db || !$config->dbprefix) { exit(2); }"
    )
    while time.monotonic() < deadline:
        try:
            configured = subprocess.run(
                ['docker', 'exec', container, 'php', '-r', php_ready],
                capture_output=True, timeout=5,
            )
            if configured.returncode == 0:
                version = subprocess.run(
                    ['docker', 'exec', '--user', 'www-data', container, 'php', 'cli/joomla.php', '--version'],
                    capture_output=True, text=True, timeout=5,
                )
                if version.returncode == 0 and expected_version in version.stdout:
                    with urllib.request.urlopen(f'http://127.0.0.1:{port}/', timeout=3) as response:
                        body = response.read().decode(errors='replace')
                        if response.status == 200 and 'Joomla Ticket Integration Test' in body:
                            return
        except (OSError, TimeoutError, subprocess.TimeoutExpired):
            pass
        time.sleep(1)
    result = subprocess.run(
        ['docker', 'logs', '--tail', '35', container], capture_output=True, text=True,
    )
    log = result.stdout + result.stderr
    for value in credentials.values():
        log = log.replace(value, '[redacted]')
    log_path = PRIVATE / (container + '-startup.log')
    log_path.write_text(log)
    log_path.chmod(0o600)
    raise RuntimeError(f'{container} not ready after {timeout}s; redacted log: {log_path}')


def start():
    PRIVATE.mkdir(mode=0o700, exist_ok=True)
    auth = PRIVATE / 'auth.json'
    if auth.exists():
        raise SystemExit('Environment already prepared; stop before recreating.')
    credentials = {'username': 'joomlaadmin', 'password': secrets.token_urlsafe(24), 'db_password': secrets.token_hex(24)}
    auth.write_text(json.dumps(credentials))
    auth.chmod(0o600)
    images = json.loads((ROOT / 'docker-images.json').read_text())
    run('docker', 'network', 'create', PREFIX)
    db_env = PRIVATE / 'db.env'
    db_env.write_text('MARIADB_ROOT_PASSWORD=' + credentials['db_password'] + '\n')
    db_env.chmod(0o600)
    run('docker', 'run', '-d', '--name', PREFIX + '-db', '--network', PREFIX, '--env-file', str(db_env), images['database'])
    for _ in range(60):
        result = subprocess.run(['docker', 'exec', PREFIX + '-db', 'healthcheck.sh', '--connect', '--innodb_initialized'], capture_output=True)
        if result.returncode == 0:
            break
        time.sleep(1)
    else:
        raise RuntimeError('Disposable MariaDB did not start')
    for major, port in [(6, 59916), (5, 59915)]:
        env = PRIVATE / f'joomla{major}.env'
        env.write_text('\n'.join([
            'JOOMLA_DB_HOST=' + PREFIX + '-db', 'JOOMLA_DB_USER=root',
            'JOOMLA_DB_PASSWORD=' + credentials['db_password'], 'JOOMLA_DB_NAME=joomla' + str(major),
            'JOOMLA_SITE_NAME=Joomla Ticket Integration Test', 'JOOMLA_ADMIN_USER=Local Test Admin',
            'JOOMLA_ADMIN_USERNAME=' + credentials['username'], 'JOOMLA_ADMIN_PASSWORD=' + credentials['password'],
            'JOOMLA_ADMIN_EMAIL=joomla@example.invalid',
        ]) + '\n')
        env.chmod(0o600)
        run('docker', 'run', '-d', '--name', PREFIX + '-' + str(major), '--network', PREFIX,
            '--env-file', str(env), '-p', f'127.0.0.1:{port}:80',
            '-v', str(ROOT / 'artifacts') + ':/artifacts:ro',
            '-v', str(ROOT / 'tests') + ':/tests:ro', images['joomla' + str(major)])
    for major, port in [(6, 59916), (5, 59915)]:
        expected = images['joomla' + str(major)].split(':', 1)[1].split('-', 1)[0]
        wait_ready(PREFIX + '-' + str(major), port, expected, credentials)
    print('Ready: isolated Joomla CLI/config/version/HTTP on 127.0.0.1:59915 and :59916')


def stop():
    for suffix in ['-5', '-6', '-db']:
        subprocess.run(['docker', 'rm', '-fv', PREFIX + suffix], capture_output=True)
    subprocess.run(['docker', 'network', 'rm', PREFIX], capture_output=True)
    for filename in ['auth.json', 'db.env', 'joomla5.env', 'joomla6.env']:
        (PRIVATE / filename).unlink(missing_ok=True)
    print('Removed only task-owned Joomla containers and credentials')


if __name__ == '__main__':
    {'start': start, 'stop': stop}[sys.argv[1]]()
