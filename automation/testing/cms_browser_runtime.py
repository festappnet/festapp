"""Use a pinned Linux browser toolchain for the owned CMS loopback fixture."""
import json
import os
from pathlib import Path

PLAYWRIGHT_IMAGE = (
    'mcr.microsoft.com/playwright:v1.65.0-noble'
    '@sha256:9beb546099e11f52d62e505537914870e01a67e0e6b00ae41da4775324e73dbe'
)


def browser_image(root):
    version = json.loads((root / 'web_client/package.json').read_text())['devDependencies']['playwright']
    if PLAYWRIGHT_IMAGE.split('@', 1)[0] != f'mcr.microsoft.com/playwright:v{version}-noble':
        raise ValueError('Update the pinned CMS browser image with the Playwright dependency')
    return PLAYWRIGHT_IMAGE


def cms_browser_command(root, name, node_args, fixture_env, timings_file=None):
    command = [
        'docker', 'run', '--pull=never', '--rm', '--init', '--name', name,
        '--network=host', '--shm-size=512m', '--user', f'{os.getuid()}:{os.getgid()}',
        '--cap-drop=ALL', '--security-opt=no-new-privileges',
        '--workdir=/workspace', '--env=HOME=/tmp', '--env=PLAYWRIGHT_BROWSERS_PATH=/ms-playwright',
    ]
    for subpath in ('scripts', 'node_modules'):
        source = root / 'web_client' / subpath
        command.extend(['--mount', f'type=bind,source={source},target=/workspace/{subpath},readonly'])
    if timings_file:
        timings = Path(timings_file).resolve()
        timings.touch(mode=0o600, exist_ok=True)
        command.extend([
            '--mount', f'type=bind,source={timings},target=/tmp/festapp-browser-timings.jsonl',
            '--env=FESTAPP_TIMINGS=/tmp/festapp-browser-timings.jsonl',
        ])
    for key in sorted(fixture_env):
        if not (key.startswith('FESTAPP_CMS_TEST_') or key == 'FESTAPP_CMS_EXPECT_COOP'):
            raise ValueError(f'Unexpected browser fixture environment key: {key}')
        # Docker reads allowed values from the fixture process environment.
        command.extend(['--env', key])
    return [*command, browser_image(root), 'node', *node_args]
