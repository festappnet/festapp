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
import sys
import time
import signal
from contextvars import ContextVar
from contextlib import contextmanager

ROOT = Path(__file__).resolve().parents[2]
POLICY = 'automation/ci/checks.json'


LOOKUP = ContextVar('ci_lookup', default=None)


class BudgetExpired(TimeoutError):
    pass


@contextmanager
def lookup(seconds=20):
    token = LOOKUP.set({'deadline':time.monotonic()+seconds, 'cache':{},
                        'apiCalls':0, 'candidates':0, 'downloadedBytes':0})
    try:
        yield LOOKUP.get()
    finally:
        LOOKUP.reset(token)


def command(argv):
    state=LOOKUP.get()
    remaining=state['deadline']-time.monotonic() if state else 20
    if remaining <= 0: raise BudgetExpired('Selector budget exhausted')
    # Kill the entire owned group, including gh credential/fetch subprocesses.
    process=subprocess.Popen(argv,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,start_new_session=True)
    try:
        output,_=process.communicate(timeout=remaining)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGKILL)
        process.communicate()
        raise BudgetExpired('Selector network/process budget exhausted') from None
    if process.returncode: raise subprocess.CalledProcessError(process.returncode,argv)
    return output


def cached(key, compute):
    state=LOOKUP.get()
    if state is None: return compute()
    if time.monotonic()>=state['deadline']: raise BudgetExpired('Selector budget exhausted')
    if key not in state['cache']: state['cache'][key]=compute()
    return state['cache'][key]


def git(*args):
    # Only immutable content is cached. Refs, ancestry and run status are fresh.
    return command(['git', *args])


def api(repository, endpoint, paginate=False):
    state=LOOKUP.get()
    if state is not None: state['apiCalls']+=1
    return json.loads(command(['gh', 'api', *(['--paginate', '--slurp'] if paginate else []),
                              f'repos/{repository}' + (f'/{endpoint}' if endpoint else '')]))


def owners(path, contract):
    return cached(('owners',id(contract),path),lambda:_owners(path,contract))


def known_tests(contract):
    return cached(('known-tests',id(contract)),lambda:set(contract['knownTestInputs']))


def _owners(path, contract):
    # The same map governs local affected selection and hosted input digests.
    if (path.startswith(('automation/ci/', '.github/workflows/')) or
            (path.endswith(('_test.sql', '.test.js', '.test.mjs', '_test.ts', '_test.dart'))
             and path not in known_tests(contract))):
        return set(contract['jobs'])
    matches = {name for name, lane in contract['jobs'].items()
               if any(fnmatch.fnmatch(path, pattern) for pattern in lane['inputs'])}
    if matches:
        return matches
    if any(fnmatch.fnmatch(path, pattern) for pattern in contract.get('independentInputs', [])):
        return set()
    return set(contract['jobs'])


def tree(sha):
    return cached(('tree',str(ROOT),sha),lambda:git('ls-tree','-r','-z',sha).split(b'\0'))


def unit_owners(path, lane, policy):
    return cached(('unit-owners',id(policy),lane,path),lambda:_unit_owners(path,lane,policy))


def _unit_owners(path, lane, policy):
    if lane not in owners(path,policy): return set()
    units=policy['jobs'][lane]['steps']
    # Unknown inputs and CI changes invalidate every unit, even with a fine map.
    if (path.startswith(('automation/ci/','.github/workflows/')) or
            (path.endswith(('_test.sql','.test.js','.test.mjs','_test.ts','_test.dart')) and path not in known_tests(policy))):
        return set(units)
    matches={unit for unit in units if any(fnmatch.fnmatch(path,pattern) for pattern in
             policy['steps'][unit].get('inputs',policy['jobs'][lane]['inputs']))}
    return matches or set(units)


def fingerprint(sha, lane, policy, unit=None):
    def compute():
        digest=hashlib.sha256()
        for entry in tree(sha):
            if not entry: continue
            path=entry.split(b'\t',1)[1].decode('utf-8')
            if (lane in owners(path,policy) if unit is None else unit in unit_owners(path,lane,policy)):
                digest.update(entry+b'\0')
        return digest.hexdigest()
    key=('fingerprint',str(ROOT),sha,lane,unit,hashlib.sha256(json.dumps(policy,sort_keys=True).encode()).hexdigest())
    return cached(key,compute)


