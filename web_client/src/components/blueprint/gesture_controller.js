
export class GestureController {
    constructor(container, callbacks) {
        this.container = container;
        // Callbacks: onPan, onZoom, onTap, onInteractionStart, onInteractionEnd
        this.callbacks = callbacks || {};

        this.state = {
            pressed: false,
            // Track touch points
            lastCount: 0,
            lastX: 0,
            lastY: 0,
            lastDist: 0,
            lastCx: 0,
            lastCy: 0,
            
            // Tap detection
            isTapCandidate: false,
            touchStartX: 0,
            touchStartY: 0,
            
            // Mouse specific
            mousePanning: false,
            mouseLastX: 0,
            mouseLastY: 0
        };

        this._bindMethods();
        this.attachEvents();
    }

    _bindMethods() {
        this._boundOnMouseMove = this.onMouseMove.bind(this);
        this._boundOnMouseUp = this.onMouseUp.bind(this);
        this._boundOnTouchStart = this.onTouchStart.bind(this);
        this._boundOnTouchMove = this.onTouchMove.bind(this);
        this._boundOnTouchEnd = this.onTouchEnd.bind(this);
        this._boundOnWheel = this.onWheel.bind(this);
        this._boundOnGesture = (e) => e.preventDefault();
    }

    attachEvents() {
        this.container.onmousedown = (e) => this.onMouseDown(e);
        this.container.onwheel = this._boundOnWheel;

        window.addEventListener('mousemove', this._boundOnMouseMove);
        window.addEventListener('mouseup', this._boundOnMouseUp);

        // Passive false to prevent scrolling
        this.container.addEventListener('touchstart', this._boundOnTouchStart, { passive: false });
        window.addEventListener('touchmove', this._boundOnTouchMove, { passive: false });
        window.addEventListener('touchend', this._boundOnTouchEnd);

        document.addEventListener('gesturestart', this._boundOnGesture);
        document.addEventListener('gesturechange', this._boundOnGesture);
        document.addEventListener('gestureend', this._boundOnGesture);
    }

    destroy() {
        window.removeEventListener('mousemove', this._boundOnMouseMove);
        window.removeEventListener('mouseup', this._boundOnMouseUp);
        
        if (this.container) {
            this.container.removeEventListener('touchstart', this._boundOnTouchStart);
            this.container.onmousedown = null;
            this.container.onwheel = null;
        }
        
        window.removeEventListener('touchmove', this._boundOnTouchMove);
        window.removeEventListener('touchend', this._boundOnTouchEnd);
        
        document.removeEventListener('gesturestart', this._boundOnGesture);
        document.removeEventListener('gesturechange', this._boundOnGesture);
        document.removeEventListener('gestureend', this._boundOnGesture);
    }

    // --- Mouse ---

    onMouseDown(e) {
        if (this.callbacks.onInteractionStart) this.callbacks.onInteractionStart();
        e.preventDefault();
        this.state.mouseLastX = e.clientX;
        this.state.mouseLastY = e.clientY;
        this.state.mousePanning = true;
        this.container.style.cursor = 'grabbing';
    }

    onMouseMove(e) {
        if (!this.state.mousePanning) return;
        e.preventDefault();
        const deltaX = e.clientX - this.state.mouseLastX;
        const deltaY = e.clientY - this.state.mouseLastY;
        this.state.mouseLastX = e.clientX;
        this.state.mouseLastY = e.clientY;

        if (this.callbacks.onPan) {
            this.callbacks.onPan(deltaX, deltaY, e.clientX, e.clientY);
        }
    }

    onMouseUp(e) {
        if (this.state.mousePanning) {
            this.state.mousePanning = false;
            this.container.style.cursor = 'default';
            if (this.callbacks.onInteractionEnd) this.callbacks.onInteractionEnd();
        }
    }

