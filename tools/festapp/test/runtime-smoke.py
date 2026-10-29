#!/usr/bin/env python3
"""Explicit local Docker gate. No production access, ports or provider calls.
Build Dockerfile.remote first; all state and Caddy containers are disposable.
"""
import json
import shlex
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
IMAGE = 'festapp-mcp-hardening-local'
CADDY = 'caddy:2.11.4@sha256:1172d4213087d3fc30bafc7ff2c2896180eb0c41ff7f75f315568fb36cabdcba'
name = 'festapp-mcp-smoke-' + uuid.uuid4().hex[:10]
volume = name + '-state'


def run(*args, success=True):
    result = subprocess.run(args, text=True, capture_output=True)
    if success and result.returncode:
        raise RuntimeError(f'{args[0:3]}: {result.stderr[-3000:]} {result.stdout[-1000:]}')
    return result


def probe(script):
    return run('docker', 'exec', name, 'node', '--input-type=module', '-e', script)


try:
    run('docker', 'volume', 'create', volume)
    bootstrap = """
      import fs from 'node:fs';
      import {canonicalBackendProfileSha256} from './automation/lib/backend_activation_manifest.mjs';
      const profile={schemaVersion:1,name:'smoke',kind:'canonical',tenantId:'smoke',
        backendOrigin:'https://api.example.invalid',publicApiKey:'sb_publishable_smoke',organizationId:1,
        activationUrl:'https://tenant.example.invalid/backend-activation.json',activationSha256:'a'.repeat(64),generation:1};
      profile.canonicalProfileSha256=canonicalBackendProfileSha256({tenantId:profile.tenantId,canonicalOrigin:profile.backendOrigin,canonicalAnonKey:profile.publicApiKey,canonicalOrganizationId:1});
      fs.writeFileSync('/state/config.json',JSON.stringify({schemaVersion:2,issuer:'https://mcp.vstupenky.online',profile,
        clients:[{id:'smoke',name:'Smoke',redirectUris:['https://client.example.invalid/callback']}]}));
      for(const dir of ['/state/keys','/state/data']){fs.mkdirSync(dir,{mode:0o700});fs.chownSync(dir,1000,1000);}
    """
    run('docker', 'run', '--rm', '--network', 'none', '--user', '0', '-v', volume + ':/state', IMAGE,
        'node', '--input-type=module', '-e', bootstrap)
    run('docker', 'run', '--rm', '--network', 'none', '-v', volume + ':/state', IMAGE,
        'node', 'tools/festapp/src/remote/main.mjs', 'secrets', 'init', '/state/keys/secrets.json')
    compose = (ROOT / 'tools/festapp/remote-compose.yml').read_text()
    health = compose.split('test: [CMD, node, -e, "', 1)[1].split('"]', 1)[0]
    health = health.replace('/run/festapp/config.json', '/state/config.json')
    command = ['node', 'tools/festapp/src/remote/main.mjs', 'serve', '/state/config.json',
               '--secrets', '/state/keys/secrets.json', '--data', '/state/data', '--port', '3399']
    run('docker', 'run', '-d', '--name', name, '--network', 'none', '--read-only', '--tmpfs', '/tmp',
        '--health-cmd', 'node -e ' + shlex.quote(health), '--health-interval', '1s',
        '-v', volume + ':/state', IMAGE, *command)
    for _ in range(50):
        state = json.loads(run('docker', 'inspect', name).stdout)[0]
        if state['State'].get('Health', {}).get('Status') == 'healthy':
            break
        if not state['State']['Running']:
            raise RuntimeError(run('docker', 'logs', name).stderr)
        time.sleep(.2)
    else:
        raise RuntimeError('Compose health probe failed')
    second = run('docker', 'run', '--rm', '--network', 'none', '-v', volume + ':/state', IMAGE, *command, success=False)
    assert second.returncode != 0 and 'SESSION_BUSY' in second.stderr, second.stderr
    with tempfile.TemporaryDirectory(prefix='festapp-caddy-smoke-', dir=ROOT / 'tools/festapp') as directory:
        directory = Path(directory)
        canonical = (ROOT / 'automation/hetzner-supabase/runtime/Caddyfile').read_text()
        snippet = (ROOT / 'tools/festapp/Caddyfile.remote').read_text()
        complete = directory / 'complete.Caddyfile'
        complete.write_text(canonical + '\n' + snippet)
        caddy_args = ['docker', 'run', '--rm', '--network', 'none', '-v', str(directory) + ':/evidence:ro',
                      '-e', 'FESTAPP_SUPABASE_SITE_ADDRESSES=api.example.invalid', CADDY]
        run(*caddy_args, 'caddy', 'validate', '--config', '/evidence/complete.Caddyfile', '--adapter', 'caddyfile')
        adapted = json.loads(run(*caddy_args, 'caddy', 'adapt', '--config', '/evidence/complete.Caddyfile', '--adapter', 'caddyfile').stdout)
        servers = adapted['apps']['http']['servers'].values()
        assert any(s.get('trusted_proxies', {}).get('source') == 'static' and s.get('trusted_proxies_strict') for s in servers)
        def objects(value):
            if isinstance(value, dict):
                yield value
                for child in value.values():
                    yield from objects(child)
            elif isinstance(value, list):
                for child in value:
                    yield from objects(child)
        proxies = [value for value in objects(adapted) if value.get('handler') == 'reverse_proxy'
                   and value.get('upstreams') == [{'dial': '127.0.0.1:3399'}]]
        assert len(proxies) == 1
        assert proxies[0]['headers']['request']['set']['X-Festapp-Client-Ip'] == ['{http.vars.client_ip}']
        global_block = canonical[:canonical.index('\n}\n') + 3]
        isolated = directory / 'isolated.Caddyfile'
        isolated.write_text(global_block.replace('{\n', '{\n admin off\n auto_https off\n', 1)
                            + snippet.replace('mcp.vstupenky.online {', 'http://mcp.vstupenky.online:8090 {'))
        run('docker', 'run', '-d', '--name', name + '-proxy', '--network', 'container:' + name,
            '-v', str(directory) + ':/evidence:ro', CADDY, 'caddy', 'run', '--config', '/evidence/isolated.Caddyfile', '--adapter', 'caddyfile')
        for _ in range(50):
            ready = run('docker', 'exec', name, 'node', '-e', "require('node:net').connect(8090,'127.0.0.1').on('connect',()=>process.exit(0)).on('error',()=>process.exit(1))", success=False)
            if ready.returncode == 0:
                break
            time.sleep(.1)
        # Different forged headers cannot escape the single Caddy-derived identity.
        probe("""
          import assert from 'node:assert/strict';
          import http from 'node:http';
          const request=(path,headers={})=>new Promise((resolve,reject)=>{
            http.get({hostname:'127.0.0.1',port:8090,path,headers:{host:'mcp.vstupenky.online',...headers}},r=>{
              let body='';r.on('data',c=>body+=c);r.on('end',()=>resolve({status:r.statusCode,headers:r.headers,body}));
            }).on('error',reject);
          });
          for(let i=0;i<241;i++){
            const r=await request('/.well-known/oauth-protected-resource',{
              'x-festapp-client-ip':`192.0.2.${i%250+1}`,'x-forwarded-for':'203.0.113.1','cf-connecting-ip':'203.0.113.2'});
            assert.equal(r.status,i<240?200:429,JSON.stringify({i,body:r.body}));
            if(i<240)assert(JSON.parse(r.body).authorization_servers.includes('https://mcp.vstupenky.online'));
            if(i===240)assert.equal(r.headers['retry-after'],'60');
          }
          const r=await request('/healthz');assert.equal(r.status,200);assert.equal(JSON.parse(r.body).ok,true);
        """)
        # Execute precisely the Compose probe after quota exhaustion as well.
        run('docker', 'exec', name, 'node', '-e', health)
        run('docker', 'rm', '-f', name + '-proxy')
    run('docker', 'kill', '--signal', 'KILL', name)
    run('docker', 'start', name)
    for _ in range(50):
        result = run('docker', 'exec', name, 'node', '-e', health, success=False)
        if result.returncode == 0:
            break
        time.sleep(.1)
    else:
        raise RuntimeError('SIGKILL/restart did not recover')
    run('docker', 'exec', name, 'node', '-e', "const fs=require('node:fs');if(!fs.existsSync('/state/data/remote-owner.sqlite'))process.exit(1)")
    print('PASS: pinned Node 24 startup, second owner, SIGKILL/restart, complete Caddy validation/trust, spoofed-IP overwrite, quota and Compose health')
except Exception:
    print(run('docker', 'logs', name, success=False).stderr[-3000:])
    raise
finally:
    run('docker', 'rm', '-f', name + '-proxy', success=False)
    run('docker', 'rm', '-f', name, success=False)
    run('docker', 'volume', 'rm', volume, success=False)