def definition(sha):
    """Trust the complete evidence producer, selector and workflow definitions."""
    return cached(('definition',str(ROOT),sha), lambda: hashlib.sha256(git(
        'ls-tree','-r','-z',sha,'automation/ci','.github/workflows','automation/test_ci.sh')).hexdigest())


def toolchain(lane, contract):
    return {**{key: os.environ.get(key) for key in
               ('RUNNER_OS', 'RUNNER_ARCH', 'ImageOS', 'ImageVersion')},
            'node': contract['jobs'][lane]['node'], 'pnpm': '11.24.0',
            'python': platform.python_version()}


def ensure_commit(sha):
    return cached(('commit',sha),lambda:_ensure_commit(sha))


def _ensure_commit(sha):
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
    expected_digest=artifact['digest']
    if not re.fullmatch('sha256:[0-9a-f]{64}',expected_digest): raise ValueError('Invalid artifact digest')
    local=None
    if os.environ.get('GITHUB_ACTIONS')=='true':
        directory=Path.home()/'.cache/festapp-ci/evidence'
        directory.mkdir(parents=True,exist_ok=True)
        local=directory/(expected_digest.split(':')[1]+'.zip')
    if local is not None and local.is_file():
        archive=local.read_bytes()
    else:
        archive=command(['gh','api',f'repos/{repository}/actions/artifacts/{artifact["id"]}/zip'])
        state=LOOKUP.get()
        if state is not None:
            state['apiCalls']+=1;state['downloadedBytes']+=len(archive)
    if len(archive)>100_000_000: raise ValueError('Oversized execution archive')
    if artifact['digest'] != 'sha256:' + hashlib.sha256(archive).hexdigest():
        raise ValueError('Artifact digest mismatch')
    if local is not None and not local.exists(): local.write_bytes(archive)
    # Never extract untrusted zip paths. Only one bounded JSON receipt is read.
    with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
        receipts = [entry for entry in bundle.infolist() if entry.filename.endswith('/receipt.json')
                    or entry.filename == 'receipt.json']
        if len(receipts) != 1 or receipts[0].file_size > 2_000_000:
            raise ValueError('Invalid receipt archive')
        receipt=json.loads(bundle.read(receipts[0]))
        return receipt, {'id':artifact['id'],'digest':artifact['digest']}


def verify_execution(receipt, run, job, lane, current, repository_id, contract, policy, trusted, unit=None):
    evidence=receipt['execution']
    source=evidence['checkoutSha']
    ensure_commit(source)
    expected=set(contract['jobs'][lane]['steps'])
    rows=receipt['units']
    if (evidence['schemaVersion'] != 2 or evidence['state'] != 'executed' or
            not receipt['complete'] or receipt['dirty'] or not receipt['inputsUnchanged'] or
            receipt['selectedJobs'] != [lane] or evidence['repositoryId'] != repository_id or
            evidence['runId'] != run['id'] or evidence['attempt'] != run['run_attempt'] or
            evidence['jobId'] != job['id'] or evidence['lane'] != lane or
            evidence['event'] != run['event'] or evidence['workflow'] != run['path'] or
            evidence['definition'] != trusted or definition(source) != trusted or
            evidence['tree'] != git('rev-parse',source+'^{tree}').decode().strip() or
            evidence['toolchain'] != toolchain(lane,contract) or
            not all(evidence['toolchain'].get(k) for k in ('RUNNER_OS','RUNNER_ARCH','ImageOS','ImageVersion')) or
            evidence['inventory'] != contract['knownTestInputs'] or
            evidence['inputSha256'] != fingerprint(source,lane,policy) or set(rows) != expected or
            not all(row['status']=='PASS' and row['state'] in ('executed','reused') for row in rows.values())):
        raise ValueError('Execution receipt does not attest these inputs')
    for name,row in rows.items():
        if row['inputSha256']!=fingerprint(source,lane,policy,name):
            raise ValueError('Incomplete aggregate unit fingerprints')
        if row['state']=='reused':
            origin=row['origin']
            if (origin['inputSha256']!=row['inputSha256'] or
                    not re.fullmatch('[0-9a-f]{40}',origin['source']) or
                    not re.fullmatch('sha256:[0-9a-f]{64}',origin['artifact']['digest']) or
                    not all(isinstance(origin[key],int) and origin[key]>0 for key in ('runId','attempt','jobId'))):
                raise ValueError('Incomplete aggregate origin')
    targets=[unit] if unit else expected
    for name in targets:
        row=rows[name]
        wanted=current if unit else fingerprint(source,lane,policy,name)
        if row['state']!='executed' or row['inputSha256']!=wanted or fingerprint(source,lane,policy,name)!=wanted:
            raise ValueError('Unit has no direct matching execution')
    cached(('checkout',source,run['id'],run['run_attempt']),lambda:validate_checkout(source,run))
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


