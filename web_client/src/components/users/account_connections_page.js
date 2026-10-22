import { SupabaseService } from '../../services/supabase_service.js';
import { GoogleAuthService } from '../../services/google_auth_service.js';
import { LocalizationService } from '../../services/localization_service.js';
import { CommonStrings } from '../shared/common_strings.js';
import { AppConfig } from '../../app_config.js';

const permissionLabels = { 'festapp:orders:read': 'ordersRead', 'festapp:orders:write': 'ordersWrite',
    'festapp:payments:write': 'paymentsWrite', 'festapp:tickets:send': 'ticketsSend' };

/** One account surface, with independent identity and delegation owners. */
export class AccountConnectionsPage {
    constructor(container, { client = SupabaseService.getClient(), google = GoogleAuthService,
        login = async () => { const { LoginModal } = await import('./login_modal.js'); document.body.appendChild(new LoginModal()); } } = {}) {
        this.container = container; this.client = client; this.google = google; this.login = login;
        this.generation = 0; this.state = 'loading'; this.appsState = 'loading'; this.googleState = 'loading';
    }
    text(key, args = {}) { return LocalizationService.tr(`AccountConnections.${key}`, args); }
    dispose() { this.generation++; this.subscription?.unsubscribe(); this.subscription = null; }
    async init() {
        const generation = ++this.generation;
        this.state = 'loading'; this.appsState = 'loading'; this.googleState = 'loading';
        this.connections = []; this.googleStatus = null; this.pendingRevoke = null;
        this.revoking = false; this.googleBusy = false; this.actionError = null; this.notice = null; this.googleActionFailed = false; this.render();
        if (!this.subscription) this.subscription = this.client.auth.onAuthStateChange?.((event, session) => {
            if (event === 'SIGNED_OUT') {
                this.generation++; this.user = null; this.connections = []; this.state = 'login'; this.render();
            } else if (event === 'SIGNED_IN' && this.user?.id !== session?.user?.id) {
                queueMicrotask(() => { if (this.subscription) void this.init(); });
            }
        })?.data?.subscription;
        try {
            const { data, error } = await this.client.auth.getSession();
            if (generation !== this.generation) return;
            if (error) throw error;
            this.user = data.session?.user;
            this.state = this.user ? 'ready' : 'login';
        } catch { if (generation !== this.generation) return; this.state = 'error'; }
        this.render();
        if (this.state === 'ready') await Promise.all([this.loadApps(generation), this.loadGoogle(generation)]);
    }
    async call(operation, connectionId) {
        const { data, error } = await this.client.functions.invoke('mcp-session-exchange', {
            body: { operation, ...(connectionId ? { connectionId } : {}) },
        });
        if (error || data?.error || !data) throw new Error('Connection management failed');
        return data;
    }
    async loadApps(generation = this.generation) {
        this.appsState = 'loading'; this.actionError = null; this.render();
        try {
            const data = await this.call('connections.list');
            if (generation !== this.generation) return;
            if (!Array.isArray(data.connections) || data.connections.some(c =>
                typeof c.id !== 'string' || !/^[A-Za-z0-9_-]{1,200}$/.test(c.id) || typeof c.client !== 'string' ||
                !Number.isFinite(Date.parse(c.expiresAt)) || !Array.isArray(c.access?.units) || !Array.isArray(c.access?.occasionIds) ||
                c.access.units.some(u => !u || !Number.isSafeInteger(u.unitId) || u.unitId <= 0 || typeof u.canCreateOccasions !== 'boolean') ||
                c.access.occasionIds.some(id => !Number.isSafeInteger(id) || id <= 0) ||
                !Array.isArray(c.permissions) || c.permissions.some(p => !Object.hasOwn(permissionLabels, p)))) throw new Error();
            this.connections = data.connections; this.appsState = 'ready';
        } catch { if (generation !== this.generation) return; this.connections = []; this.appsState = 'error'; }
        this.render();
    }
    async loadGoogle(generation = this.generation) {
        this.googleState = 'loading'; this.render();
        try {
            const status = await this.google.identityStatus();
            if (generation !== this.generation) return;
            if (typeof status.enabled !== 'boolean' || (status.enabled && typeof status.linked !== 'boolean')) throw new Error();
            this.googleStatus = status; this.googleState = 'ready';
        } catch { if (generation !== this.generation) return; this.googleState = 'error'; }
        this.render();
    }
    async startGoogle() {
        if (this.googleBusy || this.googleState !== 'ready' || !this.googleStatus?.enabled) return;
        const generation = this.generation; this.googleBusy = true; this.googleActionFailed = false; this.render();
        try { await this.google.start(this.googleStatus.linked ? 'unlink' : 'login'); }
        catch { if (generation === this.generation) this.googleActionFailed = true; }
        if (generation === this.generation) { this.googleBusy = false; this.render(); }
    }
    async revoke(id) {
        if (this.revoking || this.pendingRevoke !== id || !this.connections.some(c => c.id === id)) return;
        const generation = this.generation; this.revoking = true; this.actionError = null; this.render();
        try {
            const result = await this.call('connections.revoke', id);
            if (generation !== this.generation) return;
            if (result.connectionId !== id || result.revoked !== true) throw new Error();
            this.connections = this.connections.filter(c => c.id !== id); this.pendingRevoke = null;
            this.notice = this.text('revoked');
        } catch { if (generation !== this.generation) return; this.actionError = this.text('error'); }
        this.revoking = false; this.render();
        this.container.querySelector('[data-apps-heading]')?.focus();
    }
    render() {
        const root = document.createElement('main'); root.className = 'account-connections';
        const add = (tag, text = '', parent = root) => { const el = document.createElement(tag); el.textContent = text; parent.append(el); return el; };
        const button = (label, action, parent, disabled = false) => { const el = add('button', label, parent); el.type = 'button'; el.disabled = disabled; el.onclick = action; return el; };
        add('h1', CommonStrings.accountConnections);
        const back = add('a', CommonStrings.back); back.href = '/';
        if (this.state === 'loading') add('p', CommonStrings.loading).setAttribute('role', 'status');
        else if (this.state === 'login') {
            add('p', this.text('loginHint'));
            button(CommonStrings.signIn, () => this.login());
        } else if (this.state === 'error') {
            add('p', this.text('error')).setAttribute('role', 'alert');
            button(CommonStrings.retry, () => this.init());
        } else {
            add('p', (this.user.email ?? '').replace(new RegExp(`^${AppConfig.organization}\\+`), ''));
            add('p', this.text('intro'));
            const methods = add('section'); methods.setAttribute('aria-labelledby', 'account-signin-heading');
            add('h2', this.text('signInMethods'), methods).id = 'account-signin-heading';
            add('p', this.text('googleHint'), methods);
            if (this.googleState === 'loading') add('p', CommonStrings.loading, methods).setAttribute('role', 'status');
            else if (this.googleState === 'error') {
                add('p', this.text('error'), methods).setAttribute('role', 'alert');
                button(CommonStrings.retry, () => this.loadGoogle(), methods);
            } else if (!this.googleStatus?.enabled) add('p', this.text('googleUnavailable'), methods);
            else {
                add('h3', 'Google', methods);
                add('p', this.text(this.googleStatus.linked ? 'googleLinked' : 'googleUnlinked'), methods);
                if (this.googleActionFailed) add('p', this.text('error'), methods).setAttribute('role', 'alert');
                const action = button(this.text(this.googleStatus.linked ? 'unlinkGoogle' : 'linkGoogle'), () => this.startGoogle(), methods, this.googleBusy);
                action.dataset.googleAction = '';
            }
            const apps = add('section'); apps.id = 'apps'; apps.setAttribute('aria-labelledby', 'account-apps-heading');
            const heading = add('h2', this.text('apps'), apps); heading.id = 'account-apps-heading'; heading.tabIndex = -1; heading.dataset.appsHeading = '';
            add('p', this.text('appsHint'), apps);
            if (this.notice) add('p', this.notice, apps).setAttribute('role', 'status');
            if (this.actionError) add('p', this.actionError, apps).setAttribute('role', 'alert');
            if (this.appsState === 'loading') add('p', CommonStrings.loading, apps).setAttribute('role', 'status');
            else if (this.appsState === 'error') {
                add('p', this.text('error'), apps).setAttribute('role', 'alert');
                button(CommonStrings.retry, () => this.loadApps(), apps);
            } else if (!this.connections.length) add('p', this.text('empty'), apps);
            else for (const c of this.connections) {
                const item = add('article', '', apps); item.className = 'account-connection';
                add('h3', c.client, item);
                add('p', this.text('expires', { date: new Intl.DateTimeFormat(LocalizationService.currentLocale, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(c.expiresAt)) }), item);
                const scope = add('ul', '', item);
                for (const unit of c.access.units) add('li', this.text(unit.canCreateOccasions ? 'organizerCreate' : 'organizer', { id: unit.unitId }), scope);
                for (const id of c.access.occasionIds) add('li', this.text('occasion', { id }), scope);
                if (c.permissions.length) {
                    const permissions = add('ul', '', item);
                    for (const p of c.permissions) add('li', LocalizationService.tr(`McpConnection.${permissionLabels[p]}`), permissions);
                }
                if (this.pendingRevoke === c.id) {
                    add('p', this.text('revokeConfirm', { client: c.client }), item);
                    const confirm = button(this.text('revoke'), () => this.revoke(c.id), item, this.revoking); confirm.dataset.confirmRevoke = '';
                    button(this.text('cancel'), () => { this.pendingRevoke = null; this.render(); this.container.querySelector(`[data-revoke="${c.id}"]`)?.focus(); }, item, this.revoking);
                } else {
                    const action = button(this.text('revoke'), () => { this.pendingRevoke = c.id; this.render(); this.container.querySelector('[data-confirm-revoke]')?.focus(); }, item, this.revoking);
                    action.dataset.revoke = c.id;
                }
            }
        }
        const style = document.createElement('style');
        style.textContent = `.account-connections{max-width:720px;margin:32px auto;padding:24px;color:var(--text-color,inherit);overflow-wrap:anywhere}.account-connections a{color:inherit;text-decoration:underline;text-underline-offset:3px}.account-connections h1{font-size:2rem}.account-connections h2{font-size:1.25rem}.account-connections h3{font-size:1.125rem}.account-connections section{margin-block:32px;padding-block-start:16px;border-block-start:1px solid currentColor}.account-connections p,.account-connections li{line-height:1.6}.account-connections ul{padding-inline-start:24px}.account-connection{margin-block:24px;padding-block-end:16px;border-block-end:1px solid currentColor}.account-connections button{font:inherit;min-height:44px;padding:10px 20px;margin:8px 12px 8px 0;border-radius:24px;cursor:pointer}.account-connections button:disabled{cursor:wait}.account-connections :focus-visible{outline:3px solid var(--primary-color,#273f65);outline-offset:3px}`;
        this.container.hidden = false; this.container.style.display = 'block'; this.container.replaceChildren(style, root);
    }
}
