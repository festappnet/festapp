import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('api_artifacts', Path(__file__).parents[1] / 'check_api_artifacts.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class ArtifactGuardTest(unittest.TestCase):
    def test_forced_add_and_old_ancestry_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL, text=True).strip()
            git('init', '-q', '--initial-branch=stale')
            git('config', 'user.name', 'Fixture')
            git('config', 'user.email', 'fixture@example.invalid')
            artifact = root / guard.ARTIFACTS / 'global-api/openapi.json'
            artifact.parent.mkdir(parents=True)
            artifact.write_text('{}')
            git('add', '.')
            git('commit', '-qm', 'Old generated artifacts')
            git('checkout', '-q', '--orphan', 'clean')
            git('rm', '-rf', '.')
            (root / '.gitignore').write_text('/' + guard.ARTIFACTS + '/\n')
            git('add', '.')
            git('commit', '-qm', 'Canonical source')
            clean = git('rev-parse', 'HEAD')
            guard.check(root, clean)
            artifact.parent.mkdir(parents=True, exist_ok=True)
            artifact.write_text('{}')
            git('add', '-f', str(artifact.relative_to(root)))
            with self.assertRaisesRegex(ValueError, 'must not be tracked'):
                guard.check(root, clean)
            git('rm', '-f', str(artifact.relative_to(root)))
            git('merge', '-q', '--allow-unrelated-histories', '--strategy=ours', 'stale', '-m', 'Accidental old merge')
            with self.assertRaisesRegex(ValueError, 'Newly reachable history'):
                guard.check(root, clean)


if __name__ == '__main__':
    unittest.main()