    onWheel(e) {
        e.preventDefault();
        if (this.callbacks.onInteractionStart) this.callbacks.onInteractionStart();

        const sensitivity = 0.0015;
        const factor = Math.exp(-e.deltaY * sensitivity);

        if (this.callbacks.onZoom) {
            this.callbacks.onZoom(factor, e.clientX, e.clientY);
        }
        
        // Debounce end ? Usually wheel is discrete, but we can assume 'end' after short timeout if needed.
        // For BlueprintRenderer, it handles snapBack on timeout, so we can expose that or leave it to renderer.
        // We'll trust the renderer to handle 'end' logic via debounce if it wants, 
        // or we can just fire callbacks.
    }

    // --- Touch ---

    onTouchStart(e) {
        if (e.cancelable) e.preventDefault();
        if (this.callbacks.onInteractionStart) this.callbacks.onInteractionStart();

        if (e.touches.length === 1) {
            this.state.isTapCandidate = true;
            this.state.touchStartX = e.touches[0].clientX;
            this.state.touchStartY = e.touches[0].clientY;
        } else {
            this.state.isTapCandidate = false;
        }
        
        // Reset tracking on new finger
        this.state.lastCount = 0;
    }

    onTouchMove(e) {
        if (e.cancelable) e.preventDefault();
        
        // process.stdout.write(`Move: touches=${e.touches.length} lastCount=${this.state.lastCount}\n`);

        // Invalidate Tap
        if (this.state.isTapCandidate) {
             const t = e.touches[0];
             const dist = Math.hypot(t.clientX - this.state.touchStartX, t.clientY - this.state.touchStartY);
             if (dist > 10) this.state.isTapCandidate = false;
        }

        const touches = e.touches;
        const count = touches.length;

        // 1 Finger: Pan
        if (count === 1) {
            const x = touches[0].clientX;
            const y = touches[0].clientY;

            if (this.state.lastCount !== 1) {
                this.state.lastX = x;
                this.state.lastY = y;
                this.state.lastCount = 1;
                return;
            }

            const deltaX = x - this.state.lastX;
            const deltaY = y - this.state.lastY;
            this.state.lastX = x;
            this.state.lastY = y;

            if (this.callbacks.onPan) {
                this.callbacks.onPan(deltaX, deltaY, x, y);
            }
        }
        // 2 Fingers: Pinch
        else if (count === 2) {
            const t1 = touches[0];
            const t2 = touches[1];

            const dist = Math.hypot(t1.clientX - t2.clientX, t1.clientY - t2.clientY);
            const cx = (t1.clientX + t2.clientX) / 2;
            const cy = (t1.clientY + t2.clientY) / 2;
            
            // process.stdout.write(`Pinch: dist=${dist} lastDist=${this.state.lastDist} count=${count} lastCount=${this.state.lastCount}\n`);

            if (this.state.lastCount !== 2) {
                this.state.lastDist = dist;
                this.state.lastCx = cx;
                this.state.lastCy = cy;
                this.state.lastCount = 2;
                return;
            }

            const deltaX = cx - this.state.lastCx;
            const deltaY = cy - this.state.lastCy;
            // ("safeLastDist", this.state.lastDist);
            const safeLastDist = this.state.lastDist < 1 ? 1 : this.state.lastDist;
            const factor = dist / safeLastDist;

            // Update Sync
            this.state.lastDist = dist;
            this.state.lastCx = cx;
            this.state.lastCy = cy;
            
            // process.stdout.write(`Firing onPinch: factor=${factor}\n`);

            if (this.callbacks.onPinch) {
                // onPinch(deltaX, deltaY, zoomFactor, centerX, centerY)
                this.callbacks.onPinch(deltaX, deltaY, factor, cx, cy);
            }
        } 
        else {
             this.state.lastCount = 0;
        }
    }

    onTouchEnd(e) {
        if (e.touches.length === 0 && this.state.isTapCandidate) {
            if (this.callbacks.onTap) {
                this.callbacks.onTap(this.state.touchStartX, this.state.touchStartY);
            }
        }
        
        if (e.touches.length === 0) {
            this.state.lastCount = 0;
            if (this.callbacks.onInteractionEnd) this.callbacks.onInteractionEnd();
        } else {
            this.state.lastCount = 0; 
        }
        this.state.isTapCandidate = false;
    }
}
