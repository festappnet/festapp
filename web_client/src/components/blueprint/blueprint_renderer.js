

import { formatPrice } from '../../utils/formatters.js';
import { CommonStrings } from '../shared/common_strings.js';
import { SeatWidgetHelper } from './seat_widget_helper.js';
import { SeatStyler } from './seat_styler.js';
import { BlueprintConfig, SeatStates } from './blueprint_config.js';
import { SvgUtils } from './svg_utils.js';
import { TooltipProvider } from './tooltip_provider.js';
import { BlueprintDataPreparer } from './blueprint_data_preparer.js';
import { TransformController } from './transform_controller.js';
import { GestureController } from './gesture_controller.js';
import { BlueprintStrings } from './blueprint_strings.js';

export class BlueprintRenderer {
    constructor(container) {
        this.container = container;
        this.state = {
            panning: false,
            start: { x: 0, y: 0 },
            scalingMode: 'min' // Default requested by user (n. 4)
        };
        this.controller = new TransformController();
        this.gestureController = null;
        this.seatSize = BlueprintConfig.seatSize;
        this.data = null;
        this.onSeatClick = null;

        // Fix for "zoomed in" issue: ensure we fit to screen when container gets dimensions
        this.resizeObserver = new ResizeObserver(() => {
            if (this.data && this.contentWidth && this.contentHeight) {
                this.fitToScreen();
            }
        });
        this.resizeObserver.observe(this.container);
    }

    setScalingMode(mode) {
        this.state.scalingMode = mode;
        // Re-process not needed if data already prepared, but simple enough to re-render
        // Clear and re-render
        this.container.innerHTML = '';
        
        // Re-init container
        this.container.classList.add('blueprint-renderer-container');

        this.transformContainer = document.createElement('div');
        this.transformContainer.className = 'blueprint-transform-container';
        this.container.appendChild(this.transformContainer);
        
        // Apply sizing
        if (this.contentWidth) {
             this.transformContainer.style.width = this.contentWidth + 'px';
             this.transformContainer.style.height = this.contentHeight + 'px';
        }

        this.createZoomControls();
        this.renderBackground();
        this.renderSeats();
        this.fitToScreen();
        this.attachEvents();
    }

    render(data, onSeatClick) {
        // Process Data via Preparer
        const prepared = BlueprintDataPreparer.prepare(data);
        if (!prepared) throw new Error('Blueprint data unavailable');
        this.data = prepared;
        // Map meta to instance properties for compatibility
        if (prepared.meta) {
            Object.assign(this, prepared.meta);
        }

        this.onSeatClick = onSeatClick;
        this.container.innerHTML = '';
        this.container.classList.add('blueprint-renderer-container');

        // Transform Container
        this.transformContainer = document.createElement('div');
        this.transformContainer.className = 'blueprint-transform-container';
        // Width/Height set from this.contentWidth (mapped from meta)
        if (this.contentWidth) {
             this.transformContainer.style.width = this.contentWidth + 'px';
             this.transformContainer.style.height = this.contentHeight + 'px';
        } 
        
        this.container.appendChild(this.transformContainer);

        this.createZoomControls();

        // Build Tooltip
        this.createTooltip();

        // Render Background
        this.renderBackground();

        // Render Seats
        this.renderSeats();

        // Fit to Screen
        this.fitToScreen();

        // Attach Events
        this.attachEvents();
    }



    renderBackground() {
        const bgSource = this.data.background_svg;
        if (!bgSource) return;

        const bgContainer = document.createElement('div');
        bgContainer.className = 'blueprint-bg-container';
        
        const { svg: processedSvg, isSvg } = SvgUtils.prepareBackgroundSvg(bgSource);

        if (isSvg) {
             bgContainer.innerHTML = processedSvg;
        } else if (bgSource.startsWith('http')) {
            const img = document.createElement('img');
            img.src = bgSource;
            img.alt = 'Blueprint Background';
            img.className = 'blueprint-bg-img';
            bgContainer.appendChild(img);
        }

        this.transformContainer.appendChild(bgContainer);
    }


    
    applySeatStyle(element, obj) {
        SeatStyler.applyStyle(element, obj, this.seatSize);
    }

    updateSeat(obj) {
        if (obj.element) {
            this.applySeatStyle(obj.element, obj);
        }
    }

    /**
     * Efficiently updates the visuals of seats without clearing the DOM.
     * Expects `this.data` to be already up-to-date or passed in.
     */
    updateSeatsDOM() {
        if (!this.data || !this.data.objects) return;
        
        // Optimize: assuming the DOM elements are already linked via obj.element
        // or we recall them by dataset.seatId if refs were lost (though they are simple JS objects in memory)
        this.data.objects.forEach(obj => {
             // If obj.element is missing, try to find it
             if (!obj.element) {
                 const container = this.transformContainer.querySelector(`.blueprint-seat-container[data-seat-id="${obj.id}"]`);
                 if (container) {
                     obj.element = container.querySelector('.blueprint-seat-visual-inner');
                 }
             }

             if (obj.element) {
                 this.applySeatStyle(obj.element, obj);
             }
        });
    }

