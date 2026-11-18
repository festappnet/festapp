import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {postgresTests} from '../scripts/test-postgres.mjs';

test('isolated PostgreSQL groups cover the complete current suite exactly once',()=>{
    const authorization = postgresTests('authorization');
    const first = postgresTests('contracts-1');
    const second = postgresTests('contracts-2');
    const combined = [...authorization, ...first, ...second];
    assert.equal(authorization.length, 1);
    assert(Math.abs(first.length - second.length) <= 1);
    assert.deepEqual(combined.sort(), postgresTests());
});

test('new PostgreSQL files join the contracts group; missing or unknown groups fail closed',()=>{
    const directory=mkdtempSync(join(tmpdir(),'festapp-postgres-selection-'));
    try {
        writeFileSync(join(directory,'canonical-authorization-postgres.test.mjs'),'');
        assert.throws(()=>postgresTests('contracts-1',directory),/Empty/);
        writeFileSync(join(directory,'new-postgres.test.mjs'),'');
        writeFileSync(join(directory,'other-postgres.test.mjs'),'');
        writeFileSync(join(directory,'unrelated.test.mjs'),'');
        assert.deepEqual(postgresTests('contracts-1', directory), ['test/new-postgres.test.mjs']);
        assert.deepEqual(postgresTests('contracts-2', directory), ['test/other-postgres.test.mjs']);
        assert.throws(()=>postgresTests('typo',directory),/Unknown/);
        rmSync(join(directory,'canonical-authorization-postgres.test.mjs'));
        assert.throws(()=>postgresTests('all',directory),/missing/);
    } finally {rmSync(directory,{recursive:true,force:true});}
});
