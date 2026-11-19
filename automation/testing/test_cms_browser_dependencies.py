import unittest

from automation.testing.cms_browser_dependencies import (missing_playwright_packages, simulated_missing_packages,
                                                          ubuntu_archive_sources, apt_failure_summary)


class MissingPlaywrightPackagesTest(unittest.TestCase):
    def test_multiline_ubuntu_launcher_diagnostic(self):
        diagnostic = "\n".join((
            "browserType.launch:",
            "║ Host system is missing dependencies to run browsers. ║",
            "║ Alternatively, use apt:                             ║",
            "║     sudo apt-get install libflite1\\                 ║",
            "║         libwebpdemux2\\                             ║",
            "║         libharfbuzz-icu0                             ║",
        ))
        self.assertEqual(
            missing_playwright_packages(diagnostic),
            ("libflite1", "libwebpdemux2", "libharfbuzz-icu0"),
        )

    def test_does_not_install_packages_for_unrelated_launch_failures(self):
        self.assertEqual(missing_playwright_packages(
            "browserType.launch: Sandbox could not start.\nTry: apt-get install example"
        ), ())

    def test_does_not_interpret_extra_command_arguments(self):
        self.assertEqual(missing_playwright_packages(
            "Host system is missing dependencies to run browsers.\nsudo apt-get install libgtk-4-1 --reinstall"
        ), ())


    def test_dry_run_returns_only_requested_missing_packages(self):
        report = "Warning\nMissing system dependencies (2):\n  libflite1\n  libwebpdemux2:amd64\n"
        self.assertEqual(simulated_missing_packages(report), ("libflite1", "libwebpdemux2:amd64"))
        self.assertEqual(simulated_missing_packages("All system dependencies are installed."), ())
        self.assertEqual(simulated_missing_packages("Missing system dependencies (2):\n  libflite1"), ())


class UbuntuPackageRepairTest(unittest.TestCase):
    def test_archive_tracks_the_host_release_and_requires_signed_packages(self):
        release = 'ID=ubuntu\nVERSION_CODENAME="resolute"\n'
        amd64 = ubuntu_archive_sources(release, 'x86_64')
        self.assertIn('https://archive.ubuntu.com/ubuntu resolute-updates', amd64)
        self.assertIn('https://security.ubuntu.com/ubuntu resolute-security', amd64)
        self.assertEqual(amd64.count('signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg'), 3)
        self.assertIn('https://ports.ubuntu.com/ubuntu-ports resolute-security',
                      ubuntu_archive_sources(release, 'aarch64'))
        self.assertIsNone(ubuntu_archive_sources('ID=debian\nVERSION_CODENAME=bookworm', 'x86_64'))
        self.assertIsNone(ubuntu_archive_sources('ID=ubuntu\nVERSION_CODENAME="invalid suite"', 'x86_64'))

    def test_summary_surfaces_apt_errors_without_dumping_success_output(self):
        self.assertEqual(apt_failure_summary('Reading lists\nE: Package not found\n', 100),
                         'exit 100: E: Package not found')


if __name__ == "__main__":
    unittest.main()
