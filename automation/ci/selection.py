#!/usr/bin/env python3
"""Reuse main CI only when the complete conservative lane input tree matches."""
import argparse
from datetime import datetime, timedelta, timezone
import fnmatch
import hashlib
import json
import io
import platform
import re
import zipfile
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
POLICY = 'automation/ci/checks.json'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def api(repository, endpoint, paginate=False):
    return json.loads(subprocess.check_output(
        ['gh', 'api', *(['--paginate', '--slurp'] if paginate else []),
         f'repos/{repository}/{endpoint}'], cwd=ROOT, text=True))


def owners(path, contract):
    # The same map governs local affected selection and hosted input digests.
    if (path.startswith(('automation/ci/', '.github/workflows/')) or
            (path.endswith(('_test.sql', '.test.js', '.test.mjs', '_test.ts', '_test.dart'))
             and path not in contract['knownTestInputs'])):
        return set(contract['jobs'])
    matches = {name for name, lane in contract['jobs'].items()
               if any(fnmatch.fnmatch(path, pattern) for pattern in lane['inputs'])}
    if matches:
        return matches
    if any(fnmatch.fnmatch(path, pattern) for pattern in contract.get('independentInputs', [])):
        return set()
    return set(contract['jobs'])


def fingerprint(sha, lane, policy):
    digest = hashlib.sha256()
    for entry in git('ls-tree', '-r', '-z', sha).split(b'\0'):
        if entry and lane in owners(entry.split(b'\t', 1)[1].decode('utf-8'), policy):
            digest.update(entry + b'\0')
    return digest.hexdigest()


def definition(sha):
    """Trust the complete evidence producer, selector and workflow definitions."""
    entries = git('ls-tree', '-r', '-z', sha, 'automation/ci', '.github/workflows',
                  'automation/test_ci.sh')
    return hashlib.sha256(entries).hexdigest()


def toolchain(lane, contract):
    return {**{key: os.environ.get(key) for key in
               ('RUNNER_OS', 'RUNNER_ARCH', 'ImageOS', 'ImageVersion')},
            'node': contract['jobs'][lane]['node'], 'pnpm': '11.24.0',
            'python': platform.python_version()}


def ensure_commit(sha):
    if not re.fullmatch('[0-9a-f]{40}', sha):
        raise ValueError('Invalid checkout SHA')
    try:
        git('cat-file', '-e', sha + '^{commit}')
    except subprocess.CalledProcessError:
        git('fetch', '--no-tags', 'origin', sha)


def read_artifact(repository, run, lane):
    artifacts = api(repository, f'actions/runs/{run["id"]}/artifacts?per_page=100')['artifacts']
    matches = [a for a in artifacts if a['name'] == f'ci-{lane}-{run["run_attempt"]}']
    if len(matches) != 1:
        raise ValueError('Missing or ambiguous execution artifact')
    artifact = matches[0]
    binding = artifact['workflow_run']
    if (artifact.get('size_in_bytes', 0) > 100_000_000 or artifact['expired'] or binding['id'] != run['id'] or
            binding['repository_id'] != run['repository']['id'] or
            binding['head_repository_id'] != run['head_repository']['id'] or
            binding['head_sha'] != run['head_sha']):
        raise ValueError('Foreign or expired artifact')
    archive = subprocess.check_output(['gh', 'api',
        f'repos/{repository}/actions/artifacts/{artifact["id"]}/zip'], cwd=ROOT)
    if artifact['digest'] != 'sha256:' + hashlib.sha256(archive).hexdigest():
        raise ValueError('Artifact digest mismatch')
    # Never extract untrusted zip paths. Only one bounded JSON receipt is read.
    with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
        receipts = [entry for entry in bundle.infolist() if entry.filename.endswith('/receipt.json')
                    or entry.filename == 'receipt.json']
        if len(receipts) != 1 or receipts[0].file_size > 2_000_000:
            raise ValueError('Invalid receipt archive')
        return json.loads(bundle.read(receipts[0]))


def verify_execution(receipt, run, job, lane, current, repository_id, contract, policy, trusted):
    evidence = receipt['execution']
    source = evidence['checkoutSha']
    ensure_commit(source)
    if (evidence['schemaVersion'] != 1 or evidence['state'] != 'executed' or
            not receipt['complete'] or receipt['dirty'] or not receipt['inputsUnchanged'] or
            receipt['selectedJobs'] != [lane] or evidence['repositoryId'] != repository_id or
            evidence['runId'] != run['id'] or evidence['attempt'] != run['run_attempt'] or
            evidence['jobId'] != job['id'] or evidence['lane'] != lane or
            evidence['event'] != run['event'] or evidence['workflow'] != run['path'] or
            evidence['definition'] != trusted or definition(source) != trusted or
            evidence['tree'] != git('rev-parse', source + '^{tree}').decode().strip() or
            evidence['toolchain'] != toolchain(lane, contract) or
            not all(evidence['toolchain'].get(k) for k in ('RUNNER_OS','RUNNER_ARCH','ImageOS','ImageVersion')) or
            evidence['inputSha256'] != current or fingerprint(source, lane, policy) != current or
            evidence['inventory'] != contract['knownTestInputs'] or
            set(receipt['units']) != set(contract['jobs'][lane]['steps']) or
            not all(row['status'] == 'PASS' for row in receipt['units'].values())):
        raise ValueError('Execution receipt does not attest these inputs')
    validate_checkout(source, run)
    return source


