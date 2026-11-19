"""Read exact missing Ubuntu package names from a Playwright launch failure."""

import re


PACKAGE_NAME = re.compile(r"[a-z0-9][a-z0-9.+-]+(?::[a-z0-9][a-z0-9-]*)?")


def missing_playwright_packages(diagnostic):
    if 'Host system is missing dependencies to run browsers.' not in diagnostic:
        return ()
    lines = iter(line.strip(' \t│║') for line in diagnostic.splitlines())
    for line in lines:
        command = re.fullmatch(r'(?:sudo )?apt-get install (.+)', line)
        if not command:
            continue
        packages = command[1]
        while packages.endswith('\\'):
            continuation = next(lines, '')
            if not continuation:
                return ()
            packages = packages[:-1] + ' ' + continuation
        names = packages.split()
        if names and all(PACKAGE_NAME.fullmatch(name) for name in names):
            return tuple(names)
    return ()


def simulated_missing_packages(diagnostic):
    lines = diagnostic.splitlines()
    for index, line in enumerate(lines):
        report = re.fullmatch(r"Missing system dependencies \(([0-9]+)\):", line.strip())
        if not report:
            continue
        count = int(report[1])
        names = [line.strip() for line in lines[index + 1:index + 1 + count]]
        if count and len(names) == count and all(PACKAGE_NAME.fullmatch(name) for name in names):
            return tuple(names)
    return ()
