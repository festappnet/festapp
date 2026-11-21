#!/usr/bin/env python3
"""Render the reviewed public Auth route over the installed Caddy template."""
import argparse
from pathlib import Path


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError('Caddy template changed. Review the Auth route before rendering.')
    return source.replace(old, new, 1)


def render(source, port):
    source = replace_once(source, 'reverse_proxy 127.0.0.1:8000 {',
                          'reverse_proxy {args[0]} {')
    old_import = '\timport festapp_supabase_proxy'
    if source.count(old_import + '\n') != 3:
        raise ValueError('Caddy proxy imports changed. Review the Auth route before rendering.')
    source = source.replace(old_import + '\n', old_import + ' 127.0.0.1:8000\n')
    source = replace_once(
        source,
        '\t@auth path /auth/v1 /auth/v1/*\n\thandle @auth {\n\t\trequest_body {\n'
        '\t\t\tmax_size 64KB\n\t\t}\n' + '\t' + old_import + ' 127.0.0.1:8000',
        '\t@auth path /auth/v1 /auth/v1/*\n\thandle @auth {\n\t\trequest_body {\n'
        '\t\t\tmax_size 64KB\n\t\t}\n' + '\t' + old_import + f' 127.0.0.1:{port}',
    )
    return replace_once(source, ' /auth/v1 /auth/v1/* \\\n', '')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, required=True, help='Auth ingress loopback port')
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535 or args.port in (8000, 8443, 8999):
        parser.error('choose a dedicated loopback port')
    template = Path(__file__).resolve().parents[1] / 'runtime' / 'Caddyfile'
    print(render(template.read_text(), args.port), end='')
