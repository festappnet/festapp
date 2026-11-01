#!/usr/bin/env python3
"""Exercise the real blueprint Save text request in the production Edge image."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--evidence', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
image = 'supabase/edge-runtime:v1.74.0@sha256:ac5a8314e0c45b0f65d091643c1d6f5293e3a38f31fd3d15186e04a9d5c91cb7'
evidence = args.evidence.resolve()
evidence.mkdir(parents=True, exist_ok=False)
name = 'festapp-blueprint-text-' + uuid.uuid4().hex[:10]

# Do not add a synchronous-read override, patch dependencies in the bundle or
# import the text preparer directly: those hide the production cold-import bug.
main = '''
Deno.serve(async req => {
  try {
    const worker = await EdgeRuntime.userWorkers.create({
      servicePath:'/fixture/functions/blueprint-text-canary',memoryLimitMb:256,
      workerTimeoutMs:60000,cpuTimeSoftLimitMs:10000,cpuTimeHardLimitMs:20000,
      envVars:[],staticPatterns:['/fixture/functions/blueprint-text-canary/*.ttf']
    });
    return await worker.fetch(req);
  } catch(error) { console.error(error); return new Response(String(error),{status:500}); }
});
setTimeout(async () => {
  try {
    const results=[];
    for(let i=0;i<2;i++) {
      const response=await fetch('http://127.0.0.1:9000/');
      const text=await response.text();
      results.push({httpStatus:response.status,...JSON.parse(text)});
    }
    console.log('BLUEPRINT_TEXT_RESULT '+JSON.stringify(results));
  } catch(error) {console.log('BLUEPRINT_TEXT_ERROR '+String(error));}
},100);
'''

with tempfile.TemporaryDirectory(prefix='festapp-blueprint-text-', dir=root/'build') as temporary:
    work = Path(temporary)
    shutil.copytree(root/'supabase/functions', work/'functions')
    worker = work/'functions/blueprint-text-canary'
    worker.mkdir()
    canary=(root/'automation/tickets/blueprint-text-runtime-canary.ts').read_text()
    (worker/'index.ts').write_text(canary.replace('../../supabase/functions/','../'))
    shutil.copy(root/'vendor/blueprint/venue_seat_picker/assets/layout_fonts/Roboto-400-normal.ttf', worker/'Roboto.ttf')
    (work/'main').mkdir()
    (work/'main/index.ts').write_text(main)
    try:
        subprocess.run(['docker','run','-d','--name',name,'--memory','512m',
                        '--pids-limit','128','--cap-drop=ALL','--security-opt=no-new-privileges',
                        '-v',str(work)+':/fixture:ro',image,'start',
                        '--main-service=/fixture/main'],check=True,stdout=subprocess.DEVNULL)
        deadline = time.monotonic()+90
        while time.monotonic()<deadline:
            logs = subprocess.check_output(['docker','logs',name],stderr=subprocess.STDOUT).decode()
            if 'BLUEPRINT_TEXT_RESULT ' in logs or 'BLUEPRINT_TEXT_ERROR ' in logs:
                break
            time.sleep(1)
        (evidence/'runtime.log').write_text(logs)
        lines=[line for line in logs.splitlines() if 'BLUEPRINT_TEXT_RESULT ' in line]
        if not lines:
            raise SystemExit('FAIL: no runtime result; see '+str(evidence/'runtime.log'))
        results=json.loads(lines[-1].split('BLUEPRINT_TEXT_RESULT ',1)[1])
        (evidence/'result.json').write_text(json.dumps({'image':image,'results':results},indent=2)+'\n')
        if len(results)!=2 or any(r.get('httpStatus')!=200 or r.get('status')!=200 or
                r.get('registered')!=1 or len(r.get('textIds',[]))!=2 for r in results) or results[0]!=results[1]:
            raise SystemExit('FAIL: blueprint text Save rejected; see '+str(evidence/'result.json'))
        print('PASS: production Edge cold/warm blueprint text Save and registration')
    finally:
        subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
