import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

// Keep the existing build-time entrypoint on the single release-derived owner.
export function sourceContract() {
  return execFileSync('python3', [
    fileURLToPath(new URL('../generate_canonical_source_contract.py', import.meta.url)),
    '--print',
  ], {encoding:'utf8'});
}
if (process.argv[1]?.endsWith('/generate_source_contract.mjs')) {
  const target=new URL('../../database/tests/canonical_mutation_source_parity_test.sql',import.meta.url);
  const generated=sourceContract();
  if(process.argv.includes('--check')) {
    if(fs.readFileSync(target,'utf8')!==generated) throw new Error('source contract fixture is stale');
  } else fs.writeFileSync(target,generated);
}
