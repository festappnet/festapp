#!/usr/bin/env python3
"""Reuse main CI only when the complete conservative lane input tree matches."""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
POLICY = 'automation/ci/inputs.json'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def api(repository, endpoint, paginate=False):
    return json.loads(subprocess.check_output(
        ['gh', 'api', *(['--paginate', '--slurp'] if paginate else []),
         f'repos/{repository}/{endpoint}'], cwd=ROOT, text=True))


def fingerprint(sha, lane, policy):
    digest = hashlib.sha256()
    # Unknown paths are shared inputs. Only explicitly classified independent
    # components can be excluded; names, modes, additions and deletions count.
    for entry in git('ls-tree', '-r', '-z', sha).split(b'\0'):
        if not entry:
            continue
        path = entry.split(b'\t', 1)[1].decode('utf-8')
        owners = set()
        classified = False
        for component in policy['components']:
            if any(path.startswith(prefix) for prefix in component['prefixes']):
                classified = True
                owners.update(component['jobs'])
        if not classified or lane in owners:
            digest.update(entry + b'\0')
    return digest.hexdigest()


def reusable(lane, sha, repository, contract, policy):
    current = fingerprint(sha, lane, policy)
    # First-parent main history only. For PR merge refs this is the base side;
    # evidence from a PR/fork or a different main lineage is never accepted.
    ancestors = set(git('rev-list', '--first-parent', sha).decode().splitlines()[1:])
    workflow = contract['jobs'][lane]['workflow']
    runs = api(repository, f'actions/workflows/{workflow}/runs?branch=main&per_page=50')['workflow_runs']
    cutoff = datetime.now(timezone.utc) - timedelta(days=policy['maxAgeDays'])
    checked = set()
    for run in runs:
        source = run['head_sha']
        if source in checked or source not in ancestors:
            continue
        # Inspect only the newest attempt for a source, never an earlier green
        # attempt hidden behind a newer failed/pending run.
        checked.add(source)
        if (run['head_branch'] != 'main' or run['event'] not in ('push', 'workflow_dispatch')
                or run['path'] != f'.github/workflows/{workflow}'
                or datetime.fromisoformat(run['updated_at'].replace('Z', '+00:00')) < cutoff):
            continue
        if fingerprint(source, lane, policy) != current:
            continue
        if run['status'] != 'completed' or run['conclusion'] != 'success':
            return {'run': True, 'reason': 'Latest matching workflow did not pass'}
        pages = api(repository, f'commits/{source}/check-runs?per_page=100', paginate=True)
        checks = [c for p in pages for c in p['check_runs']
                  if c['name'] == lane and c['head_sha'] == source
                  and c.get('app', {}).get('slug') == 'github-actions']
        latest = max(checks, key=lambda c: c['id'], default=None)
        if (latest and latest['status'] == 'completed' and latest['conclusion'] == 'success'
                and latest['html_url'].startswith(run['html_url'] + '/job/')):
            job_id = latest['html_url'].rsplit('/', 1)[-1]
            job = api(repository, f'actions/jobs/{job_id}')
            if (job['run_id'] == run['id'] and any(
                    step['name'] == 'All lane tests executed' and step['conclusion'] == 'success'
                    for step in job['steps'])):
                return {'run': False, 'source': source, 'fingerprint': current, 'url': latest['html_url']}
        else:
            return {'run': True, 'reason': 'Latest matching check did not pass'}
    return {'run': True, 'reason': 'No successful main evidence with identical inputs'}


def decide(lane, event, action, ref, sha, repository, contract, policy):
    if event == 'pull_request' and action == 'ready_for_review':
        return {'run': True, 'reason': 'Full verification when leaving draft'}
    if event not in ('push', 'pull_request') or (event == 'push' and ref != 'refs/heads/main'):
        return {'run': True, 'reason': 'Explicit, merge-queue or non-main verification'}
    try:
        return reusable(lane, sha, repository, contract, policy)
    except (OSError, subprocess.CalledProcessError, ValueError, KeyError, TypeError):
        # No network, shallow history, malformed data or missing permission means
        # tests run. Selection failure must never manufacture a green result.
        return {'run': True, 'reason': 'Reuse evidence unavailable; running tests'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lane')
    args = parser.parse_args()
    contract = json.loads((ROOT / 'automation/ci/checks.json').read_text())
    if args.lane not in contract['jobs']:
        parser.error('Unknown CI lane')
    policy = json.loads((ROOT / POLICY).read_text())
    event_path = os.environ.get('GITHUB_EVENT_PATH')
    event = json.loads(Path(event_path).read_text()) if event_path else {}
    result = decide(args.lane, os.environ.get('GITHUB_EVENT_NAME'), event.get('action'),
                    os.environ.get('GITHUB_REF'), git('rev-parse', 'HEAD').decode().strip(),
                    os.environ.get('GITHUB_REPOSITORY'), contract, policy)
    print(json.dumps(result, sort_keys=True))
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'run={str(result["run"]).lower()}\n')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as output:
            if result['run']:
                output.write(f'### {args.lane}: run tests\n{result["reason"]}\n')
            else:
                output.write(f'### {args.lane}: reuse verified inputs\n'
                             f'Previous check: {result["url"]}\n\n'
                             f'Source: `{result["source"]}`\n\n'
                             f'Input SHA-256: `{result["fingerprint"]}`\n')


if __name__ == '__main__':
    main()