def job_for(repository, run, lane):
    jobs=api(repository,f'actions/runs/{run["id"]}/attempts/{run["run_attempt"]}/jobs?per_page=100')['jobs']
    matches=[job for job in jobs if job['name']==lane]
    if len(matches)!=1: raise ValueError('Execution job identity unavailable')
    job=matches[0]
    if (job['run_id']!=run['id'] or job['run_attempt']!=run['run_attempt'] or
            job['status']!='completed' or job['conclusion']!='success'):
        raise ValueError('Latest lane attempt did not pass')
    return job


def direct_marker(job):
    return any(step['name'] in ('All lane tests executed','Some lane tests executed') and step['conclusion']=='success'
               for step in job['steps']) and any(step['name']=='Lane coverage verified' and step['conclusion']=='success' for step in job['steps'])


def reusable(lane, sha, repository, contract, policy):
    trusted=definition('origin/main')
    if definition(sha)!=trusted: return {'run':True,'reason':'CI policy changes require execution'}
    units=contract['jobs'][lane]['steps']
    current={unit:fingerprint(sha,lane,policy,unit) for unit in units}
    remaining=set(units);proofs={}
    repository_id=api(repository,'')['id']
    workflow=contract['jobs'][lane]['workflow']
    runs=api(repository,f'actions/workflows/{workflow}/runs?per_page=100')['workflow_runs']
    cutoff=datetime.now(timezone.utc)-timedelta(days=policy['reusePolicy']['maxAgeDays'])
    for run in sorted(runs,key=lambda r:(r['run_number'],r['run_attempt']),reverse=True):
        if str(run['id'])==os.environ.get('GITHUB_RUN_ID'): continue
        if (run['repository']['id']!=repository_id or run['head_repository']['id']!=repository_id or
                run['event'] not in ('push','workflow_dispatch','pull_request') or
                run['path']!=f'.github/workflows/{workflow}' or
                datetime.fromisoformat(run['created_at'].replace('Z','+00:00'))<cutoff): continue
        state=LOOKUP.get()
        if state is not None: state['candidates']+=1
        # A list entry may become stale during a rerun. Refresh status/attempt
        # before admitting an immutable artifact from that execution.
        expected_id=run['id']
        run=api(repository,f'actions/runs/{expected_id}')
        if (run['id']!=expected_id or run['repository']['id']!=repository_id or run['head_repository']['id']!=repository_id or run['event'] not in ('push','workflow_dispatch','pull_request') or run['path']!=f'.github/workflows/{workflow}'):
            raise ValueError('Fresh run binding changed')
        if datetime.fromisoformat(run['created_at'].replace('Z','+00:00'))<cutoff: continue
        ensure_commit(run['head_sha'])
        if run['status']!='completed' or run['conclusion']!='success':
            if run['event']=='pull_request' or any(fingerprint(run['head_sha'],lane,policy,u)==current[u] for u in remaining):
                return {'run':True,'reason':'Newer matching or unresolved workflow did not pass'}
            continue
        # For main the API SHA is the checkout. Reject mismatches before ZIP
        # download. PRs MUST use the receipt's validated synthetic merge tree.
        candidates=remaining if run['event']=='pull_request' else {
            u for u in remaining if fingerprint(run['head_sha'],lane,policy,u)==current[u]}
        if not candidates: continue
        if run['event']!='pull_request' and definition(run['head_sha'])!=trusted: continue
        job=job_for(repository,run,lane)
        if not direct_marker(job): continue
        receipt,artifact=read_artifact(repository,run,lane)
        # Old lane receipts never supply unit evidence. Mixed receipts supply
        # only directly executed rows, never the rows that they reused.
        if receipt.get('execution',{}).get('schemaVersion')!=2: continue
        if set(receipt['units'])!=set(units): raise ValueError('Incomplete aggregate inventory')
        for unit in sorted(candidates):
            row=receipt.get('units',{}).get(unit,{})
            if row.get('state')!='executed' or row.get('inputSha256')!=current[unit]: continue
            source=verify_execution(receipt,run,job,lane,current[unit],repository_id,contract,policy,trusted,unit)
            proofs[unit]={'source':source,'inputSha256':current[unit],'url':job['html_url'],
                          'runId':run['id'],'attempt':run['run_attempt'],'jobId':job['id'],'artifact':artifact}
            remaining.remove(unit)
        if not remaining: break
    # Environment preparation cannot be reused as installed state. Any selected
    # consumer reruns its dependency closure even if a dependency has a PASS.
    selected=set(remaining)
    while True:
        expanded=selected|{dep for u in selected for dep in contract['steps'][u].get('requires',contract['steps'][u].get('after',[])) if dep in units}
        if expanded==selected: break
        selected=expanded
    proofs={u:p for u,p in proofs.items() if u not in selected}
    result={'run':bool(selected),'reason':'Verified unit coverage' if proofs else 'No verified direct unit evidence',
            'execute':[u for u in units if u in selected],'reuse':proofs}
    if not selected:
        first=next(iter(proofs.values()))
        result.update(source=first['source'],fingerprint=fingerprint(sha,lane,policy),url=first['url'],
                      runId=first['runId'],attempt=first['attempt'],jobId=first['jobId'])
    return result


