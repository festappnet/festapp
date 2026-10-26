import { offlineGrantValid, isTerminal } from '../../services/scanner_store.js';
export class ScannerController {
    constructor({ api, store, row, sync, onChange = () => {}, online = () => navigator.onLine }) {
        Object.assign(this, { api, store, row, sync, onChange, online }); this.state = 'ready'; this.serial = 0; this.started = performance.now();
    }
    emit() { this.onChange(this); }
    async loadCode(symbol) {
        if (this.state !== 'ready') return;
        if (!symbol || symbol.length > 200 || /^(festapp-login:|https?:)/i.test(symbol)) { this.state='error';this.error = 'wrong_mode'; this.emit(); return; }
        const serial = ++this.serial; this.state = 'looking_up'; this.error = null; this.emit();
        try {
            let ticket;
            if (this.online()) {
                try {ticket=await this.api.lookup(symbol.trim());}
                catch(error){
                    if(error.code || !this.store || !offlineGrantValid(this.row,Date.now(),performance.now()-this.started))throw error;
                    ticket={...await this.store.lookup(this.row.partition,symbol.trim()),source:'offline'};
                }
            }
            else {
                if (!offlineGrantValid(this.row, Date.now(), performance.now() - this.started)) throw new Error('offline_grant_expired');
                ticket = { ...await this.store.lookup(this.row.partition, symbol.trim()), source: 'offline' };
            }
            if (serial !== this.serial) return;
            this.ticket = ticket;
            this.offlineReady = ticket.source==='offline' && offlineGrantValid(this.row);
            let pending = null;
            if (this.store) { try { pending = (await this.store.list('outbox', this.row.partition)).find(r => r.payload.ticket_id === ticket.ticket_id && !isTerminal(r.state)); } catch { this.store = null; } }
            this.operation = pending || null; this.state = pending ? pending.state : 'result';
        } catch (e) { if (serial !== this.serial) return; this.error = e.message; this.state = 'error'; }
        this.emit();
    }
    async confirm(confirmUnpaid = false) {
        if (this.state !== 'result' || !this.ticket?.admission_allowed || !this.store || this.operation) return;
        if (this.ticket.online_required && (!this.online() || this.ticket.source === 'offline')) { this.error = 'online_required'; this.state = 'error'; this.emit(); return; }
        if (this.ticket.source === 'offline' && (!offlineGrantValid(this.row, Date.now(), performance.now() - this.started) || this.ticket.requires_unpaid_confirmation)) return;
        this.state = 'persisting'; this.emit();
        try {
            const payload = {
                operation_id: crypto.randomUUID(), action: 'admit_ticket', ticket_id: this.ticket.ticket_id,
                origin_session_id: this.row.session.session_id, snapshot_id: this.ticket.snapshot_id || null,
                settings_revision: this.ticket.settings_revision, eligibility_fingerprint: this.ticket.eligibility_fingerprint,
                confirm_unpaid: Boolean(confirmUnpaid), captured_at: new Date().toISOString(),
            };
            this.operation = await this.store.enqueue(this.row.partition, payload);
            this.state = 'pending'; this.emit();
            if (this.online()) { this.state = 'awaiting_server'; this.emit(); await this.sync.run(); await this.refreshOperation();
                if (['sending','pending'].includes(this.state) && offlineGrantValid(this.row)) {
                    try {const local=await this.store.lookup(this.row.partition,this.ticket.symbol);this.offlineReady=local.eligibility_fingerprint===this.ticket.eligibility_fingerprint;}catch{this.offlineReady=false;}this.emit();
                } }
        } catch (e) { this.error = 'storage_write_failed'; this.state = 'error'; this.emit(); }
    }
    async refreshOperation() {
        if (!this.operation) return;
        this.operation = await this.store.get('outbox', this.operation.key);
        this.state = this.operation.state; this.emit();
    }
    next() { if (['persisting','looking_up','awaiting_server'].includes(this.state)) return; ++this.serial; this.ticket = null; this.operation = null; this.error = null; this.state = 'ready'; this.offlineReady=false; this.emit(); }
    dispose() { ++this.serial; this.onChange = () => {}; }
}