    createZoomControls() {
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
        this.zoomInButton = button(BlueprintStrings.zoomIn, 'M5 12h14M12 5v14', () => this.zoomBy(1.25));
        this.zoomOutButton = button(BlueprintStrings.zoomOut, 'M5 12h14', () => this.zoomBy(1 / 1.25));
        const reset = button(BlueprintStrings.fitToScreen, 'M9 4H4v5M15 4h5v5M20 15v5h-5M4 15v5h5', () => this.fitToScreen());
        reset.classList.add('blueprint-zoom-reset');
        this.container.appendChild(controls);
    }

    zoomBy(factor) {
        this.cancelAnimation();
        this.hideTooltip();
        this.updateControllerDims();
        const rect = this.container.getBoundingClientRect();
        this.handleZoom(factor, rect.left + rect.width / 2, rect.top + rect.height / 2);
    }

    cancelAnimation() {
        if (this._animationFrame) cancelAnimationFrame(this._animationFrame);
        this._animationFrame = null;
    }

    updateControllerDims() {
        if (!this.container) return;
        this.controller.updateDimensions(
            this.container.clientWidth,
            this.container.clientHeight,
            this.contentWidth,
            this.contentHeight
        );
    }

    fitToScreen() {
        if (!this.contentWidth || !this.contentHeight) return;
        if (this.container.clientWidth === 0 || this.container.clientHeight === 0) return;

        this.cancelAnimation();
        this.updateControllerDims();
        this.controller.fitToScreen();
        this.updateTransform();
    }

    attachEvents() {
        if (this.gestureController) this.gestureController.destroy();
        this.gestureController = new GestureController(this.container, {
            onPan: (dx, dy, x, y) => this.handlePan(dx, dy, x, y),
            onZoom: (factor, x, y) => this.handleZoom(factor, x, y),
            onPinch: (dx, dy, factor, x, y) => this.handlePinch(dx, dy, factor, x, y),
            onTap: (x, y) => this.handleTap(x, y),
            onInteractionStart: () => {
                this.updateControllerDims();
                 if (this._animationFrame) {
                    cancelAnimationFrame(this._animationFrame);
                    this._animationFrame = null;
                 }
            },
            onInteractionEnd: () => this.snapBack()
        });
    }

    handlePan(dx, dy, x, y) {
        this.controller.onInteractionUpdate(dx, dy, 1, x, y, this.container.getBoundingClientRect());
        this.updateTransform();
    }

    handleZoom(factor, x, y) {
        this.controller.onInteractionUpdate(0, 0, factor, x, y, this.container.getBoundingClientRect(), false);
        this.updateTransform();
    }

    handlePinch(dx, dy, factor, x, y) {
        this.controller.onInteractionUpdate(dx, dy, factor, x, y, this.container.getBoundingClientRect());
        this.updateTransform();
    }

    handleTap(x, y) {
         const target = document.elementFromPoint(x, y);
         if (target) {
             const seatEl = target.closest('.blueprint-seat-container');
             if (seatEl && seatEl.dataset.seatId) {
                 const seatId = seatEl.dataset.seatId;
                 const obj = this.data.objects.find(o => String(o.id) === String(seatId));
                 if (obj && this.onSeatClick) {
                     this.onSeatClick(obj);
                 }
             }
         }
    }

    updateTransform() {
        if (!this.transformContainer) return;
        const { x, y, scale } = this.controller.state;
        this.transformContainer.style.transform = `translate(${x}px, ${y}px) scale(${scale})`;
        if (this.zoomInButton && this.zoomOutButton) {
            const relativeScale = scale / this.controller.getFitScale();
            this.zoomOutButton.disabled = relativeScale <= 1.001;
            this.zoomInButton.disabled = relativeScale >= (BlueprintConfig.maxScale || 5) - 0.001;
        }
    }

    snapBack() {
        this.updateControllerDims();
        const constrained = this.controller.getConstrainedState();
        
        // Check if we are far enough to warrant animation
        const { x, y, scale } = this.controller.state;
        if (Math.abs(constrained.x - x) > 0.5 || 
            Math.abs(constrained.y - y) > 0.5 ||
            Math.abs(constrained.scale - scale) > 0.001) {
            this.animateTo(constrained);
        }
    }

