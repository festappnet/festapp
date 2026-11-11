"""Resource-bounded execution of the canonical CI unit DAG (no CLI)."""
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED
import time


def execute_dag(units, capacities, execute, workers=3):
    pending=dict(units);running={};used={key:0 for key in capacities};results={}
    for name,unit in units.items():
        unknown=set(unit.get('after',[]))-units.keys()
        if unknown: raise ValueError(f'Unknown dependencies for {name}: {sorted(unknown)}')
        for resource,weight in unit.get('resources',{}).items():
            if resource not in capacities or weight<0 or weight>capacities[resource]:
                raise ValueError(f'Invalid resource claim {name}: {resource}={weight}')
    with ThreadPoolExecutor(max_workers=workers) as pool:
        while pending or running:
            # A failed dependency is INCOMPLETE, never a successful skipped unit.
            changed=True
            while changed:
                changed=False
                for name,unit in list(pending.items()):
                    dependencies=unit.get('after',[])
                    if any(dep in results and results[dep]['status']!='PASS' for dep in dependencies):
                        results[name]={'status':'INCOMPLETE','reason':'failed dependency','seconds':0}
                        del pending[name]
                        changed=True
            for name,unit in list(pending.items()):
                if len(running)>=workers: break
                if not all(dep in results and results[dep]['status']=='PASS' for dep in unit.get('after',[])): continue
                claims=unit.get('resources',{})
                if any(used[key]+weight>capacities[key] for key,weight in claims.items()): continue
                for key,weight in claims.items(): used[key]+=weight
                running[pool.submit(execute,name,unit)]=(name,claims,time.monotonic())
                del pending[name]
            if not running:
                if pending: raise ValueError('CI dependency cycle or unsatisfiable resource budget')
                break
            done,_=wait(running,return_when=FIRST_COMPLETED)
            for future in done:
                name,claims,started=running.pop(future)
                for key,weight in claims.items(): used[key]-=weight
                try:
                    result=future.result()
                    results[name]={'status':'PASS','seconds':time.monotonic()-started,**(result or {})}
                except Exception as error:
                    results[name]={'status':'FAIL','seconds':time.monotonic()-started,'error':str(error)}
    return results