def verify_plan(plan, lane, sha, repository, contract):
    """Recheck selected provenance at consumption, never trust a plan's claims."""
    units=set(contract['jobs'][lane]['steps'])
    execute=plan['execute'];reuse=plan['reuse']
    if (plan['schemaVersion']!=2 or plan['sha']!=sha or plan['lane']!=lane or
            set(execute)&set(reuse) or len(execute)!=len(set(execute)) or set(execute)|set(reuse)!=units or
            plan['definition']!=definition(sha) or (reuse and definition(sha)!=definition('origin/main'))):
        raise ValueError('Incomplete or foreign unit selection')
    for unit in execute:
        if any(dep in units and dep not in execute for dep in contract['steps'][unit].get('requires',contract['steps'][unit].get('after',[]))):
            raise ValueError('Missing execution dependency')
    if not reuse: return plan
    repository_id=api(repository,'')['id']
    for unit,proof in reuse.items():
        run=cached(('run',proof['runId']),lambda:api(repository,f'actions/runs/{proof["runId"]}'))
        if (run['repository']['id']!=repository_id or run['head_repository']['id']!=repository_id or
                run['event'] not in ('push','workflow_dispatch','pull_request') or run['status']!='completed' or
                run['conclusion']!='success' or run['run_attempt']!=proof['attempt'] or
                run['path']!='.github/workflows/'+contract['jobs'][lane]['workflow'] or
                datetime.fromisoformat(run['created_at'].replace('Z','+00:00'))<datetime.now(timezone.utc)-timedelta(days=contract['reusePolicy']['maxAgeDays'])):
            raise ValueError('Unit source run is stale or foreign')
        job=cached(('job',proof['runId'],proof['attempt'],lane),lambda:job_for(repository,run,lane))
        receipt,artifact=cached(('artifact',proof['runId'],proof['attempt'],lane),lambda:read_artifact(repository,run,lane))
        if not direct_marker(job) or job['id']!=proof['jobId'] or artifact!=proof['artifact']:
            raise ValueError('Unit origin changed')
        source=verify_execution(receipt,run,job,lane,fingerprint(sha,lane,contract,unit),repository_id,contract,contract,definition(sha),unit)
        if source!=proof['source'] or proof['inputSha256']!=fingerprint(sha,lane,contract,unit):
            raise ValueError('Unit fingerprint/source changed')
    return plan


