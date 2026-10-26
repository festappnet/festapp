"""Ensure GitHub and the local mirror execute the same ordered checks."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch
import tempfile
import subprocess
import fcntl
import run as runner
import yaml

ROOT = Path(__file__).resolve().parents[2]


class MirrorContractTest(unittest.TestCase):
    def test_jobs_share_every_check_in_order(self):
        contract = json.loads((ROOT / 'automation/ci/checks.json').read_text())
        referenced = []
        for name, lane in contract['jobs'].items():
            with self.subTest(job=name):
                workflow = yaml.safe_load((ROOT / '.github/workflows' / lane['workflow']).read_text())
                steps = workflow['jobs'][name]['steps']
                actual = []
                for step in steps:
                    if 'run' not in step:
                        continue
                    run = step['run'].strip()
                    prefix = 'python3 automation/ci/run.py step '
                    if run.startswith(prefix):
                        actual.append(run.removeprefix(prefix))
                    else:
                        # Only runner/SDK provisioning belongs outside the contract.
                        self.assertTrue(any(marker in run for marker in (
                            'GITHUB_OUTPUT', 'dart pub global activate fvm',
                            'sudo apt-get', 'bash automation/ci/browser.sh',
                        )), f'Unmirrored command in {name}: {run}')
                self.assertEqual(actual, lane['steps'])
                referenced.extend(actual)
                for step in steps:
                    if step.get('uses', '').startswith('actions/setup-node@'):
                        self.assertEqual(step['with']['node-version'], lane['node'])
        self.assertCountEqual(referenced, contract['steps'])

    def test_webview_release_gate_is_shared(self):
        contract = json.loads((ROOT / 'automation/ci/checks.json').read_text())
        self.assertEqual(contract['steps']['web-startup'], 'bash automation/test_web_startup.sh')
        self.assertIn('bash automation/test_web_startup.sh', (ROOT / 'automation/build_web_bundle.sh').read_text())


class RunnerSafetyTest(unittest.TestCase):
    def test_shell_failure_stops_following_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / 'must-not-exist'
            contract = {'steps': {'failure': f'exit 17\ntouch "{marker}"'}}
            with patch.object(runner, 'CONTRACT', contract):
                with self.assertRaises(subprocess.CalledProcessError) as error:
                    runner.step('failure')
            self.assertEqual(error.exception.returncode, 17)
            self.assertFalse(marker.exists())

    def test_failed_step_stops_the_lane(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / 'must-not-exist'
            contract = {'jobs': {'fixture': {'steps': ['failure', 'later']}},
                        'steps': {'failure': 'exit 19', 'later': f'touch "{marker}"'}}
            with patch.object(runner, 'CONTRACT', contract):
                with self.assertRaises(subprocess.CalledProcessError):
                    runner.lane('fixture')
            self.assertFalse(marker.exists())

    def test_another_owner_blocks_before_tools_or_database_setup(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            with (cache / 'mirror.lock').open('w') as owner:
                fcntl.flock(owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with patch.object(runner, 'CACHE', cache):
                    with self.assertRaisesRegex(RuntimeError, 'Another local CI mirror'):
                        runner.local(['seat-checkout'])


if __name__ == '__main__':
    unittest.main()
