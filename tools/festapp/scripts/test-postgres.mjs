// CI groups run in separate marked databases. Keep each group's files serial:
// some fixtures commit or replace functions and cannot share a concurrent DB.
import {readdirSync} from 'node:fs';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {dirname, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const authorization='canonical-authorization-postgres.test.mjs';

export function postgresTests(group='all',directory=resolve(root,'test')) {
    assert(['all','authorization','contracts'].includes(group),'Unknown PostgreSQL test group: '+group);
    const files=readdirSync(directory).filter(file=>file.endsWith('-postgres.test.mjs')).sort();
    assert(files.includes(authorization),'Authorization truth-table entrypoint is missing');
    const selected=files.filter(file=>group==='all'||(group==='authorization')===(file===authorization));
    assert(selected.length,'Empty PostgreSQL test group: '+group);
    return selected.map(file=>'test/'+file);
}

if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url) {
    const args=process.argv.slice(2);
    const list=args[0]==='--list';
    if(list)args.shift();
    assert(args.length<=1,'Expected one PostgreSQL test group');
    const files=postgresTests(args[0]);
    if(list)console.log(JSON.stringify(files));
    else {
        const result=spawnSync(process.execPath,['--test','--test-concurrency=1',...files],{cwd:root,stdio:'inherit'});
        if(result.error)throw result.error;
        process.exitCode=result.status??1;
    }
}
