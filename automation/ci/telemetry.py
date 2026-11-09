"""Content-addressed inputs and append-only monotonic test execution telemetry.

No command arguments, environment values or SQL content enter the trace.
"""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import time
import uuid
import threading
import re
from contextlib import contextmanager


def input_identity(root):
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root)
    paths = git('ls-files', '-z', '--cached', '--others', '--exclude-standard').split(b'\0')
    digest = hashlib.sha256()
    for name in sorted(set(paths) - {b''}):
        path = root / os.fsdecode(name)
        digest.update(name + b'\0')
        if path.is_file():
            digest.update(path.read_bytes())
        else:
            digest.update(b'<deleted>')
        digest.update(b'\0')
    return {'head': git('rev-parse', 'HEAD').decode().strip(),
            'dirty': bool(git('status', '--porcelain')), 'inputSha256': digest.hexdigest(),
            'platform': platform.platform(), 'machine': platform.machine()}


def emit(name, started, destination=None, **fields):
    destination = destination or os.environ.get('FESTAPP_TIMINGS')
    event = {'name': name, 'pid': os.getpid(), 'clock': 'system-monotonic',
             'wallStartedAtUnixSeconds': time.time() - (time.monotonic() - started), 'monotonicStart': started,
             'seconds': time.monotonic() - started, **fields}
    if destination:
        # Each process emits one complete line with one append write.
        fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(fd, (json.dumps(event) + '\n').encode())
        finally:
            os.close(fd)
    return event


@contextmanager
def phase(name, **fields):
    started = time.monotonic()
    try:
        yield
    except BaseException:
        emit(name, started, success=False, **fields)
        raise
    else:
        emit(name, started, success=True, **fields)


def owned_rss(pid):
    """Sum sampled host process-tree RSS, not container memory or unique pages."""
    processes = {}
    for line in subprocess.check_output(['ps', '-axo', 'pid=,ppid=,rss='], text=True).splitlines():
        child, parent, rss = map(int, line.split())
        processes[child] = (parent, rss)
    owned = {pid}
    while True:
        expanded = owned | {child for child, (parent, _) in processes.items() if parent in owned}
        if expanded == owned:
            return sum(processes.get(child, (0, 0))[1] for child in owned) * 1024
        owned = expanded


class ContainerMemory:
    """Read only the named owned container; Docker's streaming samples are ~2s."""
    def __init__(self, container, destination=None):
        self.destination=destination;self.container=container;self.process=None;self.thread=None;self.peak=0;self.samples=0

    def start(self):
        if not self.container:return
        self.process=subprocess.Popen(['docker','stats','--format','{{json .}}',self.container],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
        def read():
            for line in self.process.stdout:
                try:
                    # Docker streams cursor/erase controls even through a pipe.
                    row=json.loads(re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]','',line));value=row['MemUsage'].split('/')[0].strip()
                    match=re.fullmatch(r'([0-9.]+)([KMGT]?i?B)',value)
                    if not match:continue
                    units={'B':1,'kB':1000,'KB':1000,'MB':1000**2,'GB':1000**3,'KiB':1024,'MiB':1024**2,'GiB':1024**3,'TiB':1024**4}
                    self.peak=max(self.peak,int(float(match[1])*units[match[2]]));self.samples+=1
                except (ValueError,KeyError):continue
        self.thread=threading.Thread(target=read,daemon=True);self.thread.start()

    def close(self):
        if not self.process:return
        self.process.terminate()
        try:self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:self.process.kill();self.process.wait()
        self.thread.join(timeout=1)
        emit('memory.container',time.monotonic(),destination=self.destination,container=self.container,peakSampledBytes=self.peak if self.samples else None,
             samples=self.samples,method='docker stats streaming; approximately 2s interval; includes container shared memory')


def measured_process(argv, **kwargs):
    started = time.monotonic()
    process = subprocess.Popen(argv, **kwargs)
    peak = 0
    sampler=ContainerMemory(kwargs.get('env',os.environ).get('FESTAPP_MONITOR_CONTAINER'),kwargs.get('env',os.environ).get('FESTAPP_TIMINGS'))
    sampler.start()
    try:
        while process.poll() is None:
            peak = max(peak, owned_rss(process.pid))
            try:
                process.wait(timeout=.25)
            except subprocess.TimeoutExpired:
                pass
    except BaseException:
        process.terminate()
        process.wait()
        raise
    finally:
        sampler.close()
    return process.returncode, time.monotonic() - started, peak


def run_directory(cache):
    directory = cache / 'runs' / (time.strftime('%Y%m%dT%H%M%S') + '-' + uuid.uuid4().hex[:12])
    directory.mkdir(parents=True)
    return directory


def write_receipt(directory, receipt, cache=None):
    # Each run owns this file. Completed receipts are never reused by a new run.
    target = directory / 'receipt.json'
    temporary = target.with_suffix('.tmp')
    temporary.write_text(json.dumps(receipt, indent=2) + '\n')
    temporary.replace(target)
    if cache:
        pointer = cache / ('latest-' + directory.name + '.tmp')
        pointer.write_text(json.dumps({'receipt': str(target)}) + '\n')
        pointer.replace(cache / 'latest.json')


if __name__ == '__main__':
    import sys
    with phase(sys.argv[1]):
        subprocess.run(sys.argv[2:], check=True)