def decide(lane, event, action, ref, sha, repository, contract, policy, attempt=1, budget=20):
    if attempt > 1:
        return {'run': True, 'reason': 'Reruns require a fresh execution'}
    if event == 'pull_request' and action == 'ready_for_review':
        return {'run': True, 'reason': 'Full verification when leaving draft'}
    if event not in ('push', 'pull_request') or (event == 'push' and ref != 'refs/heads/main'):
        return {'run': True, 'reason': 'Explicit, merge-queue or non-main verification'}
    try:
        with lookup(seconds=budget) as metrics:
            result=reusable(lane,sha,repository,contract,policy)
            result['metrics']={k:v for k,v in metrics.items() if k not in ('cache','deadline')}
            return result
    except BudgetExpired:
        return {'run':True,'reason':'Selector 20s budget exhausted; running tests','metrics':{k:v for k,v in metrics.items() if k not in ('cache','deadline')}}
    except (OSError, subprocess.CalledProcessError, ValueError, KeyError, TypeError, AttributeError, IndexError, RuntimeError, zipfile.BadZipFile):
        # No network, shallow history, malformed data or missing permission means
        # tests run. Selection failure must never manufacture a green result.
        return {'run': True, 'reason': 'Reuse evidence unavailable; running tests'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lane')
    args = parser.parse_args()
    started=time.monotonic()
    contract = json.loads((ROOT / 'automation/ci/checks.json').read_text())
    if args.lane not in contract['jobs']:
        parser.error('Unknown CI lane')
    # Check source/semantic ownership before downloads, compilation or reuse.
    preflight_inventory()
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
                        attempt=int(os.environ.get('GITHUB_RUN_ATTEMPT', '1')),budget=max(.001,20-(time.monotonic()-started)))
    from telemetry import emit
    sha=git('rev-parse','HEAD').decode().strip()
    units=contract['jobs'][args.lane]['steps']
    result.setdefault('execute',units)
    result.setdefault('reuse',{})
    result.update(schemaVersion=2,sha=sha,lane=args.lane,definition=definition(sha))
    cache=Path.home()/'.cache/festapp-ci'
    cache.mkdir(parents=True,exist_ok=True)
    plan=cache/('selection-'+args.lane+'.json')
    plan.write_text(json.dumps(result)+'\n')
    emit('ci.selection', started, destination=str(cache/('selection-'+args.lane+'.jsonl')), lane=args.lane, **{k:v for k,v in result.items() if k not in ('lane','reuse')})
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'],'a') as env:
            env.write('FESTAPP_CI_SELECTION_PATH='+str(plan)+'\n')
    print(json.dumps(result, sort_keys=True))
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'run={str(result["run"]).lower()}\nfull={str(len(result["execute"])==len(units)).lower()}\ncms={str("wix-cms" in result["execute"]).lower()}\n')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as output:
            output.write(f'Units: {len(result["execute"])} execute, {len(result["reuse"])} verified reuse.\n\n')
            for unit,proof in result['reuse'].items():
                output.write(f'- {unit}: [direct execution]({proof["url"]}), `{proof["inputSha256"]}`\n')
            if result['run']:
                output.write(f'### {args.lane}: run tests\n{result["reason"]}\n')
            else:
                output.write(f'### {args.lane}: reuse verified inputs\n'
                             f'Previous check: {result["url"]}\n\n'
                             f'Source: `{result["source"]}`\n\n'
                             f'Input SHA-256: `{result["fingerprint"]}`\n')


def preflight_inventory():
    subprocess.run([sys.executable,str(ROOT/'automation/ci/run.py'),'inventory'],
                   cwd=ROOT,check=True,stdout=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
