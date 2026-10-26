"""Shared source/evidence fingerprint for release verification; no network/mutations."""
import hashlib
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ['contract-5.json','contract-6.json','installed-files.json','cms.json','native-publication.json','browser.json','updater-5.json','updater-6.json','live-links.json','live-browser.json','lifecycle-5.json','lifecycle-6.json','uninstall-http.json']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes():
    files = [ROOT / name for name in ['products.json','translations.json','docker-images.json']]
    for directory in ['shared','scripts','tests','updates']:
        files.extend(p for p in (ROOT / directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    return {str(p.relative_to(ROOT)):sha(p) for p in sorted(files)}


def evidence_hashes():
    return {name:sha(ROOT / 'evidence' / name) for name in EVIDENCE}
