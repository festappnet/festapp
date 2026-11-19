import unittest

from automation.testing.cms_browser_dependencies import missing_playwright_packages, simulated_missing_packages


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


if __name__ == "__main__":
    unittest.main()
