import { BlueprintStrings } from './blueprint_strings.js';

/** Commerce controls anchored to kernel geometry; the package still owns the map. */
export class BlueprintCapacityControls {
    constructor(content, options) {
        this.content = content;
        this.options = options;
        this.entries = new Map();
        this.json = JSON.stringify(options.document);
        const nodes = options.document.nodes.filter(node => node.kind === 'capacityArea');
        const scene = nodes.length ? JSON.parse(globalThis.VenueLayoutKernel.compileSceneNodes(
            this.json, JSON.stringify(nodes.map(node => node.id)), JSON.stringify(options.resources), '{}')) : {items: []};
        this.layer = document.createElement('div');
        this.layer.className = 'blueprint-capacity-layer';
        for (const node of nodes) {
            const bounds = scene.items.find(item => item.id === node.id)?.bounds;
            if (!bounds) continue;
            const group = document.createElement('div');
            group.className = 'blueprint-capacity-control';
            group.setAttribute('role', 'dialog');
            group.setAttribute('aria-modal', 'false');
            group.setAttribute('aria-label', node.label || options.messages.standing);
            const button = (text, label, action) => {
                const element = document.createElement('button');
                element.type = 'button'; element.textContent = text;
                element.setAttribute('aria-label', label);
                element.onclick = action; group.append(element); return element;
            };
            const entry = { id: node.id, node, bounds, group, editing: false, pending: false };
            entry.heading = document.createElement('strong');
            entry.heading.className = 'blueprint-capacity-heading';
            entry.heading.textContent = node.label || options.messages.standing;
            entry.details = document.createElement('span');
            entry.details.className = 'blueprint-capacity-details';
            group.append(entry.heading, entry.details);
            entry.minus = button('−', options.messages.removeOne, () => this.step(entry, -1));
            entry.count = button('', '', () => this.edit(entry));
            entry.count.className = 'blueprint-capacity-count';
            entry.plus = button('+', options.messages.addOne, () => this.step(entry, 1));
            entry.confirm = button(options.messages.confirmQuantity, options.messages.confirmQuantity, () => this.confirm(entry));
            entry.confirm.className = 'blueprint-capacity-confirm';
            entry.message = document.createElement('div');
            entry.message.className = 'blueprint-capacity-message';
            entry.message.setAttribute('role', 'status');
            group.append(entry.message);
            group.addEventListener('keydown', event => {
                if (event.key === 'Escape' && entry.editing && !entry.pending) {
                    event.preventDefault(); event.stopPropagation();
                    this.dismiss(entry, true);
                }
            });
            this.entries.set(node.id, entry); this.layer.append(group);
        }
        for (const name of ['pointerdown', 'touchstart', 'mousedown', 'click']) this.layer.addEventListener(name, event => event.stopPropagation());
        // The overlay is a sibling of the SVG. Relay wheel gestures so zoom/pan
        // keeps its cursor anchor even while the pointer is over a control.
        this.layer.addEventListener('wheel', event => {
            const svg = content.querySelector('.venue-layout-viewer > svg');
            if (!svg) return;
            const forwarded = new content.ownerDocument.defaultView.WheelEvent('wheel', {
                bubbles: true, cancelable: true,
                clientX: event.clientX, clientY: event.clientY,
                deltaX: event.deltaX, deltaY: event.deltaY, deltaZ: event.deltaZ, deltaMode: event.deltaMode,
                ctrlKey: event.ctrlKey, shiftKey: event.shiftKey, altKey: event.altKey, metaKey: event.metaKey,
            });
            svg.dispatchEvent(forwarded);
            if (forwarded.defaultPrevented) event.preventDefault();
            event.stopPropagation();
        }, {passive: false});
        content.append(this.layer);
        this.dismissOutside = event => {
            for (const entry of this.entries.values()) {
                if (entry.editing && !entry.group.contains(event.target)) this.dismiss(entry);
            }
        };
        content.ownerDocument.addEventListener('pointerdown', this.dismissOutside, true);
        content.ownerDocument.addEventListener('click', this.dismissOutside, true);
        // Capture activation using the same public kernel hit test as the viewer.
        // This prevents the package's generic below-canvas quantity editor.
        this.pointerStart = event => { this.pointer = {x: event.clientX, y: event.clientY}; };
        content.addEventListener('pointerdown', this.pointerStart, true);
        this.activate = event => {
            if (event.detail > 0 && this.pointer && Math.hypot(event.clientX - this.pointer.x, event.clientY - this.pointer.y) > 5) return;
            if (this.layer.contains(event.target)) return;
            let id = event.target.closest?.('button[data-node-id]')?.dataset.nodeId;
            const svg = content.querySelector('.venue-layout-viewer > svg');
            if (!id && svg?.contains(event.target)) {
                const inverse = svg.getScreenCTM()?.inverse();
                if (inverse) {
                    const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(inverse);
                    id = globalThis.VenueLayoutKernel.hitTest(this.json, point.x, point.y);
                }
            }
            const entry = this.entries.get(id);
            if (!entry) return;
            event.stopImmediatePropagation(); event.preventDefault(); this.edit(entry);
        };
        content.addEventListener('click', this.activate, true);
        this.update(options.capacityPresentation);
    }
    focusArea(entry) {
        this.content.querySelector(`button[data-node-id="${entry.id}"]`)?.focus({preventScroll: true});
    }
    dismiss(entry, restoreFocus = false) {
        entry.editing = false;
        this.refresh(entry);
        if (restoreFocus) this.focusArea(entry);
    }
    edit(entry) {
        if (entry.pending) return;
        if (!entry.editing) {
            for (const other of this.entries.values()) if (other !== entry) this.dismiss(other);
            entry.error = '';
            entry.editing = true;
            entry.draft = entry.state.quantity || (entry.state.selectable ? 1 : 0);
        }
        this.refresh(entry); this.position(); entry.count.focus({preventScroll: true});
    }
    step(entry, delta) {
        entry.draft = Math.max(0, Math.min(entry.state.available, entry.draft + delta));
        this.refresh(entry);
    }
    async confirm(entry) {
        if (entry.pending) return;
        entry.pending = true; entry.error = ''; this.refresh(entry);
        let restoreFocus = false;
        try {
            const result = await this.options.onQuantityRequested(entry.id, entry.draft);
            if (this.disposed) return;
            if (result?.accepted) {
                restoreFocus = entry.editing;
                entry.state = {...entry.state, quantity: entry.draft}; entry.editing = false;
            } else entry.error = result?.message || this.options.messages.quantityRejected;
        } catch (error) { entry.error = error.message || this.options.messages.quantityRejected; }
        finally {
            entry.pending = false;
            if (!this.disposed) {
                this.refresh(entry); this.position();
                if (restoreFocus) this.focusArea(entry);
                else if (entry.editing) entry.count.focus({preventScroll: true});
            }
        }
    }
    update(presentation) {
        for (const entry of this.entries.values()) {
            entry.state = presentation[entry.id] || {quantity: 0, available: 0, selectable: false};
            this.refresh(entry);
        }
        this.position();
    }
    refresh(entry) {
        const {state, editing, pending} = entry;
        entry.group.hidden = !editing;
        const count = editing ? entry.draft : state.quantity || 0;
        const summary = count > 0 ? BlueprintStrings.placeCount(count) : BlueprintStrings.chooseQuantity;
        entry.count.textContent = editing ? String(count) : summary;
        entry.heading.hidden = entry.details.hidden = !editing;
        entry.details.textContent = [state.priceLabel, this.options.messages.availableCount.replace('{count}', state.available)].filter(Boolean).join(' · ');
        entry.group.classList.toggle('has-selection', !editing && count > 0);
        entry.count.setAttribute('aria-label', `${entry.node.label || this.options.messages.standing}: ${editing ? BlueprintStrings.placeCount(count) : summary}`);
        entry.count.setAttribute('aria-expanded', String(editing));
        entry.count.disabled = pending;
        entry.group.setAttribute('aria-busy', String(pending));
        entry.group.classList.toggle('is-editing', editing);
        entry.group.setAttribute('aria-description', this.options.messages.availableCount.replace('{count}', state.available));
        entry.minus.hidden = entry.plus.hidden = entry.confirm.hidden = !editing;
        entry.minus.disabled = pending || count <= 0;
        entry.plus.disabled = pending || !state.selectable || count >= state.available;
        entry.confirm.disabled = pending || count > state.available || (count > 0 && !state.selectable);
        entry.message.textContent = entry.error || (pending ? this.options.messages.pending : !state.selectable ? state.tooltip : '');
        entry.message.hidden = !entry.message.textContent;
    }
    position() {
        const svg = this.content.querySelector('.venue-layout-viewer > svg');
        const matrix = svg?.getScreenCTM();
        if (!matrix) return;
        const parent = this.content.getBoundingClientRect();
        for (const entry of this.entries.values()) {
            const b = entry.bounds;
            const left = b.x * matrix.a + matrix.e - parent.left;
            const top = b.y * matrix.d + matrix.f - parent.top;
            const width = b.width * matrix.a, height = b.height * matrix.d;
            const controlWidth = entry.group.offsetWidth, controlHeight = entry.group.offsetHeight;
            // Keep the label at the area's center clear. Put controls in its lower half.
            const inside = width >= controlWidth + 16 && height >= controlHeight * 2 + 24;
            const x = Math.max(8, Math.min(parent.width - controlWidth - 8, left + (width - controlWidth) / 2));
            let y = inside ? top + height - controlHeight - 8 : top + height + 4;
            const zoom = this.content.querySelector('.blueprint-zoom-controls')?.getBoundingClientRect();
            if (zoom && x + controlWidth > zoom.left - parent.left && x < zoom.right - parent.left &&
                y + controlHeight > zoom.top - parent.top && y < zoom.bottom - parent.top && top >= controlHeight + 12) {
                y = top - controlHeight - 4;
            }
            entry.group.hidden = !entry.editing || left + width < 0 || top + height < 0 || left > parent.width || top > parent.height;
            entry.group.style.left = `${x}px`;
            entry.group.style.top = `${Math.max(8, Math.min(parent.height - controlHeight - 8, y))}px`;
        }
    }
    dispose() {
        this.disposed = true;
        this.content.ownerDocument.removeEventListener('pointerdown', this.dismissOutside, true);
        this.content.ownerDocument.removeEventListener('click', this.dismissOutside, true);
        this.content.removeEventListener('click', this.activate, true);
        this.content.removeEventListener('pointerdown', this.pointerStart, true);
        this.layer.remove();
    }
}
