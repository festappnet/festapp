"""Every hosted job and native mirror consumes the same unit/resource DAG."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import time
from unittest.mock import patch
import yaml
import run as runner

ROOT=Path(__file__).resolve().parents[2]


class MirrorContractTest(unittest.TestCase):
    def test_jobs_share_the_canonical_lane_and_all_units_are_owned_once(self):
        contract=runner.CONTRACT;referenced=[]
        self.assertEqual(len(contract['jobs']),8)
        for name,lane in contract['jobs'].items():
            workflow=yaml.safe_load((ROOT/'.github/workflows'/lane['workflow']).read_text())
            steps=workflow['jobs'][name]['steps']
            commands=[step['run'].strip() for step in steps if 'run' in step]
            self.assertIn('python3 automation/ci/run.py lane '+name,commands)
            for command in commands:
                self.assertTrue(command=='python3 automation/ci/run.py lane '+name or any(marker in command for marker in
                    ('GITHUB_OUTPUT','dart pub global activate fvm','sudo apt-get','bash automation/ci/browser.sh','bash automation/ci/deno.sh')),command)
            self.assertFalse(any('run.py step ' in command for command in commands))
            node=[step['with']['node-version'] for step in steps if step.get('uses','').startswith('actions/setup-node@')]
            self.assertEqual(node,[lane['node']])
            referenced.extend(lane['steps'])
        self.assertCountEqual(referenced,contract['steps'])
        for name,unit in contract['steps'].items():
            self.assertIsInstance(unit['script'],str)
            self.assertTrue(set(unit['after']).issubset(contract['steps']))
            self.assertTrue(set(unit['resources']).issubset(contract['resources']))

    def test_inventory_uses_worktree_files_instead_of_deleted_index_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            subprocess.run(['git','init','-q',str(root)],check=True)
            tests=root/'web_client/tests/core';tests.mkdir(parents=True)
            old=tests/'old.test.js';old.write_text('old')
            subprocess.run(['git','add','web_client/tests/core/old.test.js'],cwd=root,check=True)
            old.unlink()
            (tests/'new.test.js').write_text('new')
            contract={'sqlInventory':{'knownTests':[]},'knownTestInputs':['web_client/tests/core/new.test.js'],'sqlGroups':{}}
            with patch.object(runner,'ROOT',root),patch.object(runner,'CONTRACT',contract):runner.inventory()
            self.assertIn('old.test.js',subprocess.check_output(['git','ls-files'],cwd=root,text=True))

    def test_browser_installer_matches_the_declared_playwright_version(self):
        version=json.loads((ROOT/'web_client/package.json').read_text())['devDependencies']['playwright']
        installer=(ROOT/'automation/ci/browser.sh').read_text()
        self.assertIn('playwright@'+version,installer)
        self.assertIn('playwright install --with-deps chromium',installer)
        self.assertNotIn('agent-browser',installer)

    def test_flutter_browser_contracts_have_one_owner_and_semantic_inventory(self):
        steps=runner.CONTRACT['steps']
        for source in ('test/browser/browser_preference_store_test.dart',
                       'test/components/html/html_image_preview_cases.dart'):
            owners=[name for name,unit in steps.items() if source in unit['script']]
            self.assertEqual(owners,['image-client-browser'])
        command=steps['image-client-browser']['script'].splitlines()
        self.assertEqual(len(command),1)
        self.assertIn('--platform chrome',command[0])
        self.assertIn('--concurrency=1',command[0])
        inventory=json.loads((ROOT/'automation/client_test_inventory.json').read_text())
        self.assertTrue({'ticket-client','navigation-contract','image-client-browser'}
                        .issubset(inventory['ci_cases']))
        self.assertEqual(sum(row[3] for row in inventory['ci_cases']['image-client-browser']),6)
        self.assertIn('automation/testing/navigation_default.dart',
                      steps['navigation-contract']['script'])

    def test_semantic_inventory_changes_trigger_all_owning_workflows(self):
        pattern='automation/client_test_inventory.*'
        for name in ('navigation-interactions','client-contract','ticket-preview-and-delivery'):
            lane=runner.CONTRACT['jobs'][name]
            self.assertIn(pattern,lane['inputs'])
            workflow=yaml.safe_load((ROOT/'.github/workflows'/lane['workflow']).read_text())
            triggers=workflow.get('on',workflow.get(True))
            for event in ('push','pull_request'):
                paths=triggers[event].get('paths')
                if paths is not None:
                    self.assertIn(pattern,paths,(name,event))

    def test_every_hosted_lane_preserves_failure_evidence(self):
        for job in runner.CONTRACT['jobs'].values():
            workflow=yaml.safe_load((ROOT/'.github/workflows'/job['workflow']).read_text())
            for name,lane in workflow['jobs'].items():
                steps=lane['steps']
                execution=[step for step in steps if 'automation/ci/run.py lane ' in step.get('run','')]
                if not execution: continue
                with self.subTest(workflow=job['workflow'],job=name):
                    archives=[step for step in steps if step.get('uses')=='actions/upload-artifact@v7']
                    self.assertEqual(len(archives),1)
                    archive=archives[0]
                    self.assertEqual(archive['if'],'always()')
                    self.assertEqual(archive['with']['path'],'~/.cache/festapp-ci/runs')
                    self.assertLess(steps.index(execution[0]),steps.index(archive))

    def test_actual_upgrade_and_email_recovery_are_required(self):
        contract=runner.CONTRACT
        self.assertIn('seat-upgrade',contract['jobs']['seat-checkout']['steps'])
        self.assertIn('runtime.py upgrade',contract['steps']['seat-upgrade']['script'])
        filters=[filter for value in contract['sqlGroups'].values() for filter in value['filters']]
        self.assertIn('database/tests/emails/delivered_tickets_resolve_confirmation_test.sql',filters)

    def test_webview_release_gate_is_shared(self):
        self.assertIn('bash automation/test_web_startup.sh',runner.CONTRACT['steps']['web-startup']['script'])
        self.assertIn('bash automation/test_web_startup.sh',(ROOT/'automation/build_web_bundle.sh').read_text())

    def test_unknown_changed_source_and_new_test_choose_full_suite(self):
        for path in ['new/unknown.dart','database/tests/new_feature/new_test.sql','web_client/tests/new_browser.test.js']:
            jobs=runner.affected([path])
            self.assertEqual(jobs,list(runner.CONTRACT['jobs']))
        self.assertEqual(runner.affected(['integrations/wix/src/entry.js']),['wix-checkout-compatibility'])


class RunnerSafetyTest(unittest.TestCase):
    def test_total_receipt_includes_preflight_and_pinned_runtime_resolution(self):
        contract={'jobs':{'wix-checkout-compatibility':{'node':'fixture','steps':['fixture-unit']}},
                  'steps':{'fixture-unit':{'script':'true','after':[],'resources':{}}},'resources':{}}
        def preflight(*args):time.sleep(.05);return 'fixture'
        def resolve(*args,**kwargs):time.sleep(.05);return '/tmp/festapp-fixture-node\n'
        with tempfile.TemporaryDirectory() as directory,patch.object(runner,'CONTRACT',contract),\
             patch.object(runner,'CACHE',Path(directory)),patch.object(runner,'require_version',side_effect=preflight),\
             patch.object(runner.subprocess,'check_output',side_effect=resolve),\
             patch.object(runner,'input_identity',return_value={'inputSha256':'fixture'}),\
             patch.object(runner,'host_state',return_value={}),patch.object(runner,'measured_process',return_value=(0,0,1)):
            receipt=runner.local(['wix-checkout-compatibility'])
        self.assertTrue(receipt['complete'])
        self.assertGreaterEqual(receipt['preparationSeconds'],.1)
        self.assertGreaterEqual(receipt['seconds'],receipt['preparationSeconds']+receipt['executionSeconds'])

    def test_shell_failure_stops_following_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            marker=Path(directory)/'must-not-exist'
            with patch.object(runner,'CONTRACT',{'steps':{'failure':{'script':f'exit 17\ntouch "{marker}"'}}}):
                with self.assertRaises(subprocess.CalledProcessError) as error:runner.step('failure')
            self.assertEqual(error.exception.returncode,17);self.assertFalse(marker.exists())

    def test_browser_lane_preserves_explicit_executable_and_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            browser=Path(directory)/'Chrome for Testing';browser.touch()
            with patch.object(runner,'CACHE',Path(directory)),patch.dict(os.environ,{'CHROME_EXECUTABLE':str(browser)},clear=True),\
                 patch.object(runner,'require_version',return_value='fixture'),patch.object(runner,'_execute',return_value={}) as execute:
                runner.local(['web-startup'])
                self.assertEqual(os.environ['CHROME_EXECUTABLE'],str(browser))
            execute.assert_called_once()
            self.assertEqual(execute.call_args.args,(['web-startup'],))
            self.assertTrue(execute.call_args.kwargs['pinned'])
            self.assertIsInstance(execute.call_args.kwargs['command_started'],float)

    def test_invalid_browser_fails_before_checks(self):
        with tempfile.TemporaryDirectory() as directory,patch.object(runner,'CACHE',Path(directory)),\
             patch.dict(os.environ,{'CHROME_EXECUTABLE':'/missing/chrome'},clear=True),\
             patch.object(runner,'require_version'),patch.object(runner,'_execute') as execute:
            with self.assertRaisesRegex(RuntimeError,'Chrome'):runner.local(['web-startup'])
            execute.assert_not_called()

    def test_another_owner_blocks_before_tools_or_database_setup(self):
        with tempfile.TemporaryDirectory() as directory:
            cache=Path(directory)
            with (cache/'mirror.lock').open('w') as owner:
                fcntl.flock(owner,fcntl.LOCK_EX|fcntl.LOCK_NB)
                with patch.object(runner,'CACHE',cache):
                    with self.assertRaisesRegex(RuntimeError,'Another local CI mirror'):runner.local(['seat-checkout'])


if __name__=='__main__':unittest.main()
