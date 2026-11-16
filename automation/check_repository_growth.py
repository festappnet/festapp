#!/usr/bin/env python3
"""Require a recorded explanation for large text additions, across the repository."""
import argparse
import json
import os
from pathlib import Path
import subprocess

LIMIT = 10_000


def check(repository, base, head='HEAD'):
    def git(*args, data=None):
        return subprocess.check_output(['git', *args], cwd=repository, input=data)

    def additions(left, right):
        # No rename detection or path exclusions: moving/vendor/generated files
        # must not silently exempt a large addition. Binary files have no rows.
        records = git('diff', '--numstat', '-z', '--no-renames', left, right).split(b'\0')
        return sum(int(record.split(b'\t', 2)[0]) for record in records
                   if record and record.split(b'\t', 1)[0] != b'-')

    def reason(commit):
        message = git('log', '-1', '--format=%B', commit)
        trailers = git('interpret-trailers', '--parse', data=message).decode()
        return any(line.lower().startswith('large-change-reason:')
                   and len(line.split(':', 1)[1].strip()) >= 80
                   for line in trailers.splitlines())

    # Missing objects must fail, rather than make a large change look empty.
    kind = git('cat-file', '-t', base).decode().strip()
    git('cat-file', '-e', head + '^{commit}')
    revisions = [head] if kind == 'tree' else [base + '..' + head]
    commits = git('rev-list', '--reverse', *revisions).decode().splitlines()
    explained = False
    for commit in commits:
        justified = reason(commit)
        explained |= justified
        parents = git('rev-list', '--parents', '-n', '1', commit).decode().split()
        # PR test merges have GitHub-authored messages. Their incoming source
        # commits are checked individually; the aggregate diff is checked below.
        if len(parents) > 2:
            continue
        parent = parents[1] if len(parents) > 1 else git('hash-object', '-w', '-t', 'tree', '--stdin', data=b'').decode().strip()
        added = additions(parent, commit)
        if added >= LIMIT and not justified:
            raise ValueError(f'{commit[:12]} adds {added:,} text lines without a justification. '
                             'Add a Large-change-reason: commit trailer (at least 80 characters) '
                             'explaining the need, affected files and why a smaller change is insufficient.')
    added = additions(base, head)
    if added >= LIMIT and not explained:
        raise ValueError(f'The complete change adds {added:,} text lines without a justification. '
                         'Record a Large-change-reason: trailer (at least 80 characters) in a new commit.')
    return added


def event_base(repository):
    event_path = os.environ.get('GITHUB_EVENT_PATH')
    event = json.loads(Path(event_path).read_text()) if event_path else {}
    base = (event.get('pull_request', {}).get('base', {}).get('sha')
            or event.get('merge_group', {}).get('base_sha') or event.get('before'))
    if base and set(base) == {'0'}:
        return subprocess.check_output(['git', 'hash-object', '-w', '-t', 'tree', '--stdin'],
                                       cwd=repository, input=b'').decode().strip()
    return base or 'HEAD^'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--base')
    args = parser.parse_args()
    try:
        count = check(args.repository, args.base or event_base(args.repository))
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
    print(f'Repository growth checked: {count:,} added text lines; justification required from {LIMIT:,}.')
