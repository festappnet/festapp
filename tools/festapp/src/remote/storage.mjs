import { acquireProcessLock, rejectLegacyLock, createSessionQueue } from '../auth/process-lock.mjs';
import { DatabaseSync } from 'node:sqlite';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { lstat, chmod } from 'node:fs/promises';
import { join } from 'node:path';
import { privateRoot, digest } from '../context/profile.mjs';

// One process owns a local SQLite volume. A second process/replica must refuse
// startup, rather than racing downstream refresh or authorization-code consume.
export async function openRemoteStorage(root, key) {
    if (!Buffer.isBuffer(key) || key.length !== 32) throw new Error('INVALID_STORAGE_KEY');
    await privateRoot(root);
    await rejectLegacyLock(join(root, 'remote-process.lock'));
    const release = await acquireProcessLock(root, 'remote-owner.sqlite');
    const runSessionExclusive = createSessionQueue();
    let closed = false;
    let db;
    try {
        const file = join(root, 'remote.sqlite');
        try {
            const stat = await lstat(file);
            if (!stat.isFile() || stat.isSymbolicLink() || (stat.mode & 0o077) ||
                (process.getuid && stat.uid !== process.getuid()))
                throw new Error('INSECURE_REMOTE_STORAGE');
        } catch (e) { if (e.code !== 'ENOENT') throw e; }
        db = new DatabaseSync(file);
        await chmod(file, 0o600);
        db.exec('PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS records (model TEXT, id TEXT, value BLOB NOT NULL, expires INTEGER NOT NULL, grant_id TEXT, uid TEXT, user_code TEXT, PRIMARY KEY(model,id));');
        const seal = (model, id, value) => {
            const iv = randomBytes(12);
            const cipher = createCipheriv('aes-256-gcm', key, iv);
            cipher.setAAD(Buffer.from(JSON.stringify([model, id])));
            const bytes = Buffer.concat([cipher.update(JSON.stringify(value)), cipher.final()]);
            return Buffer.concat([iv, cipher.getAuthTag(), bytes]);
        };
        const unseal = (model, id, bytes) => {
            bytes = Buffer.from(bytes);
            const decipher = createDecipheriv('aes-256-gcm', key, bytes.subarray(0, 12));
            decipher.setAAD(Buffer.from(JSON.stringify([model, id])));
            decipher.setAuthTag(bytes.subarray(12, 28));
            return JSON.parse(Buffer.concat([decipher.update(bytes.subarray(28)), decipher.final()]));
        };
        const store = {
            root,
            runSessionExclusive,
            get(model, id) {
                const row = db.prepare('SELECT * FROM records WHERE model=? AND id=? AND expires>?').get(model, digest(id), Date.now());
                return row ? unseal(model, digest(id), row.value) : undefined;
            },
            put(model, id, value, seconds = 3600) {
                db.prepare('DELETE FROM records WHERE expires<=?').run(Date.now());
                if (db.prepare('SELECT COUNT(*) AS n FROM records').get().n >= 20000 && !this.get(model, id))
                    throw new Error('REMOTE_STORAGE_FULL');
                const hashed = digest(id);
                db.prepare('INSERT OR REPLACE INTO records VALUES (?,?,?,?,?,?,?)').run(
                    model, hashed, seal(model, hashed, value), Date.now() + seconds * 1000,
                    value.grantId ? digest(value.grantId) : null,
                    value.uid ? digest(value.uid) : null,
                    value.userCode ? digest(value.userCode) : null,
                );
            },
            remove(model, id) { db.prepare('DELETE FROM records WHERE model=? AND id=?').run(model, digest(id)); },
            values(model) {
                return db.prepare('SELECT id,value FROM records WHERE model=? AND expires>?').all(model, Date.now())
                    .map(r => unseal(model, r.id, r.value));
            },
            revoke(grantId) {
                const grant = this.get('Delegation', grantId);
                if (grant) {
                    this.remove('Backend', grant.binding);
                    grant.revoked = true;
                    this.put('Delegation', grantId, grant, 86400 * 7);
                }
                db.prepare('DELETE FROM records WHERE grant_id=?').run(digest(grantId));
            },
            adapter(model) {
                return {
                    upsert: async (id, value, ttl) => store.put(model, id, value, ttl),
                    find: async id => store.get(model, id),
                    findByUid: async uid => store.index(model, 'uid', uid),
                    findByUserCode: async code => store.index(model, 'user_code', code),
                    destroy: async id => store.remove(model, id),
                    consume: async id => {
                        const value = store.get(model, id);
                        if (!value || value.consumed) throw new Error('OAUTH_SOURCE_ALREADY_CONSUMED');
                        if (value) {
                            const row = db.prepare('SELECT expires FROM records WHERE model=? AND id=?').get(model, digest(id));
                            store.put(model, id, { ...value, consumed: Math.floor(Date.now() / 1000) }, Math.max(0, (row.expires - Date.now()) / 1000));
                        }
                    },
                    revokeByGrantId: async id => store.revoke(id),
                };
            },
            index(model, column, value) {
                // column is internal, never request input.
                const row = db.prepare(`SELECT id,value FROM records WHERE model=? AND ${column}=? AND expires>?`).get(model, digest(value), Date.now());
                return row ? unseal(model, row.id, row.value) : undefined;
            },
            backendStore: {
                read: async binding => store.get('Backend', binding) ?? null,
                write: async (binding, value) => {
                    const link = store.get('Binding', binding);
                    const grant = link && store.get('Delegation', link.id);
                    if (link && (!grant || grant.revoked || grant.expiresAt <= Date.now()))
                        throw new Error('CONNECTION_REVOKED');
                    // Abandoned login flows expire in ten minutes. Only an
                    // explicit consent promotes a session to the grant lifetime.
                    store.put('Backend', binding, value, grant ? (grant.expiresAt - Date.now()) / 1000 : 600);
                },
                remove: async binding => store.remove('Backend', binding),
            },
            async close() { if (closed) return; closed = true; try { db.close(); } finally { release(); } },
        };
        // Detect a wrong/missing key before accepting traffic, even after restart.
        const sentinel = store.get('Metadata', 'encryption');
        if (!sentinel) store.put('Metadata', 'encryption', { version: 1 }, 86400 * 3650);
        return store;
    } catch (e) { try { db?.close(); } finally { release(); } throw e; }
}
