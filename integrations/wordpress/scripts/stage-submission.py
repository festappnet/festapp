"""Prepare two independent, reviewable offline SVN layouts. No external write."""
import argparse, hashlib, json, shutil, zipfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
products = json.loads((root / 'products.json').read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--product', choices=[p['slug'] for p in products])
selected = parser.parse_args().product
products = [p for p in products if selected is None or p['slug'] == selected]
for product in products:
    slug, version = product['slug'], product['version']
    archive = root / 'dist' / f'{slug}-{version}.zip'
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    assert archive.with_suffix('.zip.sha256').read_text().startswith(digest)
    stage = root / 'dist' / ('wordpress-org-draft' if slug == 'vstupenky-online' else 'festapp-tickets-wordpress-org-draft')
    if stage.exists(): shutil.rmtree(stage)
    (stage / 'trunk').mkdir(parents=True)
    with zipfile.ZipFile(archive) as z:
        for entry in z.infolist():
            path = Path(entry.filename)
            assert not path.is_absolute() and path.parts[0] == slug and '..' not in path.parts and len(path.parts) > 1
            target = stage / 'trunk' / Path(*path.parts[1:])
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(z.read(entry))
    shutil.copytree(stage / 'trunk', stage / 'tags' / version)
    catalog = root / 'catalog' / ('festapp-tickets' if slug == 'festapp-tickets' else '')
    names = ['icon-128x128.png', 'icon-256x256.png', 'banner-772x250.png', 'banner-1544x500.png'] + [f'screenshot-{i}.png' for i in range(1, 6)]
    (stage / 'assets').mkdir()
    for name in names: shutil.copy2(catalog / name, stage / 'assets' / name)
    manifest = {str(p.relative_to(stage)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(stage.rglob('*')) if p.is_file()}
    (stage / 'RELEASE.json').write_text(json.dumps({'plugin': slug, 'version': version, 'zip_sha256': digest, 'state': 'prepared for owner approval; not submitted or published', 'publisher': 'festappnet', 'contact': 'info@festapp.net', 'files_sha256': manifest}, indent=2) + '\n')
print(f'PASS: {len(products)} selected offline submission tree(s), matching trunk/tag and 9 assets; no external write')
