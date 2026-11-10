"""Release admission: actual CLI/git boundary plus check-run policy cases."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import release_gate as gate

SHA = 'a' * 40


def check(name, conclusion='success', status='completed', id=1, sha=SHA):
    return dict(name=name, conclusion=conclusion, status=status, id=id,
                head_sha=sha, app={'slug': 'github-actions'})


class CheckPolicyTest(unittest.TestCase):
    def test_every_required_job_must_succeed(self):
        self.assertEqual(gate.problems([check('a'), check('b')], ['a', 'b'], SHA), [])
        for outcome in ['failure', 'cancelled', 'skipped', 'neutral', 'timed_out', None]:
            with self.subTest(outcome=outcome):
                self.assertTrue(gate.problems([check('a', outcome)], ['a'], SHA))

    def test_missing_pending_and_wrong_head_are_not_passes(self):
        for checks in [[], [check('a', status='in_progress')], [check('a', sha='b'*40)]]:
            self.assertTrue(gate.problems(checks, ['a'], SHA))

    def test_latest_rerun_wins_even_if_older_attempt_passed(self):
        self.assertTrue(gate.problems([check('a'), check('a', 'failure', id=2)], ['a'], SHA))
        self.assertFalse(gate.problems([check('a', 'failure'), check('a', id=2)], ['a'], SHA))

    def test_unlisted_failed_check_also_blocks(self):
        self.assertTrue(gate.problems([check('a'), check('new-job', 'failure')], ['a'], SHA))

    def test_failed_runtime_drift_monitor_does_not_block_its_repair(self):
        drift = check('measurement-runtime-drift', 'failure')
        self.assertTrue(gate.problems([check('a'), drift], ['a'], SHA))
        drift['_workflow_path'] = '.github/workflows/other.yml'
        self.assertTrue(gate.problems([check('a'), drift], ['a'], SHA))
        drift['_workflow_path'] = '.github/workflows/measurement-runtime-drift.yml'
        self.assertEqual(gate.problems([check('a'), drift], ['a'], SHA), [])
        self.assertTrue(gate.problems([check('a'), drift], ['a', 'measurement-runtime-drift'], SHA))

    def test_workflow_identity_comes_from_matching_suite(self):
        drift = check('measurement-runtime-drift', 'failure')
        drift['check_suite'] = {'id': 42}
        for path, expected in [('.github/workflows/other.yml', True),
                               ('.github/workflows/measurement-runtime-drift.yml', False)]:
            with patch.object(gate.subprocess, 'check_output', return_value=json.dumps({
                    'workflow_runs': [{'check_suite_id': 42, 'path': path}]})):
                gate.identify_informational_workflows([drift], 'fixture/repo')
            self.assertEqual(bool(gate.problems([drift], [], SHA)), expected)

    def test_other_app_cannot_supply_missing_github_job(self):
        fake = check('a')
        fake['app'] = {'slug': 'unrelated'}
        self.assertTrue(gate.problems([fake], ['a'], SHA))


class ReleaseCliTest(unittest.TestCase):
    def test_real_git_source_binding_and_prebuilt_deploy_failure_boundary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'automation/ci').mkdir(parents=True)
            for name in ['automation/ci/release_gate.py', 'automation/ci/selection.py',
                         'automation/ci/inputs.json', 'automation/deploy_direct.sh']:
                (root / name).write_bytes((gate.ROOT / name).read_bytes())
            (root / 'automation/ci/checks.json').write_text(json.dumps({'jobs': {'seat-checkout': {}}}))
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, text=True, stderr=subprocess.DEVNULL).strip()
            git('init', '-q')
            git('config', 'user.email', 'test@example.invalid')
            git('config', 'user.name', 'Release fixture')
            (root / '.gitignore').write_text('/bin/\n/checks.json\n/upload-must-not-run\n')
            git('add', '.')
            git('commit', '-qm', 'canonical source')
            sha = git('rev-parse', 'HEAD')
            (root / 'automation/tenant-overlay.json').write_text(json.dumps({'baseMainSha': sha}))
            git('add', '.')
            git('commit', '-qm', 'tenant overlay')
            with patch.object(gate, 'ROOT', root):
                self.assertEqual(gate.release_source(), sha)
            bin_dir = root / 'bin'
            bin_dir.mkdir()
            fake_gh = bin_dir / 'gh'
            fake_gh.write_text('#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\nprint(json.dumps({"nameWithOwner":"fixture/repo"}) if sys.argv[1]=="repo" else Path("checks.json").read_text())\n')
            fake_gh.chmod(0o755)
            marker = root / 'upload-must-not-run'
            fake_pnpm = bin_dir / 'pnpm'
            fake_pnpm.write_text('#!/bin/sh\ntouch "'+str(marker)+'"\nexit 99\n')
            fake_pnpm.chmod(0o755)
            env = {**os.environ, 'PATH': str(bin_dir)+os.pathsep+os.environ['PATH']}
            response = root / 'checks.json'
            response.write_text(json.dumps([{'check_runs': [check('seat-checkout', sha=sha)]}]))
            command = ['python3', 'automation/ci/release_gate.py']
            result = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            (root / 'uncommitted-source.js').write_text('new source')
            result = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('clean checkout', result.stderr)
            (root / 'uncommitted-source.js').unlink()
            response.write_text(json.dumps([{'check_runs': [check('seat-checkout', 'failure', sha=sha)]}]))
            result = subprocess.run(['bash', 'automation/deploy_direct.sh', '--skip-build', '--wrangler-oauth'], cwd=root, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Release blocked: CI is not green', result.stderr)
            self.assertFalse(marker.exists())
            # A tenant cannot weaken its required job set after source admission.
            (root / 'automation/ci/checks.json').write_text('{"jobs": {}}')
            git('add', 'automation/ci/checks.json')
            git('commit', '-qm', 'forged tenant policy')
            with patch.object(gate, 'ROOT', root):
                with self.assertRaisesRegex(RuntimeError, 'match canonical main'):
                    gate.release_source()


if __name__ == '__main__':
    unittest.main()
