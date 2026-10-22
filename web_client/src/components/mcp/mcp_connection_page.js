import { AppConfig } from '../../app_config.js';
import { SupabaseService } from '../../services/supabase_service.js';
import { LocalizationService } from '../../services/localization_service.js';

const orderPermissions = { 'festapp:orders:read': 'ordersRead', 'festapp:orders:write': 'ordersWrite', 'festapp:payments:write': 'paymentsWrite', 'festapp:tickets:send': 'ticketsSend' };

export const MCP_CONNECTION_PATH = '/settings/mcp-connect';

export function mcpResumeUrl(value) {
    const url = new URL(value);
    if (url.origin !== 'https://mcp.festapp.net' || url.username || url.password || url.hash ||
        !/^\/connect\/[A-Za-z0-9_-]+\/finish$/.test(url.pathname) ||
        [...url.searchParams].length !== 1 ||
        !/^[A-Za-z0-9_-]{43}$/.test(url.searchParams.get('resume') || '')) {
        throw new Error('Invalid connection continuation');
    }
    return url.href;
}

/** Tenant-owned consent; all permissions and minting stay in mcp-session-exchange. */
export class McpConnectionPage {
    constructor(container, { client = SupabaseService.getClient(), browser = window,
        resume = mcpResumeUrl, login = async () => {
            const { LoginModal } = await import('../users/login_modal.js');
            document.body.appendChild(new LoginModal());
        }, pause = () => new Promise(resolve => setTimeout(resolve, 1000)) } = {}) {
        this.container = container;
        this.client = client;
        this.browser = browser;
        this.login = login;
        this.resume = resume;
        this.pause = pause;
        this.request = new URL(browser.location.href).searchParams.get('request');
        this.selected = new Set();
        this.selectedUnits = new Map();
        this.selectedPermissions = new Set();
        this.generation = 0;
        this.busy = false;
        this.state = 'loading';
    }

    text(key, args = {}) { return LocalizationService.tr(`McpConnection.${key}`, args); }

    async call(operation) {
        const { data, error } = await this.client.functions.invoke('mcp-session-exchange', {
            body: { request: this.request, operation, ...(operation === 'approve' ? { access: this.selectedPermissions.size ? { consentVersion: 2, selection: this.access, permissions: [...this.selectedPermissions] } : this.access } : {}) },
        });
        if (error || data?.error || !data) throw new Error('Connection failed');
        return data;
    }

    get access() {
        if (!this.selectedUnits.size) return { type: 'occasions', occasionIds: [...this.selected] };
        return { type: 'selection', units: [...this.selectedUnits].map(([unitId, canCreateOccasions]) =>
            ({ unitId, canCreateOccasions })), occasionIds: [...this.selected] };
    }

    get canApprove() {
        const ids = new Set((this.details?.occasions || []).map(o => o.id));
        const units = this.details?.units || [];
        if ([...this.selectedPermissions].some(p => !this.details?.requestedPermissions?.includes(p))) return false;
        return this.selected.size + this.selectedUnits.size > 0 && this.selected.size <= 100 && this.selectedUnits.size <= 100 &&
            [...this.selected].every(id => ids.has(id)) && [...this.selectedUnits].every(([id, create]) =>
                units.some(u => u.id === id && (!create || (this.details.canRequestCreate && u.canCreateOccasions))));
    }

    dispose() { this.generation++; }

    async init() {
        const generation = ++this.generation;
        this.container.hidden = false;
        this.container.style.display = 'block';
        if (!/^[A-Za-z0-9_-]{43}$/.test(this.request || '')) {
            this.state = 'invalid';
            this.render();
            return;
        }
        this.render();
        try {
            const { data, error } = await this.client.auth.getSession();
            if (generation !== this.generation) return;
            if (error) throw error;
            this.user = data.session?.user;
            if (!this.user) this.state = 'login';
            else {
                const details = await this.call('details');
                if (generation !== this.generation) return;
                this.details = details;
                if (!Array.isArray(this.details.occasions) || this.details.occasions.some(o => !Number.isSafeInteger(o.id))) {
                    throw new Error('Invalid occasions');
                }
                // A refreshed event list cannot retain an approval for a removed event.
                const ids = new Set(this.details.occasions.map(o => o.id));
                this.selected = new Set([...this.selected].filter(id => ids.has(id)));
                const units = this.details.units || [];
                if (!Array.isArray(units) || units.some(u => !Number.isSafeInteger(u.id))) throw new Error('Invalid units');
                for (const [id, create] of this.selectedUnits) {
                    const unit = units.find(u => u.id === id);
                    if (!unit) this.selectedUnits.delete(id);
                    else this.selectedUnits.set(id, create && this.details.canRequestCreate === true && unit.canCreateOccasions === true);
                }
                const permissions = this.details.requestedPermissions ?? [];
                if (!Array.isArray(permissions) || permissions.some(p => !Object.hasOwn(orderPermissions, p))) throw new Error('Invalid permissions');
                this.selectedPermissions = new Set([...this.selectedPermissions].filter(p => permissions.includes(p)));
                if (!this.selectedPermissions.has('festapp:orders:read')) this.selectedPermissions.clear();
                this.state = 'consent';
            }
        } catch { if (generation !== this.generation) return; this.state = 'error'; }
        this.render();
    }

