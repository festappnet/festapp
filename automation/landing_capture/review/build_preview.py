#!/usr/bin/env python3
"""Render the canonical landing as a server-free local review artifact."""
import argparse
import base64
from pathlib import Path
import re
import subprocess


def build(repo, output):
    output.mkdir(parents=True, exist_ok=True)
    generated = output / 'generated.html'
    subprocess.run(['node', str(repo / 'automation/release/render_organizer_page.mjs'),
                    '--config', str(repo / 'automation/project.conf'), '--output', str(generated)], cwd=repo, check=True)
    html = generated.read_text()
    fonts = []
    for filename, weight in [('FuturaPTBook.ttf', '400'), ('FuturaPTMedium.ttf', '500 600')]:
        data = base64.b64encode((repo / 'web_client/src/assets/fonts' / filename).read_bytes()).decode()
        fonts.append(f'@font-face{{font-family:Futura;src:url(data:font/ttf;base64,{data});font-weight:{weight}}}')
    html = html.replace('</head>', '<style>' + ''.join(fonts) + '</style></head>')
    html = html.replace('href="/favicon.ico"', f'href="{(repo / "web_client/public/favicon.ico").as_uri()}"')
    html = re.sub(r'href="(/(?!organizers-media/)[^"]*)"', lambda match: 'href="https://vstupenky.online' + match.group(1) + '"', html)
    html = html.replace('/brand-logo.svg', (repo / 'web_client/public/brand-logo.svg').as_uri())
    html = re.sub(r'(?<![A-Za-z0-9/:])/organizers-media/', lambda _: (repo / 'web/organizers-media').as_uri() + '/', html)
    scripts = []
    for module, initializer in [('demo_player', 'initDemoPlayers'), ('motion', 'initMotion'), ('reference_carousel', 'initReferenceCarousels')]:
        source = (repo / f'web_client/src/marketing/{module}.js').read_text()
        source = re.sub(r'^export\s+(?=function|const|class)', '', source, flags=re.MULTILINE)
        if re.search(r'^\s*(?:import|export)\s', source, re.MULTILINE):
            raise RuntimeError(f'{module}: module dependencies need an explicit static-preview adapter')
        scripts.append('(function(){\n' + source + '\n' + initializer + '();})();')
    html = html.replace('</body>', '<script>' + '\n'.join(scripts) + '</script></body>')
    (output / 'landing.html').write_text(html)
    print(f'Static preview: {output / "landing.html"}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--output', type=Path, required=True, help='Task-owned directory outside Git')
    args = parser.parse_args()
    build(args.repo.resolve(), args.output.resolve())
