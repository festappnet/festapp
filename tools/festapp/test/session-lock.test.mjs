import test from 'node:test';
import assert from 'node:assert/strict';
import { createSessionQueue } from '../src/auth/process-lock.mjs';
import { setTimeout as delay } from 'node:timers/promises';

test('shared binding queue serializes, isolates bindings and cancels timed-out waiters', async () => {
    const run = createSessionQueue({ timeoutMs: 30 });
    let release, active = true, ran = false;
    const first = run('a', () => new Promise(r => { release = () => { active = false; r(); }; }));
    const waiting = run('a', () => { ran = true; });
    await run('b', () => assert(active));
    await assert.rejects(waiting, { code: 'SESSION_BUSY' });
    assert(active); release(); await first;
    await run('a', () => assert(!active)); await delay(10); assert(!ran);
});

test('different hosted SessionOwner instances share their storage binding queue', async t => {
    const { fixture } = await import('./fixture.mjs');
    const { openRemoteStorage } = await import('../src/remote/storage.mjs');
    const { boundOwner } = await import('../src/remote/delegation.mjs');
    const { mkdtemp, rm } = await import('node:fs/promises');
    const { tmpdir } = await import('node:os');
    const { join } = await import('node:path');
    const { randomBytes } = await import('node:crypto');
    const f = await fixture(t);
    const root = await mkdtemp(join(tmpdir(),'festapp-hosted-queue-'));
    const storage = await openRemoteStorage(root,randomBytes(32));
    t.after(async()=>{await storage.close();await rm(root,{recursive:true,force:true});});
    const owner = binding => boundOwner({profile:f.owner.profile},storage,binding);
    let active=0, maximum=0;
    await Promise.all(Array.from({length:5},()=>owner('shared').locked(async()=>{
        active++; maximum=Math.max(maximum,active); await delay(5); active--;
    })));
    assert.equal(maximum,1);
});