    async finish(operation) {
        if (this.busy || (operation === 'approve' && (this.state !== 'consent' || !this.canApprove))) return;
        const generation = this.generation;
        // Create synchronously from the approval gesture, then sever the opener.
        const callback = operation === 'approve' && this.details?.applicationType === 'native'
            ? this.browser.open('about:blank', '_blank', 'popup,width=520,height=640') : null;
        if (callback) callback.opener = null;
        this.busy = true;
        this.render();
        let dispatched = false;
        try {
            const result = await this.call(operation);
            if (generation !== this.generation) { callback?.close(); return; }
            const destination = this.resume(result.resumeUrl);
            if (!callback) {
                this.browser.location.assign(destination);
                return;
            }
            callback.location.replace(destination);
            dispatched = true;
            this.state = 'waitingForClient';
            this.render();
            for (let attempt = 0; attempt < 60; attempt++) {
                const status = await this.call('status');
                if (generation !== this.generation) { callback?.close(); return; }
                if (status.status === 'connected') {
                    try { callback.close(); } catch { /* Verified completion already owns the result. */ }
                    this.state = 'connected';
                    this.busy = false;
                    this.render();
                    return;
                }
                if (status.status !== 'pending') break;
                await this.pause();
            }
            this.state = 'completionUnknown';
        } catch {
            if (generation !== this.generation) { callback?.close(); return; }
            if (!dispatched) callback?.close();
            // Losing observation after dispatch must never offer another approval.
            this.state = dispatched ? 'completionUnknown' : 'error';
        }
        this.busy = false;
        this.render();
    }

