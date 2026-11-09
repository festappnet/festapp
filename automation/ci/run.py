#!/usr/bin/env python3
"""Canonical CI unit DAG for GitHub and the resource-bounded native local mirror."""
import argparse
import fcntl
import hashlib
import fnmatch
import platform
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time
from telemetry import input_identity, phase, measured_process, run_directory, write_receipt, emit
from scheduler import execute_dag
from resources import flutter_slot
from contextlib import nullcontext

ROOT=Path(__file__).resolve().parents[2]
CONTRACT=json.loads((ROOT/'automation/ci/checks.json').read_text())
CACHE=Path.home()/('Library/Caches/festapp-ci' if sys.platform=='darwin' else '.cache/festapp-ci')


def call(argv,**kwargs):return subprocess.run(argv,check=True,cwd=ROOT,**kwargs)


def step(name):
    script=CONTRACT['steps'][name]['script']
    if os.environ.get('FESTAPP_CLIENT_RESULTS') and 'fvm flutter test' in script:
        output=Path(os.environ['FESTAPP_CLIENT_RESULTS']);output.mkdir(parents=True,exist_ok=True)
        lines=[]
        for index,line in enumerate(script.splitlines()):
            if line.startswith('fvm flutter test '):
                line+=' --reporter=json > '+shlex.quote(str(output/f'{name}-{index}.jsonl'))+' 2> '+shlex.quote(str(output/f'{name}-{index}.stderr'))
            lines.append(line)
        script='\n'.join(lines)
    with flutter_slot() if 'fvm flutter' in script else nullcontext():
        with phase('step.'+name):call(['bash','-euo','pipefail','-c',script])


def require_version(command,expected):
    actual=subprocess.check_output(command,text=True).strip()
    if expected not in actual.split():raise RuntimeError(f'{command[0]} must be {expected}; got {actual}')
    return actual


def install(package):
    directory=Path(package).resolve()
    if not directory.is_relative_to(ROOT) or not (directory/'pnpm-lock.yaml').is_file():
        raise ValueError('Install must name a repository package with its frozen pnpm lockfile')
    paths=[directory/name for name in ('package.json','pnpm-lock.yaml','pnpm-workspace.yaml','.npmrc') if (directory/name).is_file()]
    versions={tool:subprocess.check_output([tool,'--version'],text=True).strip() for tool in ('node','pnpm')}
    if versions['pnpm']!='11.24.0':raise ValueError('pnpm 11.24.0 is required')
    digest=hashlib.sha256(json.dumps(versions,sort_keys=True).encode())
    for path in paths:digest.update(path.name.encode()+b'\0'+path.read_bytes())
    key=hashlib.sha256(str(directory).encode()).hexdigest()
    run=Path(os.environ.get('FESTAPP_CI_RUN_DIRECTORY',CACHE/'standalone-install'))
    run.mkdir(parents=True,exist_ok=True)
    with (run/('install-'+key+'.lock')).open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        stamp=run/('install-'+key+'.json');modules=directory/'node_modules/.modules.yaml'
        matching=False
        if os.environ.get('FESTAPP_CI_RUN_DIRECTORY') and stamp.exists() and modules.is_file():
            matching=json.loads(stamp.read_text())=={'input':digest.hexdigest(),'modules':hashlib.sha256(modules.read_bytes()).hexdigest()}
        if matching:
            emit('dependencies.reuse',time.monotonic(),package=str(directory.relative_to(ROOT)),node=versions['node'])
            return
        with phase('dependencies.install',package=str(directory.relative_to(ROOT)),node=versions['node']):
            subprocess.run(['pnpm','install','--frozen-lockfile'],cwd=directory,check=True,env={**os.environ,'CI':'true'})
        if modules.is_file():
            stamp.write_text(json.dumps({'input':digest.hexdigest(),'modules':hashlib.sha256(modules.read_bytes()).hexdigest()})+'\n')


def selected_units(names):
    ownership={unit:job for job,value in CONTRACT['jobs'].items() for unit in value['steps']}
    selected={name for job in names for name in CONTRACT['jobs'][job]['steps']}
    return {name:{**definition,'job':ownership[name],'after':[dependency for dependency in definition.get('after',[]) if dependency in selected]}
            for name,definition in CONTRACT['steps'].items() if name in selected}


