#!/usr/bin/env python3
"""Generate only public verified-link adapters for the currently selected tenant."""
import json, pathlib, re, sys
from urllib.parse import urlparse
root, web_link, android_id, fingerprints = sys.argv[1:]
root = pathlib.Path(root)
url = urlparse(web_link)
if url.scheme != 'https' or not url.hostname or url.path not in ('', '/'):
    raise SystemExit('Google auth App Links require a canonical HTTPS web origin')
prints = [v.strip().upper() for v in fingerprints.split(',') if v.strip()]
if any(not re.fullmatch(r'(?:[0-9A-F]{2}:){31}[0-9A-F]{2}', v) for v in prints):
    raise SystemExit('Invalid public Android SHA-256 signing certificate fingerprint')
manifest = root / 'android/app/src/main/AndroidManifest.xml'
if manifest.exists():
    source = manifest.read_text()
    block = f'''<!-- FESTAPP_GOOGLE_AUTH_LINK_BEGIN -->
            <meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="https" android:host="{url.hostname}" android:path="/app/google-auth" />
            </intent-filter>
            <!-- FESTAPP_GOOGLE_AUTH_LINK_END -->'''
    if '<!-- FESTAPP_GOOGLE_AUTH_LINK_BEGIN -->' in source:
        source = re.sub(r'<!-- FESTAPP_GOOGLE_AUTH_LINK_BEGIN -->.*?<!-- FESTAPP_GOOGLE_AUTH_LINK_END -->',block,source,flags=re.S)
    else:
        source = source.replace('        </activity>', '            '+block+'\n        </activity>',1)
    manifest.write_text(source)
assetlinks = [] if not prints else [{'relation':['delegate_permission/common.handle_all_urls'], 'target':{'namespace':'android_app','package_name':android_id,'sha256_cert_fingerprints':prints}}]
for relative in ['web/.well-known/assetlinks.json','web_client/public/.well-known/assetlinks.json']:
    path=root/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(assetlinks,indent=2)+'\n')
# Existing tenant-generated AASA identifiers stay authoritative.
for relative in ['web/apple-app-site-association','web/.well-known/apple-app-site-association']:
    path=root/relative
    if path.exists():
        data=json.loads(path.read_text())
        for detail in data.get('applinks',{}).get('details',[]):
            if 'paths' in detail and '/app/google-auth' not in detail['paths']:
                detail['paths'].insert(0,'/app/google-auth')
        for detail in data.get('applinks',{}).get('details',[]):
            if 'components' in detail and not any(c.get('/') == '/app/google-auth' for c in detail['components']):
                detail['components'].insert(0, {'/':'/app/google-auth'})
        path.write_text(json.dumps(data,indent=2)+'\n')

well_known = root / 'web/.well-known/apple-app-site-association'
if well_known.exists():
    for relative in ['web_client/public/.well-known/apple-app-site-association','web_client/public/apple-app-site-association']:
        path=root/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(well_known.read_text())
headers = root / 'web/_headers'
if headers.exists():
    path=root / 'web_client/public/_headers';path.parent.mkdir(parents=True,exist_ok=True);path.write_text(headers.read_text())
