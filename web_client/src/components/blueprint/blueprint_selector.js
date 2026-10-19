import kernelUrl from '@festapp/venue-layout/kernel?url';
import { loadKernel, loadLayoutAssets, mount } from '@festapp/venue-layout';
import { FormStrings } from '../forms/form_strings.js';
import { CommonStrings } from '../shared/common_strings.js';
import { BlueprintStrings } from './blueprint_strings.js';
import { DbForms } from '../forms/db_forms.js';
import { BlueprintLayoutAdapter } from './blueprint_layout_adapter.js';

if (typeof document !== 'undefined') {
    const cssUrl = new URL('./blueprint.css', import.meta.url).href;
    if (!document.querySelector(`link[href="${cssUrl}"]`)) {
        const link = document.createElement('link');
        link.rel = 'stylesheet'; link.href = cssUrl; document.head.appendChild(link);
    }
}

/** Host modal lifecycle only. Shared viewer owns rendering, gestures and selection. */
export class BlueprintSelector {
    constructor() { this.renderer = null; this.adapter = null; this.close = null; }

    async open(session, field, initialSeats = []) {
        this.close?.();
        const previousFocus = document.activeElement;
        const container = document.createElement('div');
        container.className = 'blueprint-modal-container';
        container.setAttribute('role', 'dialog');
        container.setAttribute('aria-modal', 'true');
        container.setAttribute('aria-label', BlueprintStrings.layoutTitle);
        const content = document.createElement('div');
        content.className = 'blueprint-content';
        const legend = document.createElement('div');
        legend.className = 'blueprint-state-legend';
        const status = document.createElement('div');
        status.className = 'blueprint-operation-status';
        status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite');
        const actions = document.createElement('div');
        actions.className = 'blueprint-modal-actions';
        const closeBtn = document.createElement('button');
        closeBtn.className = 'btn btn-secondary'; closeBtn.textContent = BlueprintStrings.close;
        const confirmBtn = document.createElement('button');
        confirmBtn.className = 'btn btn-primary btn-submit';
        confirmBtn.textContent = FormStrings.buttonContinue; confirmBtn.disabled = true;
        actions.append(closeBtn, confirmBtn);
        container.append(content, legend, status, actions); document.body.appendChild(container);
        document.body.classList.add('blueprint-active'); document.documentElement.classList.add('blueprint-active');
        const stateId = `seat-selection-${Date.now()}`;
        window.history.pushState({ ...window.history.state, blueprintOverlay: stateId }, '', '#seat-selection');
        let closed = false, closing = false, loading = false, pending = 0;
        const assetAbort = new AbortController();
        const refreshLegend = () => {
            const states = ['empty', 'available', 'selected', 'selectedByMe', 'ordered', 'used', 'blocked'];
            const counts = Object.fromEntries(states.map(state => [state, 0]));
            for (const model of this.adapter?.models.values() || []) {
                const state = ({selected_by_me: 'selectedByMe', black: 'blocked', taken: 'ordered'})[model.state] || model.state;
                if (state in counts) counts[state]++;
            }
            legend.replaceChildren(...states.map(state => {
                const label = document.createElement('span');
                label.textContent = `${BlueprintStrings.seatState(state)}: ${counts[state]}`;
                return label;
            }));
        };
        const refreshActions = () => {
            closeBtn.disabled = pending > 0;
            confirmBtn.disabled = loading || pending > 0 || !this.adapter;
            status.textContent = pending > 0 ? CommonStrings.loading : '';
        };
        const cleanup = () => {
            if (closed) return;
            closed = true;
            assetAbort.abort();
            this.selectedSeats = this.adapter?.selectedSeats ?? initialSeats;
            this.adapter?.dispose(); this.renderer?.dispose();
            this.adapter = null; this.renderer = null; this.close = null;
            container.remove();
            document.body.classList.remove('blueprint-active'); document.documentElement.classList.remove('blueprint-active');
            window.removeEventListener('popstate', popHandler); document.removeEventListener('keydown', keyHandler);
            if (previousFocus?.isConnected) previousFocus.focus();
        };
        const requestClose = () => {
            if (closed || closing || pending > 0) return;
            closing = true;
            window.history.back();
        };
        const popHandler = () => cleanup();
        const keyHandler = event => {
            if (event.defaultPrevented) return;
            if (event.key === 'Escape') { event.preventDefault(); requestClose(); }
            if (event.key === 'Tab') {
                const focusable = [...container.querySelectorAll('button:not(:disabled), [tabindex="0"], input:not(:disabled)')];
                const first = focusable[0], last = focusable.at(-1);
                if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
                else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
            }
        };
        this.close = cleanup;
        closeBtn.onclick = requestClose; confirmBtn.onclick = requestClose;
        document.addEventListener('keydown', keyHandler); window.addEventListener('popstate', popHandler);
        closeBtn.focus();

        const load = async () => {
            if (closed || loading) return;
            loading = true; refreshActions();
            const loadingLabel = document.createElement('p'); loadingLabel.textContent = CommonStrings.loading;
            content.replaceChildren(loadingLabel);
            try {
                if (session.formModel.demoSimulation) throw new Error(FormStrings.demoNotice);
                const blueprint = field?.data?.blueprintId ?? session.formModel.blueprint;
                const blueprintId = typeof blueprint === 'object' ? blueprint?.id : blueprint;
                if (!blueprintId) throw new Error(BlueprintStrings.layoutUnavailable);
                const data = await DbForms.getBlueprint(session.formModel.secret, session.formModel.key, blueprintId);
                if (closed) return;
                if (!data?.layout) throw new Error(BlueprintStrings.layoutUnavailable);
                await loadKernel(kernelUrl);
                if (closed) return;
                if (data.secret) {
                    session.formModel.secret = data.secret;
                    if (session.payload) session.payload[DbForms.metaSecret] = data.secret;
                }
                this.adapter = new BlueprintLayoutAdapter(data, { session, initialSeats });
                content.replaceChildren();
                const options = this.adapter.options();
                options.resources = await loadLayoutAssets(options.resources, { signal: assetAbort.signal });
                if (closed) return;
                options.messages = BlueprintStrings.viewerMessages;
                const select = options.onSelectionRequested;
                options.onSelectionRequested = async (ids, selecting) => {
                    pending++; refreshActions();
                    try { return await select(ids, selecting); }
                    finally { pending--; if (!closed) refreshActions(); }
                };
                const quantity = options.onQuantityRequested;
                if (quantity) options.onQuantityRequested = async (id, count) => {
                    pending++; refreshActions();
                    try { return await quantity(id, count); }
                    finally { pending--; if (!closed) refreshActions(); }
                };
                options.accessibilityLabel = BlueprintStrings.layoutTitle;
                this.renderer = mount(content, options);
                refreshLegend();
                this.adapter.onCapacityChanged = capacityPresentation => {
                    if (!closed) this.renderer.update({ capacityPresentation });
                };
                this.adapter.onPresentationChanged = seatPresentation => {
                    if (!closed) { this.renderer.update({ seatPresentation }); refreshLegend(); }
                };
            } catch (error) {
                if (closed) return;
                this.adapter?.dispose(); this.renderer?.dispose();
                this.adapter = null; this.renderer = null;
                const label = document.createElement('p'); label.className = 'blueprint-error';
                label.textContent = `${CommonStrings.error}: ${error.message}`;
                const retry = document.createElement('button'); retry.className = 'btn btn-secondary';
                retry.textContent = CommonStrings.retry; retry.onclick = load;
                content.replaceChildren(label, retry);
            } finally { loading = false; if (!closed) refreshActions(); }
        };
        await load();
    }
}