def inventory():
    actual={str(path.relative_to(ROOT)) for path in (ROOT/'database/tests').rglob('*_test.sql')}
    expected=set(CONTRACT['sqlInventory']['knownTests'])
    paths=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard'],cwd=ROOT,text=True).splitlines()
    current={path for path in paths if (ROOT/path).is_file() and path.startswith(('database/tests/','web_client/tests/','automation/tests/','supabase/functions/','test/','test_dart/','tools/festapp/test/')) and path.endswith(('_test.sql','.test.js','.test.mjs','_test.ts','_test.dart'))}
    recorded=set(CONTRACT['knownTestInputs'])
    if current!=recorded:
        raise ValueError('Test inventory ownership changed. New: '+str(sorted(current-recorded))+'; removed: '+str(sorted(recorded-current)))
    if actual!=expected:
        raise ValueError('SQL inventory changed; assign explicit CI/broad DB ownership. New: '+str(sorted(actual-expected))+'; removed: '+str(sorted(expected-actual)))
    selected=set()
    for value in CONTRACT['sqlGroups'].values():
        selected.update(path for path in actual if any(filter in path for filter in value['filters']))
    print(json.dumps({'knownSqlTests':len(actual),'seatSqlTests':sorted(selected),'broadDbTests':len(actual-selected)}))


def affected(paths):
    if not paths:return list(CONTRACT['jobs'])
    selected=set()
    for path in paths:
        # New tests cannot disappear behind an existing domain prefix.
        if path.endswith(('_test.sql','.test.js','.test.mjs','_test.ts','_test.dart')) and path not in CONTRACT['knownTestInputs']:
            return list(CONTRACT['jobs'])
        matches={job for job,value in CONTRACT['jobs'].items()
                 if any(fnmatch.fnmatch(path,pattern) for pattern in value['inputs'])}
        if path.startswith(('automation/ci/','.github/workflows/')) or not matches:
            return list(CONTRACT['jobs'])
        selected.update(matches)
    return [name for name in CONTRACT['jobs'] if name in selected]


def host_state():
    state={'loadAverage':os.getloadavg(),'cpuCount':os.cpu_count(),'host':platform.platform()}
    if sys.platform=='darwin':
        state['swap']=subprocess.check_output(['sysctl','-n','vm.swapusage'],text=True).strip()
        state['physicalMemoryBytes']=int(subprocess.check_output(['sysctl','-n','hw.memsize'],text=True))
    return state


def _execute(names, *, pinned=False, command_started=None):
    started=time.monotonic() if command_started is None else command_started
    directory=run_directory(CACHE)
    env={**os.environ,'CI':'true','FESTAPP_CI_RUN_DIRECTORY':str(directory),'FESTAPP_TIMINGS':str(directory/'timings.jsonl')}
    identity=input_identity(ROOT)
    receipt={**identity,'selectedJobs':names,'scope':'full' if set(names)==set(CONTRACT['jobs']) else 'partial',
             'complete':False,'jobs':[],'units':{},'hostStart':host_state(),'memoryMethod':'250ms sampled host process-tree RSS; Docker VM excluded. Container memory sampled separately.'}
    nodes={}
    if pinned:
        for version in {CONTRACT['jobs'][name]['node'] for name in names}:
            nodes[version]=subprocess.check_output(['pnpm',f'--package=node@{version}','dlx','node','-p','process.execPath'],cwd=ROOT,text=True).strip()
    units=selected_units(names)
    execution_started=time.monotonic()
    receipt['preparationSeconds']=execution_started-started
    receipt['preparationScope']='command preflight, Python environment and pinned Node resolution; hosted action provisioning is outside the lane'
    def execute(name,unit):
        before=time.monotonic();log=directory/(name+'.log')
        print('CI unit: '+name+' (log: '+str(log)+')',flush=True)
        unit_env={**env,'FESTAPP_CLIENT_RESULTS':str(directory/(name+'-client'))}
        version=CONTRACT['jobs'][unit['job']]['node']
        node=nodes[version] if pinned else shutil.which('node')
        if pinned:
            unit_env['PATH']=str(Path(node).parent)+os.pathsep+unit_env['PATH']
        elif subprocess.check_output([node,'--version'],text=True).strip()!='v'+version:
            raise RuntimeError('Hosted lane Node version does not match the canonical contract')
        if name in ('seat-upgrade','seat-database') and runtime.inspect():
            unit_env['FESTAPP_MONITOR_CONTAINER']=runtime.container
        command=[node,'automation/ci/node-runtime.mjs',sys.executable,'automation/ci/run.py','step',name]
        def run(lease=None):
            if lease:
                unit_env.update(runtime_module.workspace_env(lease))
                unit_env['FESTAPP_TEST_ADMIN_DATABASE_URL']=runtime.url('supabase_admin',lease['database'])
                unit_env['FESTAPP_MONITOR_CONTAINER']=runtime.container
            with log.open('w') as output:
                code,seconds,peak=measured_process(command,cwd=ROOT,env=unit_env,stdout=output,stderr=subprocess.STDOUT)
            if code:
                print('\n'.join(log.read_text().splitlines()[-35:]),file=sys.stderr)
                raise RuntimeError(f'{name} exited {code}; log: {log}')
            if name=='ticket-client':
                subprocess.run([sys.executable,'automation/client_test_inventory.py','check-ci',unit_env['FESTAPP_CLIENT_RESULTS'],'ticket-client'],cwd=ROOT,check=True)
            return {'log':str(log),'exitCode':code,'seconds':seconds,'peakSummedRssBytes':peak,
                    'workspace':lease['database'] if lease else None,'node':version,'resources':unit.get('resources',{})}
        if name in CONTRACT.get('databaseUnits',[]):
            with runtime.workspace() as lease:result=run(lease)
        else:result=run()
        print(f'PASS {name}: {time.monotonic()-before:.1f}s',flush=True)
        return result
    runtime=None;runtime_module=None
    if any(name.startswith('seat-') or name=='occasion-lifecycle' for name in units):
        sys.path.insert(0,str(ROOT/'automation/local_db'))
        import runtime as runtime_module
        runtime=runtime_module.Runtime()
    try:
        receipt['units']=execute_dag(units,CONTRACT['resources'],execute,workers=3)
        for name in names:
            results=[receipt['units'][unit] for unit in CONTRACT['jobs'][name]['steps']]
            receipt['jobs'].append({'name':name,'status':'PASS' if all(row['status']=='PASS' for row in results) else 'FAIL'})
        receipt['complete']=all(row['status']=='PASS' for row in receipt['units'].values())
    finally:
        receipt['hostEnd']=host_state()
        receipt['executionSeconds']=time.monotonic()-execution_started
        cleanup=time.monotonic()
        try:
            if runtime:
                with runtime.locked():runtime.stop()
        except Exception as error:
            receipt['complete']=False;receipt['cleanupError']=str(error)
        receipt['cleanupSeconds']=time.monotonic()-cleanup
        receipt['seconds']=time.monotonic()-started
        receipt['inputsUnchanged']=input_identity(ROOT)['inputSha256']==identity['inputSha256']
        receipt['complete'] &= receipt['inputsUnchanged']
        write_receipt(directory,receipt,CACHE)
    print('CI receipt: '+str(directory/'receipt.json'),flush=True)
    if not receipt['complete']:raise RuntimeError('CI did not complete successfully; inspect the immutable receipt')
    return receipt


