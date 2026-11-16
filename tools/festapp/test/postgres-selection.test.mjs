import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {postgresTests} from '../scripts/test-postgres.mjs';

test('isolated PostgreSQL groups cover the complete current suite exactly once',()=>{
    const authorization=postgresTests('authorization'),contracts=postgresTests('contracts');
    assert.equal(authorization.length,1);
    assert(contracts.length>0);
    assert.deepEqual([...authorization,...contracts].sort(),postgresTests());
    assert.equal(new Set([...authorization,...contracts]).size,postgresTests().length);
});

test('new PostgreSQL files join the contracts group; missing or unknown groups fail closed',()=>{
    const directory=mkdtempSync(join(tmpdir(),'festapp-postgres-selection-'));
    try {
        writeFileSync(join(directory,'canonical-authorization-postgres.test.mjs'),'');
        assert.throws(()=>postgresTests('contracts',directory),/Empty/);
        writeFileSync(join(directory,'new-postgres.test.mjs'),'');
        writeFileSync(join(directory,'unrelated.test.mjs'),'');
        assert.deepEqual(postgresTests('contracts',directory),['test/new-postgres.test.mjs']);
        assert.throws(()=>postgresTests('typo',directory),/Unknown/);
        rmSync(join(directory,'canonical-authorization-postgres.test.mjs'));
        assert.throws(()=>postgresTests('all',directory),/missing/);
    } finally {rmSync(directory,{recursive:true,force:true});}
});
