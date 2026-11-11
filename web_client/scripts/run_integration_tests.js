// Compatibility CLI for the established surcharge/integration selection.
// Setup, ownership, isolation, execution and verdicts have one canonical owner.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {globSync} from 'glob';
import {selectSqlTests} from './db_test_selection.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url));
const args=process.argv.slice(2);
const options=args.filter(arg=>arg.startsWith('--'));
if(options.some(arg=>!['--list','--diagnostic-retry'].includes(arg))) throw new Error('Unknown integration SQL option');
const files=selectSqlTests(globSync(path.join(root,'database/tests/eshop/integration/*_test.sql')),args.filter(arg=>!arg.startsWith('--')),root);
if(!files.length){console.error('Integration SQL selection is empty');process.exit(1);}
const result=spawnSync(process.execPath,[fileURLToPath(new URL('./run_db_tests.js',import.meta.url)),...files.map(file=>path.relative(root,file)),...options],{stdio:'inherit',env:process.env});
if(result.error)console.error(result.error.message);
process.exit(result.status??1);
