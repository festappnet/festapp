"""Every hosted job and native mirror consumes the same unit/resource DAG."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import time
from unittest.mock import patch
from automation.testing.cms_browser_runtime import browser_image, cms_browser_command
import yaml
import run as runner

ROOT=Path(__file__).resolve().parents[2]
GROWTH_GUARD = ('python3 -m unittest automation.tests.test_repository_growth\n'
                'python3 automation/check_repository_growth.py')


class MirrorContractTest(unittest.TestCase):
    def test_shared_playwright_cache_tracks_dependency_and_runner_versions(self):
        action_path = './.github/actions/restore-playwright-cache'
        steps = yaml.safe_load((ROOT / action_path / 'action.yml').read_text())['runs']['steps']
        command = steps[0]['run']
        self.assertEqual(steps[1]['with']['key'], '${{ steps.key.outputs.browsers }}')
        for filename, job in (
            ('wix-checkout-compatibility.yml', 'wix-checkout-compatibility'),
            ('seat-checkout-regressions.yml', 'seat-checkout'),
            ('image-upload-regressions.yml', 'server-policy'),
            ('deploy.yml', 'cloudflare'),
        ):
            workflow = yaml.safe_load((ROOT / '.github/workflows' / filename).read_text())
            self.assertIn(action_path, [step.get('uses') for step in workflow['jobs'][job]['steps']])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'web_client').mkdir()

            def key(app='1.0.0', browser='1.65.0', **platform):
                (root / 'web_client/package.json').write_text(json.dumps({
                    'version': app, 'devDependencies': {'playwright': browser},
                }))
                output = root / 'output'
                output.unlink(missing_ok=True)
                result = subprocess.run(['bash', '-e', '-c', command], cwd=root, capture_output=True,
                    env={**os.environ, 'RUNNER_OS': 'Linux', 'RUNNER_ARCH': 'X64', 'ImageOS': 'ubuntu26',
                         'ImageVersion': '20261111.82.6', 'GITHUB_OUTPUT': str(output),
                         'GITHUB_ENV': str(root / 'env'), **platform})
                return result.returncode, output.read_text() if output.exists() else ''

            chromium = key()
            self.assertEqual(chromium, (0, 'browsers=cms-browsers-Linux-X64-ubuntu26-playwright-1.65.0-chromium\n'))
            self.assertEqual(chromium, key(app='2.0.0', ImageVersion='20261119.1'))
            self.assertNotEqual(chromium, key(browser='1.66.0'))
            self.assertNotEqual(chromium, key(ImageOS='ubuntu24'))
            self.assertNotEqual(chromium, key(RUNNER_ARCH='ARM64'))
            self.assertNotEqual(key(browser='^1.65.0')[0], 0)
            self.assertNotEqual(key(ImageOS='')[0], 0)

    def test_cms_browser_image_matches_the_frozen_playwright_dependency(self):
        image = browser_image(ROOT)
        self.assertRegex(image, r'^mcr\.microsoft\.com/playwright:v[0-9.]+-noble@sha256:[0-9a-f]{64}$')
        command = cms_browser_command(ROOT, 'owned-browser', ['scripts/test.mjs'], {
            'FESTAPP_CMS_TEST_ENGINE': 'webkit',
        })
        self.assertIn('--network=host', command)
        self.assertIn('--pull=never', command)
        self.assertIn('--rm', command)
        self.assertIn('FESTAPP_CMS_TEST_ENGINE', command)
        self.assertEqual(command[-3:], [image, 'node', 'scripts/test.mjs'])
        with self.assertRaises(ValueError):
            cms_browser_command(ROOT, 'owned-browser', [], {'GH_TOKEN': 'synthetic'})
        workflow = yaml.safe_load((ROOT / '.github/workflows/wix-checkout-compatibility.yml').read_text())
        cms_steps = workflow['jobs']['wordpress-checkout-compatibility']['steps']
        cache = next(step for step in cms_steps if step.get('uses') == './.github/actions/restore-playwright-cache')
        self.assertEqual(cache['if'], "github.job == 'wix-checkout-compatibility' && steps.selection.outputs.cms == 'true'")

    def test_selection_covers_provisioning_tests_and_execution_evidence(self):
        contract = json.loads((ROOT / 'automation/ci/checks.json').read_text())
        for name, lane in contract['jobs'].items():
            with self.subTest(job=name):
                workflow = yaml.safe_load((ROOT / '.github/workflows' / lane['workflow']).read_text())
                triggers = workflow.get('on', workflow.get(True))
                self.assertNotIn('paths', triggers['push'])
                self.assertIn('ready_for_review', triggers['pull_request']['types'])
                self.assertIn('converted_to_draft', triggers['pull_request']['types'])
                self.assertIn('merge_group', triggers)
                self.assertEqual(workflow['concurrency']['cancel-in-progress'],
                                 "${{ github.event_name == 'pull_request' }}")
                self.assertIn('github.event.pull_request.number', workflow['concurrency']['group'])
                job = workflow['jobs'][name]
                self.assertIn('!github.event.pull_request.draft', job['if'])
                steps = job['steps']
                self.assertEqual(steps[0]['with']['fetch-depth'], 0)
                selection_index = 2 if name == 'server-policy' else 1
                if name == 'server-policy':
                    self.assertEqual(steps[1]['run'].strip(), GROWTH_GUARD)
                    self.assertNotIn('if', steps[1])
                self.assertEqual(steps[selection_index]['id'], 'selection')
                self.assertEqual(steps[-2]['name'], 'Lane coverage verified')
                for step in steps[selection_index + 1:]:
                    if step.get('uses', '').startswith('actions/upload-artifact@'):
                        self.assertEqual(step['if'], 'always()')
                        continue
                    if step.get('name') in ('Run canonical regression DAG','Lane coverage verified'):
                        self.assertNotIn('if',step)
                    elif step.get('name')=='All lane tests executed':
                        self.assertEqual(step['if'],"steps.selection.outputs.full == 'true'")
                    elif step.get('name')=='Some lane tests executed':
                        self.assertEqual(step['if'],"steps.selection.outputs.run == 'true' && steps.selection.outputs.full != 'true'")
                    elif name in ('client-contract', 'client-browser-contract') and step.get('uses', '').startswith('pnpm/action-setup@'):
                        self.assertEqual(step['if'], "github.job == 'client-contract' && steps.selection.outputs.run == 'true'")
                    elif name == 'server-policy' and step.get('name') in ('Install Python YAML parser', 'Install pinned Deno'):
                        outputs = {'Install Python YAML parser': 'python_yaml', 'Install pinned Deno': 'deno'}
                        self.assertEqual(step['if'], f"steps.selection.outputs.{outputs[step['name']]} == 'true'")
                    elif step.get('name') in ('Restore pinned WordPress core archive', 'Restore pinned host Chromium'):
                        cms_job = ('wordpress-checkout-compatibility' if step['name']=='Restore pinned WordPress core archive'
                                   else 'wix-checkout-compatibility')
                        self.assertEqual(step['if'], f"github.job == '{cms_job}' && steps.selection.outputs.cms == 'true'")
                    else:
                        self.assertIn(step['if'], ("steps.selection.outputs.run == 'true'","steps.selection.outputs.cms == 'true'",
                                                  "steps.selection.outputs.sql == 'true'","steps.selection.outputs.flutter == 'true'",
                                                  "steps.selection.outputs.browser == 'true'","steps.selection.outputs.deno == 'true'"))

    def test_jobs_share_the_canonical_lane_and_all_units_are_owned_once(self):
        contract=runner.CONTRACT;referenced=[]
        self.assertTrue({'seat-checkout','database-regressions','mcp-database-contracts','database-service-regressions','client-browser-contract'}
                        .issubset(contract['jobs']))
        for name,lane in contract['jobs'].items():
            workflow=yaml.safe_load((ROOT/'.github/workflows'/lane['workflow']).read_text())
            steps=workflow['jobs'][name]['steps']
            commands=[step['run'].strip().replace('${{ github.job }}', name) for step in steps if 'run' in step]
            self.assertIn('python3 automation/ci/run.py lane '+name,commands)
            for command in commands:
                self.assertTrue(command=='python3 automation/ci/run.py lane '+name or
                    (name == 'server-policy' and command == GROWTH_GUARD) or any(marker in command for marker in
                    ('automation/ci/selection.py ',"echo 'All lane tests executed'","echo 'Some lane tests executed'","echo 'Lane coverage verified'",'GITHUB_OUTPUT','dart pub global activate fvm','sudo apt-get','bash automation/ci/browser.sh','bash automation/ci/prepare-seat.sh','bash automation/ci/deno.sh','bash automation/ci/supabase.sh','python3 -m venv')),command)
            self.assertFalse(any('run.py step ' in command for command in commands))
            node=[step['with']['node-version'] for step in steps if step.get('uses','').startswith('actions/setup-node@')]
            self.assertEqual(node,[lane['node']])
            referenced.extend(lane['steps'])
        self.assertCountEqual(referenced,contract['steps'])
        for name,unit in contract['steps'].items():
            self.assertIsInstance(unit['script'],str)
            self.assertTrue(set(unit['after']).issubset(contract['steps']))
            self.assertTrue(set(unit['resources']).issubset(contract['resources']))

    def test_worker_suite_has_one_owner_and_no_cross_workflow_dependency(self):
        scripts = {name: unit['script'] for name, unit in runner.CONTRACT['steps'].items()}
        self.assertEqual([name for name, script in scripts.items()
                          if 'pnpm run typecheck && pnpm run test:unit' in script], ['image-policy'])
        self.assertNotIn('image-server-policy', scripts)

        self.assertEqual(runner.CONTRACT['steps']['mcp-auth-install']['after'], [])
        for name, lane in runner.CONTRACT['jobs'].items():
            for unit in lane['steps']:
                # Serialize shared installs/API generation in the local mirror.
                # Hosted jobs filter dependencies to their isolated worktree.
                if unit in ('wix-install','wordpress-cms-install'):
                    continue
                cross_lane = set(runner.CONTRACT['steps'][unit]['after']) - set(lane['steps'])
                allowed = {
                    'seat-mcp-prepare': {'mcp-api-prepare', 'mcp-auth-contract', 'mcp-api-contract'},
                    'database-services-mcp-prepare': {
                        'mcp-api-prepare', 'mcp-auth-contract', 'mcp-api-contract',
                        'seat-mcp-authorization', 'seat-mcp-contracts-1',
                    },
                    'seat-mcp-contracts-2': {'seat-database'},
                    'seat-database': {'seat-runtime-contract'},
                    'seat-services': {'seat-database'},
                }.get(unit, {'seat-database'} if name == 'mcp-database-contracts' else set())
                self.assertLessEqual(cross_lane, allowed, unit)
        self.assertTrue({'mcp-api-prepare', 'mcp-auth-contract', 'mcp-api-contract'}
                        .issubset(runner.CONTRACT['steps']['seat-mcp-prepare']['after']))
        for unit in ('seat-mcp-authorization','seat-mcp-contracts-1','seat-mcp-contracts-2'):
            self.assertIn(unit,runner.CONTRACT['steps']['wix-install']['after'])
        for entrypoint in ('automation/cloudflare_build.sh','automation/ci_build.sh'):
            self.assertIn('automation/build_web_bundle.sh',(ROOT/entrypoint).read_text())
        builder=(ROOT/'automation/build_web_bundle.sh').read_text()
        self.assertLess(builder.index('python3 automation/ci/release_gate.py'),
                        builder.index('rm -rf'))

    def test_postgres_mcp_files_have_only_the_complete_grouped_execution_owner(self):
        scripts={name:unit['script'] for name,unit in runner.CONTRACT['steps'].items()}
        for name,script in scripts.items():
            self.assertNotRegex(script,r'test/[\w-]+-postgres\.test\.mjs',name)
        owners={name for name,script in scripts.items() if 'scripts/test-postgres.mjs ' in script}
        self.assertEqual(owners,{'seat-mcp-authorization','seat-mcp-contracts-1','seat-mcp-contracts-2'})
        self.assertIn('test-postgres.mjs authorization',scripts['seat-mcp-authorization'])
        for index in (1, 2):
            self.assertIn(f'test-postgres.mjs contracts-{index}', scripts[f'seat-mcp-contracts-{index}'])
        self.assertIn('assemble-information-authoring-migration.py --check',scripts['mcp-api-contract'])

    def test_cluster_mutators_reserve_the_complete_admission_capacity(self):
        contract=runner.CONTRACT
        self.assertEqual(contract['resources']['ramMiB'],3500)
        for name in ['seat-upgrade','seat-runtime-contract','seat-database','wix-cms']:
            self.assertEqual(contract['steps'][name]['resources']['dbCluster'],
                             contract['resources']['dbCluster'],name)

    def test_hosted_lanes_have_capacity_to_overlap_independent_checks(self):
        for lane, concurrent in [
            ('wix-checkout-compatibility', ('wix-quick', 'wix-adapters', 'wix-cms')),
            ('ticket-preview-and-delivery', ('ticket-client', 'ticket-edge')),
        ]:
            units = runner.selected_units([lane])
            limits = {**runner.CONTRACT['resources'], **runner.CONTRACT['jobs'][lane]['hostedResources']}
            for resource, limit in limits.items():
                self.assertLessEqual(sum(units[name]['resources'].get(resource, 0) for name in concurrent),
                                     limit, (lane, resource))
        for lane, pair in (
            ('mcp-database-contracts', ('seat-mcp-authorization', 'seat-mcp-contracts-1')),
            ('database-service-regressions', ('seat-services', 'seat-mcp-contracts-2')),
        ):
            units = runner.selected_units([lane])
            self.assertEqual({name for name, unit in units.items() if unit['resources'].get('dbCluster')}, set(pair))
            self.assertEqual(sum(units[name]['resources']['dbCluster'] for name in pair),
                             runner.CONTRACT['resources']['dbCluster'])

    def test_partial_consumers_require_preparation_instead_of_independent_checks(self):
        steps=runner.CONTRACT['steps']
        self.assertEqual(steps['ticket-client']['requires'],['ticket-install'])
        self.assertEqual(steps['ticket-edge']['requires'],[])
        self.assertEqual(steps['ticket-core']['requires'],[])
        self.assertEqual(steps['seat-browser']['requires'],['seat-install'])
        self.assertEqual(steps['seat-mcp-contracts-1']['requires'], ['mcp-database-install','seat-mcp-prepare'])
        self.assertEqual(steps['seat-mcp-contracts-2']['requires'], ['database-services-mcp-prepare'])
        self.assertEqual(steps['database-services-mcp-prepare']['requires'], ['database-services-install'])
        self.assertEqual(steps['seat-mcp-prepare']['requires'],['mcp-database-install'])
        # Full runs retain the canonical order and its independent proofs.
        self.assertIn('seat-database',steps['seat-browser']['after'])
        self.assertIn('seat-runtime-contract',steps['seat-database']['after'])
        self.assertEqual(steps['ticket-client']['after'],['ticket-core'])

    def test_partial_executor_waits_for_required_install_when_ordered_check_is_reused(self):
        from scheduler import execute_dag
        import threading
        import time
        units=runner.selected_units(['ticket-preview-and-delivery'])
        selected={'ticket-client','ticket-install'}
        partial={name:{'after':[dep for dep in row['after'] if dep in selected],'resources':{}}
                 for name,row in units.items() if name in selected}
        installed=threading.Event()
        def execute(name,row):
            if name=='ticket-install':
                time.sleep(.02)
                installed.set()
            else:
                self.assertTrue(installed.is_set(),'Consumer raced dependency installation')
        results=execute_dag(partial,{},execute)
        self.assertEqual({row['status'] for row in results.values()},{'PASS'})
        self.assertNotIn('ticket-core',results)

    def test_runtime_provisioning_conditions_match_their_consumers(self):
        workflow=yaml.safe_load((ROOT/'.github/workflows/seat-checkout-regressions.yml').read_text())
        seat=workflow['jobs']['seat-checkout']['steps']
        supabase=next(s for s in seat if s.get('run') == 'bash automation/ci/supabase.sh')
        self.assertEqual(supabase['if'],"steps.selection.outputs.sql == 'true'")
        prepare=next(s for s in seat if s.get('name')=='Prepare isolated browser and database image')
        self.assertEqual(prepare['env'],{'FESTAPP_CI_NEEDS_DATABASE':'${{ steps.selection.outputs.sql }}',
                                        'FESTAPP_CI_NEEDS_BROWSER':'${{ steps.selection.outputs.browser }}'})
        ticket=workflow['jobs']['ticket-preview-and-delivery']['steps']
        sdk=next(s for s in ticket if s.get('uses','').startswith('subosito/flutter-action'))
        self.assertEqual(sdk['if'],"steps.selection.outputs.flutter == 'true'")
        node=next(s for s in ticket if s.get('uses','').startswith('actions/setup-node'))
        self.assertEqual(node['if'],"steps.selection.outputs.run == 'true'")

    def test_unselected_tools_are_not_downloaded_and_bad_flags_fail(self):
        for database,browser,code in [('false','false',0),('true','false',0),('false','true',0),('unknown','false',2)]:
            with self.subTest(database=database,browser=browser),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp)
                for name in ['automation/ci/prepare-seat.sh','automation/local_db/test-base.json']:
                    target=root/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/name,target)
                (root/'automation/ci/browser.sh').write_text('touch "$PROVISION_FIXTURE/browser.called"\n')
                (root/'automation/local_db/images.py').write_text("import os,pathlib\n(pathlib.Path(os.environ['PROVISION_FIXTURE'])/'database.called').touch()\n")
                result=subprocess.run(['bash','automation/ci/prepare-seat.sh'],cwd=root,
                    env={**os.environ,'PROVISION_FIXTURE':str(root),'FESTAPP_CI_NEEDS_DATABASE':database,
                         'FESTAPP_CI_NEEDS_BROWSER':browser},capture_output=True)
                self.assertEqual(result.returncode,code,result.stderr.decode())
                self.assertEqual((root/'database.called').exists(),database=='true' and code==0)
                self.assertEqual((root/'browser.called').exists(),browser=='true' and code==0)
    def test_inventory_uses_worktree_files_instead_of_deleted_index_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            subprocess.run(['git','init','-q',str(root)],check=True)
            tests=root/'web_client/tests/core';tests.mkdir(parents=True)
            old=tests/'old.test.js';old.write_text('old')
            subprocess.run(['git','add','web_client/tests/core/old.test.js'],cwd=root,check=True)
            old.unlink()
            (tests/'new.test.js').write_text('new')
            (root/'automation').mkdir()
            (root/'automation/client_test_inventory.json').write_text(json.dumps({'ci_cases':{},'ci_moves':{}}))
            contract={'sqlInventory':{'knownTests':[]},'knownTestInputs':['web_client/tests/core/new.test.js'],'sqlGroups':{}}
            with patch.object(runner,'ROOT',root),patch.object(runner,'CONTRACT',contract):runner.inventory()
            self.assertIn('old.test.js',subprocess.check_output(['git','ls-files'],cwd=root,text=True))

    def test_semantic_cases_require_an_executed_root_or_documented_move(self):
        contract={'steps':{'ticket-client':{'script':'fvm flutter test test/ci.dart'}}}
        manifest={'ci_cases':{'ticket-client':[['test/local_only.dart','new case',False,1]]},
                  'ci_moves':{'ticket-client':{}}}
        with self.assertRaisesRegex(ValueError,'no executed CI entrypoint'):
            runner.check_ci_entrypoints(contract,manifest)
        manifest['ci_cases']['ticket-client'][0][0]='test/component.dart'
        manifest['ci_moves']['ticket-client']['component']={
            'source':'test/component.dart','entrypoint':'test/ci.dart','added_group':'component'}
        runner.check_ci_entrypoints(contract,manifest)
        manifest['ci_moves']['ticket-client']['component']['entrypoint']='test/local_only.dart'
        with self.assertRaisesRegex(ValueError,'no executed CI entrypoint'):
            runner.check_ci_entrypoints(contract,manifest)

    def test_browser_installer_matches_the_declared_playwright_version(self):
        version=json.loads((ROOT/'web_client/package.json').read_text())['devDependencies']['playwright']
        installer=(ROOT/'automation/ci/browser.sh').read_text()
        self.assertIn('playwright@'+version,installer)
        self.assertIn('playwright install --only-shell chromium',installer)
        self.assertNotIn('--with-deps',installer)
        self.assertNotIn('apt-get',installer)
        self.assertNotIn('agent-browser',installer)

    def test_flutter_browser_contracts_have_one_owner_and_semantic_inventory(self):
        steps=runner.CONTRACT['steps']
        entrypoint = 'test/browser/client_browser_ci_cases.dart'
        owners = [name for name, unit in steps.items() if entrypoint in unit['script']]
        self.assertEqual(owners, ['image-client-browser'])
        command = steps['image-client-browser']['script'].splitlines()
        self.assertEqual(len(command), 1)
        self.assertIn('--platform chrome', command[0])
        self.assertIn('--concurrency=1', command[0])
        inventory = json.loads((ROOT/'automation/client_test_inventory.json').read_text())
        self.assertEqual({row['source'] for row in inventory['ci_moves']['image-client-browser'].values()}, {
            'test/browser/browser_preference_store_test.dart',
            'test/components/html/html_image_preview_cases.dart',
            'test/components/navigation/platform_route_parser_cases.dart',
        })
        self.assertEqual(sum(row[3] for row in inventory['ci_cases']['image-client-browser']), 10)
        self.assertIn('automation/testing/navigation_ci.dart',
                      steps['navigation-contract']['script'])
        self.assertIn('automation/testing/navigation_default.dart',
                      steps['navigation-contract']['script'])

    def test_semantic_inventory_changes_trigger_all_owning_workflows(self):
        pattern='automation/client_test_inventory.*'
        for name in ('navigation-interactions','client-contract','client-browser-contract','ticket-preview-and-delivery','ticket-rendering-contracts'):
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
        self.assertIn('seat-upgrade',contract['jobs']['database-regressions']['steps'])
        self.assertIn('runtime.py upgrade',contract['steps']['seat-upgrade']['script'])
        filters=[filter for value in contract['sqlGroups'].values() for filter in value['filters']]
        self.assertIn('database/tests/emails/delivered_tickets_resolve_confirmation_test.sql',filters)

    def test_webview_release_gate_is_shared(self):
        self.assertIn('bash automation/test_web_startup.sh',runner.CONTRACT['steps']['web-startup']['script'])
        self.assertNotIn('bash automation/test_web_startup.sh',(ROOT/'automation/build_web_bundle.sh').read_text())
        self.assertIn('python3 automation/ci/release_gate.py',(ROOT/'automation/build_web_bundle.sh').read_text())

    def test_unknown_changed_source_and_new_test_choose_full_suite(self):
        for path in ['new/unknown.dart','database/tests/new_feature/new_test.sql','web_client/tests/new_browser.test.js']:
            jobs=runner.affected([path])
            self.assertEqual(jobs,list(runner.CONTRACT['jobs']))
        self.assertEqual(runner.affected(['integrations/wix/src/entry.js']),['wix-checkout-compatibility'])


class UnitSplitContractTest(unittest.TestCase):
    def test_installed_matrix_and_cluster_claims_are_retained(self):
        contract=runner.CONTRACT
        self.assertNotIn('wix-contract',contract['steps'])
        self.assertNotIn('seat-contract',contract['steps'])
        self.assertEqual(contract['steps']['wix-cms']['resources']['browser'],1)
        self.assertEqual(contract['steps']['seat-payments']['resources']['dbCluster'], 1)
        for name in ['seat-payments','seat-orders','seat-delivery','seat-services']:
            self.assertIn(name,contract['databaseUnits'])
        def cases(suite):
            return json.loads(subprocess.check_output(
                ['python3', 'automation/testing/cms_consent_fixture.py', '--list-cases', '--suite', suite],
                cwd=ROOT, text=True))
        wordpress, other = cases('wordpress'), cases('joomla-wix-html')
        self.assertEqual(len(wordpress), 4)
        self.assertEqual(len(other), 5)
        self.assertEqual(wordpress + other, cases('all'))
        self.assertEqual({case[4] for case in wordpress}, {'firefox','webkit','chromium'})
        self.assertEqual({case[4] for case in other}, {'chromium'})
        self.assertEqual([case[1] for case in other if case[5]], ['joomla'])

    def test_shared_sql_helpers_and_cross_client_fixtures_invalidate_consumers(self):
        from selection import unit_owners
        for path in ['web_client/tests/database/disposable_database.js',
                     'web_client/tests/database/runtime_workspace.js',
                     'web_client/tests/database/payment_upgrade_fixture.js',
                     'automation/lib/migration_inputs.mjs',
                     'automation/lib/historical_sql.mjs',
                     'test/fixtures/order_item_terminology.json']:
            for unit in ['seat-payments','seat-orders','seat-delivery','seat-services']:
                lane = 'database-service-regressions' if unit == 'seat-services' else 'seat-checkout'
                self.assertIn(unit,unit_owners(path,lane,runner.CONTRACT),(unit,path))
        self.assertIn('wix-cms',unit_owners('automation/lib/migration_inputs.py',
                                          'wix-checkout-compatibility',runner.CONTRACT))

    def test_isolated_wix_test_avoids_cms_but_shared_contracts_invalidate_it(self):
        from selection import unit_owners
        lane='wix-checkout-compatibility';c=runner.CONTRACT
        path=next(path for path in (ROOT/'integrations/wix').rglob('*.test.*') if 'node_modules' not in str(path)).relative_to(ROOT).as_posix()
        units=unit_owners(path,lane,c)
        self.assertIn('wix-quick',units)
        self.assertNotIn('wix-cms',units)
        for shared in ['integrations/measurement/consent-export.php','web_client/src/embed/channel.js',
                       'web_client/pnpm-lock.yaml','supabase/functions/_shared/auth.ts','automation/testing/cms_consent_fixture.py',
                       'database/functions/eshop_forms/shared.sql','new-unknown-file']:
            self.assertIn('wix-cms',unit_owners(shared,lane,c),shared)


class RunnerSafetyTest(unittest.TestCase):
    def test_seat_provisioning_overlaps_downloads_and_requires_both_successes(self):
        for browser_exit,image_exit,major in [(0,0,'15'),(17,0,'15'),(0,19,'17'),(17,19,'17')]:
            with self.subTest(browser=browser_exit,image=image_exit),tempfile.TemporaryDirectory() as directory:
                root=Path(directory)
                for relative in ('automation/ci/prepare-seat.sh','automation/ci/browser.sh','automation/local_db/test-base.json','automation/local_db/images.py'):
                    target=root/relative;target.parent.mkdir(parents=True,exist_ok=True)
                    shutil.copyfile(ROOT/relative,target)
                binary=root/'bin';binary.mkdir()
                for name in ('docker','pnpm'):
                    tool=binary/name
                    tool.write_text('''#!/usr/bin/env python3
import os, pathlib, sys, time
root=pathlib.Path(os.environ['PROVISION_FIXTURE'])
name=pathlib.Path(sys.argv[0]).name
other='pnpm' if name=='docker' else 'docker'
(root/(name+'.started')).write_text(' '.join(sys.argv[1:]))
for _ in range(200):
    if (root/(other+'.started')).exists(): break
    time.sleep(.01)
else: sys.exit(91)
(root/(name+'.finished')).touch()
if name=='docker' and sys.argv[1:3]==['image','inspect'] and os.environ['IMAGE_EXIT']=='0':
    print('[{}]')
sys.exit(int(os.environ['BROWSER_EXIT' if name=='pnpm' else 'IMAGE_EXIT']))
''')
                    tool.chmod(0o755)
                chrome=binary/'google-chrome';chrome.touch();chrome.chmod(0o755)
                env={**os.environ,'PATH':str(binary)+os.pathsep+os.environ['PATH'],
                     'PROVISION_FIXTURE':directory,'BROWSER_EXIT':str(browser_exit),'IMAGE_EXIT':str(image_exit),
                     'FESTAPP_TEST_PG_MAJOR':major,'GITHUB_ENV':str(root/'github-env')}
                result=subprocess.run(['bash',str(root/'automation/ci/prepare-seat.sh')],env=env,timeout=10,capture_output=True,text=True)
                self.assertEqual(result.returncode,browser_exit or (1 if image_exit else 0),result.stderr)
                self.assertTrue((root/'docker.finished').exists())
                self.assertTrue((root/'pnpm.finished').exists())
                config=json.loads((ROOT/'automation/local_db/test-base.json').read_text())
                image=config['providers'][major]['image']
                expected=('image inspect '+image) if not image_exit else ('pull '+image.replace('public.ecr.aws/','docker.io/',1))
                self.assertEqual((root/'docker.started').read_text(),expected)
                self.assertIn('--only-shell chromium',(root/'pnpm.started').read_text())

    def test_ticket_rendering_has_a_single_hosted_owner(self):
        contract = runner.CONTRACT
        root = 'automation/testing/ticket_default_ci.dart'
        owners = [name for name, row in contract['steps'].items() if root in row['script']]
        self.assertEqual(owners, ['ticket-rendering-client'])
        self.assertEqual(contract['steps']['ticket-rendering-client']['requires'], ['ticket-rendering-install'])
        self.assertIn('ticket-rendering-client', contract['jobs']['ticket-rendering-contracts']['steps'])

    def test_ticket_preparation_can_overlap_edge_without_overlapping_flutter(self):
        units=runner.selected_units(['ticket-preview-and-delivery'])
        self.assertEqual(units['ticket-install']['after'],[])
        self.assertEqual(units['ticket-core']['after'],['ticket-install'])
        self.assertEqual(units['ticket-client']['after'],['ticket-core','ticket-install'])
        budget=runner.CONTRACT['resources']['ramMiB']
        edge=units['ticket-edge']['resources']['ramMiB']
        self.assertLessEqual(edge+units['ticket-install']['resources']['ramMiB'],budget)
        self.assertGreater(edge+units['ticket-client']['resources']['ramMiB'],budget)

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

    def test_all_reused_coverage_is_complete_without_executing_tools(self):
        contract={'jobs':{'fixture':{'node':'fixture','steps':['unit']}},
                  'steps':{'unit':{'script':'false','after':[],'resources':{}}},'resources':{}}
        proof={'inputSha256':'same','source':'a'*40}
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);plan=root/'plan.json'
            plan.write_text(json.dumps({'execute':[],'reuse':{'unit':proof}}))
            with patch.object(runner,'CONTRACT',contract),patch.object(runner,'CACHE',root), \
                 patch.object(runner,'input_identity',return_value={'inputSha256':'same'}), \
                 patch.object(runner,'host_state',return_value={}),patch.object(runner,'execution_identity',return_value=None), \
                 patch.object(runner,'verify_plan'),patch.object(runner.subprocess,'check_output',return_value='a'*40), \
                 patch.dict(os.environ,{'GITHUB_ACTIONS':'true','GITHUB_REPOSITORY':'fixture/repo','FESTAPP_CI_SELECTION_PATH':str(plan)}), \
                 patch.object(runner,'measured_process') as execute:
                receipt=runner.lane('fixture')
                self.assertTrue(receipt['complete']);self.assertEqual(receipt['units']['unit']['state'],'reused')
                execute.assert_not_called()

    def test_shell_failure_stops_following_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            marker=Path(directory)/'must-not-exist'
            with patch.object(runner,'CONTRACT',{'steps':{'failure':{'script':f'exit 17\ntouch "{marker}"'}}}):
                with self.assertRaises(subprocess.CalledProcessError) as error:runner.step('failure')
            self.assertEqual(error.exception.returncode,17);self.assertFalse(marker.exists())

    def test_browser_lane_preserves_explicit_executable_and_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            browser=Path(directory)/'Chrome for Testing';browser.touch()
            with patch.object(runner,'CACHE',Path(directory)),patch.dict(os.environ,{'CHROME_EXECUTABLE':str(browser),'PATH':os.defpath},clear=True),\
                 patch.object(runner,'require_version',return_value='fixture'),patch.object(runner,'call'), \
                 patch.object(runner,'_execute',return_value={}) as execute:
                runner.local(['server-policy'])
                self.assertEqual(os.environ['CHROME_EXECUTABLE'],str(browser))
            execute.assert_called_once()
            self.assertEqual(execute.call_args.args,(['server-policy'],))
            self.assertTrue(execute.call_args.kwargs['pinned'])
            self.assertIsInstance(execute.call_args.kwargs['command_started'],float)

    def test_invalid_browser_fails_before_checks(self):
        with tempfile.TemporaryDirectory() as directory,patch.object(runner,'CACHE',Path(directory)),\
             patch.dict(os.environ,{'CHROME_EXECUTABLE':'/missing/chrome'},clear=True),\
             patch.object(runner,'require_version'),patch.object(runner,'_execute') as execute:
            with self.assertRaisesRegex(RuntimeError,'Chrome'):runner.local(['server-policy'])
            execute.assert_not_called()

    def test_another_owner_blocks_before_tools_or_database_setup(self):
        with tempfile.TemporaryDirectory() as directory:
            cache=Path(directory)
            with (cache/'mirror.lock').open('w') as owner:
                fcntl.flock(owner,fcntl.LOCK_EX|fcntl.LOCK_NB)
                with patch.object(runner,'CACHE',cache):
                    with self.assertRaisesRegex(RuntimeError,'Another local CI mirror'):runner.local(['seat-checkout'])


if __name__=='__main__':unittest.main()