    animateTo(target) {
        const startX = this.controller.state.x;
        const startY = this.controller.state.y;
        const startScale = this.controller.state.scale;
        const startTime = performance.now();
        const duration = BlueprintConfig.snapAnimationDuration; // ms

        const step = (time) => {
            const progress = (time - startTime) / duration;
            if (progress < 1) {
                // Ease out cubic
                const ease = 1 - Math.pow(1 - progress, 3);
                // Update controller state manually or expose a setter?
                this.controller.state.x = startX + (target.x - startX) * ease;
                this.controller.state.y = startY + (target.y - startY) * ease;
                this.controller.state.scale = startScale + (target.scale - startScale) * ease;
                this.updateTransform();
                this._animationFrame = requestAnimationFrame(step);
            } else {
                this.controller.state.x = target.x;
                this.controller.state.y = target.y;
                this.controller.state.scale = target.scale;
                this.updateTransform();
                this._animationFrame = null;
            }
        };
        if (this._animationFrame) cancelAnimationFrame(this._animationFrame);
        this._animationFrame = requestAnimationFrame(step);
    }
    
    createTooltip() {
        if (this.tooltipElement) return;

        this.tooltipElement = document.createElement('div');
        this.tooltipElement.className = 'blueprint-tooltip';

        document.body.appendChild(this.tooltipElement);
    }

    destroy() {
        this.cancelAnimation();
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
            this.resizeObserver = null;
        }

        if (this.gestureController) {
            this.gestureController.destroy();
            this.gestureController = null;
        }

        if (this.tooltipElement) {
            this.tooltipElement.remove();
            this.tooltipElement = null;
        }
    }



    processData() {
        // Now handled by BlueprintDataPreparer
        // Kept empty if anything calls it legacy-wise, but logic moved.
    }

    renderSeats() {
        const objects = this.data.objects || [];
        
        objects.forEach(obj => {
             // Only render items with x/y
             if (obj.x === undefined || obj.y === undefined) return;

             const el = document.createElement('div');
             el.className = 'blueprint-seat-container';
             el.dataset.seatId = obj.id;
             el.style.left = (obj.x * this.seatSize) + 'px';
             el.style.top = (obj.y * this.seatSize) + 'px';
             el.style.width = this.seatSize + 'px';
             el.style.height = this.seatSize + 'px';
             
             // Inner Seat Visuals
             const inner = document.createElement('div');
             inner.className = 'blueprint-seat-visual-inner'; 
             
             this.applySeatStyle(inner, obj);

             el.appendChild(inner);

             // Interaction
             el.onclick = (e) => {
                 e.stopPropagation(); 
                 if (this.onSeatClick) this.onSeatClick(obj);
             };

             // Tooltip Events
             el.onpointerenter = (e) => this.showTooltip(obj, e);
             el.onpointerleave = () => this.hideTooltip();
             el.onpointermove = (e) => this.updateTooltipPosition(e);

             this.transformContainer.appendChild(el);
             obj.element = inner; // Store ref to update later
        });
    }
    
    // ... (applySeatStyle, updateSeat, fitToScreen ...)

    getTooltipContent(obj) {
        const context = {
            productsMap: this.productsMap,
            ticketsMap: this.ticketsMap,
            ordersMap: this.ordersMap,
            optMap: this.optMap,
            data: this.data
        };
        return TooltipProvider.getContent(obj, context);
    }

    showTooltip(obj, e) {
        if (e && e.pointerType === 'touch') return;
        if (!this.tooltipElement) return;
        
        const content = this.getTooltipContent(obj);
        if (!content) return;
        
        this.tooltipElement.innerText = content;
        // Styles derived from class, no manual overrides besides display
        this.tooltipElement.style.display = 'block';
        this.updateTooltipPosition(e);
    }

    hideTooltip() {
        if (!this.tooltipElement) return;
        this.tooltipElement.style.display = 'none';
    }

    updateTooltipPosition(e) {
        if (e && e.pointerType === 'touch') return;
        if (!this.tooltipElement || this.tooltipElement.style.display === 'none') return;
        
        // Offset from mouse
        const offset = 15;
        this.tooltipElement.style.left = (e.clientX + offset) + 'px';
        this.tooltipElement.style.top = (e.clientY + offset) + 'px';
        
        // Boundary check (keep in viewport)
        const rect = this.tooltipElement.getBoundingClientRect();
        if (rect.right > window.innerWidth) {
            this.tooltipElement.style.left = (e.clientX - rect.width - offset) + 'px';
        }
        if (rect.bottom > window.innerHeight) {
            this.tooltipElement.style.top = (e.clientY - rect.height - offset) + 'px';
        }
    }

    getPinchDist(e) {
        return Math.hypot(
            e.touches[0].clientX - e.touches[1].clientX,
            e.touches[0].clientY - e.touches[1].clientY
        );
    }
}
