#!/usr/bin/env python3
"""Add bounded swap headroom on the verified canonical host, without a restart.

Read-only preflight by default. No service limits or monitoring thresholds change.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import time

SIZE = 2 * 1024**3
FOLDER = Path('/var/lib/festapp-swap')
SWAP = FOLDER / 'swapfile'
FSTAB = Path('/etc/fstab')
SYSCTL = Path('/etc/sysctl.d/90-festapp-swap.conf')
ENTRY = f'{SWAP} none swap sw 0 0'
TUNING = '# Festapp: retain a small emergency paging reserve.\nvm.swappiness = 10\n'


def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE).strip()


def atomic(path, text, mode):
    fd, temporary = tempfile.mkstemp(prefix='.festapp-swap-', dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'w') as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    assert os.geteuid() == 0
    assert os.uname().nodename.split('.')[0] == 'festapp-supabase-rehearsal-01'
    runtime = next(line.split('=', 1)[1] for line in Path('/opt/festapp-supabase/docker/.env').read_text().splitlines()
                   if line.startswith('FESTAPP_RUNTIME_DATABASE='))
    assert runtime == 'festapp_rehearsal_20260909220601'
    identity = command('docker', 'exec', 'supabase-db', 'psql', '-X', '-U', 'postgres', '-d', runtime,
                       '-Atqc', "BEGIN READ ONLY; SELECT current_database()||'|'||count(*) FROM public.organizations WHERE id=3; COMMIT;")
    assert identity == runtime + '|1'
    with open('/run/lock/festapp-swap.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert not FOLDER.is_symlink() and not SWAP.is_symlink() and not SYSCTL.is_symlink()
        assert command('findmnt', '-no', 'FSTYPE', '-T', '/var/lib') == 'ext4'
        fstab = FSTAB.read_text()
        swap_rows = [line.split() for line in fstab.splitlines() if line.strip() and not line.lstrip().startswith('#')]
        assert all(row[0] == str(SWAP) and row == ENTRY.split() for row in swap_rows if len(row) > 2 and row[2] == 'swap'), 'Conflicting swap policy'
        active = [line.split()[0] for line in Path('/proc/swaps').read_text().splitlines()[1:]]
        assert all(path == str(SWAP) for path in active), 'Unmanaged active swap'
        if SYSCTL.exists():
            assert SYSCTL.read_text() == TUNING, 'Conflicting swappiness policy'
        if FOLDER.exists():
            info = FOLDER.stat()
            assert stat.S_ISDIR(info.st_mode) and info.st_uid == 0 and stat.S_IMODE(info.st_mode) == 0o700
        if SWAP.exists():
            info = SWAP.stat()
            assert stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_nlink == 1
            assert stat.S_IMODE(info.st_mode) == 0o600 and info.st_size == SIZE
            assert command('blkid', '-p', '-s', 'TYPE', '-o', 'value', str(SWAP)) == 'swap'
        available = shutil.disk_usage('/var/lib').free
        assert available >= (0 if SWAP.exists() else SIZE) + 4 * 1024**3, 'Insufficient remaining disk reserve'
        result = {'mode': 'apply' if args.apply else 'check', 'swapBytes': SIZE,
                  'diskFreeBytesBefore': available, 'alreadyActive': str(SWAP) in active,
                  'serviceRestart': False, 'monitoringThresholdsChanged': False}
        if not args.apply:
            print(json.dumps(result))
            return
        FOLDER.mkdir(mode=0o700, exist_ok=True)
        if not SWAP.exists():
            fd = os.open(SWAP, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            try:
                os.posix_fallocate(fd, 0, SIZE)
                os.fsync(fd)
            finally:
                os.close(fd)
            command('mkswap', str(SWAP))
        if str(SWAP) not in active:
            command('swapon', str(SWAP))
        stamp = str(time.time_ns())
        atomic(FOLDER / ('fstab-before-' + stamp), fstab, 0o600)
        atomic(FOLDER / ('swappiness-before-' + stamp), command('sysctl', '-n', 'vm.swappiness') + '\n', 0o600)
        if ENTRY not in fstab.splitlines():
            atomic(FSTAB, fstab.rstrip() + '\n' + ENTRY + '\n', stat.S_IMODE(FSTAB.stat().st_mode))
        atomic(SYSCTL, TUNING, 0o644)
        command('sysctl', '-w', 'vm.swappiness=10')
        assert str(SWAP) in Path('/proc/swaps').read_text()
        result['active'] = True
        atomic(FOLDER / 'installation.json', json.dumps(result, indent=2) + '\n', 0o600)
        print(json.dumps(result))


if __name__ == '__main__':
    main()
