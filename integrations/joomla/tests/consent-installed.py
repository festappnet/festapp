#!/usr/bin/env python3
"""Installed Joomla 5/6 asset regression, using only the environment.py disposable CMS.

The CMS envelope is a synthetic export; localhost HTTP is enabled in the installed
parser for this test only, then restored. This is not a backend or CMP E2E test.
"""
import html
import json
import os
import re
import subprocess
import urllib.request

PREFIX = os.environ.get('FESTAPP_JOOMLA_TEST_PREFIX', 'festapp-joomla-20261026')
if PREFIX != 'festapp-joomla-20261026' and not re.fullmatch(r'festapp-cms-consent-[a-z0-9-]+', PREFIX):
    raise SystemExit('Refusing unowned Joomla prefix')
PATH = '/var/www/html/modules/mod_vstupenky_online/src/Helper/consent-export.php'

def docker(*args):
    return subprocess.run(['docker', *args], check=True, capture_output=True, text=True).stdout

SERVICE = os.environ.get('FESTAPP_CMS_TEST_SERVICE', 'https://vstupenky.online')
for major, port in [(5, int(os.environ.get('FESTAPP_JOOMLA_TEST_PORT5', '59915'))), (6, int(os.environ.get('FESTAPP_JOOMLA_TEST_PORT6', '59916')))]:
    container = f'{PREFIX}-{major}'
    # Require the wrapper-owned network and expected mounted tests before any mutation.
    network = json.loads(docker('inspect', '--format', '{{json .NetworkSettings.Networks}}', container))
    if PREFIX not in network:
        raise RuntimeError('Refusing a non-disposable Joomla instance')
    original = docker('exec', container, 'cat', PATH)
    patched = original.replace("'https'", "'http'").replace("'https://'", "'http://'").replace('https:\\/\\/', 'http:\\/\\/')
    if original == patched or "=== 'http'" not in patched or 'http:\\/\\/' not in patched:
        raise RuntimeError('Unexpected parser; refusing test-only patch')
    try:
        subprocess.run(['docker','exec','-i',container,'sh','-c',f'cat > {PATH}'], input=patched, text=True, check=True)
        docker('exec', '-e', f'SITE_ORIGIN=http://127.0.0.1:{port}', '-e', f'FESTAPP_CMS_TEST_SERVICE={SERVICE}', container, 'php', '/tests/consent-installed-contract.php')
        for conflict in [False, True]:
            args = ['exec', '-e', f'SITE_ORIGIN=http://127.0.0.1:{port}', '-e', f'FESTAPP_CMS_TEST_SERVICE={SERVICE}']
            if conflict:
                args += ['-e', 'CONFLICT=1']
            docker(*args, container, 'php', '/tests/consent-installed-seed.php')
            docker('exec', container, 'php', '/tests/clear-cache.php')
            with urllib.request.urlopen(f'http://127.0.0.1:{port}/', timeout=10) as response:
                body = response.read().decode()
            values = re.findall(r'data-festapp-consent="([^"]*)"', body)
            if body.count(SERVICE + '/embed.js') != 1 or len(values) != 1:
                raise AssertionError(f'Joomla {major}: expected one helper/config attribute')
            value = html.unescape(values[0])
            if conflict and value != '':
                raise AssertionError(f'Joomla {major}: conflicting imports did not fail closed')
            if not conflict and json.loads(value)['binding']['version'] != 1:
                raise AssertionError(f'Joomla {major}: later valid import missing')
    finally:
        subprocess.run(['docker','exec','-i',container,'sh','-c',f'cat > {PATH}'], input=original, text=True, check=True)
print('PASS real Joomla 5/6 multiple-module consent asset selection')
