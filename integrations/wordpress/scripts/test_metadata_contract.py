"""Regression cases for the WordPress.org review of 27 October 2026."""
import unittest
from metadata_contract import validate_minimum_wordpress


class MinimumWordPressTest(unittest.TestCase):
    def test_matching_major_release(self):
        for version in ['6.6', '7.1']:
            with self.subTest(version=version):
                self.assertEqual(validate_minimum_wordpress(
                    f'/**\n * Requires at least: {version}\n */',
                    f'Requires at least: {version}\nTested up to: 7.1\n'), version)

    def test_rejects_reviewed_patch_version_and_prerelease(self):
        for version in ['6.6.4', '6', '7.1-beta1']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                validate_minimum_wordpress(f' * Requires at least: {version}\n',
                                           f'Requires at least: {version}\n')

    def test_rejects_mismatched_versions(self):
        with self.assertRaises(ValueError):
            validate_minimum_wordpress(' * Requires at least: 6.6\n', 'Requires at least: 6.7\n')

    def test_rejects_missing_or_ambiguous_header(self):
        for header in ['', ' * Requires at least: 6.6\n * Requires at least: 6.7\n']:
            with self.subTest(header=header), self.assertRaises(ValueError):
                validate_minimum_wordpress(header, 'Requires at least: 6.6\n')


if __name__ == '__main__':
    unittest.main()
