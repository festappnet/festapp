"""Admission and cleanup boundaries for the real two-version CMS runtime."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'automation/testing'))
from wordpress_runtime import WordPress, LABEL


class WordPressRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.project = 'festapp-cms-consent-123456abcdef'
        self.root = Path(self.directory.name) / self.project / 'integrations/wordpress'
        self.root.mkdir(parents=True)
        (self.root.parent / 'joomla').mkdir()
        for relative in ['wordpress/.wp-env.json', 'wordpress/docker-images.json', 'joomla/docker-images.json']:
            target = self.root.parent / relative
            target.write_text((ROOT / 'integrations' / relative).read_text())
        self.config = json.loads((self.root / '.wp-env.json').read_text())
        self.config['config']['WP_HOME'] = 'https://127.0.0.1:61031'
        self.config['env']['tests']['config'] = {'WP_HOME': 'https://127.0.0.1:61036'}
        (self.root / '.wp-env.json').write_text(json.dumps(self.config))

    def test_versions_and_cli_remain_isolated(self):
        calls = []
        runtime = WordPress(self.root, self.project, lambda command, **kwargs: calls.append(command))
        self.assertEqual({row['php'] for row in runtime.versions.values()}, {'8.5', '7.4'})
        self.assertEqual({row['version'] for row in runtime.versions.values()}, {'7.1.3', '6.6'})
        self.assertEqual(len({row['volume'] for row in runtime.versions.values()}), 2)
        self.assertEqual(len({row['database'] for row in runtime.versions.values()}), 2)
        for name in runtime.versions:
            runtime.cli(name, 'core', 'version')
        self.assertNotEqual(calls[0][calls[0].index('--env-file') + 1], calls[1][calls[1].index('--env-file') + 1])
        self.assertTrue(all(LABEL + '=' + self.project in command for command in calls))
        self.assertTrue(all('--rm' in command for command in calls))

    def test_unpinned_images_and_foreign_fixture_are_refused(self):
        with self.assertRaises(ValueError):
            WordPress(self.root, 'foreign', lambda *args: None)
        (self.root / 'docker-images.json').write_text(json.dumps({'wordpress:php8.5': 'latest'}))
        with self.assertRaisesRegex(ValueError, 'Digest-pinned'):
            WordPress(self.root, self.project, lambda *args: None)

    def test_foreign_cleanup_is_refused_before_any_removal(self):
        calls = []
        runtime = WordPress(self.root, self.project, lambda *args, **kwargs: calls.append(args))
        def inspect(command, **kwargs):
            data = {'Labels': {LABEL: self.project}, 'Config': {'Labels': {LABEL: self.project}}}
            if command[1] == 'volume':
                data['Labels'] = {}
            return subprocess.CompletedProcess(command, 0, json.dumps([data]), '')
        with patch('wordpress_runtime.subprocess.run', side_effect=inspect):
            with self.assertRaisesRegex(ValueError, 'Foreign'):
                runtime.stop()
        self.assertEqual(calls, [])

    def test_daemon_failure_is_not_treated_as_absence(self):
        runtime = WordPress(self.root, self.project, lambda *args: None)
        failed = subprocess.CompletedProcess([], 1, '', 'Cannot connect to the Docker daemon')
        with patch('wordpress_runtime.subprocess.run', return_value=failed):
            with self.assertRaisesRegex(RuntimeError, 'Cannot inspect'):
                runtime.stop()