def validate_checkout(source, run):
    if run['event'] == 'pull_request':
        parents = git('show', '-s', '--format=%P', source).decode().split()
        if len(parents) != 2 or parents[1] != run['head_sha']:
            raise ValueError('PR receipt is not its tested merge checkout')
        git('merge-base', '--is-ancestor', parents[0], 'origin/main')
        merged = git('merge-tree', '--write-tree', *parents).decode().strip()
        if merged != git('rev-parse', source + '^{tree}').decode().strip():
            raise ValueError('PR receipt differs from the merge result')
    else:
        if source != run['head_sha'] or run['head_branch'] != 'main':
            raise ValueError('Main execution checkout mismatch')
        git('merge-base', '--is-ancestor', source, 'origin/main')


def reusable(lane, sha, repository, contract, policy):
    current = fingerprint(sha, lane, policy)
    trusted = definition('origin/main')
    if definition(sha) != trusted:
        return {'run': True, 'reason': 'CI policy changes require execution'}
    repository_id = api(repository, '')['id']
    workflow = contract['jobs'][lane]['workflow']
    # Include internal PR executions. The receipt records the actual merge
    # checkout; run.head_sha alone is never treated as the tested input tree.
    runs = api(repository, f'actions/workflows/{workflow}/runs?per_page=100')['workflow_runs']
    cutoff = datetime.now(timezone.utc) - timedelta(days=policy['reusePolicy']['maxAgeDays'])
    for run in sorted(runs, key=lambda r: (r['run_number'], r['run_attempt']), reverse=True):
        if str(run['id']) == os.environ.get('GITHUB_RUN_ID'):
            continue
        if (run['repository']['id'] != repository_id or
                run['head_repository']['id'] != repository_id or
                run['event'] not in ('push', 'workflow_dispatch', 'pull_request') or
                run['path'] != f'.github/workflows/{workflow}' or
                datetime.fromisoformat(run['created_at'].replace('Z', '+00:00')) < cutoff):
            continue
        # A more recent pending/failed trusted run must not be hidden by an old
        # success, including a rerun whose latest artifact is not yet available.
        # Conservative when the synthetic checkout of a failed PR is unavailable.
        if run['status'] != 'completed' or run['conclusion'] != 'success':
            ensure_commit(run['head_sha'])
            if fingerprint(run['head_sha'], lane, policy) == current or run['event'] == 'pull_request':
                return {'run': True, 'reason': 'Newer matching or unresolved workflow did not pass'}
            continue
        jobs = api(repository, f'actions/runs/{run["id"]}/attempts/{run["run_attempt"]}/jobs?per_page=100')['jobs']
        matches = [j for j in jobs if j['name'] == lane]
        if len(matches) != 1:
            return {'run': True, 'reason': 'Execution job identity unavailable'}
        job = matches[0]
        if (job['run_id'] != run['id'] or job['run_attempt'] != run['run_attempt'] or
                job['status'] != 'completed' or job['conclusion'] != 'success'):
            return {'run': True, 'reason': 'Latest lane attempt did not pass'}
        if not any(step['name'] == 'All lane tests executed' and step['conclusion'] == 'success'
                   for step in job['steps']):
            continue  # Reuse is never a source of another reuse receipt.
        receipt = read_artifact(repository, run, lane)
        # Nonmatching complete executions can be ignored, malformed evidence
        # cannot authorize falling back to an earlier success.
        if receipt.get('execution', {}).get('inputSha256') != current:
            continue
        source = verify_execution(receipt, run, job, lane, current, repository_id, contract, policy, trusted)
        return {'run': False, 'source': source, 'fingerprint': current, 'url': job['html_url'],
                'runId': run['id'], 'attempt': run['run_attempt'], 'jobId': job['id']}
    return {'run': True, 'reason': 'No verified execution artifact with identical inputs'}


def decide(lane, event, action, ref, sha, repository, contract, policy, attempt=1):
    if attempt > 1:
        return {'run': True, 'reason': 'Reruns require a fresh execution'}
    if event == 'pull_request' and action == 'ready_for_review':
        return {'run': True, 'reason': 'Full verification when leaving draft'}
    if event not in ('push', 'pull_request') or (event == 'push' and ref != 'refs/heads/main'):
        return {'run': True, 'reason': 'Explicit, merge-queue or non-main verification'}
    try:
        return reusable(lane, sha, repository, contract, policy)
    except (OSError, subprocess.CalledProcessError, ValueError, KeyError, TypeError, AttributeError, IndexError, RuntimeError, zipfile.BadZipFile):
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
    if (os.environ.get('GITHUB_EVENT_NAME') == 'pull_request' and
            str(event.get('pull_request', {}).get('head', {}).get('repo', {}).get('id'))
            != os.environ.get('GITHUB_REPOSITORY_ID')):
        result = {'run': True, 'reason': 'Fork or unknown PR origin requires execution'}
    else:
        result = decide(args.lane, os.environ.get('GITHUB_EVENT_NAME'), event.get('action'),
                        os.environ.get('GITHUB_REF'), git('rev-parse', 'HEAD').decode().strip(),
                        os.environ.get('GITHUB_REPOSITORY'), contract, policy,
                        attempt=int(os.environ.get('GITHUB_RUN_ATTEMPT', '1')))
    from telemetry import emit
    import time
    emit('ci.selection', time.monotonic(), lane=args.lane, **result)
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
