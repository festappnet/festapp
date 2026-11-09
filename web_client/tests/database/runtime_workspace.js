// The same immutable base/lease owner used by CI and the public SQL CLI.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
const execute=promisify(execFile);
const runtime=fileURLToPath(new URL('../../../automation/local_db/runtime.py',import.meta.url));
export async function createTestWorkspace() {
  const {stdout}=await execute('python3',[runtime,'acquire','--owner-pid',String(process.pid)],{env:process.env,maxBuffer:4*1024*1024});
  const lease=JSON.parse(stdout);
  let released=false;
  return {...lease,async release(){
    if(released)throw new Error('SQL workspace already released');
    await execute('python3',[runtime,'release','--run-id',lease.runId],{env:process.env});
    released=true;
  }};
}
