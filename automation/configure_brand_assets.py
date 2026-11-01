#!/usr/bin/env python3
"""Generate browser brand adapters from the selected tenant's source artwork."""
import argparse
import base64
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
for flag in ('root', 'logo', 'dark-logo', 'loading-style'):
    parser.add_argument('--' + flag, required=True)
for flag in ('animation', 'dark-animation', 'icon-dir'):
    parser.add_argument('--' + flag, default='')
args = parser.parse_args()
root = Path(args.root)

def svg_adapter(source):
    path = root / source
    data = path.read_bytes()
    if path.suffix.lower() == '.svg':
        return data
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('Configured brand artwork must be SVG or PNG')
    width, height = struct.unpack('>II', data[16:24])
    image = base64.b64encode(data).decode('ascii')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">'
            f'<image width="{width}" height="{height}" href="data:image/png;base64,{image}"/>'
            '</svg>\n').encode()

if args.loading_style not in ('spinner', 'vstupenky-outline'):
    raise ValueError('Unsupported loading style')
normal, dark = svg_adapter(args.logo), svg_adapter(args.dark_logo)
if args.loading_style == 'vstupenky-outline':
    if not args.animation or not args.dark_animation:
        raise ValueError('The outline loader requires light and dark animation sources')
    animation, dark_animation = svg_adapter(args.animation), svg_adapter(args.dark_animation)
else:
    # Regenerating another tenant cannot retain the previous product animation.
    animation, dark_animation = normal, dark
outputs = {
    'web/loading-logo.svg': dark,
    'web/loading-logo-light.svg': normal,
    'web/loading-animation.svg': dark_animation,
    'web/loading-animation-light.svg': animation,
    'web_client/public/brand-logo.svg': dark,
    'web_client/public/brand-logo-light.svg': normal,
    'web_client/public/loading-animation.svg': dark_animation,
    'web_client/public/loading-animation-light.svg': animation,
}
if args.loading_style == 'vstupenky-outline':
    brand = root / 'assets/brand/vstupenky-online'
    outputs['web_client/public/brand-wordmark-stacked.svg'] = (brand / 'vstupenky-online-wordmark-dark.svg').read_bytes()
    wordmark = ET.parse(brand / 'vstupenky-online-wordmark-dark.svg').getroot()
    wordmark.set('viewBox', '65 580 1320 200')
    wordmark.set('width', '1320')
    wordmark.set('height', '200')
    domain = wordmark.find(".//*[@id='domain']")
    if domain is None:
        raise ValueError('The ticketing wordmark requires its domain lettering')
    # Keep the original outlined lettering, aligned on one desktop baseline.
    domain.set('transform', 'translate(610 -166)')
    outputs['web_client/public/brand-wordmark.svg'] = ET.tostring(wordmark)
    outputs['web_client/public/brand-symbol.svg'] = (brand / 'vstupenky-online-symbol-dark.svg').read_bytes()
else:
    outputs['web_client/public/brand-wordmark-stacked.svg'] = dark
    outputs['web_client/public/brand-wordmark.svg'] = dark
    outputs['web_client/public/brand-symbol.svg'] = dark
for name in ('favicon.ico', 'favicon-16x16.png', 'favicon-32x32.png',
             'android-chrome-192x192.png', 'android-chrome-512x512.png', 'apple-touch-icon.png'):
    source = root / args.icon_dir / name if args.icon_dir else root / 'web' / name
    if source.exists():
        data = source.read_bytes()
        if args.icon_dir:
            outputs['web/' + name] = data
        outputs['web_client/public/' + name] = data
        if args.icon_dir and name == 'favicon.ico':
            outputs['web_client/favicon.ico'] = data
    elif args.icon_dir:
        raise ValueError('Missing configured icon: ' + name)
for target, data in outputs.items():
    path = root / target
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
