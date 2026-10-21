"""Offline wrapper contracts; fake executables never launch Flutter or a backend."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[2]


class WrapperContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ('automation', 'web_client', 'bin'):
            (self.root/name).mkdir()
        for name in ('test_all.sh', 'test_all.py', 'test_all_commands.json'):
            shutil.copy(REPO/'automation'/name, self.root/'automation'/name)
        (self.root/'automation/test_client.sh').write_text('test "$PWD" = "$EXPECTED_ROOT" || exit 29\necho client >> "$CALLS"\nexit "${CLIENT_CODE:-0}"\n')
        self.env = {**os.environ, 'PATH': str(self.root/'bin')+os.pathsep+os.environ['PATH'],
                    'DATABASE_URL': '', 'SUPABASE_URL': '', 'CALLS': str(self.root/'calls'),
                    'FESTAPP_ALL_RESULTS': str(self.root/'results'), 'EXPECTED_ROOT': str(self.root)}
        for name, body in [('pnpm', 'echo web >> "$CALLS"\nexit "${WEB_CODE:-0}"'), ('pg_isready', 'exit 1')]:
            self.fake(name, body)

    def fake(self, name, body):
        path = self.root/'bin'/name
        path.write_text('#!/bin/sh\n'+body+'\n')
        path.chmod(0o755)

    def run_wrapper(self, *lanes):
        return subprocess.run(['bash', str(self.root/'automation/test_all.sh'), *lanes],
                              cwd='/tmp', env=self.env, capture_output=True, text=True, timeout=15)

    def summary(self):
        return json.loads((self.root/'results/summary.json').read_text())

    def test_failure_aggregation_and_later_lanes(self):
        for web, client in [('0','0'), ('17','0'), ('0','23'), ('17','23')]:
            self.env.update(WEB_CODE=web, CLIENT_CODE=client)
            (self.root/'calls').unlink(missing_ok=True)
            run = self.run_wrapper('web', 'flutter')
            self.assertEqual(run.returncode, int(web != '0' or client != '0'), run.stderr)
            self.assertEqual((self.root/'calls').read_text().splitlines(), ['web', 'client'])
            rows = self.summary()['lanes']
            self.assertEqual([r['status'] for r in rows], ['PASS' if web == '0' else 'FAIL', 'PASS' if client == '0' else 'FAIL'])
            self.assertTrue(all(r['seconds'] >= 0 for r in rows))
            self.assertGreaterEqual(self.summary()['seconds'], sum(r['seconds'] for r in rows))

    def test_missing_selected_prerequisites_are_incomplete_and_nonzero(self):
        shutil.rmtree(self.root/'web_client')
        self.assertEqual(self.run_wrapper('web', 'db', 'integration', 'flutter').returncode, 1)
        rows = self.summary()['lanes']
        self.assertFalse(self.summary()['complete'])
        self.assertEqual(rows[0]['status'], 'INCOMPLETE')
        self.assertEqual(next(r for r in rows if r['name']=='flutter')['status'], 'PASS')

    def test_required_nonexecutable_automation_uses_interpreter_and_continues(self):
        good = self.root/'good.sh'
        good.write_text('echo required >> "$CALLS"\n')
        (self.root/'automation/test_all_commands.json').write_text(json.dumps([
            ['bash', 'missing.sh'], ['bash', str(good)]]))
        self.assertEqual(self.run_wrapper('automation').returncode, 1)
        self.assertEqual((self.root/'calls').read_text().strip(), 'required')

    def test_output_and_summary_do_not_log_database_credentials(self):
        self.env['DATABASE_URL'] = 'postgresql://user:secret-sentinel@localhost/test'
        result = self.run_wrapper('web')
        self.assertEqual(result.returncode, 0)
        self.assertNotIn('secret-sentinel', result.stdout+result.stderr+json.dumps(self.summary()))

    def test_argument_list_preserves_shell_metacharacters(self):
        value = 'literal;$(touch SHOULD_NOT_EXIST)'
        (self.root/'automation/test_all_commands.json').write_text(json.dumps([
            [sys.executable, '-c', 'import sys; print(sys.argv[1])', value]]))
        result = self.run_wrapper('automation')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(value, result.stdout)
        self.assertFalse((self.root/'SHOULD_NOT_EXIST').exists())

    def test_exited_parent_cannot_leave_owned_background_child(self):
        child = self.root/'background.py'
        pidfile = self.root/'background.pid'
        child.write_text('import signal,time\nsignal.signal(signal.SIGTERM, lambda *_: None)\ntime.sleep(60)\n')
        self.fake('pnpm', f'{sys.executable} {child} &\necho $! > {pidfile}')
        result = self.run_wrapper('web')
        self.assertEqual(result.returncode, 0, result.stderr)
        pid = int(pidfile.read_text())
        deadline = time.monotonic()+2
        while time.monotonic()<deadline:
            try: os.kill(pid, 0)
            except ProcessLookupError: break
            time.sleep(.02)
        else: self.fail(f'Exited parent left owned child: {pid}')

    def test_timeout_and_interrupt_reap_grandchild_even_after_parent_exits(self):
        # Exercise the production lifecycle with a short injected web deadline.
        wrapper = self.root/'automation/test_all.py'
        wrapper.write_text(wrapper.read_text().replace("ROOT/'web_client', 60", "ROOT/'web_client', 1.5"))
        for interrupt in (False, True):
            with self.subTest(interrupt=interrupt):
                pidfile = self.root/'pid'
                pidfile.unlink(missing_ok=True)
                child = self.root/'child.py'
                child.write_text('import signal,time\nsignal.signal(signal.SIGTERM, lambda *_: None)\ntime.sleep(60)\n')
                self.fake('pnpm', f'{sys.executable} {child} &\necho $! > {pidfile}\n' + ('wait' if interrupt else 'sleep 5'))
                process = subprocess.Popen(['bash', str(self.root/'automation/test_all.sh'), 'web'],
                                           env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                self.addCleanup(lambda: process.kill() if process.poll() is None else None)
                deadline = time.monotonic()+5
                while not pidfile.exists() and time.monotonic()<deadline:
                    time.sleep(.01)
                self.assertTrue(pidfile.exists())
                if interrupt:
                    process.send_signal(signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=8)
                self.assertEqual(process.returncode, 143 if interrupt else 1, stdout+stderr)
                pid = int(pidfile.read_text())
                deadline = time.monotonic()+2
                while time.monotonic()<deadline:
                    try: os.kill(pid, 0)
                    except ProcessLookupError: break
                    time.sleep(.02)
                else: self.fail(f'Owned grandchild survived: {pid}')
