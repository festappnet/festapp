#!/usr/bin/env python3
"""Loopback diagnostics only. No SQL, shell or release operation in the API."""
import hashlib
import hmac
import json
import os
import subprocess
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

CONFIG = Path(os.environ.get('FESTAPP_AGENT_CONFIG', '/run/secrets/broker.json'))
DATABASE = 'festapp_rehearsal_20260909220601'
ROLE = 'festapp_agent_diagnostics'
OPERATIONS = {
    'probe': "SELECT json_build_object('database',current_database(),'role',current_user,'organization',organization) FROM agent_operations.identity",
    'ledger': "SELECT coalesce(json_agg(version),'[]'::json) FROM agent_operations.migrations",
}


class Denied(Exception):
    pass


def authorize(config, headers, body, now=None):
    now = time.time() if now is None else now
    secret = headers.get('X-Festapp-Agent-Token', '')
    digest = hashlib.sha256(secret.encode()).hexdigest()
    if config.get('revoked', True) or now >= config.get('expires_at', 0):
        raise Denied()
    if not secret or not hmac.compare_digest(digest, config['token_sha256']):
        raise Denied()
    if set(body) != {'operation', 'tenant', 'organization'}:
        raise Denied()
    if body['tenant'] != 'festapp' or type(body['organization']) is not int or body['organization'] != 1:
        raise Denied()
    if body['operation'] not in OPERATIONS:
        raise Denied()
    return body['operation']


def query(operation):
    # Input never enters SQL or the command. Credentials stay in mounted pgpass.
    sql = ('BEGIN READ ONLY; SET LOCAL statement_timeout=3000; '
           'SET LOCAL lock_timeout=1000; ' + OPERATIONS['probe'] + '; ')
    if operation != 'probe':
        sql += OPERATIONS[operation] + '; '
    sql += 'ROLLBACK;'
    result = subprocess.run(
        ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-h', 'db',
         '-U', ROLE, '-d', DATABASE, '-c', sql],
        capture_output=True, timeout=6, check=True,
        env={**os.environ, 'PGCONNECT_TIMEOUT': '3', 'PGPASSFILE': '/run/secrets/pgpass'},
    )
    if len(result.stdout) > 16384:
        raise Denied()
    rows = result.stdout.decode().splitlines()
    identity = json.loads(rows[0])
    if identity != {'database': DATABASE, 'role': ROLE, 'organization': 1}:
        raise Denied()
    return identity if operation == 'probe' else json.loads(rows[1])


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(3)

    def log_message(self, *_args):
        pass  # Never log request lines, headers or bodies.

    def do_POST(self):
        status, response, operation = 403, {'error': 'denied'}, 'denied'
        raw = b''
        try:
            if self.path != '/v1/diagnostics' or self.headers.get('Transfer-Encoding'):
                raise Denied()
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 1024:
                raise Denied()
            raw = self.rfile.read(size)
            if len(raw) != size:
                raise Denied()
            body = json.loads(raw)
            if not isinstance(body, dict):
                raise Denied()
            config = json.loads(CONFIG.read_text())
            operation = authorize(config, self.headers, body)
            response = {'data': query(operation)}
            status = 200
        except (Denied, ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError, IndexError):
            pass
        # Fixed identity: arbitrary request fields and secrets never enter logs.
        print(json.dumps({'identity': 'festapp-workstation', 'operation': operation,
                          'tenant': 'festapp', 'status': status,
                          'digest': hashlib.sha256(raw).hexdigest()}), flush=True)
        payload = json.dumps(response).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(payload)


if __name__ == '__main__':
    # Container port is published exclusively on host loopback in compose.
    HTTPServer(('0.0.0.0', 8789), Handler).serve_forever()
