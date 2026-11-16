#!/usr/bin/env python3
"""Prepare the fixed 0.8.4/17.12 package from an installed configuration copy.

Runs off-host with PyYAML 6.0.3. Does not read .env, contact production, build,
start services or execute SQL. Installed overrides remain the configuration
authority; only the reviewed image, router, memory and gateway deltas apply.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.request
import yaml

HERE = Path(__file__).resolve().parent
COMMIT = '189adda99d1b56da55fc5a6ee3f849354aaea92a'
BASE = ['docker-compose.yml', 'docker-compose.festapp.yml', 'docker-compose.database-target.yml',
        'docker-compose.email.yml', 'docker-compose.pgbackrest.yml', 'docker-compose.resource-budget.yml',
        'caddy/Caddyfile', 'volumes/api/envoy/cds.yaml', 'volumes/api/envoy/lds.template.yaml',
        'volumes/functions/main/index.ts', 'studio-customization/install-logout.mjs']
SERVICES = {'studio':'studio', 'api-gw':'envoy', 'auth':'auth', 'rest':'rest',
            'realtime':'realtime', 'meta':'postgresMeta', 'functions':'edgeRuntime', 'supavisor':'supavisor'}


def routes(value):
    if isinstance(value, dict):
        if 'routes' in value:
            return value['routes']
        for child in value.values():
            found = routes(child)
            if found is not None:
                return found
    elif isinstance(value, list):
        for child in value:
            found = routes(child)
            if found is not None:
                return found


def prepare(installed, output, source_sha, db_image, baseline_db_image, rehearsal):
    assert re.fullmatch('[a-f0-9]{40}', source_sha)
    assert all(re.fullmatch('sha256:[a-f0-9]{64}', v) for v in [db_image, baseline_db_image])
    assert not output.exists()
    assert yaml.__version__ == '6.0.3'
    pins = json.loads((HERE/'pins.json').read_text())
    assert pins['supabase']['commit'] == COMMIT
    images = pins['supabase']['images']
    baseline = {name: hashlib.sha256((installed/name).read_bytes()).hexdigest() for name in BASE}
    text = (installed/'docker-compose.festapp.yml').read_text()
    for key in [*SERVICES.values(), 'postgres']:
        image = images[key]
        repository = image.split(':', 1)[0]
        text, count = re.subn(r'(?m)^(    image: )'+re.escape(repository)+r':[^\n]+$',
                             lambda match: match[1]+image, text)
        assert count == 1, 'Installed image contract changed: '+key
    assert 'mem_limit:' not in text.split('  functions:\n',1)[1].split('\n  db:',1)[0]
    text = text.replace('  functions:\n', '  functions:\n    mem_limit: 2147483648\n'
        '    command: !override [start, --user-worker-request-idle-timeout, "150000", --main-service, /home/deno/functions/main]\n', 1)
    assert 'DENO_TLS_CA_STORE:' not in text
    text = text.replace('      FESTAPP_MCP_TENANTS_JSON:',
        '      DENO_TLS_CA_STORE: system,mozilla\n      FESTAPP_MCP_TENANTS_JSON:', 1)
    assert 'DENO_TLS_CA_STORE: system,mozilla' in text
    lds = yaml.safe_load((installed/'volumes/api/envoy/lds.template.yaml').read_text())
    request = urllib.request.Request('https://raw.githubusercontent.com/supabase/supabase/'+COMMIT+
        '/docker/volumes/api/envoy/lds.template.yaml', headers={'User-Agent':'festapp-runtime-update'})
    upstream_bytes = urllib.request.urlopen(request, timeout=30).read()
    upstream = yaml.safe_load(upstream_bytes)
    old_routes, new_routes = routes(lds), routes(upstream)
    discovery = [r for r in new_routes if any('well-known' in str(v) and 'jwks' not in str(v)
                 for v in r.get('match', {}).values())]
    assert len(discovery) == 3
    index = next(i for i,r in enumerate(old_routes) if r.get('match', {}).get('prefix') == '/.well-known/oauth-authorization-server')
    old_routes[index:index+1] = copy.deepcopy(discovery)
    old = next(r for r in old_routes if r.get('match', {}).get('prefix') == '/functions/v1/')
    new = next(r for r in new_routes if r.get('match', {}).get('prefix') == '/functions/v1/')
    old['route'] = copy.deepcopy(new['route'])
    # Festapp browser Functions still rely on the installed gateway CORS
    # contract, including disabled-feature errors. Preserve that policy; the
    # upstream 0.8.4 per-route disable breaks existing clients.
    # Function authorization and tenant feature configuration stay unchanged.
    cds = yaml.safe_load((installed/'volumes/api/envoy/cds.yaml').read_text())

    def clusters(value):
        if isinstance(value, dict):
            if value.get('@type','').endswith('.Cluster'):
                value['ignore_health_on_host_removal'] = True
            for child in value.values():
                clusters(child)
        elif isinstance(value, list):
            for child in value:
                clusters(child)
    clusters(cds)
    lds_text = yaml.safe_dump(lds,sort_keys=False)
    # Preserve string types after sed substitutes optional legacy-mode keys.
    # An unquoted empty substitution becomes YAML null and invalid Envoy RBAC.
    lds_text = re.sub(r'(?m)^(\s*exact: )(\$\{[A-Z_]+\})$', r'\1"\2"', lds_text)
    payload = {'docker-compose.festapp.yml':text.encode(),
        'volumes/api/envoy/cds.yaml':yaml.safe_dump(cds,sort_keys=False).encode(),
        'volumes/api/envoy/lds.template.yaml':lds_text.encode(),
        'volumes/functions/main/index.ts':(HERE/'functions-main/index.ts').read_bytes(),
        'volumes/functions/main/memory-pressure.ts':(HERE/'functions-main/memory-pressure.ts').read_bytes(),
        'volumes/functions/deno.jsonc':(HERE/'functions-main/deno.jsonc').read_bytes(),
        'studio-customization/install-logout.mjs':(HERE/'studio-customization/install-logout.mjs').read_bytes()}
    os.umask(0o077)
    output.mkdir(mode=0o700)
    for name, content in payload.items():
        target = output/name
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(content)
    manifest = {'manifest_version':1, 'source_sha':source_sha, 'target':'api.festapp.net',
        'postgres_version_num':'170012', 'db_image':db_image, 'baseline_db_image':baseline_db_image,
        'files':{name:hashlib.sha256(content).hexdigest() for name,content in payload.items()},
        'baseline_files':baseline, 'images':{service:images[key] for service,key in SERVICES.items()},
        'rehearsal':json.loads(rehearsal.read_text()),
        'upstream_lds_sha256':hashlib.sha256(upstream_bytes).hexdigest()}
    manifest['images']['db'] = db_image
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Prepared fixed runtime package; no production changes.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--installed-dir',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--source-sha',required=True)
    parser.add_argument('--db-image',required=True)
    parser.add_argument('--baseline-db-image',required=True)
    parser.add_argument('--rehearsal',type=Path,required=True)
    args=parser.parse_args()
    prepare(args.installed_dir,args.output,args.source_sha,args.db_image,args.baseline_db_image,args.rehearsal)