def lane(name):return _execute([name],pinned=False)


def local(names):
    command_started=time.monotonic()
    previous=os.environ.copy()
    try:
        CACHE.mkdir(parents=True,exist_ok=True)
        with (CACHE/'mirror.lock').open('a') as lock:
            try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:raise RuntimeError('Another local CI mirror is running; wait for it to finish.')
            require_version(['pnpm','--version'],'11.24.0')
            if any(name in names for name in ('seat-checkout','ticket-preview-and-delivery','server-policy')):require_version(['deno','--version'],'2.9.0')
            if {'seat-checkout','web-startup','client-contract'}.intersection(names):
                browser=(os.environ.get('CHROME_EXECUTABLE') or shutil.which('google-chrome') or shutil.which('chromium'))
                if not browser and sys.platform=='darwin':browser='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
                if not browser or not Path(browser).is_file():raise RuntimeError('Install Chrome/Chromium before browser lanes')
                os.environ['CHROME_EXECUTABLE']=browser
            if 'image-contract' in names:
                venv=CACHE/'python'
                call([sys.executable,'-m','venv',str(venv)])
                call([str(venv/'bin/pip'),'--quiet','install','PyYAML==6.0.3'])
                os.environ['PATH']=str(venv/'bin')+os.pathsep+os.environ['PATH']
            if 'seat-checkout' in names:
                require_version(['supabase','--version'],'2.111.0')
            return _execute(names,pinned=True,command_started=command_started)
    finally:os.environ.clear();os.environ.update(previous)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['local','lane','step','list','install','affected','inventory'])
    parser.add_argument('names',nargs='*');args=parser.parse_args()
    if args.mode=='list':print('\n'.join(CONTRACT['jobs']));return
    if args.mode=='install':install(args.names[0]);return
    if args.mode=='inventory':inventory();return
    if args.mode=='affected':print(json.dumps({'scope':'targeted-recommendation','jobs':affected(args.names),'paths':args.names,'broaderDbCommand':['bash','automation/test_all.sh','db'] if any(path.endswith('_test.sql') for path in args.names) else None}));return
    if args.mode=='step':step(args.names[0]);return
    names=args.names or list(CONTRACT['jobs'])
    for name in names:
        if name not in CONTRACT['jobs']:parser.error('Unknown lane: '+name)
    if args.mode=='lane':lane(names[0])
    else:local(names)


if __name__=='__main__':
    try:main()
    except (RuntimeError,ValueError,subprocess.CalledProcessError,KeyError,IndexError) as error:
        print(str(error),file=sys.stderr);sys.exit(1)
