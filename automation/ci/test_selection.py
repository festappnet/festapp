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

    def test_real_pr_merge_tree_squash_rebase_and_changed_base(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            def git(*args):
                return subprocess.check_output(['git',*args],cwd=root,stderr=subprocess.DEVNULL).decode().strip()
            git('init','-q','-b','main');git('config','user.email','test@example.invalid');git('config','user.name','Merge fixture')
            (root/'lib').mkdir();(root/'lib/screen.dart').write_text('base')
            git('add','.');git('commit','-qm','base');base=git('rev-parse','HEAD')
            git('checkout','-qb','feature');(root/'lib/screen.dart').write_text('feature')
            git('add','.');git('commit','-qm','feature');head=git('rev-parse','HEAD')
            git('checkout','main');git('merge','--no-ff','-m','synthetic merge','feature')
            merge=git('rev-parse','HEAD');git('update-ref','refs/remotes/origin/main',base)
            with patch.object(selection,'ROOT',root):
                selection.validate_checkout(merge,{'event':'pull_request','head_sha':head})
                expected=selection.fingerprint(merge,'navigation-interactions',CONTRACT)
                git('checkout','-qb','squash',base);git('merge','--squash','feature');git('commit','-qm','squash')
                self.assertEqual(selection.fingerprint('HEAD','navigation-interactions',CONTRACT),expected)
                git('checkout','-qb','rebased',base);git('cherry-pick',head)
                self.assertEqual(selection.fingerprint('HEAD','navigation-interactions',CONTRACT),expected)
                # A changed base that contributes source bytes must invalidate.
                (root/'lib/base.dart').write_text('base advanced');git('add','.');git('commit','-qm','changed base')
                self.assertNotEqual(selection.fingerprint('HEAD','navigation-interactions',CONTRACT),expected)
                with self.assertRaises(ValueError):
                    selection.validate_checkout(head,{'event':'pull_request','head_sha':head})

    def test_shared_contracts_and_new_packages_are_never_excluded(self):
        for path in ['packages/festapp_contracts/email.json', 'packages/new_package/pubspec.yaml',
                     '.github/workflows/new.yml', 'automation/ci/checks.json']:
            self.assertEqual(selection.owners(path, CONTRACT), set(CONTRACT['jobs']))

    def test_local_and_hosted_owners_agree_and_ui_has_no_sql_or_wix_consumer(self):
        import run as runner
        for path in ['lib/screen.dart', 'web_client/src/main.js', 'pubspec.lock',
                     'database/functions/example.sql', 'docs/guide.md', 'unknown',
                     'packages/festapp_contracts/payments.json']:
            self.assertEqual(set(runner.affected([path])), selection.owners(path, CONTRACT))
        self.assertNotIn('seat-checkout', selection.owners('lib/screen.dart', CONTRACT))
        self.assertNotIn('wix-checkout-compatibility', selection.owners('lib/screen.dart', CONTRACT))



class ReusePolicyTest(unittest.TestCase):
    def setUp(self):
        import copy
        self.contract = copy.deepcopy(CONTRACT)
        self.source = BASE
        self.run = dict(id=123, run_number=1, run_attempt=1, head_sha=BASE,
                        repository={'id':7}, head_repository={'id':7}, head_branch='main',
                        event='push', status='completed', conclusion='success',
                        path='.github/workflows/image-service-regressions.yml',
                        created_at=datetime.now(timezone.utc).isoformat(), html_url=URL)
        self.job = dict(id=456, run_id=123, run_attempt=1, name='image-contract',
                        status='completed', conclusion='success', html_url=URL+'/job/456',
                        steps=[dict(name='All lane tests executed', conclusion='success')])
        self.tools = dict(RUNNER_OS='Linux',RUNNER_ARCH='X64',ImageOS='ubuntu24',ImageVersion='fixture',
                          node='22.23.3',pnpm='11.24.0',python='fixture')
        self.receipt = dict(complete=True, dirty=False, inputsUnchanged=True,
                            selectedJobs=['image-contract'],
                            units={unit: {'status':'PASS'} for unit in CONTRACT['jobs']['image-contract']['steps']},
                            execution=dict(schemaVersion=1,state='executed',repositoryId=7,runId=123,
                                attempt=1,jobId=456,lane='image-contract',event='push',workflow=self.run['path'],
                                definition='trusted',checkoutSha=BASE,tree='tested-tree',toolchain=self.tools,
                                inputSha256='same-inputs',inventory=CONTRACT['knownTestInputs']))
        self.artifact = dict(id=99,name='ci-image-contract-1',expired=False,
                             workflow_run=dict(id=123,repository_id=7,head_repository_id=7,head_sha=BASE))
        self.missing = False
        self.corrupt = False
        self.parents = ('c'*40)+' '+BASE
        self.checkout_available = True

    def evaluate(self, fingerprint=None, runs=None, definition=None):
        import hashlib, io, zipfile
        archive = io.BytesIO()
        with zipfile.ZipFile(archive,'w') as bundle:
            bundle.writestr('run/receipt.json', json.dumps(self.receipt))
        payload=archive.getvalue()
        self.artifact['digest']='sha256:'+hashlib.sha256(payload).hexdigest()
        def api(repository, endpoint, paginate=False):
            if not endpoint: return {'id':7}
            if endpoint.startswith('actions/workflows/'):
                return {'workflow_runs':runs if runs is not None else [self.run]}
            if endpoint.endswith('/artifacts?per_page=100'):
                return {'artifacts':[] if self.missing else [self.artifact]}
            if '/jobs?' in endpoint:return {'jobs':[self.job]}
            raise AssertionError(endpoint)
        def git(*args):
            if args[:2] == ('rev-parse',BASE+'^{tree}'):return b'tested-tree'
            if args[0]=='show':return self.parents.encode()
            if args[0]=='merge-tree':return b'tested-tree'
            if args[0]=='merge-base':
                if not self.checkout_available: raise ValueError('foreign base')
                return b''
            raise AssertionError(args)
        with patch.object(selection,'git',side_effect=git), \
             patch.object(selection,'ensure_commit'), \
             patch.object(selection,'definition',side_effect=definition or (lambda *args:'trusted')), \
             patch.object(selection,'fingerprint',side_effect=fingerprint or (lambda *args:'same-inputs')), \
             patch.object(selection,'toolchain',return_value=self.tools), \
             patch.object(selection,'api',side_effect=api), \
             patch.object(selection.subprocess,'check_output',return_value=payload+(b'changed' if self.corrupt else b'')):
            return selection.decide('image-contract','push',None,'refs/heads/main',SHA,
                                    'fixture/repo',self.contract,self.contract)

    def test_direct_executed_receipt_and_identical_inputs(self):
        result=self.evaluate()
        self.assertFalse(result['run'])
        self.assertEqual(result['source'],BASE)
        self.assertEqual(result['jobId'],456)
        self.assertTrue(self.evaluate(fingerprint=lambda sha,*args:sha)['run'])

    def test_pr_merge_squash_and_rebase_commit_identity_is_not_input_identity(self):
        self.run['event']='pull_request'
        self.receipt['execution']['event']='pull_request'
        for main_identity in ['merge-result','squash-result','rebase-result']:
            with self.subTest(main=main_identity):
                self.assertFalse(self.evaluate()['run'])
        self.parents=('c'*40)+' '+('d'*40)
        self.assertTrue(self.evaluate()['run'])
        self.parents=('c'*40)+' '+BASE
        self.checkout_available=False
        self.assertTrue(self.evaluate()['run'])

    def test_fork_foreign_repository_attempt_and_expiry_are_rejected(self):
        for field,value in [('head_repository',{'id':8}),('repository',{'id':8}),
                            ('run_attempt',2),('event','pull_request_target'),
                            ('path','.github/workflows/other.yml'),
                            ('created_at',(datetime.now(timezone.utc)-timedelta(days=8)).isoformat())]:
            with self.subTest(field=field):
                old=self.run[field];self.run[field]=value
                self.assertTrue(self.evaluate()['run']);self.run[field]=old

    def test_pending_failure_skipped_and_newer_attempt_never_hide_behind_old_success(self):
        for field,value in [('status','in_progress'),('conclusion','failure'),('conclusion','skipped')]:
            old=self.run[field];self.run[field]=value
            self.assertTrue(self.evaluate()['run']);self.run[field]=old
        older=dict(self.run)
        self.run['run_attempt']=2;self.run['conclusion']='failure'
        self.assertTrue(self.evaluate(runs=[older,self.run])['run'])

    def test_artifact_api_binding_digest_deletion_and_payload(self):
        self.missing=True;self.assertTrue(self.evaluate()['run']);self.missing=False
        self.corrupt=True;self.assertTrue(self.evaluate()['run']);self.corrupt=False
        self.artifact['expired']=True;self.assertTrue(self.evaluate()['run']);self.artifact['expired']=False
        for field in ['id','repository_id','head_repository_id','head_sha']:
            old=self.artifact['workflow_run'][field];self.artifact['workflow_run'][field]='foreign'
            self.assertTrue(self.evaluate()['run']);self.artifact['workflow_run'][field]=old
        self.receipt['execution']['repositoryId']=99
        self.assertTrue(self.evaluate()['run'])

    def test_receipt_cannot_chain_or_forge_workflow_toolchain_inventory_checkout(self):
        for field,value in [('state','reused'),('schemaVersion',0),('definition','old'),
                            ('jobId',99),('attempt',2),('tree','head-tree'),('inventory',[]),
                            ('toolchain',{}),('inputSha256','other'),('event','other')]:
            with self.subTest(field=field):
                old=self.receipt['execution'][field];self.receipt['execution'][field]=value
                self.assertTrue(self.evaluate()['run']);self.receipt['execution'][field]=old
        for field,value in [('complete',False),('dirty',True),('inputsUnchanged',False),('units',{})]:
            old=self.receipt[field];self.receipt[field]=value
            self.assertTrue(self.evaluate()['run']);self.receipt[field]=old
        self.assertTrue(self.evaluate(definition=lambda sha:'changed' if sha==SHA else 'trusted')['run'])
        self.assertTrue(self.evaluate(definition=lambda sha:'changed' if sha==BASE else 'trusted')['run'])

    def test_job_api_requires_final_success_and_real_execution(self):
        for field,value in [('run_id',99),('run_attempt',2),('status','in_progress'),
                            ('conclusion','failure'),('steps',[])]:
            old=self.job[field];self.job[field]=value
            self.assertTrue(self.evaluate()['run']);self.job[field]=old

    def test_api_unavailability_runs_tests(self):
        for error in [OSError('offline'),ValueError('bad JSON'),KeyError('missing'),
                      subprocess.CalledProcessError(1,['gh','api'])]:
            with patch.object(selection,'reusable',side_effect=error):
                self.assertTrue(selection.decide('image-contract','push',None,'refs/heads/main',SHA,
                                                'fixture/repo',CONTRACT,CONTRACT)['run'])

    def test_manual_review_transition_and_merge_queue_execute(self):
        with patch.object(selection,'reusable') as reuse:
            for event,action,ref in [('pull_request','ready_for_review','refs/pull/1/merge'),
                                     ('workflow_dispatch',None,'refs/heads/main'),
                                     ('merge_group',None,'refs/heads/queue')]:
                self.assertTrue(selection.decide('image-contract',event,action,ref,SHA,
                                                'fixture/repo',CONTRACT,CONTRACT)['run'])
            self.assertTrue(selection.decide('image-contract','push',None,'refs/heads/main',SHA,
                                            'fixture/repo',CONTRACT,CONTRACT,attempt=2)['run'])
            reuse.assert_not_called()


if __name__ == '__main__':
    unittest.main()
