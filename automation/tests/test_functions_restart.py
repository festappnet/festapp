"""Regression for the 2026-10-27 partial-Compose email outage."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import types
import unittest
import urllib.error
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / 'automation/hetzner-supabase/runtime'
spec = importlib.util.spec_from_file_location('functions_restart', RUNTIME / 'restart-production-functions.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class FunctionsRestartTest(unittest.TestCase):
    def setUp(self):
        self.environment = {key: 'fixture-secret' for key in guard.REQUIRED_ENV}
        self.environment.update(SUPABASE_DB_URL='postgres://fixture@db/' + guard.DATABASE,
                                APP_LINKS_ORGANIZATION_ID='3')
        self.model = {'services': {'functions': {'environment': self.environment,
                                               'image': 'runtime:pinned', 'command': ['start']}}}
        self.container = {'Id': 'existing-container', 'State': {'Running': True},
                          'Config': {'Env': [k + '=' + v for k, v in self.environment.items()],
                                     'Image': 'runtime:pinned', 'Cmd': ['start']}}
        self.files = ['docker-compose.yml', 'docker-compose.festapp.yml',
                      'docker-compose.database-target.yml', 'docker-compose.email.yml',
                      'docker-compose.pgbackrest.yml', 'docker-compose.resource-budget.yml']

    def execute(self, model=None, drained='t'):
        calls = []

        def command(args, environment=None):
            calls.append(args)
            if 'compose' in args:
                return json.dumps(model or self.model)
            if 'inspect' in args:
                return json.dumps([self.container])
            if 'restart' in args:
                return 'existing-container'
            raise AssertionError(args)

        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / '.env').write_text('COMPOSE_FILE=' + ':'.join(self.files))
            with patch.object(guard, 'ROOT', folder), patch.object(guard.os, 'geteuid', return_value=0), \
                 patch.object(guard.os, 'uname', return_value=types.SimpleNamespace(nodename=guard.HOST)), \
                 patch.dict(os.environ, {}, clear=True), patch.object(guard, 'command', side_effect=command), \
                 patch.object(guard, 'sql', side_effect=['t', drained]), patch.object(guard, 'probe') as probe:
                try:
                    guard.run(restart=True)
                finally:
                    self.calls = calls
                probe.assert_called_once_with(self.container)

    def test_partial_overlay_cannot_stop_the_live_container(self):
        partial = copy.deepcopy(self.model)
        partial['services']['functions']['environment'] = {'DEFAULT_EMAIL': 'fixture-secret'}
        with self.assertRaisesRegex(RuntimeError, 'environment is missing'):
            self.execute(partial)
        self.assertFalse(any('restart' in args for args in self.calls))

    def test_only_same_container_is_restarted_after_complete_preflight(self):
        self.execute()
        changes = [args for args in self.calls if 'restart' in args or 'up' in args]
        self.assertEqual(changes, [['docker', 'restart', '--time', '30', 'existing-container']])

    def test_inflight_email_prevents_restart(self):
        with self.assertRaisesRegex(RuntimeError, 'Pause and drain'):
            self.execute(drained='f')
        self.assertFalse(any('restart' in args for args in self.calls))

    def test_shell_cannot_override_the_canonical_overlay_selection(self):
        text = 'COMPOSE_FILE=' + ':'.join(self.files) + '\nEMAIL_PAYLOAD_KEY=canonical'
        with self.assertRaisesRegex(RuntimeError, 'COMPOSE_'):
            guard.compose_inputs(text, {'COMPOSE_FILE': ':'.join(self.files[:2])})
        _, env = guard.compose_inputs(text, {'EMAIL_PAYLOAD_KEY': 'wrong', 'PATH': '/bin'})
        self.assertEqual(env, {'PATH': '/bin'})
        with self.assertRaisesRegex(RuntimeError, 'complete canonical'):
            guard.compose_inputs('COMPOSE_FILE=' + ':'.join(self.files[:2]), {})

    def test_other_runtime_setting_cannot_be_silently_lost(self):
        self.model['services']['functions']['environment']['FESTAPP_MCP_TENANTS_JSON'] = '[{}]'
        with self.assertRaisesRegex(RuntimeError, 'environments differ'):
            self.execute()
        self.assertFalse(any('restart' in args for args in self.calls))

    @unittest.skipUnless(shutil.which('docker'), 'Docker Compose CLI required')
    def test_real_compose_email_overlay_is_required_by_guard(self):
        # Real interpolation/merging, not a fabricated already-correct model.
        environment = {k: v for k, v in os.environ.items() if not k.startswith('COMPOSE_')}
        environment.update(self.environment)
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory) / 'compose.json'
            base.write_text(json.dumps({'services': {
                'functions': {'image': 'runtime:pinned', 'command': ['start'], 'environment': {
                    'DEFAULT_EMAIL': 'fixture-secret', 'SUPABASE_DB_URL': self.environment['SUPABASE_DB_URL']}},
                'auth': {'image': 'auth:pinned'},
            }}))
            args = (['docker-compose'] if shutil.which('docker-compose') else ['docker', 'compose']) + ['-f', str(base)]
            partial = json.loads(subprocess.check_output(args + ['config', '--format', 'json'], env=environment))
            with self.assertRaisesRegex(RuntimeError, 'environment is missing'):
                guard.validate_configuration(partial, self.container)
            full = json.loads(subprocess.check_output(args + ['-f', str(RUNTIME / 'docker-compose.email.yml'),
                                                            'config', '--format', 'json'], env=environment))
            desired = full['services']['functions']['environment']
            self.container['Config']['Env'] = [k + '=' + str(v) for k, v in desired.items()]
            guard.validate_configuration(full, self.container)

    def test_worker_probe_waits_for_startup_then_requires_unauthorized(self):
        self.container['NetworkSettings'] = {'Networks': {'private': {'IPAddress': '172.20.0.9'}}}
        unauthorized = urllib.error.HTTPError('fixture', 401, 'Unauthorized', {}, None)
        with patch.object(guard.urllib.request, 'urlopen', side_effect=[urllib.error.URLError('starting'), unauthorized]) as request, \
             patch.object(guard.time, 'sleep'):
            guard.probe(self.container)
        self.assertEqual(request.call_count, 2)
        self.assertEqual(request.call_args.args[0].data, b'{}')

    def test_worker_error_does_not_pass_the_health_gate(self):
        self.container['NetworkSettings'] = {'Networks': {'private': {'IPAddress': '172.20.0.9'}}}
        with patch.object(guard.urllib.request, 'urlopen', side_effect=urllib.error.HTTPError('fixture', 500, 'Failed', {}, None)):
            with self.assertRaisesRegex(RuntimeError, 'probe failed'):
                guard.probe(self.container)


if __name__ == '__main__':
    unittest.main()
