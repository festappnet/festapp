import { isTerminal } from './scanner_store.js';
export class ScannerSync {
    constructor({ store, api, partition, onChange = () => {}, now = () => Date.now(), random = Math.random }) {
        Object.assign(this, { store, api, partition, onChange, now, random }); this.holder = crypto.randomUUID(); this.stopped = false;
    }
    run() {
        if (this.running || this.stopped) return this.running;
        this.running = this.drain().finally(() => { this.running = null; }); return this.running;
    }
    async drain() {
        const started = performance.now();
        const lease = await this.store.claimLease(this.partition, this.holder);
        if (!lease) return;
        const blocked = (await this.store.list('outbox', this.partition)).filter(r=>r.state==='blocked_auth');
        for(let i=0;i<blocked.length;i+=50) {
            const current=await this.store.claimLease(this.partition,this.holder);if(!current)return;
            try {for(const receipt of await this.api.receipts(blocked.slice(i,i+50).map(r=>r.key)))await this.store.updateOperation(receipt.operation_id,{state:receipt.outcome,receipt},current);} catch {return;}
        }
        const pending = (await this.store.list('outbox', this.partition)).filter(r => !isTerminal(r.state) && !['blocked_auth','blocked_schema'].includes(r.state) && r.nextAttemptAt <= this.now());
        for (let i = 0; i < pending.length && !this.stopped; i += 50) {
            // Renew before each bounded RPC. Every write checks the fencing generation.
            let currentLease = await this.store.claimLease(this.partition, this.holder);
            if (!currentLease) return;
            const candidates = pending.slice(i, i + 50);
            for(const row of candidates)if(row.schema_version && row.schema_version!==1)await this.store.updateOperation(row.key,{state:'blocked_schema',lastError:'incompatible_operation_schema'},currentLease);
            const batch=candidates.filter(row=>!row.schema_version || row.schema_version===1);
            if(!batch.length)continue;
            try {
                const uncertain = batch.filter(r => r.state === 'sending');
                const recovered = uncertain.length ? await this.api.receipts(uncertain.map(r => r.key)) : [];
                for (const receipt of recovered) await this.store.updateOperation(receipt.operation_id, { state: receipt.outcome, receipt }, currentLease);
                const unresolved = batch.filter(r => !recovered.some(x => x.operation_id === r.key));
                if (unresolved.length) {
                    currentLease = await this.store.claimLease(this.partition, this.holder);
                    if (!currentLease) return;
                    for (const row of unresolved) await this.store.updateOperation(row.key, { state: 'sending', attempts: row.attempts + 1 }, currentLease);
                    const receipts = await this.api.sync(unresolved.map(r => r.payload));
                    if(this.stopped)return;
                    for (const receipt of receipts) await this.store.updateOperation(receipt.operation_id, { state: receipt.outcome, receipt }, currentLease);
                }
            } catch (error) {
                if(this.stopped)return;
                const auth = [401, 403].includes(error.code);
                for (const row of batch) await this.store.updateOperation(row.key, {
                    state: auth ? 'blocked_auth' : error.code===400 ? 'blocked_schema' : 'sending', lastError: error.message,
                    attempts: row.attempts + 1, nextAttemptAt: this.now() + Math.max(error.retryAfter || 0, Math.min(30000, 1000 * 2 ** Math.min(row.attempts, 5)) * (0.8 + this.random() * 0.4)),
                }, currentLease);
                await this.onChange({ error: error.message, auth }); break;
            }
        }
        if(!this.stopped)await this.onChange({ latency: performance.now() - started });
    }
    stop() { this.stopped = true; }
}
