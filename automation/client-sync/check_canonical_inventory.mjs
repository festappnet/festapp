import fs from 'node:fs';
import path from 'node:path';

export function verifyRegistrySlice(inventory, sql) {
  const errors=[];
  for(const row of inventory.registry) {
    const start=sql.indexOf(`'${row.component}','${row.relation}'`);
    const end=sql.indexOf("'migrate'",start);
    const body=sql.slice(start,end);
    if(start<0 || end<0) {errors.push(`missing registry source ${row.component}/${row.relation}`);continue;}
    const arrays=[...body.matchAll(/ARRAY\[([^\]]*)\]/g)].map(m=>[...m[1].matchAll(/'([^']*)'/g)].map(x=>x[1]));
    if(JSON.stringify(arrays[1])!==JSON.stringify(row.writers) || JSON.stringify(arrays[2])!==JSON.stringify(row.legacy)) errors.push(`current registry writer drift ${row.component}/${row.relation}`);
  }
  if(/cutover_ready\s*=\s*true/.test(sql))errors.push('additive slice sets readiness');
  return errors;
}
export function checkCanonicalInventory(root, dartFiles) {
  const inventory=JSON.parse(fs.readFileSync(path.join(root,'automation/client-sync/canonical-mutation-inventory.json'),'utf8'));
  const sql=fs.readFileSync(path.join(root,'supabase/migrations/20261007130000_canonical_mutation_registry.sql'),'utf8');
  const errors=verifyRegistrySlice(inventory,sql);
  const forwardSql=inventory.forwardMigrations.map(name=>fs.readFileSync(path.join(root,'supabase/migrations',name),'utf8')).join('\n');
  for(const f of inventory.functions) {
    const source=fs.readFileSync(path.join(root,f.source),'utf8');
    if(!source.includes(`FUNCTION public.${f.name}(`)) errors.push(`missing current SQL owner ${f.name}`);
    const pattern=new RegExp(`CREATE OR REPLACE FUNCTION public\\.${f.name}\\([\\s\\S]*?AS\\s+(\\$\\w*\\$)([\\s\\S]*?)\\1`,'gi');
    const currentBody=[...source.matchAll(pattern)].at(-1)?.[2]?.trim();
    const forwardBody=[...forwardSql.matchAll(pattern)].at(-1)?.[2]?.trim();
    if(forwardBody==null && f.introducedMigration)errors.push(`missing forward migration owner ${f.signature}`);
    else if(forwardBody!=null && currentBody!==forwardBody)errors.push(`forward migration body drift ${f.signature}`);
    if(!fs.existsSync(path.join(root,f.contractTest)))errors.push(`missing contract test ${f.name}`);
  }
  for(const file of dartFiles) {
    const source=fs.readFileSync(file,'utf8');
    for(const rpc of inventory.forbiddenRpcNames)if(new RegExp(`\\.rpc\\(\\s*['"]${rpc}['"]`).test(source))errors.push(`forbidden RPC ${rpc}: ${path.relative(root,file)}`);
    if(/\.from\(\s*Tb\.(user_groups|user_group_info|activities|activity_assignments|activity_history)\.table\)[\s\S]{0,240}?\.(insert|update|delete|upsert)\(/.test(source))errors.push(`scoped direct DML: ${path.relative(root,file)}`);
  }
  const places=fs.readFileSync(path.join(root,'lib/components/map/db_places.dart'),'utf8');
  if(/\.from\(Tb\.places\.table\)[\s\S]{0,240}?\.(insert|update|delete|upsert)\(/.test(places))errors.push('direct place DML remains');
  return {inventory,errors};
}
