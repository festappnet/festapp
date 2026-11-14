#!/usr/bin/env python3
"""Bounded host cleanup; archive old recovery payloads before local removal."""
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import socket
import stat
import subprocess
import tarfile
import tempfile
import time

HOST = 'festapp-supabase-rehearsal-01'
DATABASE = 'festapp_rehearsal_20260909220601'
EVIDENCE = Path('/var/lib/festapp-rehearsal-evidence')
FUNCTIONS = Path('/opt/festapp-supabase/docker/volumes')
STATE = Path('/var/lib/festapp-host-retention')
DAYS = 14
SUFFIXES = ('.dump', '.dump.age', '.tar', '.tar.age', '.tar.gz', '.sql.gz')


def run(args, **kwargs):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        # Provider errors can include sensitive values. Keep journal errors bounded.
        raise RuntimeError(f'{args[0]} failed (exit {result.returncode})')
    return result.stdout


def fingerprint(path):
    s = path.lstat()
    if not stat.S_ISREG(s.st_mode):
        raise ValueError('Not a regular file')
    return (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)


def old_tree(path, cutoff):
    """A recent file/directory or a symlink fences the whole release directory."""
    if path.is_symlink() or not path.is_dir():
        return False
    for root, dirs, files in os.walk(path, followlinks=False):
        for item in [Path(root)] + [Path(root) / name for name in dirs + files]:
            s = item.lstat()
            if stat.S_ISLNK(s.st_mode) or s.st_mtime >= cutoff:
                return False
    return True


def protected(path, mounts):
    return any(path == mount or path in mount.parents or mount in path.parents for mount in mounts)


def candidates(evidence, functions, mounts, now):
    cutoff = now - DAYS * 86400
    payloads = []
    for directory in sorted(evidence.iterdir()):
        if protected(directory, mounts) or not old_tree(directory, cutoff):
            continue
        files = [p for p in directory.rglob('*') if p.is_file()
                 and p.name.endswith(SUFFIXES) and p.stat().st_size >= 10 * 1024**2]
        if files:
            payloads.append((directory, files))
    backups = sorted([p for p in functions.iterdir()
                      if re.fullmatch(r'functions\.pre-production-\d{8}T\d{6}Z', p.name)
                      and p.is_dir() and not p.is_symlink()], key=lambda p: p.name)
    remove = [p for p in backups[:-2] if not protected(p, mounts) and old_tree(p, cutoff)]
    return payloads, remove


def digest_stream(stream):
    h = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        h.update(chunk)
    return h.hexdigest()


def remote_env():
    config = Path('/etc/festapp-backup/r2.env')
    s = config.stat()
    if s.st_uid != 0 or stat.S_IMODE(s.st_mode) != 0o600:
        raise RuntimeError('Backup config must be root-owned mode 0600')
    values = {}
    for line in config.read_text().splitlines():
        if line.strip() and not line.lstrip().startswith('#'):
            key, sep, value = line.partition('=')
            if sep:
                words = shlex.split(value)
                if len(words) == 1:
                    values[key.strip()] = words[0]
    if values['R2_BUCKET'] != 'festapp-supabase-backups' or not re.fullmatch(
            r'https://[a-zA-Z0-9]+\.r2\.cloudflarestorage\.com/?', values['R2_ENDPOINT']):
        raise RuntimeError('Unexpected backup destination')
    if not values['AGE_RECIPIENT'].startswith('age1'):
        raise RuntimeError('Unexpected encryption recipient')
    env = os.environ.copy()
    env.update(RCLONE_CONFIG_R2_TYPE='s3', RCLONE_CONFIG_R2_PROVIDER='Cloudflare',
               RCLONE_CONFIG_R2_ACCESS_KEY_ID=values['AWS_ACCESS_KEY_ID'],
               RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=values['AWS_SECRET_ACCESS_KEY'],
               RCLONE_CONFIG_R2_ENDPOINT=values['R2_ENDPOINT'],
               RCLONE_CONFIG_R2_NO_CHECK_BUCKET='true')
    return env, values['AGE_RECIPIENT']


