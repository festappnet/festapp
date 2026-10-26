#!/usr/bin/env python3
"""Generate standalone Joomla modules; only shared/ and products.json are sources."""
import hashlib
import json
import shutil
from xml.sax.saxutils import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build():
    products = json.loads((ROOT / 'products.json').read_text())
    for product in products:
        target = ROOT / 'build' / product['element']
        if target.exists():
            shutil.rmtree(target)
        update_servers = ''
        if product.get('update_url'):
            update_servers = '  <updateservers><server type="extension" priority="1" name="' + escape(product['name'], {'"': '&quot;'}) + '">' + escape(product['update_url']) + '</server></updateservers>\n'
        replacements = {**product, 'key': product['element'].upper(), 'update_servers': update_servers}
        def expand(value):
            for key, replacement in replacements.items():
                value = value.replace('@@' + key.upper() + '@@', replacement)
            if '@@' in value:
                raise ValueError('Unexpanded template marker')
            return value
        for source in sorted((ROOT / 'shared').rglob('*')):
            if not source.is_file():
                continue
            rel = source.relative_to(ROOT / 'shared')
            name = str(rel).removesuffix('.in')
            if name == 'module.xml':
                name = product['element'] + '.xml'
            dest = target / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(expand(source.read_text()))
        for locale, strings in json.loads((ROOT / 'translations.json').read_text()).items():
            language = target / 'language' / locale
            language.mkdir(parents=True)
            text = '; Copyright (C) 2026 Festapp. GNU GPL version 2 or later.\n'
            text += product['element'].upper() + '=' + json.dumps(product['name'], ensure_ascii=False) + '\n'
            for key, value in strings.items():
                text += product['element'].upper() + '_' + key + '=' + json.dumps(expand(value), ensure_ascii=False) + '\n'
            for suffix in ['ini', 'sys.ini']:
                (language / (product['element'] + '.' + suffix)).write_text(text)
    return products


if __name__ == '__main__':
    build()
    print('Built 2 Joomla modules')
