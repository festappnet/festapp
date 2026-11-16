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


def execution_identity(root, lane, contract):
    """Hosted identity enriches the existing receipt, never a local attestation."""
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        return None
    from selection import api, definition, fingerprint, toolchain
    repository = os.environ['GITHUB_REPOSITORY']
    run_id = int(os.environ['GITHUB_RUN_ID'])
    attempt = int(os.environ['GITHUB_RUN_ATTEMPT'])
    try:
        jobs = api(repository, f'actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100')['jobs']
        job = [job for job in jobs if job['name'] == lane]
        if len(job) != 1:
            return None
    except (OSError, subprocess.CalledProcessError, ValueError, KeyError, TypeError):
        # An API outage removes transferable evidence, not test execution.
        return None
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root, text=True).strip()
    sha = git('rev-parse', 'HEAD')
    return {'schemaVersion': 2, 'state': 'executed', 'lane': lane,
            'repositoryId': int(os.environ['GITHUB_REPOSITORY_ID']),
            'runId': run_id, 'attempt': attempt, 'jobId': job[0]['id'],
            'event': os.environ['GITHUB_EVENT_NAME'],
            'workflow': '.github/workflows/' + contract['jobs'][lane]['workflow'],
            'definition': definition(sha), 'checkoutSha': sha, 'tree': git('rev-parse', 'HEAD^{tree}'),
            'inputSha256': fingerprint(sha, lane, contract), 'toolchain': toolchain(lane, contract),
            'inventory': contract['knownTestInputs']}


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


def hosted_report(repository, contract, days=7, limit=100):
    """Bounded read-only baseline, including failed/cancelled jobs and reruns.

    GitHub does not expose pure runner queue time or billed minutes here.
    Job creation-to-start includes workflow/concurrency scheduling.
    """
    from concurrent.futures import ThreadPoolExecutor
    from datetime import datetime, timedelta, timezone
    from selection import api
    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).strftime('%Y-%m-%d')
    workflows = sorted({job['workflow'] for job in contract['jobs'].values()})
    def fetch(workflow):
        runs = api(repository, f'actions/workflows/{workflow}/runs?branch=main&created=>={cutoff}&per_page={min(limit,100)}')['workflow_runs']
        rows = []
        def seconds(start, end):
            if not start or not end: return None
            return max(0, (datetime.fromisoformat(end.replace('Z','+00:00')) - datetime.fromisoformat(start.replace('Z','+00:00'))).total_seconds())
        for run in runs:
            for attempt in range(1, run['run_attempt'] + 1):
                pages = api(repository, f'actions/runs/{run["id"]}/attempts/{attempt}/jobs?per_page=100', paginate=True)
                for page in pages:
                    for job in page['jobs']:
                        rows.append({'workflow':workflow, 'runId':run['id'], 'attempt':attempt,
                                     'sha':run['head_sha'], 'name':job['name'], 'conclusion':job['conclusion'],
                                     'url':job['html_url'],
                                     'mode':hosted_mode(job.get('steps',[])),
                                     'workflowCreatedToStartSeconds':seconds(run['created_at'],job['started_at']),
                                     'workflowCreatedToJobCreatedSeconds':seconds(run['created_at'],job.get('created_at')),
                                     'createdToStartSeconds':seconds(job.get('created_at',run['created_at']),job['started_at']),
                                     'runnerSeconds':seconds(job['started_at'],job['completed_at']),
                                     'steps':[{'name':step['name'],'seconds':seconds(step.get('started_at'),step.get('completed_at')),
                                               'conclusion':step['conclusion']} for step in job.get('steps',[])]})
        return {'workflow':workflow,'sampleRuns':len(runs),'jobs':rows}
    with ThreadPoolExecutor(max_workers=4) as pool: samples=list(pool.map(fetch,workflows))
    return summarize_hosted_samples(repository,contract,cutoff,limit,samples)


def hosted_mode(steps):
    outcomes={step['name']:step['conclusion'] for step in steps}
    if 'Lane coverage verified' in outcomes:
        if outcomes['Lane coverage verified']!='success': return 'unknown'
        if outcomes.get('All lane tests executed')=='success': return 'full'
        if outcomes.get('Some lane tests executed')=='success': return 'mixed'
        return 'reuse'
    return {'success':'full','skipped':'reuse'}.get(outcomes.get('Run canonical regression DAG'),'unknown')


def summarize_hosted_samples(repository,contract,cutoff,limit,samples):
    def percentile(values, fraction):
        values=sorted(v for v in values if v is not None)
        return values[min(len(values)-1,int((len(values)-1)*fraction))] if values else None
    jobs=[job for sample in samples for job in sample['jobs']]
    groups={}
    def summarize(rows):
        durations=[row['runnerSeconds'] for row in rows]
        return {'observations':len(rows),'runnerMinutes':sum(v or 0 for v in durations)/60,
                      'runnerSecondsP50':percentile(durations,.5),'runnerSecondsP95':percentile(durations,.95),
                      'createdToStartP50':percentile([row['createdToStartSeconds'] for row in rows],.5),
                      'workflowCreatedToStartP50':percentile([row.get('workflowCreatedToStartSeconds') for row in rows],.5)}
    for name in contract['jobs']:
        rows=[row for row in jobs if row['name']==name]
        groups[name]=summarize(rows)
        groups[name]['byMode']={mode:summarize([row for row in rows if row.get('mode')==mode]) for mode in ('full','mixed','reuse','unknown')}
    return {'repository':repository,'since':cutoff,'maxRunsPerWorkflow':limit,'groups':groups,'samples':samples,
            'limitations':['Runner minutes are elapsed job durations, not billing.',
                            'Queue includes workflow/concurrency scheduling; pure runner wait unavailable.',
                            'Cold/warm and change class unknown without artifact evidence; not inferred.',
                            'Only available runs, at most 100 per workflow; small-sample p95 is descriptive.']}


if __name__ == '__main__':
    import sys
    if sys.argv[1] == 'hosted-report':
        root=Path(__file__).resolve().parents[2]
        report=hosted_report(sys.argv[2],json.loads((root/'automation/ci/checks.json').read_text()))
        Path(sys.argv[3]).write_text(json.dumps(report,indent=2)+'\n')
        print('Hosted baseline saved: '+sys.argv[3])
    else:
        with phase(sys.argv[1]):
            subprocess.run(sys.argv[2:], check=True)
