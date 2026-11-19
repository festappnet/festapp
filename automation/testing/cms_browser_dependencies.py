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


def ubuntu_archive_sources(release, machine):
    """Use official signed archives for the detected runner release and architecture."""
    fields = dict(line.split('=', 1) for line in release.splitlines() if '=' in line and not line.startswith('#'))
    codename = fields.get('VERSION_CODENAME', '').strip('"')
    if fields.get('ID', '').strip('"') != 'ubuntu' or not re.fullmatch('[a-z]+', codename):
        return None
    if machine in ('aarch64', 'arm64'):
        archive = security = 'https://ports.ubuntu.com/ubuntu-ports'
    elif machine in ('x86_64', 'amd64'):
        archive = 'https://archive.ubuntu.com/ubuntu'
        security = 'https://security.ubuntu.com/ubuntu'
    else:
        return None
    options = '[signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg]'
    components = 'main restricted universe multiverse'
    return ''.join(f'deb {options} {origin} {suite} {components}\n'
                   for origin, suite in ((archive, codename), (archive, codename+'-updates'),
                                         (security, codename+'-security')))


def apt_failure_summary(diagnostic, returncode):
    lines = [re.sub(r'://[^/\s@]+@', '://[redacted]@', line.strip())[:360] for line in diagnostic.splitlines()
             if line.startswith(('E:', 'Err:', 'W: Failed to fetch', 'dpkg: error', 'Failed to fetch'))]
    return f'exit {returncode}' + (': ' + ' | '.join(lines[-5:]) if lines else '')
