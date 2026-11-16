"""Optional CMS base-image transfer cache; never saves containers or volumes."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = Path.home() / '.cache/festapp-cms-images'
INPUTS = ('automation/ci/docker_cache.py',
          '.github/workflows/wix-checkout-compatibility.yml',
          'integrations/wordpress/.wp-env.json',
          'integrations/wordpress/pnpm-lock.yaml',
          'integrations/joomla/docker-images.json',
          'integrations/wordpress/scripts/setup-backend.mjs')
UPSTREAM = re.compile(r'^(?:(?:docker\.io/)?library/)?(?:wordpress|mariadb|mysql|joomla)@sha256:[0-9a-f]{64}$|^(?:public\.ecr\.aws/|docker\.io/)?supabase/[a-z0-9_-]+@sha256:[0-9a-f]{64}$')
IMAGE_ID = re.compile(r'^sha256:[0-9a-f]{64}$')


def key():
    digest = hashlib.sha256(b'cms-base-images-v1\0')
    for name in INPUTS:
        digest.update(name.encode() + b'\0' + (ROOT / name).read_bytes() + b'\0')
    for name in ('RUNNER_OS', 'RUNNER_ARCH', 'ImageOS'):
        digest.update((name + '=' + os.environ.get(name, 'native')).encode() + b'\0')
    return digest.hexdigest()


def docker(*args):
    return subprocess.check_output(['docker', *args], stderr=subprocess.DEVNULL)


def digest_file(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def wordpress_refs():
    config = json.loads((ROOT / 'integrations/wordpress/.wp-env.json').read_text())
    versions = {config['phpVersion'], config.get('env', {}).get('tests', {}).get('phpVersion', config['phpVersion'])}
    if any(not isinstance(version, str) or not re.fullmatch(r'\d+\.\d+', version) for version in versions):
        raise ValueError('Expected explicit WordPress PHP versions')
    return sorted(ref for version in versions for ref in
                  (f'wordpress:php{version}', f'wordpress:cli-php{version}'))


def prefetch_wordpress():
    # BuildKit may otherwise retain a base only in its private build cache,
    # outside docker image save. Explicit pulls make its immutable layers
    # transferable and still resolve mutable upstream tags on every run.
    with ThreadPoolExecutor(max_workers=4) as workers:
        list(workers.map(lambda ref: docker('pull', ref), wordpress_refs()))
    return True


def restore(directory=DIRECTORY):
    (directory / 'verified-key').unlink(missing_ok=True)
    manifest_path = directory / 'manifest.json'
    archive = directory / 'images.tar'
    if not manifest_path.is_file() or not archive.is_file():
        return False
    try:
        manifest = json.loads(manifest_path.read_text())
        images = manifest['images']
        if (manifest['key'] != key() or not images or
                any(not IMAGE_ID.fullmatch(row['id']) or not row['digests'] or
                    any(not UPSTREAM.fullmatch(ref) for ref in row['digests']) for row in images) or
                manifest['sha256'] != digest_file(archive)):
            return False
        docker('image', 'load', '--input', str(archive))
        loaded = json.loads(docker('image', 'inspect', *[row['id'] for row in images]))
        if {row['Id'] for row in loaded} != {row['id'] for row in images}:
            raise ValueError('Loaded image identity mismatch')
        (directory / 'verified-key').write_text(key())
        return True
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError):
        return False


def save(directory=DIRECTORY):
    verified = directory / 'verified-key'
    if verified.is_file() and verified.read_text() == key():
        return True
    ids = sorted(set(docker('image', 'ls', '--quiet', '--no-trunc').decode().split()))
    if not ids:
        return False
    images = json.loads(docker('image', 'inspect', *ids))
    # No commit/export/build cache: only upstream images with registry digests.
    # Locally built plugin images may contain fixture inputs and are excluded.
    selected = [{'id': row['Id'], 'digests': row['RepoDigests']}
                for row in images if row.get('RepoDigests') and
                all(UPSTREAM.fullmatch(ref) for ref in row['RepoDigests'])]
    if not selected:
        return False
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / 'images.tar'
    temporary = directory / 'images.pending.tar'
    docker('image', 'save', '--output', str(temporary), *[row['id'] for row in selected])
    temporary.replace(archive)
    manifest = {'key': key(), 'images': selected, 'sha256': digest_file(archive)}
    (directory / 'manifest.json').write_text(json.dumps(manifest, sort_keys=True) + '\n')
    return True


if __name__ == '__main__':
    mode = sys.argv[1]
    if mode == 'key':
        print(key())
    elif mode in ('restore', 'save', 'prefetch-wordpress'):
        enabled = os.environ.get('FESTAPP_CMS_IMAGE_CACHE') == '1'
        try:
            result = enabled and (prefetch_wordpress() if mode == 'prefetch-wordpress' else globals()[mode]())
        except (OSError, ValueError, subprocess.CalledProcessError):
            result = False
        print(f'CMS upstream image cache {mode}: {"ready" if result else "unavailable; normal runtime resolution retained"}')
    else:
        raise SystemExit('Expected key, restore or save')
