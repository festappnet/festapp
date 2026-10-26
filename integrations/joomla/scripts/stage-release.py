#!/usr/bin/env python3
"""Stage the Czech release and stable Joomla update feed without publishing."""
import hashlib
import json
import shutil
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
product = next(p for p in json.loads((ROOT / 'products.json').read_text()) if p['element'] == 'mod_vstupenky_online')
manifest = json.loads((ROOT / 'evidence/packages.json').read_text())
name = product['element'] + '-' + product['version'] + '.zip'
package = manifest['packages'][name]
source = ROOT / package['immutable']
sha = hashlib.sha256(source.read_bytes()).hexdigest()
assert sha == package['sha256']
stage = ROOT / 'dist' / 'sha256' / sha
stage.mkdir(parents=True, exist_ok=True)
zip_path = stage / 'vstupenky.online.zip'
if zip_path.exists() and zip_path.read_bytes() != source.read_bytes():
    raise RuntimeError('Immutable release already differs')
if not zip_path.exists():
    shutil.copyfile(source, zip_path)
(zip_path.with_suffix('.zip.sha256')).write_text(sha + '  vstupenky.online.zip\n')
tag = 'joomla-vstupenky-online-v' + product['version']
url = 'https://github.com/festappnet/festapp/releases/download/' + tag + '/vstupenky.online.zip'
feed = '''<?xml version="1.0" encoding="utf-8"?>
<updates>
  <update>
    <name>vstupenky.online</name>
    <description>Prodej vstupenek na webu Joomla přes uložený veřejný formulář.</description>
    <element>mod_vstupenky_online</element>
    <type>module</type><client>site</client>
    <version>''' + product['version'] + '''</version>
    <infourl title="vstupenky.online pro Joomla">https://github.com/festappnet/festapp/tree/main/integrations/joomla</infourl>
    <downloads><downloadurl type="full" format="zip">''' + escape(url) + '''</downloadurl></downloads>
    <sha256>''' + sha + '''</sha256>
    <tags><tag>stable</tag></tags>
    <maintainer>Festapp</maintainer><maintainerurl>https://vstupenky.online/support/</maintainerurl>
    <targetplatform name="joomla" version="(5\\.4|6\\.1)" />
    <php_minimum>8.3</php_minimum>
  </update>
</updates>
'''
updates = ROOT / 'updates'
updates.mkdir(exist_ok=True)
(updates / 'vstupenky-online.xml').write_text(feed)
# Mutable convenience copy, rejected by the gate if it differs from the seal.
shutil.copyfile(zip_path, ROOT / 'dist/vstupenky.online.zip')
release = {'element':product['element'],'version':product['version'],'tag':tag,'zip':str(zip_path.relative_to(ROOT)),'sha256':sha,'download_url':url,'update_url':product['update_url'],'update_feed_sha256':hashlib.sha256(feed.encode()).hexdigest()}
(ROOT / 'dist/CANDIDATE.json').write_text(json.dumps(release,indent=2)+'\n')
print('Staged Czech release ' + product['version'] + ': ' + sha)
