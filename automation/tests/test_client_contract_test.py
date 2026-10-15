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


class ClientRunnerContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="festapp-runner-contract-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        automation = self.root / "automation"
        automation.mkdir()
        for name in ("test_client.sh", "test_client.py", "client_test_inventory.py"):
            shutil.copy(REPO / "automation" / name, automation)
        (automation / "client_test_inventory.json").write_text('{"moves":{},"cases":[]}')
        for directory in (self.root, self.root / "packages/festapp_core"):
            (directory / ".dart_tool").mkdir(parents=True)
            (directory / ".dart_tool/package_config.json").write_text('{}')
        (self.root / "test_dart").mkdir()
        binary = self.root / "bin"
        binary.mkdir()
        fake = binary / "fvm"
        fake.write_text('''#!/usr/bin/env python3
import json,os,sys,time
if 'run' in sys.argv:
    if os.environ.get('SCHEDULE_DIR'):
        from pathlib import Path
        time.sleep(.1)
        (Path(os.environ['SCHEDULE_DIR']) / 'guard.done').write_text('done')
    sys.exit(1 if os.environ.get('FAIL_GUARD') else 0)
lane = 'flutter' if sys.argv[1] == 'flutter' else 'adapters' if 'test_dart' in sys.argv else 'core'
with open(os.environ['CALLS'], 'a') as f: f.write(lane+'\\n')
if os.environ.get('ARGUMENTS'):
    with open(os.environ['ARGUMENTS'], 'a') as f: f.write(json.dumps(sys.argv)+'\\n')
if os.environ.get('SCHEDULE_DIR'):
    from pathlib import Path
    schedule = Path(os.environ['SCHEDULE_DIR'])
    if lane == 'flutter':
        if not all((schedule / (name+'.done')).exists() for name in ['core','adapters','guard']): sys.exit(23)
    else:
        time.sleep(.1)
        (schedule / (lane+'.done')).write_text('done')
fail = lane in os.environ.get('FAIL_LANES','').split(',')
print(json.dumps({'type':'done','success':not fail,'time':1}))
sys.exit(1 if fail else 0)
''')
        fake.chmod(0o755)
        self.env = {**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"],
                    "CALLS": str(self.root / "calls"), "FESTAPP_CLIENT_RESULTS": str(self.root / "results")}

    def run_client(self, *args, failures=""):
        return subprocess.run(["bash", str(self.root / "automation/test_client.sh"), *args],
                              cwd="/tmp", env={**self.env, "FAIL_LANES": failures},
                              capture_output=True, text=True, timeout=15)

    def test_all_waits_for_every_lane_and_propagates_each_failure(self):
        for failures in ("", "core", "flutter", "adapters", "core,flutter,adapters"):
            with self.subTest(failures=failures):
                (self.root / "calls").unlink(missing_ok=True)
                result = self.run_client(failures=failures)
                self.assertEqual(result.returncode == 0, not failures, result.stderr)
                self.assertCountEqual((self.root / "calls").read_text().splitlines(), ["core", "flutter", "adapters"])

    def test_concurrency_is_bounded_by_default_and_explicitly_overridable(self):
        self.env.pop('FESTAPP_CLIENT_CONCURRENCY', None)
        result = self.run_client()
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = json.loads((self.root / 'results/summary.json').read_text())
        self.assertGreaterEqual(summary['concurrency'], 1)
        self.assertLessEqual(summary['concurrency'], 2)
        arguments = self.root / 'arguments.jsonl'
        self.env.update(FESTAPP_CLIENT_CONCURRENCY='3', ARGUMENTS=str(arguments))
        result = self.run_client()
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = [json.loads(line) for line in arguments.read_text().splitlines()]
        self.assertEqual(len(commands), 3)
        self.assertTrue(all('--concurrency=3' in command for command in commands))
        for invalid in ('0', '-1', 'many'):
            self.env['FESTAPP_CLIENT_CONCURRENCY'] = invalid
            result = self.run_client()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('positive integer', result.stderr)

    def test_flutter_waits_for_dart_vm_memory_phase_even_after_failure(self):
        directory = self.root / 'schedule'
        directory.mkdir()
        self.env['SCHEDULE_DIR'] = str(directory)
        for failures in ('', 'core,adapters'):
            for path in directory.iterdir():
                path.unlink()
            result = self.run_client(failures=failures)
            self.assertEqual(result.returncode == 0, not failures, result.stderr)
            summary = json.loads((self.root / 'results/summary.json').read_text())
            self.assertTrue(summary['flutter']['success'])
            self.assertEqual(summary['schedule'], 'Dart+VM then Flutter')

    def test_architecture_failure_is_not_masked_by_passing_test_lanes(self):
        self.env['FAIL_GUARD'] = '1'
        result = self.run_client()
        self.assertNotEqual(result.returncode, 0)
        summary = json.loads((self.root / 'results/summary.json').read_text())
        self.assertFalse(summary['architectureSuccess'])
        self.assertTrue(all(summary[lane]['success'] for lane in ['core', 'adapters', 'flutter']))

    def test_partial_mode_is_explicit(self):
        result = self.run_client("core")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PARTIAL core", result.stdout)
        self.assertEqual((self.root / "calls").read_text(), "core\n")

    def test_unknown_argument_and_missing_dependencies_fail(self):
        self.assertNotEqual(self.run_client("unknown").returncode, 0)
        (self.root / "packages/festapp_core/.dart_tool/package_config.json").unlink()
        self.assertNotEqual(self.run_client().returncode, 0)

    def test_missing_fvm_fails_without_system_sdk_fallback(self):
        binary = self.root / 'only-system-tools'
        binary.mkdir()
        for name, target in [('bash', shutil.which('bash')), ('python3', sys.executable),
                             ('dirname', shutil.which('dirname'))]:
            (binary / name).symlink_to(target)
        result = subprocess.run([str(binary / 'bash'), str(self.root / 'automation/test_client.sh')],
                                env={**self.env, 'PATH': str(binary)}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('require FVM', result.stderr)

    def test_semantic_inventory_rejects_missing_and_duplicate_executions(self):
        source = 'test/example_cases.dart'
        manifest = self.root / 'automation/client_test_inventory.json'
        manifest.write_text(json.dumps({'moves': {}, 'cases': [[source, 'group behavior', False, 1]]}))
        results = self.root / 'inventory-results'
        results.mkdir()
        events = results / 'flutter.jsonl'
        event = {'type': 'testStart', 'test': {'name': 'group behavior',
                 'url': str(self.root / source), 'metadata': {'skip': False}}}
        command = [sys.executable, str(self.root / 'automation/client_test_inventory.py'), 'check', str(results)]
        events.write_text('')
        self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
        events.write_text(json.dumps(event) + '\n')
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
        events.write_text((json.dumps(event) + '\n') * 2)
        self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)

    def test_grouped_inventory_preserves_multiple_physical_origins(self):
        manifest = self.root / 'automation/client_test_inventory.json'
        sources = ['test/first_test.dart', 'test/second_test.dart']
        moved = ['test/first_cases.dart', 'test/second_cases.dart']
        manifest.write_text(json.dumps({'moves': {case: {'source': source, 'added_group': f'scope{index}', 'entrypoint': 'test/combined_test.dart'} for index, (case, source) in enumerate(zip(moved, sources))},
            'cases': [[source, 'same behavior', False, 1] for source in sources]}))
        results = self.root / 'grouped-results'
        results.mkdir()
        events = [{'type': 'testStart', 'test': {'name': f'scope{index} same behavior',
            'root_url': str(self.root / 'test/combined_test.dart'),
            'url': str(self.root / source), 'metadata': {'skip': False}}}
            for index, source in enumerate(moved)]
        output = results / 'flutter.jsonl'
        command = [sys.executable, str(self.root / 'automation/client_test_inventory.py'), 'check', str(results)]
        output.write_text(''.join(json.dumps(event) + '\n' for event in events))
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
        for event in events:
            event['test']['suiteID'] = 1
            event['test']['root_url'] = str(self.root / 'test/support/wrapper.dart')
            event['test']['url'] = 'package:flutter_test/src/widget_tester.dart'
        suite = {'type': 'suite', 'suite': {'id': 1, 'path': str(self.root / 'test/combined_test.dart')}}
        output.write_text(''.join(json.dumps(event) + '\n' for event in [suite, *events]))
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
        output.write_text(json.dumps(events[0]) + '\n')
        self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)

    def test_nested_registration_uses_explicit_longest_path_and_rejects_collision(self):
        manifest = self.root / 'automation/client_test_inventory.json'
        moves = {
            'test/parent_cases.dart': {'source': 'test/old_parent_test.dart',
                'added_group': 'session parent', 'entrypoint': 'test/session_test.dart'},
            'test/child_cases.dart': {'source': 'test/old_child_test.dart',
                'added_group': 'session parent child', 'entrypoint': 'test/session_test.dart'},
        }
        manifest.write_text(json.dumps({'moves': moves, 'cases': [
            ['test/old_parent_test.dart', 'own behavior', False, 1],
            ['test/old_child_test.dart', 'child behavior', False, 1],
        ]}))
        results = self.root / 'nested-results'
        results.mkdir()
        events = [{'type': 'suite', 'suite': {'id': 1, 'path': str(self.root / 'test/session_test.dart')}}]
        for name in ['session parent own behavior', 'session parent child child behavior']:
            events.append({'type': 'testStart', 'test': {'suiteID': 1, 'name': name,
                'url': 'package:flutter_test/src/widget_tester.dart', 'metadata': {'skip': False}}})
        (results / 'flutter.jsonl').write_text(''.join(json.dumps(event) + '\n' for event in events))
        command = [sys.executable, str(self.root / 'automation/client_test_inventory.py'), 'check', str(results)]
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
        moves['test/conflicting_cases.dart'] = {**moves['test/child_cases.dart'], 'source': 'test/other_test.dart'}
        manifest.write_text(json.dumps({'moves': moves, 'cases': []}))
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Ambiguous documented origin', result.stderr)

    def test_loading_named_widget_case_is_not_synthetic_discovery(self):
        source = 'test/font_picker_test.dart'
        manifest = self.root / 'automation/client_test_inventory.json'
        manifest.write_text(json.dumps({'moves': {}, 'cases': [
            [source, 'loading is visible and disposed response cannot update picker', False, 1],
        ]}))
        results = self.root / 'loading-results'
        results.mkdir()
        events = [
            {'type': 'suite', 'suite': {'id': 1, 'path': str(self.root / source)}},
            {'type': 'testStart', 'test': {'suiteID': 1, 'name': 'loading '+str(self.root / source), 'url': None, 'metadata': {'skip': False}}},
            {'type': 'testStart', 'test': {'suiteID': 1,
                'name': 'loading is visible and disposed response cannot update picker',
                'url': 'package:flutter_test/src/widget_tester.dart',
                'root_url': str(self.root / source), 'metadata': {'skip': False}}},
        ]
        (results / 'flutter.jsonl').write_text(''.join(json.dumps(event) + '\n' for event in events))
        command = [sys.executable, str(self.root / 'automation/client_test_inventory.py'), 'check', str(results)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('1 baseline cases accounted for, 0 added', result.stdout)

    def test_cancellation_reaps_owned_grandchildren(self):
        fake = self.root / "bin/fvm"
        fake.write_text('''#!/usr/bin/env python3
import os,subprocess,sys,time
if 'run' in sys.argv:
    if os.environ.get('SCHEDULE_DIR'):
        from pathlib import Path
        time.sleep(.1)
        (Path(os.environ['SCHEDULE_DIR']) / 'guard.done').write_text('done')
    sys.exit(1 if os.environ.get('FAIL_GUARD') else 0)
child = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(60)'])
with open(os.environ['CALLS'], 'a') as f: f.write(str(child.pid)+'\\n')
time.sleep(60)
''')
        process = subprocess.Popen(["bash", str(self.root / "automation/test_client.sh")],
                                   env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        deadline = time.monotonic() + 5
        calls = self.root / "calls"
        while time.monotonic() < deadline:
            if calls.exists() and len(calls.read_text().splitlines()) == 3:
                break
            time.sleep(.02)
        self.assertTrue(calls.exists(), 'Child processes did not start')
        pids = [int(value) for value in calls.read_text().splitlines()]
        process.send_signal(signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=8)
        self.assertEqual(process.returncode, 143, stdout + stderr)
        for pid in pids:
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)


if __name__ == "__main__":
    unittest.main()
