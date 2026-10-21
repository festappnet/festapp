"""Broad test wrapper: explicit lane outcomes and owned process-group lifetime."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent


def stop_group(process):
    # Descendants can outlive their immediate parent, so always signal the group.
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            return
        except PermissionError:
            if process.poll() is None:
                raise
        if sig == signal.SIGTERM:
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
    process.wait()


def main():
    allowed = ('web', 'db', 'flutter', 'integration', 'automation')
    selected = set(sys.argv[1:] or allowed)
    if selected - set(allowed):
        print('Usage: automation/test_all.sh [web|db|flutter|integration|automation]', file=sys.stderr)
        return 1
    output = Path(os.environ.get('FESTAPP_ALL_RESULTS') or tempfile.mkdtemp(prefix='festapp-all-'))
    output.mkdir(parents=True, exist_ok=True)
    expected = selected | ({'deno'} if selected & {'db', 'integration'} else set())
    receipts = []
    current = None
    started = time.monotonic()

    def save():
        complete = ({row['name'] for row in receipts} == expected
                    and not any(row['status'] in ('INCOMPLETE', 'INTERRUPTED') for row in receipts))
        summary = {'lanes': receipts, 'selected': sorted(expected),
                   'seconds': time.monotonic() - started,
                   'success': complete and all(row['status'] in ('PASS', 'SKIP') for row in receipts),
                   'complete': complete}
        (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        return summary

    def cancel(signum, _frame):
        if current is not None:
            stop_group(current)
        receipts.append({'name': 'wrapper', 'status': 'INTERRUPTED', 'seconds': time.monotonic()-started})
        save()
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)

    def run(command, cwd=ROOT, timeout=None):
        nonlocal current
        if not cwd.is_dir() or not shutil.which(command[0]):
            return 'INCOMPLETE', None
        try:
            current = subprocess.Popen(command, cwd=cwd, start_new_session=True)
            try:
                code = current.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                stop_group(current)
                return 'FAIL', 124
            finally:
                # Reap descendants even if the immediate child exited first.
                stop_group(current)
            return ('PASS' if code == 0 else 'FAIL'), code
        except OSError:
            return 'INCOMPLETE', None
        finally:
            current = None

    def lane(name, commands, missing=None):
        begin = time.monotonic()
        status, code = ('INCOMPLETE', None) if missing else ('PASS', 0)
        if missing:
            print(f'{name}: required prerequisite missing: {missing}', flush=True)
        else:
            for command, cwd, timeout in commands:
                result, result_code = run(command, cwd, timeout)
                if result != 'PASS':
                    if status != 'INCOMPLETE':
                        status, code = result, result_code
        row = {'name': name, 'status': status, 'exitCode': code, 'seconds': time.monotonic()-begin}
        receipts.append(row)
        print(f'{name}: {status} ({row["seconds"]:.2f}s)', flush=True)
        save()

    def command(argv, cwd=ROOT, timeout=None):
        return argv, cwd, timeout

    database = os.environ.get('DATABASE_URL')
    if not database and selected & {'db', 'integration'} and shutil.which('pg_isready'):
        probe = subprocess.run(['pg_isready', '-h', '127.0.0.1', '-p', '55432', '-d', 'postgres'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if probe.returncode == 0:
            os.environ['DATABASE_URL'] = 'postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable'
            database = True
    if 'web' in selected:
        lane('web', [command(['pnpm', 'test'], ROOT/'web_client', 60)])
    if 'db' in selected:
        runner = ROOT/'web_client/scripts/run_db_tests.js'
        lane('db', [command(['node', str(runner)])],
             missing='DATABASE_URL or DB runner' if not database or not runner.is_file() else None)
    if 'flutter' in selected:
        lane('flutter', [command(['bash', str(ROOT/'automation/test_client.sh'), 'all'])],
             missing='client runner' if not (ROOT/'automation/test_client.sh').is_file() else None)
    if selected & {'db', 'integration'}:
        # Both test_*.ts and *_test.ts are established executable test contracts.
        tests = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'supabase/functions').rglob('*.ts')
                       if (p.name.startswith('test_') or p.name.endswith('_test.ts')) and 'node_modules' not in p.parts)
        lane('deno', [
            command(['node', 'automation/hetzner-supabase/merge/edge-function-test-coverage.mjs']),
            command(['deno', 'run', '--frozen', '--lock=supabase/functions/deno.lock', '--allow-read',
                     'automation/generate_email_preview_examples.ts', '--check']),
            command(['deno', 'test', '--frozen', '--lock=supabase/functions/deno.lock',
                     '--allow-env', '--allow-net', '--allow-read', *tests])],
            missing='Deno or discovered tests' if not shutil.which('deno') or not tests else None)
    if 'integration' in selected:
        worker = ROOT/'workers/image-worker'
        lane('integration', [command(['pnpm', 'run', 'test:integration'], worker)],
             missing='DATABASE_URL or image-worker dependencies' if not database or not (worker/'node_modules/.bin/vitest').is_file() else None)
    if 'automation' in selected:
        manifest = ROOT/'automation/test_all_commands.json'
        commands = json.loads(manifest.read_text()) if manifest.is_file() else []
        lane('automation', [command(argv) for argv in commands],
             missing='automation command manifest' if not manifest.is_file() else None)
    summary = save()
    print(f'Summary: {output / "summary.json"}', flush=True)
    return 0 if summary['success'] else 1


if __name__ == '__main__':
    sys.exit(main())