def archive(directory, files, state, env, recipient):
    before = {p: fingerprint(p) for p in files}
    required = sum(v[2] for v in before.values())
    if shutil.disk_usage(state).free < required * 1.02 + 1024**3:
        raise RuntimeError('Insufficient staging space; originals preserved')
    with tempfile.TemporaryDirectory(prefix='archive-', dir=state) as temporary:
        encrypted = Path(temporary) / 'payloads.tar.gz.age'
        with encrypted.open('xb') as output, tempfile.TemporaryFile() as errors:
            encoder = subprocess.Popen(['age', '-r', recipient], stdin=subprocess.PIPE,
                                       stdout=output, stderr=errors)
            try:
                with tarfile.open(fileobj=encoder.stdin, mode='w|gz') as tar:
                    for path in files:
                        if fingerprint(path) != before[path]:
                            raise RuntimeError('Recovery payload changed before archival')
                        tar.add(path, arcname=str(path.relative_to(EVIDENCE)), recursive=False)
                encoder.stdin.close()
                if encoder.wait() != 0:
                    raise RuntimeError('Encryption failed; originals preserved')
            finally:
                if encoder.poll() is None:
                    encoder.kill()
                    encoder.wait()
        with encrypted.open('rb') as handle:
            checksum = digest_stream(handle)
        remote = f'r2:festapp-supabase-backups/host-evidence/{HOST}/{directory.name}/{checksum}.tar.gz.age'
        base = ['rclone', '--config', '/dev/null']
        run(base + ['copyto', str(encrypted), remote, '--immutable', '--retries', '3'], env=env)
        # Read the complete object back; size-only checks cannot prove recoverability.
        with tempfile.TemporaryFile() as errors:
            reader = subprocess.Popen(base + ['cat', remote], env=env,
                                      stdout=subprocess.PIPE, stderr=errors)
            try:
                actual = digest_stream(reader.stdout)
                code = reader.wait()
            finally:
                reader.stdout.close()
                if reader.poll() is None:
                    reader.kill()
                    reader.wait()
        if code != 0 or actual != checksum:
            raise RuntimeError('Off-host checksum mismatch; originals preserved')
        # Preserve a locator before deleting anything. Unknown/current files stay local.
        receipt = {'version': 1, 'remote': remote, 'sha256': checksum,
                   'archived_at': dt.datetime.now(dt.timezone.utc).isoformat(),
                   'files': {str(p.relative_to(EVIDENCE)): list(s) for p, s in before.items()},
                   'off_host_verified': True}
        receipt_path = state / (checksum + '.json')
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
        with receipt_path.open('r') as handle:
            os.fsync(handle.fileno())
        # Also place a locator alongside the original evidence metadata.
        (directory / ('archived-payloads-' + checksum[:16] + '.json')).write_text(
            json.dumps(receipt, indent=2) + '\n')
        removed = 0
        for path, expected in before.items():
            if fingerprint(path) != expected:
                raise RuntimeError('Recovery payload changed; preserving changed file')
            path.unlink()
            removed += expected[2]
        return removed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    os.umask(0o077)
    if os.geteuid() != 0 or socket.gethostname().split('.')[0] != HOST:
        raise RuntimeError('Run as root on the canonical host')
    lines = Path('/opt/festapp-supabase/docker/.env').read_text().splitlines()
    if 'FESTAPP_RUNTIME_DATABASE=' + DATABASE not in lines:
        raise RuntimeError('Canonical database identity mismatch')
    STATE.mkdir(mode=0o700, exist_ok=True)
    with (STATE / '.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        ids = run(['docker', 'ps', '-aq'], text=True).split()
        containers = json.loads(run(['docker', 'inspect'] + ids, text=True)) if ids else []
        mounts = [Path(m['Source']) for c in containers for m in c.get('Mounts', []) if m.get('Source')]
        payloads, backups = candidates(EVIDENCE, FUNCTIONS, mounts, time.time())
        print(json.dumps({'apply': args.apply, 'recovery_payload_bytes': sum(
            p.stat().st_size for _, files in payloads for p in files),
            'evidence_directories': len(payloads), 'function_backups': len(backups)}), flush=True)
        if not args.apply:
            return
        free_before = shutil.disk_usage('/').free
        env, recipient = remote_env()
        for directory, files in payloads:
            size = archive(directory, files, STATE, env, recipient)
            print(json.dumps({'archived': directory.name, 'local_bytes_removed': size}), flush=True)
        for path in backups:
            # Recheck eligibility immediately before removal.
            if old_tree(path, time.time() - DAYS * 86400):
                shutil.rmtree(path)
        # Docker itself protects all containers, including stopped containers.
        run(['docker', 'image', 'prune', '--all', '--force', '--filter', 'until=336h'])
        result = {'finished_at': dt.datetime.now(dt.timezone.utc).isoformat(),
                  'free_before': free_before, 'free_after': shutil.disk_usage('/').free}
        (STATE / 'latest.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()
