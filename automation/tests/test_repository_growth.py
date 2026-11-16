from pathlib import Path
import subprocess
import tempfile
import unittest

from automation.check_repository_growth import check, LIMIT


class RepositoryGrowthTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git('init', '-q', '--initial-branch=main')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('commit', '--allow-empty', '-qm', 'Base')
        self.base = self.git('rev-parse', 'HEAD')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root,
                                       stderr=subprocess.DEVNULL, text=True).strip()

    def commit(self, message, name='source.dart', lines=LIMIT):
        (self.root / name).write_text('source line\n' * lines)
        self.git('add', '.')
        self.git('commit', '-qm', message)

    def test_large_code_addition_is_blocked_and_reason_is_commit_bound(self):
        self.commit('Large source')
        with self.assertRaisesRegex(ValueError, 'without a justification'):
            check(self.root, self.base)
        self.git('commit', '--amend', '-qm', 'Large source\n\nLarge-change-reason: '
                 'This source import is needed for the complete parser grammar; every rule is maintained here, '
                 'and splitting it would hide dependencies between those rules.')
        self.assertEqual(check(self.root, self.base), LIMIT)
        self.commit('Another large file', name='another.sql')
        with self.assertRaisesRegex(ValueError, 'without a justification'):
            check(self.root, self.base)

    def test_aggregate_smaller_commits_also_require_an_explanation(self):
        self.commit('First part', lines=LIMIT // 2)
        self.commit('Second part', name='more.json', lines=LIMIT // 2)
        with self.assertRaisesRegex(ValueError, 'complete change'):
            check(self.root, self.base)

    def test_added_then_deleted_code_still_requires_a_reason(self):
        self.commit('Temporary large addition')
        self.git('rm', 'source.dart')
        self.git('commit', '-qm', 'Remove it again')
        with self.assertRaisesRegex(ValueError, 'without a justification'):
            check(self.root, self.base)

    def test_github_style_merge_keeps_source_commit_justification(self):
        self.git('checkout', '-qb', 'feature')
        self.commit('Import grammar\n\nLarge-change-reason: '
                    'The parser requires this complete authored grammar; separating the interdependent rules '
                    'would conceal missing productions and prevent compilation.')
        self.git('checkout', '-q', 'main')
        self.git('commit', '--allow-empty', '-qm', 'Other work')
        self.git('merge', '--no-ff', '-qm', 'Merge feature into main', 'feature')
        self.assertEqual(check(self.root, self.base), LIMIT)

    def test_small_changes_and_binary_files_do_not_count_as_large_text(self):
        self.commit('Small edit', lines=LIMIT - 1)
        (self.root / 'image.bin').write_bytes(b'\0' * 100_000)
        self.git('add', '.')
        self.git('commit', '-qm', 'Binary input')
        self.assertEqual(check(self.root, self.base), LIMIT - 1)
        with self.assertRaises(subprocess.CalledProcessError):
            check(self.root, 'missing-base')


if __name__ == '__main__':
    unittest.main()
