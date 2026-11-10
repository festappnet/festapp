#!/usr/bin/env python3
"""Require successful GitHub CI for the exact canonical source of a web release."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CANONICAL_RELEASE_FILES = (
    'automation/ci/checks.json', 'automation/ci/release_gate.py',
    'automation/ci/selection.py', 'automation/ci/run.py',
    'automation/ci/telemetry.py', 'automation/ci/resources.py',
    'automation/release/build_receipt.py', 'automation/build_web_bundle.sh',
    'automation/cloudflare_build.sh', 'automation/ci_build.sh',
    'automation/verify_web_build.mjs', 'automation/lib/verify_bundle_entries.mjs',
)


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


# Informational monitors of deployed state. A failing drift check must not block
# the release that repairs the drift.
INFORMATIONAL_CHECKS = {'measurement-runtime-drift'}


def problems(checks, required, sha):
    latest = {}
    for check in checks:
        if check.get('head_sha') != sha or check.get('app', {}).get('slug') != 'github-actions':
            continue
        if (check['name'] in INFORMATIONAL_CHECKS and check['name'] not in required
                and check.get('_workflow_path') == '.github/workflows/measurement-runtime-drift.yml'):
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


def identify_informational_workflows(checks, repository):
    """Check-runs lack workflow paths; resolve their suite via Actions runs.

    Missing metadata or unavailable lookup fails closed: the check still blocks.
    """
    paths = {}
    for check in checks:
        if check.get('name') not in INFORMATIONAL_CHECKS:
            continue
        suite = check.get('check_suite', {}).get('id')
        if not isinstance(suite, int):
            continue
        if suite not in paths:
            paths[suite] = None
            try:
                data = json.loads(subprocess.check_output(['gh', 'api',
                    f'repos/{repository}/actions/runs?check_suite_id={suite}&per_page=100'],
                    cwd=ROOT, text=True, stderr=subprocess.DEVNULL))
                runs = [r for r in data['workflow_runs'] if r.get('check_suite_id') == suite]
                if len(runs) == 1:
                    paths[suite] = runs[0].get('path')
            except (subprocess.CalledProcessError, OSError, ValueError, KeyError):
                pass
        check['_workflow_path'] = paths[suite]


def release_source():
    metadata = json.loads((ROOT / 'automation/tenant-overlay.json').read_text())
    sha = metadata['baseMainSha']
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise RuntimeError('Invalid canonical baseMainSha')
    subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'HEAD'], cwd=ROOT, check=True)
    if git('status', '--porcelain', '--untracked-files=normal'):
        raise RuntimeError('Release requires a clean checkout, including untracked source files')
    # The tenant cannot weaken the required job set or the gate itself.
    for name in CANONICAL_RELEASE_FILES:
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
    identify_informational_workflows(checks, repository)
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
