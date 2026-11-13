import { CONNECTION_DURATION_DAYS, DEFAULT_CONNECTION_DURATION_DAYS, CONNECTION_IDLE_SECONDS, DAY_SECONDS, consentDeadline } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
import { MCP_PERMISSIONS, MCP_CONSENT_MODES, permissionsForConsent, validPermissions } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';
import { ACCOUNT_CONNECTIONS_PATH } from '../users/account_connections_links.js';
import { CommonStrings } from '../shared/common_strings.js';
import { AppConfig } from '../../app_config.js';
import { connectionPageStyles } from '../users/connection_page_styles.js';
import { SupabaseService } from '../../services/supabase_service.js';
import { LocalizationService } from '../../services/localization_service.js';



export const MCP_CONNECTION_PATH = '/settings/mcp-connect';

// The first-party exchange returns the issuer from its protected tenant registry.
// Request input and the broker's continuation cannot choose this trust anchor.
export function mcpResumeUrl(value, issuer) {
    const expected = new URL(issuer);
    if (expected.protocol !== 'https:' || expected.origin !== issuer)
        throw new Error('Invalid connection issuer');
    const url = new URL(value);
    if (url.origin !== expected.origin || url.username || url.password || url.hash ||
        !/^\/connect\/[A-Za-z0-9_-]+\/finish$/.test(url.pathname) ||
        [...url.searchParams].length !== 1 ||
        !/^[A-Za-z0-9_-]{43}$/.test(url.searchParams.get('resume') || '')) {
        throw new Error('Invalid connection continuation');
    }
    return url.href;
}

