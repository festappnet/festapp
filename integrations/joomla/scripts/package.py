#!/usr/bin/env python3
"""Reproducible candidate ZIPs; every distinct byte stream also has immutable storage."""
import io
import json
import zipfile
from build import ROOT, build, digest


def package():
    products = build()
    output = ROOT / 'artifacts'
    output.mkdir(exist_ok=True)
    inputs = [ROOT / 'products.json', ROOT / 'translations.json', ROOT / 'scripts/build.py', ROOT / 'scripts/package.py'] + sorted((ROOT / 'shared').rglob('*'))
    receipt = {'inputs': {str(p.relative_to(ROOT)): digest(p) for p in inputs if p.is_file()}, 'packages': {}}
    for p in products:
        base = ROOT / 'build' / p['element']
        name = p['element'] + '-' + p['version'] + '.zip'
        files = sorted(f for f in base.rglob('*') if f.is_file())
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for f in files:
                info = zipfile.ZipInfo(str(f.relative_to(base)), (2026, 10, 26, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                z.writestr(info, f.read_bytes(), compresslevel=9)
        data = buffer.getvalue()
        import hashlib
        sha = hashlib.sha256(data).hexdigest()
        immutable = output / 'sha256' / sha / name
        immutable.parent.mkdir(parents=True, exist_ok=True)
        if immutable.exists() and immutable.read_bytes() != data:
            raise RuntimeError('Immutable artifact collision')
        if not immutable.exists():
            immutable.write_bytes(data)
        (output / name).write_bytes(data)  # Explicit mutable build candidate, never the reviewed release.
        receipt['packages'][name] = {'sha256': sha, 'immutable': str(immutable.relative_to(ROOT)), 'files': {str(f.relative_to(base)): digest(f) for f in files}}
    (ROOT / 'evidence').mkdir(exist_ok=True)
    (ROOT / 'evidence/packages.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    receipt = package()
    print('\n'.join(v['sha256'] + '  ' + k for k, v in receipt['packages'].items()))
