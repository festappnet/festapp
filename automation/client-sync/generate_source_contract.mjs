import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {mutationInventory} from './canonical_mutation_contraction.mjs';
// Build-time contract only. Domain routing and DML remain handwritten.
export function sourceContract() {
 const names=new Set();
 const checks=mutationInventory.functions.map(owner=>{
  if(names.has(owner.signature))throw new Error(`duplicate current SQL owner ${owner.signature}`);
  names.add(owner.signature);
  const source=fs.readFileSync(new URL(`../../${owner.source}`,import.meta.url),'utf8');
  const pattern=new RegExp(`CREATE OR REPLACE FUNCTION public\\.${owner.name}\\([\\s\\S]*?AS\\s+(\\$\\w*\\$)([\\s\\S]*?)\\1`,'i');
  const body=source.match(pattern)?.[2];
  if(!body)throw new Error(`missing current SQL body ${owner.signature}`);
  const hash=createHash('md5').update(body.trim()).digest('hex');
  return ` PERFORM assert_true(EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.${owner.signature}') AND md5(btrim(prosrc,E' \\n\\r\\t'))='${hash}'),'current SQL source parity: ${owner.signature}');`;
 });
 return `-- Generated source contract. Refresh with node automation/client-sync/generate_source_contract.mjs.\nDO $$ BEGIN\n${checks.join('\n')}\nEND $$;\n`;
}
if(process.argv[1]?.endsWith('/generate_source_contract.mjs')) {
 const url=new URL('../../database/tests/canonical_mutation_source_parity_test.sql',import.meta.url);
 const generated=sourceContract();
 if(process.argv.includes('--check')) {if(fs.readFileSync(url,'utf8')!==generated)throw new Error('source contract fixture is stale');}
 else fs.writeFileSync(url,generated);
 console.log(`canonical SQL source contract: ${mutationInventory.functions.length} owners`);
}
