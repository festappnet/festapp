#!/usr/bin/env python3
"""Qualify the candidate Caddy and strict Auth routing in a disposable container."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory
from time import monotonic, sleep
from uuid import uuid4


BASE = Path(__file__).resolve().parent
PRODUCTION_CADDY = 'caddy:2.11.4@sha256:1172d4213087d3fc30bafc7ff2c2896180eb0c41ff7f75f315568fb36cabdcba'
# The immutable release index includes the production arm64 manifest and the CI amd64 sibling.
CADDY = 'caddy:2.11.4@sha256:0c994536bddb66445885237f1a5dcc1916bccea922661c76b4e9fc24061f9b52'
PUBLIC_PORT = 18081
BROKER_PORT = 18082


def docker(*args, **kwargs):
    return subprocess.run(['docker', *args], text=True, timeout=120, **kwargs)


def objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from objects(child)


def upstreams(routes):
    return [
        entry['dial']
        for item in objects(routes)
        if item.get('handler') == 'reverse_proxy'
        for entry in item.get('upstreams', [])
    ]


def check_routes(container):
    adapted = docker('exec', container, 'caddy', 'adapt', '--adapter', 'caddyfile',
                     '--config', '/tmp/Caddyfile', capture_output=True, check=True)
    servers = json.loads(adapted.stdout)['apps']['http']['servers']
    public, = [server for server in servers.values() if f':{PUBLIC_PORT}' in server['listen']]
    admin, = [server for server in servers.values() if '127.0.0.1:8999' in server['listen']]
    auth, = [route for route in objects(public['routes']) if 'handle' in route
             and any(any(pattern.startswith('/auth') for pattern in match.get('path', []))
                     for match in route.get('match', []))]
    assert auth['match'] == [{'path': ['/auth/v1', '/auth/v1/*']}]
    assert upstreams(auth['handle']) == [f'127.0.0.1:{BROKER_PORT}']
    assert sorted(upstreams(public['routes'])) == sorted([f'127.0.0.1:{BROKER_PORT}', '127.0.0.1:8000'])
    assert upstreams(admin['routes']) == ['127.0.0.1:8000']


def probe(container, port, path, method='GET', host='127.0.0.1'):
    post = ['--post-data='] if method == 'POST' else []
    return docker('exec', container, 'wget', '-S', '-T', '2', '-O', '-',
                  '--header', f'Host: {host}:{port}', *post,
                  f'http://127.0.0.1:{port}{path}', capture_output=True)


def check_live(container):
    deadline = monotonic() + 10
    while monotonic() < deadline:
        result = probe(container, PUBLIC_PORT, '/auth/v1/health')
        if 'upstream-fixture' in result.stdout:
            break
        sleep(0.15)
    else:
        raise RuntimeError('Disposable Caddy and Auth broker did not become ready')
    cases = [
        (PUBLIC_PORT, 'POST', '/auth/v1/factors', 403, None),
        (PUBLIC_PORT, 'POST', '/auth/v1/passkeys/authentication/options', 403, None),
        (PUBLIC_PORT, 'GET', '/auth/v1/admin/users', 403, None),
        (PUBLIC_PORT, 'GET', '/rest/v1', 200, 'upstream-fixture'),
        (PUBLIC_PORT, 'GET', '/graphql/v1', 200, 'upstream-fixture'),
        (PUBLIC_PORT, 'GET', '/realtime/v1', 200, 'upstream-fixture'),
        (PUBLIC_PORT, 'GET', '/functions/v1', 200, 'upstream-fixture'),
        (PUBLIC_PORT, 'GET', '/storage/v1', 410, None),
        (8999, 'GET', '/auth/v1/admin/users', 200, 'protected-admin-fixture'),
    ]
    for port, method, path, status, body in cases:
        host = 'localhost' if port == 8999 else '127.0.0.1'
        result = probe(container, port, path, method, host)
        assert re.search(rf'HTTP/1\.[01] {status}\b', result.stderr) and (body is None or result.stdout == body), (
            port, method, path, result.stdout[:300], result.stderr[:600])


def main():
    compose = (BASE.parent / 'runtime' / 'docker-compose.festapp.yml').read_text()
    assert re.search(r'^\s+image: (caddy:\S+@sha256:[0-9a-f]{64})$', compose, re.M)[1] == PRODUCTION_CADDY, (
        'Requalify the matching release when the production Caddy pin changes')
    candidate = subprocess.check_output([sys.executable, BASE / 'render-caddy.py', '--port', str(BROKER_PORT)], text=True)
    architecture = docker('info', '--format', '{{.Architecture}}', capture_output=True, check=True).stdout.strip()
    goarch = {'aarch64': 'arm64', 'arm64': 'arm64', 'x86_64': 'amd64', 'amd64': 'amd64'}[architecture]
    container = f'festapp-mfa-caddy-{uuid4()}'
    with TemporaryDirectory(prefix='festapp-mfa-caddy-') as directory:
        probe_dir = Path(directory)
        (probe_dir / 'Caddyfile').write_text(candidate + '''
http://:8000 {
    bind 127.0.0.1
    @protected {
        path /auth/v1/admin/users
        header Authorization "Basic disposable-fixture"
    }
    respond @protected "protected-admin-fixture" 200
    respond "upstream-fixture" 200
}
''')
        subprocess.run(['go', 'build', '-mod=readonly', '-o', probe_dir / 'auth-ingress', '.'], cwd=BASE,
                       env={**os.environ, 'GOOS': 'linux', 'GOARCH': goarch, 'CGO_ENABLED': '0'}, check=True, timeout=120)
        try:
            docker('create', '--name', container, '--network', 'none',
                   '-e', f'FESTAPP_SUPABASE_SITE_ADDRESSES=http://127.0.0.1:{PUBLIC_PORT}',
                   '-e', 'FESTAPP_SUPABASE_ADMIN_HOSTNAME=localhost',
                   '-e', 'FESTAPP_SUPABASE_ADMIN_BASIC_AUTH=disposable-fixture',
                   CADDY, 'caddy', 'run', '--adapter', 'caddyfile', '--config', '/tmp/Caddyfile',
                   capture_output=True, check=True)
            for name in ('Caddyfile', 'auth-ingress'):
                docker('cp', str(probe_dir / name), f'{container}:/tmp/{name}', capture_output=True, check=True)
            docker('start', container, capture_output=True, check=True)
            check_routes(container)
            docker('exec', '-d', '-e', 'FESTAPP_AUTH_POLICY_SERVICE_TOKEN=disposable-fixture',
                   container, '/tmp/auth-ingress', '-listen', f'127.0.0.1:{BROKER_PORT}',
                   '-upstream', 'http://127.0.0.1:8000', '-policy-origin', 'http://127.0.0.1:8000', check=True)
            check_live(container)
        except subprocess.CalledProcessError as error:
            logs = docker('logs', container, capture_output=True)
            print(error.stderr or '', logs.stderr, file=sys.stderr)
            raise
        finally:
            docker('rm', '-fv', container, capture_output=True)
    print('Pinned Caddy and strict Auth broker verified public denial, forwarded Auth and API routes, and protected administration.')


if __name__ == '__main__':
    main()
