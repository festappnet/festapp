"""Run the real public PostgREST API on the CMS fixture's owned database."""
import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import subprocess
import time
from urllib.error import URLError
from urllib.request import ProxyHandler, Request, build_opener


OWNER_LABEL = 'net.festapp.cms-rest'
# The OCI index contains Linux amd64 for Actions and arm64 for Apple Silicon.
POSTGREST_IMAGE = 'postgrest/postgrest:v14.18@sha256:c7cd7e265a85b05248abf53f4473fcec7e327c282d0bd0cf60f1551996d09fcf'


def anon_token(secret):
    def encode(value):
        return base64.urlsafe_b64encode(value).rstrip(b'=')

    payload = b'.'.join(encode(json.dumps(value, separators=(',', ':')).encode()) for value in (
        {'alg': 'HS256', 'typ': 'JWT'},
        {'role': 'anon', 'iss': 'supabase', 'exp': int(time.time()) + 3600},
    ))
    signature = hmac.new(secret.encode(), payload, hashlib.sha256).digest()
    return (payload + b'.' + encode(signature)).decode()


def write_private(path, data):
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
        output.write(data)


def prepare_rest_image(run):
    architecture = run(['docker', 'version', '--format', '{{.Server.Arch}}'], capture=True).strip()
    if architecture not in ('amd64', 'arm64'):
        raise RuntimeError(f'Unsupported PostgREST test architecture: {architecture}')
    platform = f'linux/{architecture}'
    present = subprocess.run(['docker', 'image', 'inspect', '--format', '{{.Architecture}}', POSTGREST_IMAGE],
                             capture_output=True, text=True)
    if present.returncode or present.stdout.strip() != architecture:
        run(['docker', 'pull', '--platform', platform, POSTGREST_IMAGE], label='backend.postgrest-image')
    return platform


def start_rest(platform, wp, project, port, run):
    if not re.fullmatch(r'festapp-cms-consent-[a-f0-9]{12}', project):
        raise ValueError('Owned CMS project required')
    container = 'supabase_db_' + project
    network = 'supabase_network_' + project
    owner = run(['docker', 'inspect', '--format', '{{index .Config.Labels "com.supabase.cli.project"}}',
                 container], capture=True).strip()
    if owner != project:
        raise ValueError('Foreign CMS database refused')
    secret = secrets.token_hex(32)
    token = anon_token(secret)
    private = wp/'.private'
    environment = private/'postgrest.env'
    write_private(environment, '\n'.join([
        f'PGRST_DB_URI=postgresql://authenticator:postgres@{container}:5432/postgres',
        'PGRST_DB_SCHEMAS=public,graphql_public', 'PGRST_DB_EXTRA_SEARCH_PATH=public,extensions',
        'PGRST_DB_ANON_ROLE=anon', 'PGRST_DB_MAX_ROWS=1000', f'PGRST_JWT_SECRET={secret}',
    ]) + '\n')
    try:
        run(['docker', 'run', '-d', '--pull=never', '--platform', platform, '--name', project+'-rest', '--label', OWNER_LABEL+'='+project,
             '--network', network, '--publish', f'127.0.0.1:{port}:3000',
             '--env-file', environment, POSTGREST_IMAGE], label='backend.postgrest')
    finally:
        environment.unlink()

    url = f'http://127.0.0.1:{port}'
    probe = Request(url+'/rpc/get_form_measurement_policy',
                    data=b'{"p_form_link":"embedded-synthetic"}',
                    headers={'Content-Type': 'application/json', 'Authorization': 'Bearer '+token})
    client = build_opener(ProxyHandler({}))
    deadline = time.monotonic() + 45
    while True:
        try:
            with client.open(probe, timeout=2) as response:
                json.load(response)
            break
        except (URLError, ConnectionError, TimeoutError) as error:
            state = run(['docker', 'inspect', '--format', '{{.State.Status}} {{.State.ExitCode}}',
                         project+'-rest'], capture=True).strip()
            if not state.startswith('running '):
                run(['docker', 'logs', project+'-rest'], label='backend.postgrest-diagnostics')
                raise RuntimeError(f'Owned PostgREST stopped before readiness ({state})') from error
            if time.monotonic() >= deadline:
                run(['docker', 'logs', project+'-rest'], label='backend.postgrest-diagnostics')
                raise RuntimeError('Owned PostgREST never served the public form RPC') from error
            time.sleep(.2)
    write_private(private/'backend-status.json', json.dumps({'API_URL': url, 'ANON_KEY': token}))


def stop_rest(project, run):
    name = project+'-rest'
    result = subprocess.run(['docker', 'container', 'inspect', '--format',
                             '{{index .Config.Labels "'+OWNER_LABEL+'"}}', name],
                            capture_output=True, text=True)
    if result.returncode:
        if 'no such container' in result.stderr.lower() or 'no such object' in result.stderr.lower():
            return
        raise RuntimeError('Cannot inspect the owned CMS PostgREST container')
    if result.stdout.strip() != project:
        raise ValueError('Foreign PostgREST container refused')
    run(['docker', 'rm', '-f', name], label='cleanup.postgrest')
