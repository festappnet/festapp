import { connectionActive, connectionIssuable } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
import { errors } from 'oidc-provider';
import { acquireProcessLock, rejectLegacyLock, createSessionQueue } from '../auth/process-lock.mjs';
import { DatabaseSync } from 'node:sqlite';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { deflateSync, inflateSync } from 'node:zlib';
import { lstat, chmod } from 'node:fs/promises';
import { join } from 'node:path';
import { privateRoot, digest } from '../context/profile.mjs';

// Exact spent-token membership is packed into 256 encrypted buckets in the
// same owner. No live proof is evicted. Each bucket is capped at 128 KiB
// compressed / 2 MiB decoded; overflow refuses consumption atomically.
export const REFRESH_REPLAY_LIMITS = Object.freeze({buckets:256,compressedBytes:131072,decodedBytes:2097152,admittedConnections:16,refreshPerMinute:12});

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
        const seal = (model, id, value, encryptionKey = key) => {
            const iv = randomBytes(12);
            const cipher = createCipheriv('aes-256-gcm', encryptionKey, iv);
            cipher.setAAD(Buffer.from(JSON.stringify([model, id])));
            let encoded = Buffer.from(JSON.stringify(value));
            if (model === 'RefreshReplay') {
                if (encoded.length > REFRESH_REPLAY_LIMITS.decodedBytes) throw new Error('REFRESH_REPLAY_FULL');
                encoded = deflateSync(encoded);
                if (encoded.length > REFRESH_REPLAY_LIMITS.compressedBytes) throw new Error('REFRESH_REPLAY_FULL');
            }
            const bytes = Buffer.concat([cipher.update(encoded), cipher.final()]);
            return Buffer.concat([iv, cipher.getAuthTag(), bytes]);
        };
        const unseal = (model, id, bytes, encryptionKey = key) => {
            bytes = Buffer.from(bytes);
            const decipher = createDecipheriv('aes-256-gcm', encryptionKey, bytes.subarray(0, 12));
            decipher.setAAD(Buffer.from(JSON.stringify([model, id])));
            decipher.setAuthTag(bytes.subarray(12, 28));
            let encoded = Buffer.concat([decipher.update(bytes.subarray(28)), decipher.final()]);
            if (model === 'RefreshReplay') encoded = inflateSync(encoded,{maxOutputLength:REFRESH_REPLAY_LIMITS.decodedBytes});
            return JSON.parse(encoded);
        };
        const transaction = action => {
            db.exec('BEGIN IMMEDIATE');
            try { const result = action(); db.exec('COMMIT'); return result; }
            catch (error) { db.exec('ROLLBACK'); throw error; }
        };
        // Called only inside the transaction owned by activation or revocation.
        const revokeRecords = grantId => {
            const grant = store.get('Delegation', grantId);
            if (grant) {
                store.remove('Backend', grant.binding);
                store.putUntil('Delegation', grantId, { ...grant, revoked: true }, grant.expiresAt);
            }
            db.prepare('DELETE FROM records WHERE grant_id=?').run(digest(grantId));
        };
        const replayBucket = id => digest(id).slice(0,2);
        const archiveRefresh = (id, value, expires) => {
            const bucketId = replayBucket(id), now = Date.now();
            const bucket = store.get('RefreshReplay',bucketId) ?? {version:1,entries:{}};
            for (const [key,entry] of Object.entries(bucket.entries)) if(entry.expires<=now) delete bucket.entries[key];
            bucket.entries[digest(id)] = {expires,value};
            // Store admission and compression happen before deletion of the
            // original token, under the same FULL SQLite transaction.
            store.putUntil('RefreshReplay',bucketId,bucket,Math.max(...Object.values(bucket.entries).map(e=>e.expires)));
            store.remove('RefreshToken',id);
        };
        const store = {
            root,
            stats() {
                const rows = db.prepare('SELECT model,COUNT(*) AS n FROM records WHERE expires>? GROUP BY model').all(Date.now());
                return { replayBytes: db.prepare("SELECT coalesce(sum(length(value)),0) n FROM records WHERE model='RefreshReplay' AND expires>?").get(Date.now()).n, capacity: 20000, replayLimits: REFRESH_REPLAY_LIMITS, records: rows.reduce((sum,r)=>sum+r.n,0), byModel: Object.fromEntries(rows.map(r=>[r.model,r.n])) };
            },
            // Offline operator tool only; the process lock prevents opening this
            // owner alongside the service. A crash leaves either the old or new
            // key valid, never a partly re-encrypted DB. Secrets files are staged
            // separately before this transaction and never overwritten here.
            rekey(newKey) {
                if(!Buffer.isBuffer(newKey)||newKey.length!==32||newKey.equals(key))throw new Error('INVALID_NEW_STORAGE_KEY');
                const replacement=Buffer.from(newKey);
                const count=transaction(()=>{
                    const rows=db.prepare('SELECT model,id,value FROM records').all();
                    const update=db.prepare('UPDATE records SET value=? WHERE model=? AND id=?');
                    for(const row of rows){
                        const value=unseal(row.model,row.id,row.value),encrypted=seal(row.model,row.id,value,replacement);
                        if(JSON.stringify(unseal(row.model,row.id,encrypted,replacement))!==JSON.stringify(value))throw new Error('STORAGE_REKEY_VERIFICATION_FAILED');
                        update.run(encrypted,row.model,row.id);
                    }
                    return rows.length;
                });
                key=replacement;
                return {reencryptedRecords:count};
            },
            // Offline restore recovery only. Never retain OAuth credentials from
            // a rolled-back backup: it may predate revocation or consumption.
            invalidateRestoredState() {
                return transaction(() => {
                    const count = db.prepare("SELECT COUNT(*) AS n FROM records WHERE model<>'Metadata'").get().n;
                    db.prepare("DELETE FROM records WHERE model<>'Metadata'").run();
                    return { invalidatedRecords: count };
                });
            },
            runSessionExclusive,
            get(model, id) {
                const row = db.prepare('SELECT * FROM records WHERE model=? AND id=? AND expires>?').get(model, digest(id), Date.now());
                return row ? unseal(model, digest(id), row.value) : undefined;
            },
            put(model, id, value, seconds = 3600) {
                return this.putUntil(model, id, value, Date.now() + seconds * 1000);
            },
            // Absolute consent deadlines must survive clock movement during writes.
            putUntil(model, id, value, expiresAt) {
                db.prepare('DELETE FROM records WHERE expires<=?').run(Date.now());
                if (db.prepare('SELECT COUNT(*) AS n FROM records').get().n >= 20000 && !this.get(model, id))
                    throw new Error('REMOTE_STORAGE_FULL');
                const hashed = digest(id);
                db.prepare('INSERT OR REPLACE INTO records VALUES (?,?,?,?,?,?,?)').run(
                    model, hashed, seal(model, hashed, value), expiresAt,
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
            revoke(grantId) { return transaction(() => revokeRecords(grantId)); },
            discardUnissuedTokens(grantId) {
                db.prepare("DELETE FROM records WHERE grant_id=? AND model IN ('AccessToken','RefreshToken')").run(digest(grantId));
            },
            activateConnection(grantId) {
                return transaction(() => {
                    const grant = this.get('Delegation', grantId);
                    if (!connectionIssuable(grant)) throw new errors.InvalidGrant('consent expired');
                    if (grant.replaces) {
                        const old = this.get('Delegation', grant.replaces);
                        if (!connectionActive(old) || ['userId', 'clientId', 'profileBinding'].some(k => old[k] !== grant[k]))
                            throw new errors.InvalidGrant('replacement target inactive');
                        revokeRecords(old.id);
                    }
                    const backend = this.get('Backend', grant.binding);
                    if (!backend) throw new errors.InvalidGrant('backend session expired');
                    const issued = { ...grant, lifecycle: 'issued', issuedAt: Date.now(), lastTokenExchangeAt: Date.now() };
                    this.putUntil('Delegation', grantId, issued, grant.expiresAt);
                    this.putUntil('Binding', grant.binding, { id: grantId }, grant.expiresAt);
                    this.putUntil('Backend', grant.binding, backend, grant.expiresAt);
                    return issued;
                });
            },
            refreshConnection(grantId) {
                return transaction(() => {
                    const grant = this.get('Delegation', grantId);
                    if (!connectionActive(grant)) throw new errors.InvalidGrant('connection inactive');
                    const updated = { ...grant, lastTokenExchangeAt: Date.now() };
                    this.putUntil('Delegation', grantId, updated, grant.expiresAt);
                    return updated;
                });
            },
            adapter(model) {
                return {
                    upsert: async (id, value, ttl) => store.put(model, id, value, ttl),
                    find: async id => {
                        const active = store.get(model,id);
                        if (active || model !== 'RefreshToken') return active;
                        const entry = store.get('RefreshReplay',replayBucket(id))?.entries[digest(id)];
                        return entry?.expires > Date.now() ? entry.value : undefined;
                    },
                    findByUid: async uid => store.index(model, 'uid', uid),
                    findByUserCode: async code => store.index(model, 'user_code', code),
                    destroy: async id => store.remove(model, id),
                    consume: async id => transaction(() => {
                        const value = store.get(model, id);
                        if (!value || value.consumed) throw new Error('OAUTH_SOURCE_ALREADY_CONSUMED');
                        if (value) {
                            const row = db.prepare('SELECT expires FROM records WHERE model=? AND id=?').get(model, digest(id));
                            const consumed = { ...value, consumed: Math.floor(Date.now() / 1000) };
                            if (model === 'RefreshToken') archiveRefresh(id,consumed,row.expires);
                            else store.putUntil(model,id,consumed,row.expires);
                        }
                    }),
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
                    if (link && !connectionActive(grant) && !connectionIssuable(grant))
                        throw new Error('CONNECTION_REVOKED');
                    // Abandoned login flows expire in ten minutes. Only an
                    // successful code exchange promotes a session to the grant lifetime.
                    if (grant) store.putUntil('Backend', binding, value, grant.lifecycle === 'pending' ? grant.pendingExpiresAt : grant.expiresAt);
                    else store.put('Backend', binding, value, 600);
                },
                remove: async binding => store.remove('Backend', binding),
            },
            async close() { if (closed) return; closed = true; try { db.close(); } finally { release(); } },
        };
        // Detect a wrong/missing key before accepting traffic, even after restart.
        const sentinel = store.get('Metadata', 'encryption');
        if (!sentinel) store.put('Metadata', 'encryption', { version: 1 }, 86400 * 3650);
        if (!store.get('Metadata', 'connection-lifecycle')) transaction(() => {
            for (const grant of store.values('Delegation')) {
                if (!grant.lifecycle) store.putUntil('Delegation', grant.id, { ...grant, lifecycle: 'legacy' }, grant.expiresAt);
            }
            store.put('Metadata', 'connection-lifecycle', { version: 1 }, 86400 * 3650);
        });
        if (!store.get('Metadata','refresh-replay-v1')) transaction(() => {
            // Upgrade preserves the exact provider payload and original expiry,
            // including client/key/resource fields used before reuse detection.
            // Existing unconsumed opaque token strings remain unchanged.
            for (const row of db.prepare("SELECT id,value,expires FROM records WHERE model='RefreshToken' AND expires>?").all(Date.now())) {
                const value=unseal('RefreshToken',row.id,row.value);
                if(value.consumed) archiveRefresh(value.jti,value,row.expires);
            }
            store.put('Metadata','refresh-replay-v1',{version:1},86400*3650);
        });
        return store;
    } catch (e) { try { db?.close(); } finally { release(); } throw e; }
}
