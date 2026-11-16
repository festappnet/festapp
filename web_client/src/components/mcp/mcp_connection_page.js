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
        this.closeUnavailable = false;
        this.permissionMode = 'requested';
    }

    text(key, args = {}) { return LocalizationService.tr(`McpConnection.${key}`, args); }

    async call(operation, mfa) {
        const { data, error } = await this.client.functions.invoke('mcp-session-exchange', {
            headers: new URL(this.browser.location.href).searchParams.has('issuer')
                ? { 'X-Festapp-Mcp-Issuer': new URL(this.browser.location.href).searchParams.get('issuer') } : {},
            body: { request: this.request, operation, ...(mfa ? { mfa } : {}), ...(operation === 'approve' ? { access: this.connection || Array.isArray(this.details?.requestedPermissions) ? { consentVersion: 2, selection: this.access, permissions: permissionsForConsent(this.details?.requestedPermissions ?? [], this.permissionMode), ...(this.details?.api ? {apiReview:{...this.details.api,version:1}} : {}), ...(this.connection ? { connection: this.connection } : {}) } : this.access } : {}) },
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
                this.mfaFactor = this.user.factors?.find(f => f.status === 'verified' && f.factor_type === 'totp');
                if (this.user.factors?.some(f => f.status === 'verified')) {
                    const assurance = await this.client.auth.mfa.getAuthenticatorAssuranceLevel();
                    if (assurance.error) throw assurance.error;
                    if (assurance.data.currentLevel !== 'aal2') {
                        this.state = this.mfaFactor ? 'mfaLogin' : 'mfaUnsupported';
                        this.render();
                        return;
                    }
                }
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

    async finish(operation, mfa) {
        if (this.busy || (operation === 'approve' && (this.state !== 'consent' || !this.canApprove))) return;
        if (operation === 'approve' && this.mfaFactor && !mfa) {
            this.state = 'mfaApproval';
            this.render();
            return;
        }
        const generation = this.generation;
        // Create synchronously from the approval gesture, then sever the opener.
        const callback = operation === 'approve' && this.details?.applicationType === 'native'
            ? this.browser.open('about:blank', '_blank', 'popup,width=520,height=640') : null;
        if (callback) callback.opener = null;
        this.busy = true;
        this.render();
        let dispatched = false;
        try {
            const result = await this.call(operation, mfa);
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
        const button = (key, action, disabled = false, parent = root) => {
            const element = add('button', this.text(key), parent);
            element.type = 'button';
            if (key === 'approve' || key === 'connecting' || key === 'login' || key === 'closeWindow') element.dataset.primary = '';
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
            const identity = add('header', '');
            identity.className = 'mcp-identity';
            add('h2', this.details.client, identity);
            if (this.details.api) {
                const api = add('div', '', identity);
                api.className = 'mcp-api-disclosure';
                add('p', `API: ${this.details.api.resource}`, api);
                add('p', `Data: ${this.details.api.dataProfile}`, api);
            }
            if (this.details.regionalPortal) {
                const { name: portal, platform } = this.details.regionalPortal;
                add('p', this.text('regionalPlatform', { portal, platform }), identity);
            }
            add('p', this.user.email?.replace(new RegExp(`^${AppConfig.organization}\\+`), '') || '', identity).className = 'connection-identity';
            const settings = add('div', '');
            settings.className = 'mcp-settings';
            if (this.details.requestedPermissions?.length || this.details.canRequestCreate) {
                const permissionSettings = add('div', '', settings);
                const label = add('label', this.text('permissionMode'), permissionSettings);
                const mode = add('select', '', label); mode.name = 'permissionMode'; mode.disabled = this.busy;
                for (const value of MCP_CONSENT_MODES) {
                    const option = add('option', this.text(`permissionMode_${value}`), mode);
                    option.value = value; option.selected = this.permissionMode === value;
                }
                const hint = add('p', this.text(`permissionHint_${this.permissionMode}`), permissionSettings);
                hint.id = 'mcp-permission-hint';
                hint.className = 'mcp-field-hint';
                mode.setAttribute('aria-describedby', hint.id);
                mode.addEventListener('change', () => {
                    this.permissionMode = mode.value; this.render();
                    this.container.querySelector('[name="permissionMode"]')?.focus();
                });
            }
            if (this.connection) {
                const choices = this.details.connections;
                const durationSettings = add('div', '', settings);
                durationSettings.className = 'mcp-duration';
                const durationLabel = add('label', this.text('durationLabel'), durationSettings);
                const duration = add('select', '', durationLabel); duration.name = 'durationDays'; duration.disabled = this.busy;
                for (const days of CONNECTION_DURATION_DAYS.filter(days=>days<=(this.details.maxConsentDays??365))) {
                    const option = add('option', this.text(`duration${days}`), duration); option.value = String(days);
                    option.selected = this.connection.durationDays === days;
                }
                duration.addEventListener('change', () => {
                    this.connection.durationDays = Number(duration.value); this.render();
                    this.container.querySelector('[name="durationDays"]')?.focus();
                });
                const durationHint = add('div', '', durationSettings);
                durationHint.id = 'mcp-duration-hint';
                durationHint.className = 'mcp-field-hint';
                duration.setAttribute('aria-describedby', durationHint.id);
                add('p', this.text('consentDeadline', { date: new Intl.DateTimeFormat(LocalizationService.currentLocale, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(consentDeadline(this.connection.durationDays))) }), durationHint);
                add('p', this.text('idleDurationHint', { days: CONNECTION_IDLE_SECONDS / DAY_SECONDS }), durationHint);
                if (this.connection.durationDays === 365) add('p', this.text('longDurationHint'), durationHint).dataset.longDurationHint = '';

                const section = add('fieldset', ''); section.disabled = this.busy;
                add('legend', this.text('connectionChoice'), section);
                if (choices.length) {
                    for (const mode of ['replace', 'new']) {
                        const label = add('label', '', section);
                        label.className = 'mcp-choice';
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
                            item.className = 'mcp-existing-connection';
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
            const fieldset = add('fieldset', '');
            fieldset.disabled = this.busy;
            add('legend', this.text('choose'), fieldset);
            add('p', this.text('chooseScope'), fieldset).className = 'mcp-scope-hint';
            const occasions = this.details.occasions;
            const checkbox = (title, checked, action, parent = fieldset) => {
                const label = add('label', '', parent);
                label.className = 'mcp-choice';
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
            const effectivePermissions = permissionsForConsent(this.details.requestedPermissions ?? [], this.permissionMode);
            if (effectivePermissions.length) {
                const list = add('ul', '', summary);
                for (const scope of effectivePermissions) add('li', this.text(MCP_PERMISSIONS[scope].label), list);
            }
            const selectionSummary = add('p', this.text(this.selectedUnits.size || this.selected.size ? 'selectionSummary' : 'selectionRequired', { organizers: this.selectedUnits.size, occasions: this.selected.size }));
            selectionSummary.className = 'mcp-selection-summary';
            add('p', this.text('duration', { appName: AppConfig.appName }));
            const actions = add('div', '');
            actions.className = 'mcp-actions';
            button(this.busy ? 'connecting' : 'approve', () => this.finish('approve'), !this.canApprove, actions);
            button('cancel', () => this.finish('cancel'), false, actions);
        } else if (['mfaLogin', 'mfaApproval'].includes(this.state)) {
            add('p', this.text(this.state === 'mfaLogin' ? 'mfaLoginHint' : 'mfaApprovalHint'));
            const form = add('form', '');
            const label = add('label', this.text('mfaCode'), form);
            const input = document.createElement('input');
            input.type = 'password';
            input.inputMode = 'numeric';
            input.autocomplete = 'one-time-code';
            input.pattern = '[0-9]{6}';
            input.maxLength = 6;
            input.required = true;
            input.disabled = this.busy;
            label.appendChild(input);
            const submit = add('button', this.text('mfaVerify'), form);
            submit.type = 'submit';
            submit.dataset.primary = '';
            submit.disabled = this.busy;
            form.addEventListener('submit', async event => {
                event.preventDefault();
                if (this.busy || !form.reportValidity()) return;
                const code = input.value;
                input.value = '';
                if (this.state === 'mfaApproval') {
                    this.state = 'consent';
                    await this.finish('approve', { factorId: this.mfaFactor.id, code });
                    return;
                }
                this.busy = true;
                this.render();
                try {
                    const result = await this.client.auth.mfa.challengeAndVerify({ factorId: this.mfaFactor.id, code });
                    if (result.error) throw result.error;
                    this.busy = false;
                    await this.init();
                } catch {
                    this.busy = false;
                    this.state = 'mfaLogin';
                    this.mfaFailed = true;
                    this.render();
                }
            });
            if (this.mfaFailed) add('p', this.text('mfaFailed')).setAttribute('role', 'alert');
            button('cancel', () => this.finish('cancel'));
        } else if (this.state === 'login') {
            add('p', this.text('loginHint'));
            button('login', () => this.login());
            button('cancel', () => this.finish('cancel'));
        } else if (this.state === 'connected') {
            add('p', this.text('connectedClient'));
            add('p', this.text(this.closeUnavailable ? 'closeManually' : 'closeHint'));
            if (!this.closeUnavailable) button('closeWindow', () => {
                // User-opened tabs may refuse close(); opener/history heuristics
                // are unreliable after OAuth navigation and opener isolation.
                try { this.browser.close(); } catch { /* Offer the same fallback when closing throws. */ }
                if (this.browser.closed) return;
                this.closeUnavailable = true;
                this.render();
                this.container.querySelector('[data-back-to-tenant]')?.focus();
            });
            const back = add('a', this.text('backToTenant', { tenant: AppConfig.appName }));
            back.href = '/';
            back.dataset.backToTenant = '';
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
.mcp-identity{padding-bottom:24px;border-bottom:1px solid var(--connection-line)}
.mcp-identity h2{margin:0;font-size:1.3rem}
.mcp-api-disclosure{margin-top:12px;font-size:.875rem}
.mcp-api-disclosure p{margin:2px 0}
.mcp-settings{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px;margin-top:28px;align-items:start}
.mcp-settings:empty{display:none}
.mcp-settings>div:only-child{grid-column:1/-1}
.mcp-field-hint{font-size:.875rem;line-height:1.5;margin-top:8px!important}
.mcp-field-hint p{margin:6px 0;line-height:1.5}
.mcp-existing-connection{padding:12px 0;border-bottom:1px solid var(--connection-line)}
.mcp-existing-connection h3{margin:0 0 8px}
.mcp-existing-connection p{margin:4px 0;font-size:.875rem}
.mcp-actions{display:flex;flex-wrap:wrap;gap:12px;margin-top:24px}
.mcp-actions button{margin:0}
.mcp-scope-hint{margin:0 0 16px!important}

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
.mcp-connection fieldset{min-width:0;border:0;padding:24px 0 0;margin:28px 0;border-top:1px solid var(--connection-line)}
.mcp-connection legend{font-size:1.125rem;font-weight:600;padding:0 12px 0 0}
.mcp-connection label{display:grid;gap:8px;min-width:0;margin:12px 0;font-weight:500;line-height:1.4}
.mcp-settings label{margin-top:0}
.mcp-connection label.mcp-choice{display:flex;align-items:center;gap:12px;min-height:44px;margin:0;padding:10px 0;cursor:pointer}
.mcp-connection input[type=checkbox],.mcp-connection input[type=radio]{width:22px;height:22px;margin:0;flex-shrink:0;accent-color:var(--primary-color,#4465a6)}
.mcp-connection select,.mcp-connection input[type=text],.mcp-connection input[type=password]{display:block;width:100%;min-width:0;min-height:48px;padding:10px 12px;font:inherit;font-weight:400;line-height:1.4;color:var(--text-color,#20242b);background:var(--card-bg,#fff);border:1px solid var(--connection-control-line);border-radius:8px;caret-color:var(--connection-link);color-scheme:light}
.mcp-connection select:disabled,.mcp-connection input:disabled{cursor:not-allowed}
body.dark-mode .mcp-connection select,body.dark-mode .mcp-connection input[type=text],body.dark-mode .mcp-connection input[type=password]{color-scheme:dark}
@media(max-width:600px){.mcp-settings{grid-template-columns:minmax(0,1fr);gap:20px}.mcp-actions{flex-direction:column}.mcp-actions button{width:100%}.mcp-organizer-header{align-items:flex-start}.mcp-organizer-header .mcp-organizer-toggle{margin-inline-start:34px}.mcp-organizer-occasions{margin-inline-start:0;padding-inline-start:12px}}
.mcp-connection a{display:block;margin-top:20px}
`;
        this.container.replaceChildren(style, root);
    }
}
