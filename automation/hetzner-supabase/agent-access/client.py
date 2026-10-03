#!/usr/bin/env python3
"""Fetch only diagnostics using a dedicated Keychain credential."""
import argparse
import json
import subprocess
import urllib.error
import urllib.request

SERVICE = 'festapp-agent-diagnostics'
ACCOUNT = 'festapp-workstation'
URL = 'https://agent-supabase.festapp.net/v1/diagnostics'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=('probe', 'ledger'))
    args = parser.parse_args()
    try:
        saved = subprocess.run(['security', 'find-generic-password', '-s', SERVICE,
                                '-a', ACCOUNT, '-w'], capture_output=True, check=True)
        credentials = json.loads(saved.stdout)
        request = urllib.request.Request(URL, method='POST',
            data=json.dumps({'operation': args.operation, 'tenant': 'festapp', 'organization': 1}).encode(),
            headers={'Content-Type': 'application/json',
                     'CF-Access-Client-Id': credentials['client_id'],
                     'CF-Access-Client-Secret': credentials['client_secret'],
                     'X-Festapp-Agent-Token': credentials['broker_token']})
        # Redirects may lead to a login page. Never forward credential headers.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *_args):
                return None
        with urllib.request.build_opener(NoRedirect).open(request, timeout=10) as response:
            data = response.read(16385)
            if len(data) > 16384:
                raise ValueError()
            print(json.dumps(json.loads(data)))
    except (subprocess.SubprocessError, OSError, ValueError, KeyError):
        raise SystemExit('Agent diagnostics unavailable; check provisioning or credential expiry.')


if __name__ == '__main__':
    main()
