#!/usr/bin/env python3
"""Require successful GitHub CI for the exact canonical source of a web release."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def problems(checks, required, sha):
    latest = {}
    for check in checks:
        if check.get('head_sha') != sha or check.get('app', {}).get('slug') != 'github-actions':
            continue
        name = check['name']
        if name not in latest or check['id'] > latest[name]['id']:
            latest[name] = check
    failures = []
    for name in sorted(set(required) | set(latest)):
        check = latest.get(name)
        if check is None:
            failures.append(f'{name}: missing')
        elif check['status'] != 'completed' or check.get('conclusion') != 'success':
            failures.append(f'{name}: {check["status"]}/{check.get("conclusion")} {check.get("html_url", "")}')
    return failures


def release_source():
    metadata = json.loads((ROOT / 'automation/tenant-overlay.json').read_text())
    sha = metadata['baseMainSha']
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise RuntimeError('Invalid canonical baseMainSha')
    subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'HEAD'], cwd=ROOT, check=True)
    if git('status', '--porcelain', '--untracked-files=normal'):
        raise RuntimeError('Release requires a clean checkout, including untracked source files')
    # The tenant cannot weaken the required job set or the gate itself.
    for name in ('automation/ci/checks.json', 'automation/ci/release_gate.py'):
        if subprocess.check_output(['git', 'show', f'{sha}:{name}'], cwd=ROOT) != (ROOT / name).read_bytes():
            raise RuntimeError(f'Release gate must match canonical main: {name}')
    return sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-sha', help='Inspect a main commit before preparing its tenant overlay')
    args = parser.parse_args()
    sha = args.source_sha or release_source()
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise RuntimeError('A full source SHA is required')
    repository = json.loads(subprocess.check_output(
        ['gh', 'repo', 'view', '--json', 'nameWithOwner'], cwd=ROOT, text=True))['nameWithOwner']
    pages = json.loads(subprocess.check_output(['gh', 'api', '--paginate', '--slurp',
        f'repos/{repository}/commits/{sha}/check-runs?per_page=100'], cwd=ROOT, text=True))
    checks = [check for page in pages for check in page['check_runs']]
    required = json.loads((ROOT / 'automation/ci/checks.json').read_text())['jobs']
    failures = problems(checks, required, sha)
    if failures:
        raise RuntimeError('Release blocked: CI is not green for ' + sha + '\n' + '\n'.join(failures))
    print(f'Release CI passed: {len(required)} required jobs at {sha}')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
