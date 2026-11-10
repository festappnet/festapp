"""CI input invalidation and trusted executed-check reuse boundaries."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import selection

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = json.loads((ROOT / 'automation/ci/checks.json').read_text())
POLICY = json.loads((ROOT / selection.POLICY).read_text())
SHA = 'a' * 40
BASE = 'b' * 40
URL = 'https://github.com/fixture/repo/actions/runs/123'


class InputTreeTest(unittest.TestCase):
    def test_real_git_tree_invalidates_content_modes_names_deletions_and_unknowns(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL).decode().strip()
            git('init', '-q')
            git('config', 'user.email', 'test@example.invalid')
            git('config', 'user.name', 'CI input fixture')
            def commit(path, content):
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content)
                git('add', '.')
                git('commit', '-qm', path)
                return git('rev-parse', 'HEAD')
            baseline = commit('lib/screen.dart', 'original')
            with patch.object(selection, 'ROOT', root):
                initial = {lane: selection.fingerprint(baseline, lane, POLICY) for lane in CONTRACT['jobs']}
                ui = commit('lib/screen.dart', 'changed')
                self.assertEqual(selection.fingerprint(ui, 'wix-checkout-compatibility', POLICY), initial['wix-checkout-compatibility'])
                self.assertNotEqual(selection.fingerprint(ui, 'navigation-interactions', POLICY), initial['navigation-interactions'])
                documentation = commit('docs/guide.md', 'Documentation only')
                for lane in CONTRACT['jobs']:
                    self.assertEqual(selection.fingerprint(documentation, lane, POLICY),
                                     selection.fingerprint(ui, lane, POLICY))
                for path in ['packages/festapp_core/lib/rules.dart', 'packages/festapp_core/pubspec.lock',
                             'supabase/functions/_shared/ticket-assets/font.ttf', 'test/widgets/example.dart',
                             'automation/ci/selection.py', 'automation/project.conf', 'pubspec.lock',
                             'packages/new_unknown_package/file', 'new-unknown-file']:
                    with self.subTest(path=path):
                        head = commit(path, 'input')
                        self.assertNotEqual(selection.fingerprint(head, 'client-contract', POLICY),
                                            selection.fingerprint(git('rev-parse', 'HEAD^'), 'client-contract', POLICY))
                # Renames, mode changes and deleted inputs must also invalidate.
                before = selection.fingerprint(head, 'client-contract', POLICY)
                git('mv', 'lib/screen.dart', 'lib/renamed.dart')
                git('commit', '-qm', 'rename')
                renamed = selection.fingerprint('HEAD', 'client-contract', POLICY)
                self.assertNotEqual(before, renamed)
                (root / 'lib/renamed.dart').chmod(0o755)
                git('add', 'lib/renamed.dart')
                git('commit', '-qm', 'executable mode')
                mode = selection.fingerprint('HEAD', 'client-contract', POLICY)
                self.assertNotEqual(renamed, mode)
                git('rm', 'lib/renamed.dart')
                git('commit', '-qm', 'delete')
                self.assertNotEqual(mode, selection.fingerprint('HEAD', 'client-contract', POLICY))

    def test_shared_contracts_and_new_packages_are_never_excluded(self):
        self.assertTrue(all(set(component['jobs']) <= set(CONTRACT['jobs']) for component in POLICY['components']))
        for path in ['packages/festapp_contracts/email.json', 'packages/new_package/pubspec.yaml',
                     '.github/workflows/new.yml', 'automation/ci/checks.json']:
            self.assertFalse(any(path.startswith(prefix) for c in POLICY['components'] for prefix in c['prefixes']))


class ReusePolicyTest(unittest.TestCase):
    def setUp(self):
        self.run = dict(id=123, head_sha=BASE, head_branch='main', event='push', status='completed',
                        conclusion='success', path='.github/workflows/image-service-regressions.yml',
                        updated_at=datetime.now(timezone.utc).isoformat(), html_url=URL)
        self.check = dict(id=456, head_sha=BASE, name='image-contract', status='completed',
                          conclusion='success', app={'slug': 'github-actions'}, html_url=URL+'/job/456')
        self.job = dict(run_id=123, steps=[dict(name='All lane tests executed', conclusion='success')])

    def evaluate(self, fingerprint=None, runs=None):
        def api(repository, endpoint, paginate=False):
            if endpoint.startswith('actions/workflows/'):
                return {'workflow_runs': runs if runs is not None else [self.run]}
            if endpoint.startswith('commits/'):
                return [{'check_runs': [self.check]}]
            return self.job
        with patch.object(selection, 'git', return_value=(SHA+'\n'+BASE+'\n').encode()), \
             patch.object(selection, 'fingerprint', side_effect=fingerprint or (lambda *args: 'same-inputs')), \
             patch.object(selection, 'api', side_effect=api):
            return selection.decide('image-contract', 'push', None, 'refs/heads/main', SHA,
                                    'fixture/repo', CONTRACT, POLICY)

    def test_reuse_requires_executed_main_tests_and_identical_inputs(self):
        result = self.evaluate()
        self.assertFalse(result['run'])
        self.assertEqual(result['source'], BASE)
        self.assertTrue(self.evaluate(fingerprint=lambda sha, *args: sha)['run'])

    def test_pending_failed_skipped_foreign_and_wrong_lineage_evidence_runs_tests(self):
        for field, value in [('status','in_progress'), ('conclusion','failure'),
                             ('conclusion','skipped'), ('head_branch','feature'),
                             ('head_sha','c'*40), ('event','pull_request'),
                             ('path','.github/workflows/other.yml'),
                             ('updated_at',(datetime.now(timezone.utc)-timedelta(days=8)).isoformat())]:
            with self.subTest(field=field, value=value):
                old = self.run[field]
                self.run[field] = value
                self.assertTrue(self.evaluate()['run'])
                self.run[field] = old
        for field, value in [('conclusion','skipped'), ('status','in_progress'),
                             ('head_sha',SHA), ('html_url',URL+'/different/456'),
                             ('app',{'slug':'foreign'})]:
            with self.subTest(check=field):
                old = self.check[field]
                self.check[field] = value
                self.assertTrue(self.evaluate()['run'])
                self.check[field] = old

    def test_reuse_cannot_refresh_its_own_expiry_or_be_mistaken_for_execution(self):
        for steps in [[], [dict(name='All lane tests executed', conclusion='skipped')],
                      [dict(name='Post actions/checkout@v4', conclusion='success')]]:
            self.job['steps'] = steps
            self.assertTrue(self.evaluate()['run'])
        self.job['steps'] = [dict(name='All lane tests executed', conclusion='success')]
        self.job['run_id'] = 999
        self.assertTrue(self.evaluate()['run'])

    def test_failed_latest_matching_run_cannot_fall_back_to_older_green(self):
        older = dict(self.run)
        self.run['conclusion'] = 'failure'
        self.assertTrue(self.evaluate(runs=[self.run, older])['run'])

    def test_missing_history_or_api_failure_runs_tests(self):
        for error in [OSError('offline'), ValueError('invalid JSON'), KeyError('bad data'),
                      subprocess.CalledProcessError(1, ['gh','api'])]:
            with patch.object(selection, 'reusable', side_effect=error):
                result = selection.decide('image-contract','push',None,'refs/heads/main',SHA,
                                          'fixture/repo',CONTRACT,POLICY)
                self.assertTrue(result['run'])

    def test_review_transition_manual_dispatch_and_merge_queue_force_full_verification(self):
        with patch.object(selection, 'reusable') as reuse:
            for event, action, ref in [('pull_request','ready_for_review','refs/pull/1/merge'),
                                       ('workflow_dispatch',None,'refs/heads/main'),
                                       ('merge_group',None,'refs/heads/gh-readonly-queue/main/test')]:
                result = selection.decide('image-contract',event,action,ref,SHA,'fixture/repo',CONTRACT,POLICY)
                self.assertTrue(result['run'])
            reuse.assert_not_called()

    def test_pr_updates_can_reuse_only_proven_unchanged_main_inputs(self):
        with patch.object(selection, 'reusable', return_value={'run':False}) as reuse:
            result = selection.decide('image-contract','pull_request','synchronize','refs/pull/1/merge',
                                      SHA,'fixture/repo',CONTRACT,POLICY)
            self.assertFalse(result['run'])
            reuse.assert_called_once()


if __name__ == '__main__':
    unittest.main()
