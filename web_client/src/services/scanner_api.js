export class ScannerError extends Error {
    constructor(reason, code = 0, retryAfter = 0) { super(reason); this.code = Number(code); this.retryAfter = retryAfter; }
}
export class ScannerApi {
    constructor(client, session = null, timeout = 10000) { this.client = client; this.session = session; this.timeout = timeout; }
    async call(name, params = {}, scoped = true) {
        const abort = new AbortController(); const timer = setTimeout(() => abort.abort(), this.timeout);
        try {
            let query = this.client.rpc(name, { ...(scoped ? { p_session: this.session.session_id, p_token: this.session.token } : {}), ...params });
            if (query.abortSignal) query = query.abortSignal(abort.signal);
            const { data, error } = await Promise.race([query,new Promise((_,reject)=>abort.signal.addEventListener('abort',()=>reject(new ScannerError('timeout')),{once:true}))]);
            if (error) throw new ScannerError(error.message || 'transport_error', error.code?.startsWith('PT') ? error.code.slice(2) : error.code==='42501' ? 403 : error.code?.startsWith('22') ? 400 : error.status || 0);
            if (data?.code !== 200) throw new ScannerError(data?.reason || data?.message || 'rpc_failed', data?.code, data?.retry_after_ms);
            return data;
        } catch (e) { if (e instanceof ScannerError) throw e; throw new ScannerError(abort.signal.aborted ? 'timeout' : 'network_error'); }
        finally { clearTimeout(timer); }
    }
    async open(params) { const r = await this.call('open_scanner_session', params, false); this.session = { ...r.data, server_time: r.server_time }; return this.session; }
    async lookup(symbol) { const r = await this.call('lookup_scanner_ticket', { p_symbol: symbol }); return { ...r.data, settings_revision: r.settings_revision, source: 'online' }; }
    async search(query, after = 0) { return (await this.call('search_scanner_tickets', { p_query: query, p_after: after })).data; }
    async receipts(ids) { return (await this.call('get_scanner_receipts', { p_operation_ids: ids })).data; }
    async sync(operations) { return (await this.call('sync_scanner_operations', { p_operations: operations })).data; }
    async summary() { return (await this.call('get_scanner_summary')).data; }
    async prepare(store, partition) {
        const manifest = (await this.call('prepare_scanner_snapshot')).data;
        const pages = [];
        for (const page of manifest.pages) pages.push((await this.call('get_scanner_snapshot_page', { p_snapshot: manifest.snapshot_id, p_page: page.index })).data);
        return store.activateSnapshot(partition, manifest, pages);
    }
}
