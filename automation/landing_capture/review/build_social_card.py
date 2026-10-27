#!/usr/bin/env python3
"""Render the code-native, branded 1200x630 sharing card in an isolated browser."""
from pathlib import Path
import argparse
import base64
import re
from capture_review import Browser


def build(repo, output):
    output.mkdir(parents=True, exist_ok=True)
    source = (repo / 'automation/release/organizers/page.html').read_text()
    paths = re.search(r'<g class="sketch-scene" data-sketch-scene="0"[^>]*>(.*?)</g>', source).group(1)
    fonts = ''
    for name, weight in [('Futura PT Book.ttf', 400), ('Futura PT Medium.ttf', 500)]:
        data = base64.b64encode((repo / 'automation/fonts' / name).read_bytes()).decode()
        fonts += f'@font-face{{font-family:Futura;src:url(data:font/ttf;base64,{data});font-weight:{weight}}}'
    page = f'''<!doctype html><html lang="cs"><meta charset="utf-8"><style>{fonts}
*{{box-sizing:border-box}}body{{margin:0;background:#ebf1f6;color:#253759;font-family:Futura,sans-serif}}
main{{width:1200px;height:630px;overflow:hidden;position:relative;padding:48px 72px}}
.brand{{font-size:28px;font-weight:500;letter-spacing:-1px}}h1{{font-size:76px;font-weight:500;line-height:1.12;letter-spacing:-2px;margin:72px 0 32px;position:relative;z-index:1}}h1 span{{color:#4465a6}}
p{{font-size:27px;line-height:1.5;margin:0;max-width:650px;position:relative;z-index:1}}
.plan{{position:absolute;left:790px;top:-105px;width:580px;height:754px;stroke:#7193b5;stroke-width:1;fill:none;opacity:.48}}.sketch-fill{{fill:#80bdf2;fill-opacity:.24}}
</style><main><div class="brand">vstupenky.online</div><h1><span>Vstupenky</span><br>pro Vaši akci.</h1><p>Vlastní plánek. Vlastní vstupenka.<br>QR platby bez transakčních poplatků.</p><svg class="plan" viewBox="0 0 300 390" aria-hidden="true">{paths}</svg></main></html>'''
    document = output / 'social-card.html'
    document.write_text(page)
    browser = Browser(output)
    owned = False
    try:
        browser.run('open', document.as_uri())
        browser.verify_owned()
        owned = True
        browser.run('set', 'viewport', '1200', '630')
        browser.run('wait', '--fn', 'document.fonts.status==="loaded"')
        target = repo / 'web/organizers-media/organizers-social.png'
        browser.run('screenshot', str(target))
        print(f'Sharing card: {target}')
    finally:
        if owned:
            browser.run('close')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build(args.repo.resolve(), args.output.resolve())
