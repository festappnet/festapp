const STORES = ['sessions', 'snapshots', 'tickets', 'outbox', 'receipts', 'preferences', 'sync_leases'];
const TERMINAL = new Set(['accepted', 'conflict', 'rejected']);
export const isTerminal = state => TERMINAL.has(state);
export class ScannerStore {
    constructor({ indexedDB = globalThis.indexedDB, name = 'festapp-scanner-v1', now = () => Date.now() } = {}) {
        this.idb = indexedDB; this.name = name; this.now = now;
    }
    async open() {
        if (!this.idb) throw new Error('storage_unavailable');
        this.db = await new Promise((resolve, reject) => {
            const r = this.idb.open(this.name, 1);
            r.onupgradeneeded = () => { for (const name of STORES) if (!r.result.objectStoreNames.contains(name)) r.result.createObjectStore(name, { keyPath: 'key' }); };
            r.onsuccess = () => resolve(r.result);
            r.onerror = () => reject(new Error('storage_unavailable'));
            r.onblocked = () => reject(new Error('storage_upgrade_blocked'));
        });
        this.db.onversionchange = () => { this.close(); };
        await this.put('preferences', { key: 'write-probe', at: this.now() });
        await this.transaction(['snapshots','tickets','preferences'],'readwrite',s=>{
            s.snapshots.getAll().onsuccess=e=>{
                const expired=e.target.result.filter(r=>Date.parse(r.manifest.expires_at)+86400000<this.now());
                for(const row of expired){s.snapshots.delete(row.key);s.preferences.get(`${row.partition}:active-snapshot`).onsuccess=p=>{if(p.target.result?.snapshot_id===row.key)s.preferences.delete(`${row.partition}:active-snapshot`);};}
                if(expired.length)s.tickets.getAll().onsuccess=t=>{for(const row of t.target.result)if(expired.some(x=>x.key===row.snapshot_id))s.tickets.delete(row.key);};
            };
        });
        return this;
    }
    transaction(names, mode, work) {
        return new Promise((resolve, reject) => {
            if (!this.db) { reject(new Error('storage_unavailable')); return; }
            let tx; let result;
            try {
                tx = this.db.transaction(names, mode, { durability: 'strict' });
                result = work(Object.fromEntries(names.map(n => [n, tx.objectStore(n)])));
            } catch (e) { reject(e); return; }
            tx.oncomplete = () => resolve(typeof result === 'function' ? result() : result);
            tx.onerror = tx.onabort = () => reject(tx.error || new Error('storage_write_failed'));
        });
    }
    async get(name, key) { let row; await this.transaction([name], 'readonly', s => { s[name].get(key).onsuccess = e => { row = e.target.result; }; }); return row; }
    put(name, row) { return this.transaction([name], 'readwrite', s => s[name].put(row)); }
    async list(name, partition) { let rows = []; await this.transaction([name], 'readonly', s => { s[name].getAll().onsuccess = e => { rows = e.target.result.filter(r => !partition || r.partition === partition); }; }); return rows; }
    async saveSession(session, backend) {
        const partition = JSON.stringify([backend.generation, backend.origin, backend.organization, session.occasion_id, session.session_id]);
        const row = { key: partition, partition, backend, session, savedAt: this.now(), serverAt: Date.parse(session.server_time), wallAt: this.now(), locked: false };
        await this.put('sessions', row); return row;
    }
    async enqueue(partition, payload) {
        // Duplicate submits/tabs see the same durable operation, without a second pending overlay ledger.
        let saved;
        await this.transaction(['outbox'], 'readwrite', s => {
            s.outbox.getAll().onsuccess = e => {
                saved = e.target.result.find(r => r.partition === partition && r.payload.ticket_id === payload.ticket_id && !isTerminal(r.state));
                if (!saved) { saved = { key: payload.operation_id, partition, payload, schema_version: 1, state: 'pending', attempts: 0, nextAttemptAt: 0 }; s.outbox.add(saved); }
            };
        }); return saved;
    }
    async claimLease(partition, holder, ttl = 15000) {
        let lease = null;
        await this.transaction(['sync_leases'], 'readwrite', s => {
            s.sync_leases.get(partition).onsuccess = e => {
                const old = e.target.result;
                if (!old || old.expiresAt <= this.now() || old.holder === holder) {
                    lease = { key: partition, holder, generation: (old?.generation || 0) + 1, expiresAt: this.now() + ttl };
                    s.sync_leases.put(lease);
                }
            };
        }); return lease;
    }
    async updateOperation(key, patch, lease) {
        let updated = false;
        await this.transaction(['outbox', 'receipts', 'sync_leases'], 'readwrite', s => {
            s.sync_leases.get(lease.key).onsuccess = e => {
                const current = e.target.result;
                if (!current || current.holder !== lease.holder || current.generation !== lease.generation || current.expiresAt <= this.now()) return;
                s.outbox.get(key).onsuccess = e2 => {
                    const op = e2.target.result;
                    if (!op || isTerminal(op.state)) return;
                    if (patch.receipt) s.receipts.put({ key, partition: op.partition, receipt: patch.receipt });
                    s.outbox.put({ ...op, ...patch }); updated = true;
                };
            };
        }); return updated;
    }
    async activateSnapshot(partition, manifest, pages) {
        if (manifest.schema_version !== 1 || manifest.pages.length !== pages.length) throw new Error('snapshot_incomplete');
        const tickets = []; let bytes = 0;
        for (let i = 0; i < pages.length; i++) {
            const page = pages[i], expected = manifest.pages[i];
            const raw = new TextEncoder().encode(page.payload_text);
            const digest = [...new Uint8Array(await crypto.subtle.digest('SHA-256', raw))].map(x => x.toString(16).padStart(2, '0')).join('');
            if (expected.index !== i || page.page_index !== i || digest !== expected.digest || digest !== page.digest) throw new Error('snapshot_digest_mismatch');
            bytes += raw.byteLength; tickets.push(...JSON.parse(page.payload_text));
        }
        if (tickets.length !== manifest.ticket_count || bytes !== manifest.byte_count || new Set(tickets.map(t => t.ticket_id)).size !== tickets.length) throw new Error('snapshot_incomplete');
        await this.transaction(['snapshots', 'tickets', 'preferences'], 'readwrite', s => {
            // No deletion until every page/digest is verified. Pointer and ticket set commit atomically.
            s.tickets.getAll().onsuccess = e => {
                for (const r of e.target.result) if (r.partition === partition) s.tickets.delete(r.key);
                for (const ticket of tickets) s.tickets.put({ key: `${partition}:${ticket.ticket_id}`, partition, ticket, snapshot_id: manifest.snapshot_id });
                s.snapshots.put({ key: manifest.snapshot_id, partition, manifest });
                s.preferences.put({ key: `${partition}:active-snapshot`, partition, snapshot_id: manifest.snapshot_id });
            };
        }); return manifest;
    }
    async snapshot(partition) {
        const pointer = await this.get('preferences', `${partition}:active-snapshot`);
        return pointer ? (await this.get('snapshots', pointer.snapshot_id))?.manifest : null;
    }
    async lookup(partition, symbol) {
        const snapshot = await this.snapshot(partition);
        if (!snapshot || Date.parse(snapshot.expires_at) <= this.now()) throw new Error('offline_grant_expired');
        const row = (await this.list('tickets', partition)).find(r => r.ticket.symbol === symbol);
        if (!row) throw new Error('offline_not_found');
        // Only a receipt for this exact snapshot generation can provide a used
        // overlay. A newer snapshot after admin unused has a different fingerprint.
        const accepted=(await this.list('outbox',partition)).find(op=>op.payload.ticket_id===row.ticket.ticket_id
            && op.state==='accepted' && op.receipt?.eligibility_fingerprint===row.ticket.eligibility_fingerprint
            && Date.parse(op.receipt.committed_at)>=Date.parse(snapshot.server_time));
        return { ...row.ticket, ...(accepted?{state:'used',admission_allowed:false,updated_at:accepted.receipt.committed_at}:{}), snapshot_id: snapshot.snapshot_id, settings_revision: snapshot.settings_revision };
    }
    async lockSession(partition) {
        const row = await this.get('sessions', partition);
        await this.transaction(['sessions', 'tickets', 'preferences'], 'readwrite', s => {
            s.sessions.put({ ...row, locked: true });
            s.preferences.delete(`${partition}:active-snapshot`);
            s.tickets.getAll().onsuccess = e => { for (const r of e.target.result) if (r.partition === partition) s.tickets.delete(r.key); };
        });
    }
    close() { this.db?.close(); this.db = null; }
}
export function offlineGrantValid(row, now = Date.now(), elapsed = 0) {
    if (!row || row.locked || !Number.isFinite(row.serverAt) || now < row.wallAt - 1000) return false;
    const anchoredNow = row.serverAt + Math.max(now - row.wallAt, elapsed);
    return anchoredNow < Date.parse(row.session.offline_until) && now - row.wallAt < 12 * 3600000;
}
