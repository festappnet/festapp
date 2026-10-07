#!/usr/bin/env python3
"""SSH ProxyCommand: Keychain service credential stays out of argv and logs."""
import datetime
import json
import os
import re
import subprocess
import sys

SERVICE = 'festapp-backend-ssh'
ACCOUNT = 'festapp-workstation'


def load_credentials():
    result = subprocess.run(['security', 'find-generic-password', '-s', SERVICE,
                             '-a', ACCOUNT, '-w'], capture_output=True, check=True)
    config = json.loads(result.stdout)
    if not re.fullmatch(r'[a-z0-9-]+\.festapp\.net', config['hostname']):
        raise ValueError('Invalid target')
    if not isinstance(config['client_id'], str) or not config['client_id'].endswith('.access'):
        raise ValueError('Invalid service identity')
    if not isinstance(config['client_secret'], str) or not config['client_secret']:
        raise ValueError('Missing credential')
    expiry = datetime.datetime.fromisoformat(config['expires_at'].replace('Z', '+00:00'))
    if expiry <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError('Expired credential')
    return config


def main():
    try:
        config = load_credentials()
        env = dict(os.environ)
        env['TUNNEL_SERVICE_TOKEN_ID'] = config['client_id']
        env['TUNNEL_SERVICE_TOKEN_SECRET'] = config['client_secret']
        os.execvpe('cloudflared', ['cloudflared', 'access', 'ssh', '--hostname', config['hostname']], env)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        sys.stderr.write('Festapp SSH credential unavailable, invalid or expired.\n')
        raise SystemExit(1)


if __name__ == '__main__':
    main()