    render() {
        const root = document.createElement('section');
        root.className = 'mcp-connection';
        root.setAttribute('aria-busy', String(this.busy || this.state === 'loading'));
        const add = (tag, text, parent = root) => {
            const element = document.createElement(tag);
            element.textContent = text;
            parent.appendChild(element);
            return element;
        };
        const button = (key, action, disabled = false) => {
            const element = add('button', this.text(key));
            element.type = 'button';
            element.disabled = this.busy || disabled;
            element.addEventListener('click', action);
            return element;
        };
        add('h1', this.text(this.state === 'connected' ? 'connected' : 'heading'));
        if (this.state === 'consent') {
            add('h2', this.text('client', { client: this.details.client }));
            add('p', this.user.email?.replace(new RegExp(`^${AppConfig.organization}\\+`), '') || '');
            add('p', this.text('treeScope'));
            const fieldset = add('fieldset', '');
            fieldset.disabled = this.busy;
            add('legend', this.text('choose'), fieldset);
            const occasions = this.details.occasions;
            const checkbox = (title, checked, action, parent = fieldset) => {
                const label = add('label', '', parent);
                const input = document.createElement('input');
                input.type = 'checkbox';
                input.checked = checked;
                input.addEventListener('change', action);
                label.appendChild(input);
                add('span', title, label);
                return input;
            };
            const units = this.details.units || [];
            if (occasions.length > 100) add('p', this.text('selectionLimit'), fieldset);
            if (occasions.length) {
                const all = !this.selectedUnits.size && occasions.every(o => this.selected.has(o.id));
                const bulk = checkbox(this.text('selectAll'), all, () => {
                    this.selected.clear(); this.selectedUnits.clear();
                    if (!all) occasions.forEach(o => this.selected.add(o.id));
                    this.render();
                    this.container.querySelector('[data-select-all]')?.focus();
                });
                bulk.dataset.selectAll = '';
                bulk.disabled = occasions.length > 100;
                bulk.indeterminate = !all && (this.selected.size > 0 || this.selectedUnits.size > 0);
            }
            const groups = new Map(units.map(u => [u.id, { unit: u, occasions: [] }]));
            for (const occasion of occasions) {
                if (!groups.has(occasion.unitId)) groups.set(occasion.unitId, { occasions: [] });
                groups.get(occasion.unitId).occasions.push(occasion);
            }
            const title = ([id, group]) => group.unit?.title || `${this.text('organizer')}${id ? ` #${id}` : ''}`;
            const compare = new Intl.Collator(undefined, { sensitivity: 'base' }).compare;
            for (const [id, group] of [...groups].sort((a, b) => compare(title(a), title(b)) || (a[0] || 0) - (b[0] || 0))) {
                const section = add('div', '', fieldset);
                section.className = 'mcp-organizer';
                const heading = add('h3', '', section);
                const whole = this.selectedUnits.has(id);
                const creates = whole ? this.selectedUnits.get(id) : this.details.canRequestCreate === true && group.unit?.canCreateOccasions === true;
                const parent = checkbox(title([id, group]), whole, () => {
                    if (whole) this.selectedUnits.delete(id);
                    else {
                        this.selectedUnits.set(id, creates);
                        group.occasions.forEach(o => this.selected.delete(o.id));
                    }
                    this.render();
                    this.container.querySelector(`[data-unit="${id}"]`)?.focus();
                }, heading);
                parent.dataset.unit = id ?? '';
                parent.disabled = !group.unit || (!whole && this.selectedUnits.size >= 100);
                parent.indeterminate = !whole && group.occasions.some(o => this.selected.has(o.id));
                heading.querySelector('span').dataset.unitHeading = id ?? '';
                const hint = add('p', this.text(!group.unit ? 'individualOnlyHint' : creates ? 'organizerCreateHint' : 'organizerReadHint'), section);
                hint.className = 'mcp-organizer-hint';
                hint.id = `mcp-unit-hint-${id ?? 'individual'}`;
                parent.setAttribute('aria-describedby', hint.id);
                const children = add('div', '', section);
                children.className = 'mcp-organizer-occasions';
                for (const occasion of [...group.occasions].sort((a, b) => compare(a.title, b.title) || a.id - b.id)) {
                    const input = checkbox(occasion.title, whole || this.selected.has(occasion.id), () => {
                        if (input.checked) this.selected.add(occasion.id);
                        else this.selected.delete(occasion.id);
                        this.render();
                        this.container.querySelector(`[data-occasion="${occasion.id}"]`)?.focus();
                    }, children);
                    input.dataset.occasion = occasion.id;
                    input.disabled = whole || (!input.checked && this.selected.size >= 100);
                }
            }
            const permissions = this.details.requestedPermissions || [];
            if (permissions.length) {
                const permissionFields = add('fieldset', '');
                permissionFields.disabled = this.busy;
                add('legend', this.text('orderPermissions'), permissionFields);
                add('p', this.text('orderPermissionsHint'), permissionFields);
                for (const scope of permissions) {
                    const input = checkbox(this.text(orderPermissions[scope]), this.selectedPermissions.has(scope), () => {
                        if (input.checked) {
                            this.selectedPermissions.add('festapp:orders:read');
                            this.selectedPermissions.add(scope);
                        } else if (scope === 'festapp:orders:read') this.selectedPermissions.clear();
                        else this.selectedPermissions.delete(scope);
                        this.render();
                        this.container.querySelector(`[data-permission="${scope}"]`)?.focus();
                    }, permissionFields);
                    input.dataset.permission = scope;
                    input.disabled = scope !== 'festapp:orders:read' && !permissions.includes('festapp:orders:read');
                }
            }
            add('p', this.text('duration'));
            button(this.busy ? 'connecting' : 'approve', () => this.finish('approve'), !this.canApprove);
            button('cancel', () => this.finish('cancel'));
        } else if (this.state === 'login') {
            add('p', this.text('loginHint'));
            button('login', () => this.login());
            button('cancel', () => this.finish('cancel'));
        } else if (this.state === 'connected') {
            add('p', this.text('connectedClient', { client: this.details.client }));
            add('p', this.text('closeHint'));
            button('closeWindow', () => this.browser.close());
            const back = add('a', this.text('backToTenant', { tenant: AppConfig.appName }));
            back.href = '/';
        } else {
            const message = add('p', this.text(this.state === 'loading' ? 'connecting' : this.state));
            message.setAttribute('role', this.state === 'error' ? 'alert' : 'status');
            if (this.state === 'error') button('retry', () => this.init());
        }
        const style = document.createElement('style');
        style.textContent = `.mcp-connection{max-width:640px;margin:32px auto;padding:24px;color:var(--text-color,inherit)}.mcp-connection h1{font-size:2rem}.mcp-organizer{margin-block:24px}.mcp-organizer h3{font-size:1.125rem;margin:0}.mcp-organizer-hint{margin:0 0 8px;padding-inline-start:34px;font-size:.875rem}.mcp-organizer-occasions{margin-inline-start:10px;padding-inline-start:24px;border-inline-start:1px solid currentColor}.mcp-connection h3 label{padding-bottom:4px}.mcp-connection p{line-height:1.6}.mcp-connection fieldset{border:0;padding:0;margin:24px 0}.mcp-connection legend{font-weight:600;margin-bottom:12px}.mcp-connection label{display:flex;align-items:center;gap:12px;padding:12px 0;cursor:pointer}.mcp-connection input{width:22px;height:22px;flex-shrink:0;accent-color:var(--primary-color,#273f65)}.mcp-connection button{min-height:44px;margin:8px 12px 8px 0;padding:10px 22px;border-radius:24px;cursor:pointer}.mcp-connection button:disabled{cursor:default}.mcp-connection a{display:block;margin-top:16px}.mcp-connection :focus-visible{outline:3px solid var(--primary-color,#273f65);outline-offset:3px}`;
        this.container.replaceChildren(style, root);
    }
}
