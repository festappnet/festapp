"""CI input invalidation and trusted executed-check reuse boundaries."""
from datetime import datetime, timedelta, timezone
import json
import copy
from pathlib import Path
import subprocess
import sys
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


class CanonicalTranslationOwnershipTest(unittest.TestCase):
    def test_every_web_catalog_consumer_is_invalidated_by_the_canonical_source(self):
        consumers={name for name,job in CONTRACT['jobs'].items() if 'web_client/**' in job['inputs']}
        for locale in ['cs','en','sk','de','pl','uk']:
            self.assertTrue(consumers.issubset(selection.owners(f'assets/translations/{locale}.json',CONTRACT)))


class CmsDependencyOwnershipTest(unittest.TestCase):
    def test_mcp_source_does_not_invalidate_independent_sql_executors(self):
        independent={'occasion-lifecycle','seat-authorization','seat-google-auth',
                     'seat-payments','seat-orders','seat-delivery','seat-notifications','seat-browser'}
        for path in ['tools/festapp/src/remote/views.mjs',
                     'tools/festapp/src/operations/orders.mjs']:
            units=selection.unit_owners(path,'seat-checkout',CONTRACT)
            self.assertTrue(independent.isdisjoint(units),path)
            self.assertTrue({'seat-mcp-prepare','seat-mcp-authorization','seat-mcp-contracts'}.issubset(units),path)
        for path in ['database/functions/eshop/finalize_ticket_order.sql',
                     'database/tests/helpers/reset_owned_sequences.sql']:
            self.assertTrue(independent.issubset(selection.unit_owners(path,'seat-checkout',CONTRACT)),path)
        self.assertIn('seat-services',selection.unit_owners('tools/festapp/test/postgres.mjs','seat-checkout',CONTRACT))

    def test_ticket_core_and_edge_have_only_their_actual_platform_inputs(self):
        lane='ticket-preview-and-delivery'
        for path in ['lib/components/occasion_settings/occasion_settings_layout.dart',
                     'test/components/occasion/occasion_setup_feedback_cases.dart']:
            units=selection.unit_owners(path,lane,CONTRACT)
            self.assertIn('ticket-client',units)
            self.assertTrue({'ticket-core','ticket-edge','ticket-install'}.isdisjoint(units))
        self.assertIn('ticket-core',selection.unit_owners('packages/festapp_core/lib/eshop/customer_label.dart',lane,CONTRACT))
        self.assertIn('ticket-edge',selection.unit_owners('supabase/functions/preview-ticket-layout/entrypoint_test.ts',lane,CONTRACT))
        for path in ['test/fixtures/ticket_layout/background.png',
                     'database/fixtures/demo_occasions/concert-layout.json',
                     'assets/brand/apple-wallet/provenance.json']:
            self.assertIn(lane,selection.owners(path,CONTRACT))
            self.assertIn('ticket-edge',selection.unit_owners(path,lane,CONTRACT))
        self.assertIn('ticket-core',selection.unit_owners('assets/email_templates/preview_examples.json',lane,CONTRACT))
        self.assertEqual(selection.unit_owners('unknown_shared/input.dat',lane,CONTRACT),set(CONTRACT['jobs'][lane]['steps']))

    def test_image_health_checker_has_only_actual_consumers(self):
        self.assertEqual(selection.owners('automation/verify_image_service.mjs',CONTRACT),
                         {'image-contract','web-startup'})

    def fingerprints(self, changed):
        import hashlib
        lane='wix-checkout-compatibility'
        paths=['web_client/src/components/forms/form_page.js',changed]
        def tree(sha):
            return [b'100644 blob '+hashlib.sha1((path+('changed' if sha==SHA and path==changed else 'original')).encode()).hexdigest().encode()+b'\t'+path.encode() for path in paths]
        with patch.object(selection,'tree',side_effect=tree):
            return {unit:(selection.fingerprint(BASE,lane,CONTRACT,unit),selection.fingerprint(SHA,lane,CONTRACT,unit)) for unit in ['wix-quick','wix-cms']}

    def test_edge_order_handler_change_reruns_transport_contracts_without_reinstalling_real_cms(self):
        result=self.fingerprints('supabase/functions/send-ticket-order/ticketOrderRpc.ts')
        self.assertEqual(*result['wix-cms'])
        self.assertNotEqual(*result['wix-quick'])

    def test_form_schema_browser_and_shared_runtime_changes_still_invalidate_cms(self):
        for path in ['web_client/src/components/forms/form_page.js',
                     'supabase/migrations/20261116120000_bank_multicurrency_availability.sql',
                     'supabase/functions/_shared/communicationTone.ts',
                     'web_client/scripts/test_cms_managed_consent_browser.mjs',
                     'automation/testing/cms_consent_fixture.py','new_area/unclassified.ts']:
            with self.subTest(path=path):
                self.assertNotEqual(*self.fingerprints(path)['wix-cms'])

    def test_canonical_software_version_has_an_explicit_release_contract_owner(self):
        self.assertEqual(selection.owners('automation/release/software-version.conf',CONTRACT),{'web-startup'})

    def test_checkout_ui_does_not_reexecute_unrelated_backend_contracts(self):
        units=selection.unit_owners('web_client/src/components/forms/order_result.js','seat-checkout',CONTRACT)
        self.assertIn('seat-browser',units)
        for backend in ['seat-authorization','seat-google-auth','seat-notifications','occasion-lifecycle']:
            self.assertNotIn(backend,units)
            self.assertIn(backend,selection.unit_owners('database/functions/eshop/finalize_ticket_order.sql','seat-checkout',CONTRACT))

    def test_mcp_database_groups_follow_backend_inputs_without_checkout_ui(self):
        lane='seat-checkout'
        groups={'seat-mcp-authorization','seat-mcp-contracts'}
        self.assertTrue(groups.isdisjoint(selection.unit_owners('web_client/src/components/forms/order_result.js',lane,CONTRACT)))
        for path in ['database/functions/eshop/finalize_ticket_order.sql',
                     'tools/festapp/src/operations.mjs',
                     'tools/festapp/scripts/test-postgres.mjs',
                     'database/tests/helpers/authorization_context_reference.sql']:
            self.assertTrue(groups.issubset(selection.unit_owners(path,lane,CONTRACT)),path)


