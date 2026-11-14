#!/usr/bin/env python3
"""Reject tracked API outputs and their reintroduction through new ancestry."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ARTIFACTS = 'tools/festapp/contracts/api-v1'


def check(repository, base=None):
    def git(*args, required=True):
        result = subprocess.run(['git', *args], cwd=repository, capture_output=True, text=True)
        if required and result.returncode:
            raise RuntimeError(result.stderr.strip())
        return result

    if git('ls-files', '--', ARTIFACTS).stdout.strip():
        raise ValueError('Generated API outputs must not be tracked, including git add -f')
    if base is None and os.environ.get('GITHUB_EVENT_PATH'):
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        base = event.get('before') or event.get('pull_request', {}).get('base', {}).get('sha')
    base = base or 'refs/remotes/origin/main'
    exists = git('rev-parse', '--verify', base + '^{commit}', required=False)
    revisions = ['HEAD', '^' + exists.stdout.strip()] if exists.returncode == 0 else ['HEAD']
    commits = git('rev-list', '--full-history', *revisions, '--', ARTIFACTS).stdout.splitlines()
    for commit in commits:
        if git('ls-tree', '-r', '--name-only', commit, '--', ARTIFACTS).stdout.strip():
            raise ValueError('Newly reachable history contains generated API outputs: ' + commit)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--base')
    args = parser.parse_args()
    try:
        check(args.repository, args.base)
    except (ValueError, RuntimeError) as error:
        raise SystemExit(str(error))
    print('API outputs and newly reachable history are clean')
