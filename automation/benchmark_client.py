#!/usr/bin/env python3
"""One complete warm-up and three comparable offline client benchmark runs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import statistics
import subprocess
import time

from test_client import client_concurrency

ROOT = Path(__file__).resolve().parent.parent


def fingerprint():
    paths = set()
    for name in ('lib', 'test', 'test_dart', 'packages/festapp_core', 'assets', 'web',
                 'android/app/src/main/res/values', 'android/app/src/main/res/values-night'):
        for path in (ROOT / name).rglob('*'):
            if path.is_file() and not any(part in {'.dart_tool', 'build'} for part in path.relative_to(ROOT).parts):
                paths.add(path)
    for name in ('pubspec.yaml', 'pubspec.lock', '.fvmrc',
                 'automation/test_client.sh', 'automation/test_client.py',
                 'automation/client_test_inventory.py', 'automation/client_test_inventory.json',
                 'automation/client_test_classification.json', 'automation/benchmark_client.py',
                 'supabase/functions/_shared/ticket-assets/font-catalog.json'):
        path = ROOT / name
        if path.exists():
            paths.add(path)
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(str(path.relative_to(ROOT)).encode())
        digest.update(b'\0')
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
    return digest.hexdigest()


def owned_rss(pid):
    result = subprocess.run(['ps', '-axo', 'pid=,ppid=,rss='], capture_output=True, text=True, check=True)
    processes = {}
    for line in result.stdout.splitlines():
        child, parent, rss = map(int, line.split())
        processes[child] = (parent, rss)
    owned = {pid}
    while True:
        children = {child for child, (parent, _) in processes.items() if parent in owned}
        expanded = owned | children
        if expanded == owned:
            break
        owned = expanded
    return sum(processes.get(child, (0, 0))[1] for child in owned) * 1024


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (output / 'benchmark-summary.json').exists():
        raise SystemExit('Use a fresh output directory; existing benchmark receipts are preserved.')
    expected = fingerprint()
    version = subprocess.run(['fvm', 'flutter', '--version', '--machine'], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout
    version = json.loads(version[version.index('{'):])
    metadata = {'sourceSha256': expected, 'host': platform.platform(), 'machine': platform.machine(),
                'logicalCpus': os.cpu_count(), 'physicalMemoryBytes': int(subprocess.run(['sysctl', '-n', 'hw.memsize'], capture_output=True, text=True, check=True).stdout) if platform.system() == 'Darwin' else os.sysconf('SC_PHYS_PAGES') * os.sysconf('SC_PAGE_SIZE'),
                'sdk': version, 'concurrency': client_concurrency(), 'memoryBudgetBytes': 3_000_000_000, 'complete': False,
                'memoryMethod': 'Peak sum of owned-process RSS sampled once per second; shared pages may be counted repeatedly.',
                'coldRun': None, 'warmup': None, 'runs': []}
    (output / 'benchmark-summary.json').write_text(json.dumps(metadata, indent=2) + '\n')
    process = None

    def cancel(signum, _frame):
        if process is not None and process.poll() is None:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGINT, cancel)
    signal.signal(signal.SIGTERM, cancel)
    for index in range(4):
        label = 'warmup' if index == 0 else f'warm-{index}'
        if fingerprint() != expected:
            raise SystemExit('Benchmark inputs changed before run; preserved existing receipts.')
        location = output / label
        location.mkdir(exist_ok=True)
        env = {**os.environ, 'FESTAPP_CLIENT_RESULTS': str(location)}
        peak = 0
        load_start = os.getloadavg()
        started = time.monotonic()
        with (location / 'runner.log').open('w') as log:
            process = subprocess.Popen([str(ROOT / 'automation/test_client.sh')], cwd=ROOT,
                                       env=env, stdout=log, stderr=subprocess.STDOUT)
            while process.poll() is None:
                peak = max(peak, owned_rss(process.pid))
                try:
                    process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    pass
        if process.returncode:
            raise SystemExit(f'{label} failed; see {location / "runner.log"}')
        summary = json.loads((location / 'summary.json').read_text())
        summary.update({'peakSummedRssBytes': peak, 'loadAverageStart': load_start, 'loadAverageEnd': os.getloadavg(), 'observedSeconds': time.monotonic() - started,
                        'sourceSha256': expected, 'inputsUnchanged': fingerprint() == expected})
        (location / 'benchmark.json').write_text(json.dumps(summary, indent=2) + '\n')
        if not summary['inputsUnchanged']:
            raise SystemExit(f'Benchmark inputs changed during {label}; receipt cannot be combined into a median.')
        if index == 0:
            metadata['warmup'] = summary
        else:
            metadata['runs'].append(summary)
        (output / 'benchmark-summary.json').write_text(json.dumps(metadata, indent=2) + '\n')
        print(f'{label}: complete suite {summary["seconds"]:.2f}s; peak sampled RSS {peak / 2**30:.2f} GiB', flush=True)
    metadata['complete'] = True
    metadata['medianSeconds'] = statistics.median(run['seconds'] for run in metadata['runs'])
    metadata['laneMedianSeconds'] = {lane: statistics.median(run[lane]['seconds'] for run in metadata['runs'])
                                    for lane in ('core', 'adapters', 'flutter')}
    metadata['targets'] = {'wholeUnder40s': metadata['medianSeconds'] <= 40,
                           'coreUnder5s': metadata['laneMedianSeconds']['core'] <= 5,
                           'memoryUnder3GB': max(run['peakSummedRssBytes'] for run in [metadata['warmup'], *metadata['runs']]) <= metadata['memoryBudgetBytes']}
    (output / 'benchmark-summary.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(f'Warm median: {metadata["medianSeconds"]:.2f}s; targets: {metadata["targets"]}')


if __name__ == '__main__':
    main()