class VersionProjectionTest(unittest.TestCase):
    def test_real_version_commit_reuses_functional_units_while_startup_and_checkout_still_run(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            def git(*args):
                return subprocess.check_output(['git',*args],cwd=root,stderr=subprocess.DEVNULL).decode().strip()
            git('init','-q');git('config','user.email','test@example.invalid');git('config','user.name','CI fixture')
            def commit(version):
                files={'web_client/package.json':json.dumps({'name':'festapp-web-client','version':version,'dependencies':{'pg':'8'}},indent=2),
                       'web_client/src/version.js':"// Auto-generated by automation/configure_version.js\nexport const APP_VERSION = '"+version+"+1';\n",
                       'web_client/index.html':'<script>window.__FESTAPP_BUILD_VERSION__ = "'+version+'+1"; start();</script>'}
                for path,body in files.items():
                    target=root/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(body)
                git('add','.');git('commit','-qm',version);return git('rev-parse','HEAD')
            before=commit('0.20.625');after=commit('0.20.626')
            with patch.object(selection,'ROOT',root),selection.lookup():
                for lane,unit in [('wix-checkout-compatibility','wix-cms'),('seat-checkout','seat-mcp-prepare'),
                                  ('seat-checkout','seat-mcp-authorization'),('seat-checkout','seat-mcp-contracts')]:
                    self.assertEqual(selection.fingerprint(before,lane,CONTRACT,unit),selection.fingerprint(after,lane,CONTRACT,unit),unit)
                for lane,unit in [('web-startup','web-startup'),('seat-checkout','seat-browser')]:
                    self.assertNotEqual(selection.fingerprint(before,lane,CONTRACT,unit),selection.fingerprint(after,lane,CONTRACT,unit),unit)

    def entry(self,body,path='web_client/package.json',rule='package-version',mode=b'100644'):
        import hashlib
        entry=mode+b' blob '+hashlib.sha1(body.encode()).hexdigest().encode()+b'\t'+path.encode()
        with patch.object(selection,'git',return_value=body.encode()):
            return selection.projected_entry(entry,{path:rule})

    def test_package_version_only_is_stable_but_dependencies_scripts_and_export_order_are_inputs(self):
        base={'name':'festapp-web-client','version':'0.20.625','dependencies':{'pg':'8.0.0'},
              'scripts':{'build':'vite build'},'exports':{'node':'./node.js','default':'./fallback.js'}}
        original=self.entry(json.dumps(base,indent=2))
        self.assertEqual(original,self.entry(json.dumps({**base,'version':'0.20.626'},indent=2)))
        for fields in [{'dependencies':{'pg':'9.0.0'}},{'scripts':{'build':'other command'}},
                       {'exports':{'default':'./fallback.js','node':'./node.js'}},
                       {'unknownFutureField':'new'}]:
            self.assertNotEqual(original,self.entry(json.dumps({**base,**fields},indent=2)))
        self.assertNotEqual(original,self.entry(json.dumps(base,indent=2),mode=b'100755'))

    def test_generated_stamp_and_html_version_only_are_stable_but_code_changes_are_inputs(self):
        for path,rule,template in [
            ('web_client/src/version.js','generated-web-version',"// Auto-generated by automation/configure_version.js\nexport const APP_VERSION = '__VALUE__';\n"),
            ('web_client/index.html','html-build-version','<script>window.__FESTAPP_BUILD_VERSION__ = "__VALUE__"; start();</script>')]:
            before=template.replace('__VALUE__','0.20.625+1156');after=template.replace('__VALUE__','0.20.626+1157')
            original=self.entry(before,path,rule)
            self.assertEqual(original,self.entry(after,path,rule))
            self.assertNotEqual(original,self.entry(after+'\nchangedCode();',path,rule))
        self.assertNotEqual(self.entry('not JSON'),self.entry('different malformed JSON'))
        with self.assertRaisesRegex(ValueError,'Unknown CI input projection'):
            self.entry('{}',rule='unknown-rule')


class ScopedPolicyTest(unittest.TestCase):
    def test_registered_test_in_another_lane_does_not_invalidate_cms(self):
        changed=copy.deepcopy(CONTRACT)
        path='test/sessions/new_ticket_test.dart'
        changed['knownTestInputs'].append(path)
        changed['steps']['ticket-client']['script']+='fvm flutter test --concurrency=1 '+path+'\n'
        with selection.lookup(), patch.object(selection,'tree',return_value=[]):
            cms=selection.fingerprint(BASE,'wix-checkout-compatibility',CONTRACT,'wix-cms')
            self.assertEqual(cms,selection.fingerprint(SHA,'wix-checkout-compatibility',changed,'wix-cms'))
            self.assertNotEqual(selection.fingerprint(BASE,'ticket-preview-and-delivery',CONTRACT,'ticket-client'),
                                selection.fingerprint(SHA,'ticket-preview-and-delivery',changed,'ticket-client'))

    def test_own_contract_environment_and_shared_policy_changes_invalidate(self):
        mutations=[lambda p:p['steps']['wix-cms'].update(script='different command'),
                   lambda p:p['steps']['wix-install'].update(script='different install'),
                   lambda p:p['steps']['wix-cms']['inputs'].append('new/**'),
                   lambda p:p['steps']['wix-cms']['resources'].update(ramMiB=4000),
                   lambda p:p['reusePolicy'].update(maxAgeDays=8),
                   lambda p:p.update(unknownFuturePolicy=True),
                   lambda p:p['knownTestInputs'].append('integrations/tests/new.test.mjs')]
        for mutate in mutations:
            changed=copy.deepcopy(CONTRACT);mutate(changed)
            with self.subTest(mutation=mutate),selection.lookup(),patch.object(selection,'tree',return_value=[]):
                self.assertNotEqual(selection.fingerprint(BASE,'wix-checkout-compatibility',CONTRACT,'wix-cms'),
                                    selection.fingerprint(SHA,'wix-checkout-compatibility',changed,'wix-cms'))

    def test_independent_sibling_command_does_not_reinstall_cms(self):
        changed=copy.deepcopy(CONTRACT)
        changed['steps']['wix-quick']['script']+='\nnode --test another-contract.test.js\n'
        with selection.lookup(),patch.object(selection,'tree',return_value=[]):
            self.assertEqual(selection.fingerprint(BASE,'wix-checkout-compatibility',CONTRACT,'wix-cms'),
                             selection.fingerprint(SHA,'wix-checkout-compatibility',changed,'wix-cms'))
            self.assertNotEqual(selection.fingerprint(BASE,'wix-checkout-compatibility',CONTRACT),
                                selection.fingerprint(SHA,'wix-checkout-compatibility',changed))

    def test_raw_registry_is_projected_but_executable_ci_remains_trusted(self):
        def entries(sha):
            return b'100644 blob '+sha.encode()+b'\t'+selection.POLICY.encode()+b'\0'+b'100644 blob stable\tautomation/ci/run.py\0'
        with selection.lookup(),patch.object(selection,'git',side_effect=lambda *args:entries(args[3])):
            self.assertEqual(selection.definition(BASE),selection.definition(SHA))
        for path in ['automation/ci/run.py','.github/workflows/seat-checkout-regressions.yml']:
            with selection.lookup(),patch.object(selection,'git',side_effect=lambda *args:b'100644 blob '+args[3].encode()+b'\t'+path.encode()+b'\0'):
                self.assertNotEqual(selection.definition(BASE),selection.definition(SHA))
        with selection.lookup(),patch.object(selection,'tree',side_effect=lambda sha:entries(sha).split(b'\0')):
            self.assertEqual(selection.fingerprint(BASE,'wix-checkout-compatibility',CONTRACT,'wix-cms'),
                             selection.fingerprint(SHA,'wix-checkout-compatibility',CONTRACT,'wix-cms'))


class InventoryPreflightTest(unittest.TestCase):
    def test_provisioning_follows_selected_executors(self):
        flags=selection.provisioning_flags
        self.assertEqual(flags([],CONTRACT),dict(flutter=False,sql=False,browser=False))
        self.assertEqual(flags(['ticket-edge'],CONTRACT),dict(flutter=False,sql=False,browser=False))
        self.assertTrue(flags(['ticket-core'],CONTRACT)['flutter'])
        self.assertEqual(flags(['seat-mcp-contracts'],CONTRACT),dict(flutter=False,sql=True,browser=False))
        self.assertEqual(flags(['seat-browser'],CONTRACT),dict(flutter=False,sql=True,browser=True))
        with self.assertRaises(KeyError):flags(['unregistered-executor'],CONTRACT)

    def test_registration_failure_prevents_selection_and_reuse(self):
        with patch.object(sys,'argv',['selection.py','seat-checkout']), \
             patch.object(selection,'preflight_inventory',side_effect=ValueError('registration failed')), \
             patch.object(selection,'decide') as decide:
            with self.assertRaisesRegex(ValueError,'registration failed'):
                selection.main()
            decide.assert_not_called()


class ApiTransportTest(unittest.TestCase):
    def test_repository_root_has_no_trailing_slash_and_nested_endpoints_keep_separator(self):
        with patch.object(selection,'command',return_value=b'{"id":7}') as call:
            self.assertEqual(selection.api('fixture/repo',''),{'id':7})
            self.assertEqual(call.call_args.args[0],['gh','api','repos/fixture/repo'])
            selection.api('fixture/repo','actions/runs',paginate=True)
            self.assertEqual(call.call_args.args[0],['gh','api','--paginate','--slurp',
                                                    'repos/fixture/repo/actions/runs'])


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

    def test_real_unit_inputs_track_renames_deletions_helpers_and_locks(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            def git(*args):return subprocess.check_output(['git',*args],cwd=root,stderr=subprocess.DEVNULL).decode().strip()
            git('init','-q');git('config','user.email','test@example.invalid');git('config','user.name','Unit fixture')
            (root/'web_client').mkdir()
            path=root/'web_client/pnpm-lock.yaml';path.write_text('frozen')
            git('add','.');git('commit','-qm','lock')
            with patch.object(selection,'ROOT',root),selection.lookup():
                lane='wix-checkout-compatibility';unit='wix-cms'
                before=selection.fingerprint('HEAD',lane,CONTRACT,unit)
                git('mv','web_client/pnpm-lock.yaml','web_client/pnpm-old.yaml');git('commit','-qm','rename')
                after=selection.fingerprint(git('rev-parse','HEAD'),lane,CONTRACT,unit)
                self.assertNotEqual(before,after)
                git('rm','web_client/pnpm-old.yaml');git('commit','-qm','delete')
                deleted=selection.fingerprint(git('rev-parse','HEAD'),lane,CONTRACT,unit)
                self.assertNotEqual(after,deleted)
                for name in ['integrations/measurement/consent-export.php','automation/testing/cms_consent_fixture.py','web_client/scripts/native_browser.mjs']:
                    file=root/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_text('helper')
                    git('add','.');git('commit','-qm','helper')
                    changed=selection.fingerprint(git('rev-parse','HEAD'),lane,CONTRACT,unit)
                    self.assertNotEqual(deleted,changed);deleted=changed

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
                        steps=[dict(name='All lane tests executed', conclusion='success'),dict(name='Lane coverage verified',conclusion='success')])
        self.tools = dict(RUNNER_OS='Linux',RUNNER_ARCH='X64',ImageOS='ubuntu24',ImageVersion='fixture',
                          node='22.23.4',pnpm='11.24.0',python='fixture')
        self.receipt = dict(complete=True, dirty=False, inputsUnchanged=True,
                            selectedJobs=['image-contract'],
                            units={unit: {'status':'PASS','state':'executed','inputSha256':'same-inputs'} for unit in CONTRACT['jobs']['image-contract']['steps']},
                            execution=dict(schemaVersion=2,state='executed',repositoryId=7,runId=123,
                                attempt=1,jobId=456,lane='image-contract',event='push',workflow=self.run['path'],
                                definition='trusted',checkoutSha=BASE,tree='tested-tree',toolchain=self.tools,
                                inputSha256='same-inputs',inventory=CONTRACT['knownTestInputs']))
        self.artifact = dict(id=99,name='ci-image-contract-1',expired=False,
                             workflow_run=dict(id=123,repository_id=7,head_repository_id=7,head_sha=BASE))
        self.missing = False
        self.corrupt = False
        self.parents = ('c'*40)+' '+BASE
        self.checkout_available = True
        self.original_contract=copy.deepcopy(self.contract)

    def evaluate(self, fingerprint=None, runs=None, definition=None, consume=False,
                 expire_endpoint=None, expire_unit=None, jobs=None):
        import hashlib, io, zipfile
        archive = io.BytesIO()
        with zipfile.ZipFile(archive,'w') as bundle:
            bundle.writestr('run/receipt.json', json.dumps(self.receipt))
        payload=archive.getvalue()
        self.artifact['digest']='sha256:'+hashlib.sha256(payload).hexdigest()
        def api(repository, endpoint, paginate=False):
            if endpoint==expire_endpoint:
                selection.LOOKUP.get()['deadline']=0
                raise selection.BudgetExpired('fixture lookup deadline')
            if not endpoint: return {'id':7}
            if endpoint.startswith('actions/runs/') and endpoint.count('/') == 2:
                run_id = int(endpoint.rsplit('/', 1)[1])
                if run_id == self.run['id']:
                    return self.run
                return next(run for run in runs if run['id'] == run_id)
            if endpoint.startswith('actions/workflows/'):
                return {'workflow_runs':runs if runs is not None else [self.run]}
            if endpoint.endswith('/artifacts?per_page=100'):
                return {'artifacts':[] if self.missing else [self.artifact]}
            if '/jobs?' in endpoint:
                run_id = int(endpoint.split('/')[2])
                return {'jobs': (jobs or {}).get(run_id, [self.job])}
            raise AssertionError(endpoint)
        def git(*args):
            if args[:2] == ('rev-parse',BASE+'^{tree}'):return b'tested-tree'
            if args[0]=='show':return self.parents.encode()
            if args[0]=='merge-tree':return b'tested-tree'
            if args[0]=='merge-base':
                if not self.checkout_available: raise ValueError('foreign base')
                return b''
            raise AssertionError(args)
        original_verify=selection.verify_execution
        def verify(*args,**kwargs):
            unit=args[-1]
            if unit==expire_unit:
                selection.LOOKUP.get()['deadline']=0
                raise selection.BudgetExpired('fixture verification deadline')
            return original_verify(*args,**kwargs)
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(selection.Path,'home',return_value=Path(directory)), \
             patch.object(selection,'git',side_effect=git), \
             patch.object(selection,'ensure_commit'), \
             patch.object(selection,'source_policy',return_value=self.original_contract), \
             patch.object(selection,'verify_execution',side_effect=verify), \
             patch.object(selection,'definition',side_effect=definition or (lambda *args:'trusted')), \
             patch.object(selection,'fingerprint',side_effect=fingerprint or (lambda *args:'same-inputs')), \
             patch.object(selection,'toolchain',return_value=self.tools), \
             patch.object(selection,'api',side_effect=api), \
             patch.object(selection,'command',return_value=payload+(b'changed' if self.corrupt else b'')):
            result=selection.decide('image-contract','push',None,'refs/heads/main',SHA,
                                    'fixture/repo',self.contract,self.contract)
            if consume:
                result.update(schemaVersion=2,sha=SHA,lane='image-contract',definition='trusted')
                with selection.lookup():selection.verify_plan(result,'image-contract',SHA,'fixture/repo',self.contract)
            return result

    def test_direct_executed_receipt_and_identical_inputs(self):
        result=self.evaluate()
        self.assertFalse(result['run'])
        self.assertEqual(result['source'],BASE)
        self.assertEqual(result['jobId'],456)
        self.assertTrue(self.evaluate(fingerprint=lambda sha,*args:sha)['run'])

    def test_host_image_build_id_is_audit_only_but_os_and_pinned_tools_stay_exact(self):
        self.receipt['execution']['toolchain']={**self.tools,'ImageVersion':'other-host-image-build'}
        self.assertFalse(self.evaluate(consume=True)['run'])
        for field in ['RUNNER_OS','RUNNER_ARCH','ImageOS','node','pnpm','python']:
            self.receipt['execution']['toolchain']={**self.tools,field:'different'}
            self.assertTrue(self.evaluate()['run'],field)
        for value in [None,'',123,{'not':'a build ID'}]:
            self.receipt['execution']['toolchain']={**self.tools,'ImageVersion':value}
            self.assertTrue(self.evaluate()['run'])
        self.receipt['execution']['toolchain']={**self.tools,'unknownFutureTool':'unverified'}
        self.assertTrue(self.evaluate()['run'])

    def test_historical_inventory_is_verified_against_its_source_contract(self):
        self.contract['knownTestInputs'].append('test/sessions/new_ticket_test.dart')
        self.assertFalse(self.evaluate(consume=True)['run'])
        # Relabelling old aggregate evidence with today's inventory is rejected.
        self.receipt['execution']['inventory']=self.contract['knownTestInputs']
        self.assertTrue(self.evaluate()['run'])

    def test_current_unit_cannot_reuse_a_different_source_command(self):
        import hashlib
        def digest(sha,lane,policy,unit=None):
            return hashlib.sha256(selection.policy_inputs(lane,policy,unit)).hexdigest()
        self.receipt['execution']['inputSha256']=digest(BASE,'image-contract',self.original_contract)
        for name,row in self.receipt['units'].items():
            row['inputSha256']=digest(BASE,'image-contract',self.original_contract,name)
        self.contract['steps']['image-policy']['script']+='\nnew meaningful test'
        result=self.evaluate(fingerprint=digest,consume=True)
        self.assertIn('image-policy',result['execute'])
        self.assertNotIn('image-policy',result['reuse'])

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

    def test_skipped_pr_without_regression_steps_does_not_block_valid_evidence(self):
        draft = {**self.run, 'id':124, 'run_number':2, 'event':'pull_request',
                 'conclusion':'skipped'}
        job = {**self.job, 'run_id':124, 'conclusion':'skipped', 'steps':[]}
        result = self.evaluate(runs=[self.run, draft], jobs={124:[job]}, consume=True)
        self.assertFalse(result['run'])
        self.assertEqual({proof['runId'] for proof in result['reuse'].values()}, {123})
        for change in ({'steps':self.job['steps']}, {'run_attempt':2}):
            result = self.evaluate(runs=[self.run, draft], jobs={124:[{**job, **change}]})
            self.assertTrue(result['run'])
            self.assertFalse(result['reuse'])

    def test_failed_main_blocks_only_matching_units(self):
        for policy in (self.contract, self.original_contract):
            policy['steps']['image-storage']['after'] = []
        failed = {**self.run, 'id':124, 'run_number':2, 'head_sha':'d'*40,
                  'conclusion':'failure'}
        def digest(sha, lane, policy, unit=None):
            return 'other-inputs' if sha == failed['head_sha'] and unit != 'image-storage' else 'same-inputs'
        result = self.evaluate(fingerprint=digest, runs=[self.run, failed], consume=True)
        self.assertEqual(result['execute'], ['image-storage'])
        self.assertEqual(set(result['reuse']), {'image-install','image-policy','image-preflight'})

    def test_older_failed_pr_does_not_invalidate_newer_verified_coverage(self):
        for policy in (self.contract, self.original_contract):
            policy['steps']['image-storage']['after'] = []
        self.run['run_number'] = 2
        failed = {**self.run, 'id':122, 'run_number':1, 'event':'pull_request',
                  'conclusion':'failure'}
        def digest(sha, lane, policy, unit=None):
            return 'changed' if sha == SHA and unit == 'image-storage' else 'same-inputs'
        result = self.evaluate(fingerprint=digest, runs=[failed, self.run], consume=True)
        self.assertEqual(result['execute'], ['image-storage'])
        self.assertEqual(set(result['reuse']), {'image-install','image-policy','image-preflight'})

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

    def test_mixed_coverage_consumes_only_direct_unit_proofs(self):
        # Simulate one changed late unit; its preparation/dependency closure
        # reruns while unchanged independent units retain direct provenance.
        self.contract['steps']['image-storage']['after']=[]
        def digest(sha,lane,policy,unit=None):
            return 'changed' if sha==SHA and unit=='image-storage' else 'same-inputs'
        result=self.evaluate(fingerprint=digest,consume=True)
        self.assertEqual(result['execute'],['image-storage'])
        self.assertEqual(set(result['reuse']),set(self.contract['jobs']['image-contract']['steps'])-{'image-storage'})

    def test_check_order_is_not_an_unnecessary_runtime_dependency(self):
        import copy
        step=self.contract['steps']['image-storage']
        step['after']=['image-policy']
        step['requires']=['image-install']
        self.original_contract=copy.deepcopy(self.contract)
        baseline=self.evaluate()
        def digest(sha,lane,policy,unit=None):
            return 'changed' if sha==SHA and unit=='image-storage' else 'same-inputs'
        result=self.evaluate(fingerprint=digest,consume=True)
        self.assertEqual(set(result['execute']),{'image-storage','image-install'})
        self.assertIn('image-policy',result['reuse'])
        result['execute'].remove('image-install')
        result['reuse']['image-install']=baseline['reuse']['image-install']
        with patch.object(selection,'definition',return_value='trusted'):
            with self.assertRaisesRegex(ValueError,'Missing execution dependency'):
                selection.verify_plan(result,'image-contract',SHA,'fixture/repo',self.contract)

    def test_budget_expiry_keeps_verified_units_and_executes_changed_remainder(self):
        self.contract['steps']['image-storage']['after']=[]
        self.original_contract['steps']['image-storage']['after']=[]
        self.run['run_number']=2
        older={**self.run,'id':122,'run_number':1}
        def digest(sha,lane,policy,unit=None):
            return 'changed' if sha==SHA and unit=='image-storage' else 'same-inputs'
        result=self.evaluate(fingerprint=digest,runs=[older,self.run],
                             expire_endpoint='actions/runs/122',consume=True)
        self.assertEqual(result['execute'],['image-storage'])
        self.assertEqual(set(result['reuse']),{'image-install','image-policy','image-preflight'})
        self.assertIn('budget',result['reason'])
        self.assertEqual({p['source'] for p in result['reuse'].values()},{BASE})

    def test_budget_never_admits_a_unit_whose_verification_did_not_finish(self):
        for policy in (self.contract,self.original_contract):
            for unit in policy['jobs']['image-contract']['steps']:policy['steps'][unit]['after']=[]
        result=self.evaluate(expire_unit='image-policy',consume=True)
        self.assertEqual(set(result['reuse']),{'image-install'})
        self.assertEqual(set(result['execute']),{'image-policy','image-preflight','image-storage'})
        result=self.evaluate(expire_endpoint='actions/runs/123',consume=True)
        self.assertFalse(result['reuse'])
        self.assertEqual(set(result['execute']),set(self.contract['jobs']['image-contract']['steps']))

    def test_mixed_receipt_cannot_refresh_a_reused_units_origin(self):
        self.receipt['units']['image-storage']['state']='reused'
        result=self.evaluate()
        self.assertTrue(result['run'])
        self.assertNotIn('image-storage',result.get('reuse',{}))
        self.receipt['execution']['schemaVersion']=1
        self.assertTrue(self.evaluate()['run'])

    def test_incomplete_new_inventory_and_failed_unit_are_not_coverage(self):
        for mutation in ['missing','new','failed','old-toolchain']:
            import copy
            original=copy.deepcopy(self.receipt)
            if mutation=='missing':del self.receipt['units']['image-policy']
            if mutation=='new':self.receipt['units']['new']={'status':'PASS','state':'executed'}
            if mutation=='failed':self.receipt['units']['image-policy']['status']='FAIL'
            if mutation=='old-toolchain':self.receipt['execution']['toolchain']={}
            self.assertTrue(self.evaluate()['run'],mutation)
            self.receipt=original

    def test_reuse_only_job_is_ignored_before_artifact_download(self):
        self.job['steps']=[dict(name='Lane coverage verified',conclusion='success')]
        with patch.object(selection,'read_artifact') as read:
            self.assertTrue(self.evaluate()['run'])
            read.assert_not_called()

    def test_one_candidate_does_not_repeat_api_or_archive_per_unit(self):
        result=self.evaluate(consume=True)
        self.assertFalse(result['run'])
        self.assertEqual(result['metrics']['candidates'],1)
        # All four units share one immutable origin archive.
        self.assertGreater(result['metrics']['downloadedBytes'],0)

    def test_plan_requires_complete_disjoint_coverage_and_dependency_closure(self):
        units=self.contract['jobs']['image-contract']['steps']
        plan=dict(schemaVersion=2,sha=SHA,lane='image-contract',definition='trusted',execute=units,reuse={})
        import copy
        with patch.object(selection,'definition',return_value='trusted'):
            selection.verify_plan(plan,'image-contract',SHA,'fixture/repo',self.contract)
            for field,value in [('execute',[]),('execute',[units[-1]]),('sha',BASE),('schemaVersion',1),('lane','other')]:
                changed=copy.deepcopy(plan);changed[field]=value
                with self.assertRaises(ValueError):selection.verify_plan(changed,'image-contract',SHA,'fixture/repo',self.contract)

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


class SelectorBudgetTest(unittest.TestCase):
    def test_timeout_kills_network_process_and_its_child(self):
        import time
        with tempfile.TemporaryDirectory() as directory:
            marker=Path(directory)/'escaped'
            child="import time,pathlib; time.sleep(.4); pathlib.Path("+repr(str(marker))+").touch()"
            parent="import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',"+repr(child)+"]); time.sleep(10)"
            started=time.monotonic()
            with selection.lookup(seconds=.15):
                with self.assertRaises(selection.BudgetExpired):selection.command([sys.executable,'-c',parent])
            self.assertLess(time.monotonic()-started,1)
            time.sleep(.5)
            self.assertFalse(marker.exists())
        with patch.object(selection,'reusable',side_effect=selection.BudgetExpired()):
            result=selection.decide('image-contract','push',None,'refs/heads/main',SHA,'fixture/repo',CONTRACT,CONTRACT)
            self.assertTrue(result['run']);self.assertIn('budget',result['reason'])

    def test_tree_cache_is_scoped_to_one_lookup(self):
        with patch.object(selection,'git',return_value=b'') as git:
            with selection.lookup():
                for unit in CONTRACT['jobs']['image-contract']['steps']:
                    selection.fingerprint(SHA,'image-contract',CONTRACT,unit)
            self.assertEqual(git.call_count,1)
            with selection.lookup():selection.fingerprint(SHA,'image-contract',CONTRACT)
            self.assertEqual(git.call_count,2)


if __name__ == '__main__':
    unittest.main()
