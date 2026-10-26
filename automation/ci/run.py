#!/usr/bin/env python3
"""Shared GitHub checks and native local mirror. No production credentials needed."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = json.loads((ROOT / 'automation/ci/checks.json').read_text())
CACHE = Path.home() / 'Library/Caches/festapp-ci' if sys.platform == 'darwin' else Path.home() / '.cache/festapp-ci'


def call(argv, **kwargs):
    return subprocess.run(argv, check=True, cwd=ROOT, **kwargs)


def step(name):
    script = CONTRACT['steps'][name]
    if 'fvm ' in script and not os.environ.get('GITHUB_ACTIONS'):
        while True:
            processes = subprocess.check_output(['ps', '-axo', 'args='], text=True)
            if not any('flutter_tools.snapshot' in line for line in processes.splitlines()):
                break
            print('Waiting for the workstation Flutter task to finish...', flush=True)
            time.sleep(10)
    call(['bash', '-euo', 'pipefail', '-c', script])


def lane(name):
    for name in CONTRACT['jobs'][name]['steps']:
        started = time.monotonic()
        print(f'CI step: {name}', flush=True)
        step(name)
        print(f'CI step passed: {name} ({time.monotonic() - started:.1f}s)', flush=True)


def require_version(command, expected):
    actual = subprocess.check_output(command, text=True).strip()
    if expected not in actual.split():
        raise RuntimeError(f'{command[0]} must be {expected}; got {actual}')


def local(names):
    CACHE.mkdir(parents=True, exist_ok=True)
    # One owner across worktrees. Never stop another session's DB or Flutter task.
    with (CACHE / 'mirror.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another local CI mirror is running; wait for it to finish.')
        require_version(['pnpm', '--version'], '11.24.0')
        if any(n in names for n in ('seat-checkout', 'ticket-preview-and-delivery')):
            require_version(['deno', '--version'], '2.9.0')
        browser_jobs = {'seat-checkout', 'web-startup', 'client-contract'}
        if browser_jobs.intersection(names):
            require_version(['agent-browser', '--version'], '0.39.4')
            browser = shutil.which('google-chrome') or shutil.which('chromium')
            if not browser and sys.platform == 'darwin':
                browser = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
            if not browser or not Path(browser).is_file():
                raise RuntimeError('Install Chrome/Chromium before running browser lanes.')
            os.environ['AGENT_BROWSER_EXECUTABLE_PATH'] = browser
            os.environ['CHROME_EXECUTABLE'] = browser
        if 'image-contract' in names:
            venv = CACHE / 'python'
            call([sys.executable, '-m', 'venv', str(venv)])
            call([str(venv / 'bin/pip'), '--quiet', 'install', 'PyYAML==6.0.3'])
            os.environ['PATH'] = str(venv / 'bin') + os.pathsep + os.environ['PATH']
        database = 'seat-checkout' in names
        if database:
            require_version(['supabase', '--version'], '2.111.0')
            workdir = CACHE / 'database'
            configdir = workdir / 'supabase'
            configdir.mkdir(parents=True, exist_ok=True)
            config = (ROOT / 'automation/local_db/supabase/config.toml').read_text()
            config = config.replace('festapp-db-tests-pg15', 'festapp-ci-mirror').replace('55432', '55442').replace('55430', '55440')
            (configdir / 'config.toml').write_text(config)
            os.environ.update(FESTAPP_LOCAL_DB_WORKDIR=str(workdir), FESTAPP_LOCAL_DB_PROJECT_ID='festapp-ci-mirror', FESTAPP_LOCAL_DB_PORT='55442')
            url = 'postgresql://postgres:postgres@127.0.0.1:55442/postgres?sslmode=disable'
            os.environ.update(DATABASE_URL=url, SEAT_CHECKOUT_DATABASE_URL=url)
        receipt = {'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                   'dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
                   'platform': sys.platform, 'jobs': [], 'complete': False}
        started = time.monotonic()
        try:
            for name in names:
                log = CACHE / f'{name}.log'
                before = time.monotonic()
                print(f'Local CI: {name} (log: {log})', flush=True)
                version = CONTRACT['jobs'][name]['node']
                with log.open('w') as output:
                    result = subprocess.run(['pnpm', f'--package=node@{version}', 'dlx', 'node',
                        'automation/ci/node-runtime.mjs', 'python3', 'automation/ci/run.py', 'lane', name],
                        cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
                receipt['jobs'].append({'name': name, 'seconds': round(time.monotonic()-before, 2), 'exitCode': result.returncode, 'log': str(log)})
                if result.returncode:
                    print('\n'.join(log.read_text().splitlines()[-60:]), file=sys.stderr)
                    raise RuntimeError(f'Local CI failed: {name}. Full log: {log}')
                print(f'PASS {name}: {time.monotonic()-before:.1f}s', flush=True)
            receipt['complete'] = True
        finally:
            receipt['seconds'] = round(time.monotonic()-started, 2)
            (CACHE / 'latest.json').write_text(json.dumps(receipt, indent=2)+'\n')
            if database:
                call(['bash', 'automation/bootstrap_local_db.sh', '--stop'], stdout=subprocess.DEVNULL)
        print(f'Local CI passed. Receipt: {CACHE / "latest.json"}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['local', 'lane', 'step', 'list'])
    parser.add_argument('names', nargs='*')
    args = parser.parse_args()
    if args.mode == 'list':
        print('\n'.join(CONTRACT['jobs']))
    elif args.mode == 'step':
        step(args.names[0])
    elif args.mode == 'lane':
        lane(args.names[0])
    else:
        names = args.names or list(CONTRACT['jobs'])
        for name in names:
            if name not in CONTRACT['jobs']:
                parser.error(f'Unknown lane: {name}')
        local(names)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, KeyError, IndexError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
