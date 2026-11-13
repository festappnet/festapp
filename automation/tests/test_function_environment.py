import contextlib
from copy import deepcopy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'hetzner-supabase/runtime/update-production-function-environment.py'
spec = importlib.util.spec_from_file_location('migration', SCRIPT)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class FunctionEnvironmentTest(unittest.TestCase):
    def fixture(self):
        key, replacement = 'FESTAPP_MCP_TENANTS_JSON', 'private-replacement-value'
        env = {key: 'original-value', **{key: 'configured' for key in migration.runtime.REQUIRED_ENV}}
        env['SUPABASE_DB_URL'] = 'postgresql://local/' + migration.runtime.DATABASE
        env['APP_LINKS_ORGANIZATION_ID'] = '3'
        model = {'services': {'functions': {'environment': env, 'image': 'pinned-image', 'command': ['serve']}, 'auth': {'image': 'unchanged-auth'}}}
        container = {'Id': 'before', 'Image': 'sha256:pinned', 'State': {'Running': True}, 'HostConfig': {'Memory': 512},
                     'Mounts': [{'Destination': '/functions', 'Source': '/canonical/functions'}],
                     'Config': {'Env': [f'{k}={v}' for k, v in env.items()], 'Image': 'pinned-image',
                                'Cmd': ['serve'], 'Labels': {'com.docker.compose.config-hash': 'baseline-hash'}}}
        proposed = deepcopy(model); proposed['services']['functions']['environment'][key] = replacement
        after = deepcopy(container); after['Id'] = 'after'
        after['Config']['Env'] = [f'{k}={replacement if k == key else v}' for k, v in env.items()]
        return key, replacement, model, proposed, container, after

    def test_only_exact_selected_service_key_can_change(self):
        key, value, before, after, _, _ = self.fixture()
        migration.validate_change(before, after, key, value)
        for change in ['image', 'other-service', 'other-env']:
            changed = deepcopy(after)
            if change == 'image': changed['services']['functions']['image'] = 'unexpected'
            elif change == 'other-service': changed['services']['auth']['image'] = 'unexpected'
            else: changed['services']['functions']['environment']['EMAIL_PAYLOAD_KEY'] = 'unexpected'
            with self.assertRaises(RuntimeError): migration.validate_change(before, changed, key, value)

    def test_recreation_rejects_image_mount_resource_or_other_credential_drift(self):
        key, value, _, _, before, after = self.fixture()
        migration.validate_recreated(before, after, key, value)
        for change in ['image', 'mount', 'resource', 'credential']:
            changed = deepcopy(after)
            if change == 'image': changed['Image'] = 'other-image'
            elif change == 'mount': changed['Mounts'][0]['Source'] = '/wrong'
            elif change == 'resource': changed['HostConfig']['Memory'] = 1
            else: changed['Config']['Env'].append('UNREVIEWED_SECRET=unreviewed')
            with self.assertRaises(RuntimeError): migration.validate_recreated(before, changed, key, value)

    def migration_case(self, fail=False, drained=True):
        key, value, before_model, proposed, before, after = self.fixture()
        with tempfile.TemporaryDirectory(prefix='festapp-function-environment-') as directory:
            root = Path(directory)
            files = ['docker-compose.yml', 'docker-compose.festapp.yml', 'docker-compose.database-target.yml',
                     'docker-compose.email.yml', 'docker-compose.pgbackrest.yml', 'docker-compose.resource-budget.yml']
            original = 'COMPOSE_FILE=' + ':'.join(files) + '\n' + key + "='original-value'\n"
            (root / '.env').write_text(original)
            value_file = SimpleNamespace(lstat=lambda: SimpleNamespace(st_mode=0o100600, st_uid=0), read_text=lambda: value)
            calls, sql_calls = [], []
            def command(args, environment=None):
                calls.append(args)
                if args[:2] == ['docker', 'inspect']:
                    return json.dumps([after if value in (root / '.env').read_text() else before])
                if '--hash' in args: return 'functions baseline-hash'
                if 'config' in args:
                    return json.dumps(proposed if 'candidate' in args[3] else before_model)
                if 'up' in args:
                    if fail and sum('up' in call for call in calls) == 1: raise RuntimeError('fixed safe failure')
                    return ''
                raise AssertionError(args)
            def sql(query):
                sql_calls.append(query)
                return 't' if 'current_database' in query or drained else 'f'
            stdout = io.StringIO()
            with patch.object(migration.runtime, 'ROOT', root), patch.object(migration.runtime, 'command', command), \
                 patch.object(migration.runtime, 'sql', sql), patch.object(migration.runtime, 'probe', lambda _: None), \
                 patch.object(migration.os, 'geteuid', lambda: 0), \
                 patch.object(migration.os, 'uname', lambda: SimpleNamespace(nodename=migration.runtime.HOST)), \
                 patch.dict(migration.os.environ, {}, clear=True), contextlib.redirect_stdout(stdout):
                if fail or not drained:
                    with self.assertRaises(RuntimeError): migration.run(key, value_file, True)
                else: migration.run(key, value_file, True)
            self.assertNotIn(value, stdout.getvalue())
            self.assertTrue(all(query.startswith('SELECT ') for query in sql_calls))
            if fail or not drained: self.assertEqual((root / '.env').read_text(), original)
            else:
                self.assertIn(value, (root / '.env').read_text())
                self.assertEqual(next(root.glob('.env.before-functions-*')).read_text(), original)
            changes = [call for call in calls if 'up' in call]
            self.assertEqual(len(changes), 2 if fail else (1 if drained else 0))
            for call in changes:
                self.assertEqual(call[-1], 'functions')
                self.assertIn('--no-deps', call)
                self.assertEqual([call[i + 1] for i, arg in enumerate(call) if arg == '-f'], files)

    def test_full_overlay_recreation_is_bounded_and_retains_private_backup(self): self.migration_case()
    def test_failed_recreation_restores_original_environment_without_resuming_email(self): self.migration_case(fail=True)
    def test_undrained_email_prevents_environment_write_or_recreation(self): self.migration_case(drained=False)


if __name__ == '__main__': unittest.main()
