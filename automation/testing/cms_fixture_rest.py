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


def prepare_rest_image(root, run):
    pins = json.loads((root/'automation/hetzner-supabase/runtime/pins.json').read_text())
    image = pins['supabase']['images']['rest']
    if not re.fullmatch(r'postgrest/postgrest:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}', image):
        raise ValueError('PostgREST image must be pinned by digest')

    present = subprocess.run(['docker', 'image', 'inspect', image],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if present.returncode:
        run(['docker', 'pull', image], label='backend.postgrest-image')
    return image


def start_rest(image, wp, project, port, run):
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
        run(['docker', 'run', '-d', '--pull=never', '--name', project+'-rest', '--label', OWNER_LABEL+'='+project,
             '--network', network, '--publish', f'127.0.0.1:{port}:3000',
             '--env-file', environment, image], label='backend.postgrest')
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
            if time.monotonic() >= deadline:
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
