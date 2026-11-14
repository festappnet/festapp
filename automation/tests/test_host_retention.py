import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('host_retention', Path(__file__).parents[1] /
    'hetzner-supabase/maintenance/host-retention.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


class RetentionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.evidence = self.root / 'evidence'
        self.functions = self.root / 'functions'
        self.state = self.root / 'state'
        for p in (self.evidence, self.functions, self.state):
            p.mkdir()
        self.now = time.time()
        self.old = self.now - 30 * 86400

    def aged(self, path):
        for root, dirs, files in os.walk(path):
            for p in [Path(root)] + [Path(root) / n for n in dirs + files]:
                os.utime(p, (self.old, self.old), follow_symlinks=False)

    def payload(self, name):
        directory = self.evidence / name
        directory.mkdir()
        path = directory / 'before.dump'
        with path.open('wb') as handle:
            handle.truncate(11 * 1024**2)
        (directory / 'result.json').write_text('{}')
        self.aged(directory)
        return path

    def test_selection_fences_recent_symlinked_and_mounted_trees_and_keeps_two_backups(self):
        keep = self.payload('old')
        self.payload('recent').write_bytes(b'recent')
        linked = self.payload('linked')
        (linked.parent / 'link').symlink_to(keep)
        self.aged(linked.parent)
        mounted = self.payload('mounted')
        for day in range(1, 5):
            directory = self.functions / f'functions.pre-production-2026100{day}T000000Z'
            directory.mkdir()
            self.aged(directory)
        unknown = self.functions / 'functions.pre-unknown'
        unknown.mkdir()
        self.aged(unknown)
        payloads, backups = m.candidates(self.evidence, self.functions, [mounted.parent], self.now)
        self.assertEqual([p for _, files in payloads for p in files], [keep])
        self.assertEqual([p.name for p in backups], [
            'functions.pre-production-20261001T000000Z', 'functions.pre-production-20261002T000000Z'])

    @unittest.skipUnless(shutil.which('age') and shutil.which('age-keygen'), 'age tools required')
    def test_real_encrypted_roundtrip_and_corruption_preserves_original(self):
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        cli = bin_dir / 'rclone'
        cli.write_text('''#!/usr/bin/env python3
import os, pathlib, shutil, sys
args=sys.argv[3:]
remote=pathlib.Path(os.environ['TEST_REMOTE'])
if args[0]=='copyto':
    if os.environ.get('TEST_UPLOAD_FAIL'):
        sys.exit(43)
    shutil.copyfile(args[1], remote)
elif args[0]=='cat':
    sys.stdout.buffer.write(b'corrupt' if os.environ.get('TEST_CORRUPT') else remote.read_bytes())
    if os.environ.get('TEST_TOUCH'):
        target=pathlib.Path(os.environ['TEST_TOUCH'])
        target.write_bytes(b'changed during upload')
else:
    sys.exit(42)
''')
        cli.chmod(0o755)
        key = self.root / 'key'
        subprocess.run(['age-keygen', '-o', str(key)], capture_output=True, check=True)
        recipient = subprocess.run(['age-keygen', '-y', str(key)], capture_output=True,
                                   text=True, check=True).stdout.strip()
        remote = self.root / 'remote.age'
        env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'], TEST_REMOTE=str(remote))
        original = self.payload('good')
        with patch.object(m, 'EVIDENCE', self.evidence):
            removed = m.archive(original.parent, [original], self.state, env, recipient)
        self.assertEqual(removed, 11 * 1024**2)
        self.assertFalse(original.exists())
        self.assertTrue((original.parent / 'result.json').exists())
        self.assertEqual(len(list(original.parent.glob('archived-payloads-*.json'))), 1)
        plaintext = subprocess.run(['age', '-d', '-i', str(key), str(remote)], capture_output=True, check=True).stdout
        with tarfile.open(fileobj=io.BytesIO(plaintext), mode='r:gz') as tar:
            self.assertEqual(tar.getnames(), ['good/before.dump'])
            self.assertEqual(tar.extractfile('good/before.dump').read(), b'\0' * removed)
        bad = self.payload('bad')
        with patch.object(m, 'EVIDENCE', self.evidence):
            with self.assertRaisesRegex(RuntimeError, 'checksum mismatch'):
                m.archive(bad.parent, [bad], self.state, dict(env, TEST_CORRUPT='1'), recipient)
        self.assertTrue(bad.exists())
        self.assertFalse(list(bad.parent.glob('archived-payloads-*.json')))
        for name, settings, message in [
                ('failed', {'TEST_UPLOAD_FAIL': '1'}, 'rclone failed'),
                ('changed', {}, 'Recovery payload changed')]:
            path = self.payload(name)
            if name == 'changed':
                settings['TEST_TOUCH'] = str(path)
            with patch.object(m, 'EVIDENCE', self.evidence):
                with self.assertRaisesRegex(RuntimeError, message):
                    m.archive(path.parent, [path], self.state, dict(env, **settings), recipient)
            self.assertTrue(path.exists())

    def test_low_staging_space_preserves_original(self):
        original = self.payload('large')
        with patch.object(m.shutil, 'disk_usage', return_value=shutil._ntuple_diskusage(100, 99, 1)):
            with self.assertRaisesRegex(RuntimeError, 'Insufficient staging'):
                m.archive(original.parent, [original], self.state, {}, 'unused')
        self.assertTrue(original.exists())


if __name__ == '__main__':
    unittest.main()
