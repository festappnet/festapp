import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const historical='supabase/migrations/20261024020000_pregenerated_ticket_batches.sql';
const digest=()=>createHash('sha256').update(readFileSync(historical)).digest('hex');
test('applied batch history refuses rewriting after the seat-order forward deepens its owners',()=>{
 const before=digest();assert.equal(before,'dad0ef111e05a7154ceaee99fc97e0d5b5c83badf24077cacea54155c5b4630c');
 const result=spawnSync('python3',['automation/assemble-ticket-batches-migration.py'],{encoding:'utf8'});
 assert.notEqual(result.status,0);assert.match(result.stderr,/immutable/);assert.equal(digest(),before);
});
test('terminal seat-order forward follows batch and ACL prerequisites and reproduces canonical owners',()=>{
 const version='20261024023000';for(const parent of ['20261024020000','20261024021000'])assert(version>parent);
 for(const script of ['automation/assemble-seat-order-migration.py','automation/assemble-ticket-batches-migration.py','automation/generate_canonical_source_contract.py']){
  const result=spawnSync('python3',[script,'--check'],{encoding:'utf8'});assert.equal(result.status,0,result.stderr);
 }
});