/** Tenant-owned consent; the issuer verifies membership and permissions before minting. */
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
        this.expandedUnits = new Map();
        this.generation = 0;
        this.busy = false;
        this.state = 'loading';
        this.permissionMode = 'requested';
    }

    text(key, args = {}) { return LocalizationService.tr(`McpConnection.${key}`, args); }

    async call(operation) {
        const { data, error } = await this.client.functions.invoke('mcp-session-exchange', {
            headers: new URL(this.browser.location.href).searchParams.has('issuer')
                ? { 'X-Festapp-Mcp-Issuer': new URL(this.browser.location.href).searchParams.get('issuer') } : {},
            body: { request: this.request, operation, ...(operation === 'approve' ? { access: this.connection || Array.isArray(this.details?.requestedPermissions) ? { consentVersion: 2, selection: this.access, permissions: permissionsForConsent(this.details?.requestedPermissions ?? [], this.permissionMode), ...(this.details?.api ? {apiReview:{...this.details.api,version:1}} : {}), ...(this.connection ? { connection: this.connection } : {}) } : this.access } : {}) },
        });
        if (error || data?.error || !data) throw new Error('Connection failed');
        return data;
    }

    get access() {
        if (!this.selectedUnits.size) return { type: 'occasions', occasionIds: [...this.selected] };
        return { type: 'selection', units: [...this.selectedUnits].map(([unitId, canCreateOccasions]) =>
            ({ unitId, canCreateOccasions: canCreateOccasions && this.canRequestCreate })), occasionIds: [...this.selected] };
    }

    get canRequestCreate() { return this.permissionMode === 'requested' && this.details?.canRequestCreate === true; }

    get canApprove() {
        if (this.connection && (!['new', 'replace'].includes(this.connection.mode) || !CONNECTION_DURATION_DAYS.includes(this.connection.durationDays) || this.connection.name.length > 80 || /[\u0000-\u001f\u007f]/u.test(this.connection.name) ||
            (this.connection.mode === 'replace' && !this.connection.connectionId) ||
            (this.connection.mode === 'new' && this.details.connections?.length && !this.connection.name.trim()))) return false;
        const ids = new Set((this.details?.occasions || []).map(o => o.id));
        const units = this.details?.units || [];
        if (!MCP_CONSENT_MODES.includes(this.permissionMode) || !validPermissions(this.details?.requestedPermissions ?? [])) return false;
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
                const latest = details.connections?.find(c => c.defaultEligible !== false);
                this.connection = details.connections ? { mode: latest ? 'replace' : (details.connections.length ? '' : 'new'), ...(latest ? { connectionId: latest.id } : {}), name: latest?.name || '', durationDays: DEFAULT_CONNECTION_DURATION_DAYS } : undefined;
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
                if (!Array.isArray(permissions) || permissions.some(p => !Object.hasOwn(MCP_PERMISSIONS, p))) throw new Error('Invalid permissions');
                if (!validPermissions(permissions)) throw new Error('Invalid permissions');
                // Human-readable presets only narrow the requested scopes;
                // live SQL still owns current account rights.
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
            const destination = this.resume(result.resumeUrl, result.issuer);
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
        root.className = `mcp-connection connection-page${this.state === 'connected' ? ' mcp-connected' : ''}`;
        if (this.state === 'connected') root.setAttribute('role', 'status');
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
            if (key === 'approve' || key === 'login' || key === 'closeWindow') element.dataset.primary = '';
            element.disabled = this.busy || disabled;
            element.addEventListener('click', action);
            return element;
        };
        if (this.state === 'connected') {
            const mark = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            mark.setAttribute('viewBox', '0 0 24 24');
            mark.setAttribute('aria-hidden', 'true');
            mark.classList.add('mcp-success-mark');
            const check = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            check.setAttribute('d', 'm6 12 4 4 8-8');
            mark.appendChild(check);
            root.appendChild(mark);
        }
        add('h1', this.text(this.state === 'connected' ? 'connected' : 'heading'));
        if (this.state === 'consent') {
            add('h2', this.details.client);
            if(this.details.api){add('p',`API: ${this.details.api.resource}`);add('p',`Data: ${this.details.api.dataProfile}`);}
            if (this.details.regionalPortal) {
                const { name: portal, platform } = this.details.regionalPortal;
                add('p', this.text('regionalPlatform', { portal, platform }));
            }
            add('p', this.user.email?.replace(new RegExp(`^${AppConfig.organization}\\+`), '') || '');
            if (this.details.requestedPermissions?.length || this.details.canRequestCreate) {
                const label = add('label', this.text('permissionMode'));
                const mode = add('select', '', label); mode.name = 'permissionMode'; mode.disabled = this.busy;
                for (const value of MCP_CONSENT_MODES) {
                    const option = add('option', this.text(`permissionMode_${value}`), mode);
                    option.value = value; option.selected = this.permissionMode === value;
                }
                add('p', this.text(`permissionHint_${this.permissionMode}`));
                mode.addEventListener('change', () => {
                    this.permissionMode = mode.value; this.render();
                    this.container.querySelector('[name="permissionMode"]')?.focus();
                });
            }
            if (this.connection) {
                const choices = this.details.connections;
                const durationLabel = add('label', this.text('durationLabel'));
                const duration = add('select', '', durationLabel); duration.name = 'durationDays'; duration.disabled = this.busy;
                for (const days of CONNECTION_DURATION_DAYS.filter(days=>days<=(this.details.maxConsentDays??365))) {
                    const option = add('option', this.text(`duration${days}`), duration); option.value = String(days);
                    option.selected = this.connection.durationDays === days;
                }
                duration.addEventListener('change', () => {
                    this.connection.durationDays = Number(duration.value); this.render();
                    this.container.querySelector('[name="durationDays"]')?.focus();
                });
                add('p', this.text('consentDeadline', { date: new Intl.DateTimeFormat(LocalizationService.currentLocale, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(consentDeadline(this.connection.durationDays))) }));
                add('p', this.text('idleDurationHint', { days: CONNECTION_IDLE_SECONDS / DAY_SECONDS }));
                if (this.connection.durationDays === 365) add('p', this.text('longDurationHint')).dataset.longDurationHint = '';

                const section = add('fieldset', ''); section.disabled = this.busy;
                add('legend', this.text('connectionChoice'), section);
                if (choices.length) {
                    for (const mode of ['replace', 'new']) {
                        const label = add('label', '', section);
                        const radio = document.createElement('input'); radio.type = 'radio'; radio.name = 'connection-mode';
                        radio.value = mode; radio.checked = this.connection.mode === mode;
                        radio.addEventListener('change', () => {
                            const target = choices.find(c => c.defaultEligible !== false);
                            this.connection = { mode, durationDays: this.connection.durationDays, name: mode === 'replace' ? target?.name || '' : '',
                                ...(mode === 'replace' && target ? { connectionId: target.id } : {}) }; this.render();
                        });
                        label.appendChild(radio); add('span', this.text(mode === 'replace' ? 'replaceConnection' : 'newDevice'), label);
                    }
                    if (this.connection.mode === 'replace') {
                        const label = add('label', this.text('replaceTarget'), section);
                        const select = add('select', '', label); select.name = 'connectionId';
                        if (!this.connection.connectionId) {
                            const placeholder = add('option', this.text('replaceTarget'), select); placeholder.value = '';
                        }
                        for (const [index, c] of choices.entries()) {
                            const date = new Intl.DateTimeFormat(LocalizationService.currentLocale, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(c.expiresAt));
                            const option = add('option', `${index + 1}. ${c.name || this.details.client} · ${date}`, select); option.value = c.id;
                            option.selected = c.id === this.connection.connectionId;
                        }
                        select.addEventListener('change', () => {
                            this.connection.connectionId = select.value;
                            this.connection.name = choices.find(c => c.id === select.value)?.name || ''; this.render();
                        });
                        // Show every target's scope before approval, using text nodes only.
                        for (const [index, c] of choices.entries()) {
                            const item = add('article', '', section);
                            add('h3', `${index + 1}. ${c.name || this.details.client}`, item);
                            add('p', this.text('connectionExpiry', { date: new Intl.DateTimeFormat(LocalizationService.currentLocale, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(c.expiresAt)) }), item);
                            for (const u of c.access.units) add('p', this.text(u.canCreateOccasions ? 'connectionOrganizerCreate' : 'connectionOrganizer', { id: u.unitId }), item);
                            for (const id of c.access.occasionIds) add('p', this.text('connectionOccasion', { id }), item);
                            add('p', this.text('sameRights'), item);
                        }
                        add('p', this.text('replaceHint'), section);
                    }
                }
                const label = add('label', this.text(this.connection.mode === 'new' && choices.length ? 'deviceNameRequired' : 'deviceName'), section);
                const name = add('input', '', label); name.type = 'text'; name.maxLength = 80; name.value = this.connection.name;
                name.dataset.connectionName = ''; name.required = this.connection.mode === 'new' && choices.length > 0;
                name.addEventListener('input', () => {
                    this.connection.name = name.value;
                    const approve = root.querySelector('button[data-primary]'); if (approve) approve.disabled = this.busy || !this.canApprove;
                });
            }
            add('p', this.text('chooseScope'));
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
                const header = add('div', '', section);
                header.className = 'mcp-organizer-header';
                const heading = add('h3', '', header);
                const whole = this.selectedUnits.has(id);
                const creates = this.canRequestCreate && (whole ? this.selectedUnits.get(id) : group.unit?.canCreateOccasions === true);
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
                const selectedCount = group.occasions.filter(o => this.selected.has(o.id)).length;
                const status = add('p', this.text(whole ? 'wholeOrganizerSelected' : 'groupSelection', { selected: selectedCount, count: group.occasions.length }), section);
                status.className = 'mcp-organizer-hint';
                const hint = add('p', this.text(!group.unit ? 'individualOnlyHint' : creates ? 'organizerCreateHint' : 'organizerReadHint'), section);
                hint.className = 'mcp-organizer-hint';
                hint.id = `mcp-unit-hint-${id ?? 'individual'}`;
                parent.setAttribute('aria-describedby', hint.id);
                const key = String(id ?? 'individual');
                if (!this.expandedUnits.has(key)) this.expandedUnits.set(key, groups.size <= 2);
                const expanded = this.expandedUnits.get(key);
                const toggle = add('button', this.text(expanded ? 'hideOccasions' : 'showOccasions', { count: group.occasions.length }), header);
                toggle.type = 'button';
                toggle.className = 'mcp-organizer-toggle';
                toggle.dataset.unitToggle = key;
                toggle.setAttribute('aria-expanded', String(expanded));
                toggle.setAttribute('aria-controls', `mcp-unit-events-${key}`);
                toggle.setAttribute('aria-label', `${toggle.textContent}: ${title([id, group])}`);
                toggle.addEventListener('click', () => {
                    this.expandedUnits.set(key, !expanded);
                    this.render();
                    this.container.querySelector(`[data-unit-toggle="${key}"]`)?.focus();
                });
                const children = add('div', '', section);
                children.id = `mcp-unit-events-${key}`;
                children.hidden = !expanded;
                children.className = 'mcp-organizer-occasions';
                if (whole) add('p', this.text('inheritedSelectionHint'), children);
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
            const summary = add('section', '');
            summary.className = 'mcp-access-summary';
            add('h2', this.text('accessSummary'), summary);
            add('p', this.text('sameRights'), summary);
            const selectionSummary = add('p', this.text(this.selectedUnits.size || this.selected.size ? 'selectionSummary' : 'selectionRequired', { organizers: this.selectedUnits.size, occasions: this.selected.size }));
            selectionSummary.className = 'mcp-selection-summary';
            add('p', this.text('duration', { appName: AppConfig.appName }));
            button(this.busy ? 'connecting' : 'approve', () => this.finish('approve'), !this.canApprove);
            button('cancel', () => this.finish('cancel'));
        } else if (this.state === 'login') {
            add('p', this.text('loginHint'));
            button('login', () => this.login());
            button('cancel', () => this.finish('cancel'));
        } else if (this.state === 'connected') {
            add('p', this.text('connectedClient'));
            add('p', this.text('closeHint'));
            button('closeWindow', () => this.browser.close());
            const back = add('a', this.text('backToTenant', { tenant: AppConfig.appName }));
            back.href = '/';
        } else {
            const message = add('p', this.text(this.state === 'loading' ? 'connecting' : this.state));
            message.setAttribute('role', this.state === 'error' ? 'alert' : 'status');
            if (this.state === 'error') button('retry', () => this.init());
        }
        if (this.user) {
            const management = add('a', CommonStrings.accountConnections);
            management.href = `${ACCOUNT_CONNECTIONS_PATH}#apps`;
            management.target = '_blank';
            management.rel = 'noopener noreferrer';
        }
        const style = document.createElement('style');
        style.textContent = connectionPageStyles + `
.mcp-connection h2{margin-block-start:24px}
.mcp-connected{max-width:640px}
.mcp-success-mark{display:block;width:48px;height:48px;margin-bottom:20px;color:var(--connection-link);fill:none;stroke:currentColor;stroke-width:2.5;stroke-linecap:round;stroke-linejoin:round}
.mcp-connected button[data-primary]{margin-top:20px}
.mcp-connected>p:first-of-type{font-size:1.125rem}

.mcp-organizer{margin-block:12px;padding-block:12px;border-block-end:1px solid var(--connection-line)}
.mcp-organizer:last-child{border-block-end:0}
.mcp-organizer h3{margin:0;flex:1;min-width:0}
.mcp-organizer-header{display:flex;align-items:center;flex-wrap:wrap;gap:8px 16px}
.mcp-organizer-header .mcp-organizer-toggle{font-size:.875rem;margin:0;padding:8px 12px}
.mcp-access-summary{margin-block:28px;padding-block:20px;border-block:1px solid var(--connection-line)}
.mcp-access-summary h2{font-size:1.125rem;margin:0}
.mcp-access-summary ul{padding-inline-start:24px;line-height:1.6}
.mcp-selection-summary{font-weight:600}
.mcp-organizer label span{overflow-wrap:anywhere}
.mcp-organizer-hint{margin:0 0 8px!important;padding-inline-start:34px;font-size:.875rem}
.mcp-organizer-occasions{margin:12px 0 0 10px;padding-inline-start:20px;border-inline-start:1px solid var(--connection-line)}
.mcp-connection fieldset{border:0;padding:0;margin:28px 0}
.mcp-connection legend{font-weight:600;margin-bottom:16px}
.mcp-connection label{display:flex;align-items:center;gap:12px;min-height:44px;padding:10px 0;cursor:pointer}
.mcp-connection input:not([type=text]){width:22px;height:22px;flex-shrink:0;accent-color:var(--primary-color,#243858)}
.mcp-connection input[type=text]{width:100%;padding:10px;font:inherit;box-sizing:border-box}
.mcp-connection a{display:block;margin-top:20px}
`;
        this.container.replaceChildren(style, root);
    }
}
