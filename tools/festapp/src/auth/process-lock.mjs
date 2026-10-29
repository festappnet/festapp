import { DatabaseSync } from 'node:sqlite';
import { open, lstat } from 'node:fs/promises';
import { constants } from 'node:fs';
import { join } from 'node:path';
import { performance } from 'node:perf_hooks';
import { setTimeout as delay } from 'node:timers/promises';
import { privateRoot } from '../context/profile.mjs';
import { OperationError } from '../errors.mjs';

export async function rejectLegacyLock(path) {
    try { await lstat(path); } catch (error) { if (error.code === 'ENOENT') return; throw error; }
    throw new Error('LEGACY_LOCK_CONFLICT');
}

// Stable private inode. Never unlink it, including after release or a crash.
export async function acquireProcessLock(root, name, { timeoutMs = 0 } = {}) {
    await privateRoot(root);
    if (!/^[a-zA-Z0-9_-]+\.sqlite$/.test(name)) throw new Error('INVALID_LOCK_NAME');
    const file = join(root, name);
    const handle = await open(file, constants.O_CREAT | constants.O_RDWR | constants.O_NOFOLLOW, 0o600);
    try {
        const stat = await handle.stat();
        if (!stat.isFile() || stat.mode & 0o077 || (process.getuid && stat.uid !== process.getuid())) throw new Error('INSECURE_LOCK_FILE');
    } finally { await handle.close(); }
    const deadline = performance.now() + timeoutMs;
    for (;;) {
        let db;
        try {
            db = new DatabaseSync(file);
            db.exec('PRAGMA busy_timeout=0; BEGIN EXCLUSIVE;');
            let released = false;
            return () => {
                if (released) return;
                released = true;
                try { db.exec('ROLLBACK'); } finally { db.close(); }
            };
        } catch (error) {
            db?.close();
            if (error.errcode !== 5 && error.errcode !== 6) throw error;
            if (performance.now() >= deadline) throw new OperationError('SESSION_BUSY', true);
            await delay(Math.min(50, Math.max(1, deadline - performance.now())));
        }
    }
}

// One queue per storage owner, shared by every SessionOwner for a binding.
// A timed-out waiter is removed and can never execute or release the holder.
export function createSessionQueue({ timeoutMs = 10000 } = {}) {
    const queues = new Map();
    return (binding, action) => new Promise((resolve, reject) => {
        let queue = queues.get(binding);
        if (!queue) { queue = []; queues.set(binding, queue); }
        const item = { action, resolve, reject, timer: null };
        const run = async () => {
            clearTimeout(item.timer);
            try { resolve(await action()); } catch (error) { reject(error); }
            finally {
                queue.shift();
                if (queue.length) queue[0].run(); else queues.delete(binding);
            }
        };
        item.run = run;
        if (queue.length >= 64) return reject(new OperationError('SESSION_BUSY', true));
        queue.push(item);
        if (queue.length === 1) run();
        else item.timer = setTimeout(() => {
            queue.splice(queue.indexOf(item), 1);
            reject(new OperationError('SESSION_BUSY', true));
        }, timeoutMs);
    });
}
