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

    createZoomControls(content) {
        const controls = document.createElement('div');
        controls.className = 'blueprint-zoom-controls';
        controls.setAttribute('role', 'group');
        controls.setAttribute('aria-label', BlueprintStrings.zoomControls);
        // Keep controls outside the transformed map and its gesture handling.
        for (const event of ['mousedown', 'touchstart', 'pointerdown', 'click', 'wheel']) {
            controls.addEventListener(event, e => e.stopPropagation());
        }
        const button = (label, path, action) => {
            const element = document.createElement('button');
            element.type = 'button';
            element.className = 'blueprint-zoom-button';
            const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            svg.setAttribute('viewBox', '0 0 24 24');
            svg.setAttribute('aria-hidden', 'true');
            svg.setAttribute('focusable', 'false');
            const icon = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            icon.setAttribute('d', path);
            svg.appendChild(icon);
            element.appendChild(svg);
            element.title = label;
            element.setAttribute('aria-label', label);
            element.addEventListener('click', event => {
                action();
                // Pointer activation should not leave a focus ring after release.
                // Keyboard clicks have detail 0 and retain their visible focus.
                if (event.detail > 0) element.blur();
            });
            controls.appendChild(element);
            return element;
        };
        this.zoomInButton = button(BlueprintStrings.zoomIn, 'M5 12h14M12 5v14', () => this.renderer?.zoomBy(1.25));
        this.zoomOutButton = button(BlueprintStrings.zoomOut, 'M5 12h14', () => this.renderer?.zoomBy(1 / 1.25));
        const reset = button(BlueprintStrings.fitToScreen, 'M9 4H4v5M15 4h5v5M20 15v5h-5M4 15v5h5', () => this.renderer?.fitToScreen());
        reset.classList.add('blueprint-zoom-reset');
        this.zoomControls = controls;
        content.appendChild(controls);
    }

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
        const status = document.createElement('div');
        status.className = 'blueprint-operation-status';
        status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite');
        const confirmBtn = document.createElement('button');
        confirmBtn.className = 'btn btn-primary btn-submit blueprint-btn-confirm';
        confirmBtn.type = 'button';
        confirmBtn.textContent = FormStrings.buttonContinue; confirmBtn.disabled = true;
        container.append(content, status, confirmBtn); document.body.appendChild(container);
        document.body.classList.add('blueprint-active'); document.documentElement.classList.add('blueprint-active');
        const stateId = `seat-selection-${Date.now()}`;
        window.history.pushState({ ...window.history.state, blueprintOverlay: stateId }, '', '#seat-selection');
        let closed = false, closing = false, loading = false, pending = 0;
        const assetAbort = new AbortController();
        const refreshActions = () => {
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
        confirmBtn.onclick = requestClose;
        document.addEventListener('keydown', keyHandler); window.addEventListener('popstate', popHandler);
        confirmBtn.focus();

        const load = async () => {
            if (closed || loading) return;
            loading = true; refreshActions();
            const loadingLabel = document.createElement('div'); loadingLabel.className = 'blueprint-loading';
            const spinner = document.createElement('div'); spinner.className = 'sp-loader';
            loadingLabel.setAttribute('role', 'status'); loadingLabel.setAttribute('aria-label', CommonStrings.loading);
            loadingLabel.append(spinner);
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
                this.createZoomControls(content);
                const options = this.adapter.options();
                options.minZoom = 1; options.maxZoom = 5;
                options.canvasCornerRadius = 12;
                options.tooltipOffset = 15;
                options.tooltipStyle = {
                    zIndex: '3100', background: 'var(--card-bg, #fff)', border: '2px solid var(--text-color, #000)',
                    borderRadius: '8px', padding: '6px 10px', color: 'var(--text-color, #000)',
                    font: 'inherit', fontSize: '14px', lineHeight: 'normal',
                    whiteSpace: 'pre-wrap', boxShadow: '0 2px 8px rgba(0,0,0,0.1)', maxWidth: '300px',
                };
                options.onCameraChanged = state => {
                    this.zoomInButton.disabled = !state.canZoomIn;
                    this.zoomOutButton.disabled = !state.canZoomOut;
                };
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
                this.adapter.onCapacityChanged = capacityPresentation => {
                    if (!closed) this.renderer.update({ capacityPresentation });
                };
                this.adapter.onPresentationChanged = seatPresentation => {
                    if (!closed) { this.renderer.update({ seatPresentation }); }
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
