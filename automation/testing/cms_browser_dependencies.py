"""Read exact missing Ubuntu package names from a Playwright launch failure."""

import re


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
        if names and all(re.fullmatch(r'[a-z0-9][a-z0-9.+-]+', name) for name in names):
            return tuple(names)
    return ()
