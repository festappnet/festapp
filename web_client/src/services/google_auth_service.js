import { helpActionFromWebPath, helpActionWebPath } from './help_action_routes.js';
import { AppConfig } from '../app_config.js';
import { SupabaseService } from './supabase_service.js';
import { AuthService } from './auth_service.js';
import { organizerCreatePath } from './organizer_entry.js';

export function safeAuthReturnPath(value) {
    const organizer = organizerCreatePath(value);
    if (organizer) return organizer;
    const help = helpActionFromWebPath(value);
    if (help) return helpActionWebPath(help);
    // Other query continuations must match their own exact first-party contract.
    if (typeof value === 'string' && /^\/settings\/mcp-connect\?request=[A-Za-z0-9_-]{43}$/.test(value)) return value;
    return typeof value === 'string' && /^\/(?!\/)[A-Za-z0-9/_-]*$/.test(value) && !value.includes('..') ? value : '/';
}
const key = 'festapp-google-attempt-v1';
const encode = bytes => btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
export class GoogleAuthService {
    static _completing = null;
    static _pending = null;
    static clientId() { return `${AppConfig.organization}:web:${window.location.origin}`; }
    static async request(endpoint, body) {
        const { data, error } = await SupabaseService.getClient().functions.invoke(`google-auth-${endpoint}`, {
            body: { ...body, organization: AppConfig.organization, clientId: this.clientId() },
        });
        if (error || data?.error) {
            let code = data?.error;
            if (!code && error?.context?.json) {
                try { code = (await error.context.json()).error; } catch { /* no public error */ }
            }
            throw new Error(code || 'auth_temporarily_unavailable');
        }
        return data;
    }
    static identityStatus() { return this.request('start', { operation: 'identity_status' }); }
    static async capability() {
        try { return (await this.request('start', { operation: 'capability' })).enabled === true; } catch { return false; }
    }
    static async start(intent = "login") {
        const verifier = encode(crypto.getRandomValues(new Uint8Array(32)));
        const challenge = encode(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
        const data = await this.request('start', { challenge, intent });
        const destination = new URL(data.url);
        const backend = new URL(SupabaseService._backend.supabaseUrl);
        if (destination.origin !== backend.origin || destination.pathname !== '/functions/v1/google-auth-start') throw new Error('invalid_provider_proof');
        const path = window.location.pathname + window.location.search;
        const returnPath = organizerCreatePath(path) ||
            (window.location.pathname === '/settings/mcp-connect' || helpActionFromWebPath(path) ? path : window.location.pathname);
        sessionStorage.setItem(key, JSON.stringify({ attempt: data.attempt, verifier, expires: Date.now() + 600000, returnPath: safeAuthReturnPath(returnPath) }));
        window.location.assign(destination.href);
    }
    static takeCallback() {
        const url = new URL(window.location.href);
        if (!url.searchParams.has('google_code') && !url.searchParams.has('google_error')) return null;
        const callback = { code: url.searchParams.get('google_code'), attempt: url.searchParams.get('google_attempt'), error: url.searchParams.get('google_error') };
        for (const name of ['google_code', 'google_attempt', 'google_error']) url.searchParams.delete(name);
        let organizer;
        try {
            const pending = JSON.parse(sessionStorage.getItem(key));
            if (pending?.attempt === callback.attempt && pending.expires > Date.now()) {
                organizer = organizerCreatePath(pending.returnPath);
            }
        } catch { /* Missing or invalid tab state cannot select a continuation. */ }
        // Keep the known workflow even if Google is cancelled or account proof
        // fails and the user switches to ordinary email sign-in in this dialog.
        history.replaceState(history.state, '', organizer || url.pathname + url.search + url.hash);
        return callback;
    }
    static complete(callback) {
        if (!this._completing) this._completing = this._complete(callback).finally(() => { this._completing = null; });
        return this._completing;
    }
    static async _complete(callback) {
        let pending;
        try { pending = JSON.parse(sessionStorage.getItem(key)); } catch { /* invalid storage */ }
        sessionStorage.removeItem(key);
        if (callback.error) throw new Error(callback.error === 'provider_cancelled' ? 'provider_cancelled' : 'invalid_provider_proof');
        if (!pending || pending.expires <= Date.now() || pending.attempt !== callback.attempt) throw new Error('attempt_expired');
        this._pending = pending; // continuation exists only in memory
        const result = await this.request('complete', { ...pending, operation: 'claim', code: callback.code });
        return await this._accept(result);
    }
    static async advance(operation, payload = {}) {
        if (!this._pending || this._pending.expires <= Date.now()) throw new Error('attempt_expired');
        if (this._completing) return this._completing;
        this._completing = this.request('complete', { ...this._pending, operation, ...payload })
            .then(result => this._accept(result)).finally(() => { this._completing = null; });
        return this._completing;
    }
    static async _accept(result) {
        if (result.status === 'unlinked') {
            const returnPath = this._pending.returnPath;
            this._pending = null;
            return { ...result, returnPath };
        }
        if (result.status === 'authenticated') {
            await AuthService.completeExternalLogin(result);
            const returnPath = this._pending.returnPath;
            this._pending = null;
            return { ...result, returnPath };
        }
        this._pending.continuation = result.continuation;
        return result;
    }
    static cancel() { sessionStorage.removeItem(key); this._pending = null; }
}
