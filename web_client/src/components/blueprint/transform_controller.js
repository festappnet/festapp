
import { BlueprintConfig } from './blueprint_config.js';

export class TransformController {
    constructor() {
        this.state = { x: 0, y: 0, scale: 1 };
        this.dims = {
            viewportW: 0,
            viewportH: 0,
            contentW: 100,
            contentH: 100
        };
    }

    updateDimensions(viewportW, viewportH, contentW, contentH) {
        this.dims.viewportW = viewportW;
        this.dims.viewportH = viewportH;
        this.dims.contentW = contentW || 100;
        this.dims.contentH = contentH || 100;
    }

    setState(x, y, scale) {
        this.state = { x, y, scale };
    }

    getState() {
        return { ...this.state };
    }

    getFitScale() {
        const { viewportW, viewportH, contentW, contentH } = this.dims;
        if (!contentW || !contentH || !viewportW || !viewportH) return 1;
        // 5% margin (0.95) for "mini border"
        return Math.min(viewportW / contentW, viewportH / contentH) * 0.95;
    }

    fitToScreen() {
        if (!this.dims.contentW || !this.dims.contentH) return;

        const { viewportW, viewportH, contentW, contentH } = this.dims;
        const scale = this.getFitScale();

        // Center it
        const scaledWidth = contentW * scale;
        const scaledHeight = contentH * scale;

        const offsetX = (viewportW - scaledWidth) / 2;
        const offsetY = (viewportH - scaledHeight) / 2;

        this.state = { x: offsetX, y: offsetY, scale };
        return this.state;
    }

    // Unified interaction handler to prevent state drift
    onInteractionUpdate(deltaX, deltaY, scaleFactor, cx, cy, containerRect, allowOverscroll = true) {
         const { contentW, contentH } = this.dims;
         
         // 1. Calculate Target Scale
         let newScale = this.state.scale * scaleFactor;
         
         // Limits
         const fitScale = this.getFitScale();
         const minScale = fitScale; // Hard floor? or Allow resistance?
         const maxScale = fitScale * (BlueprintConfig.maxScale || 5);
         
         // Clamp Scale (Simple hard limits for stability first)
         if (newScale < minScale) newScale = minScale;
         if (newScale > maxScale) newScale = maxScale;
         
         // Recalculate factor based on clamped scale to ensure position math matches
         // effectiveFactor = newScale / oldScale
         // BUT: If we clamp, we must use the effective factor for the position update 
         // so the zoom is consistently "around the mouse".
         const effectiveFactor = newScale / this.state.scale;
         
         // 2. Calculate New Position
         // Math:
         // We want to translate by (deltaX, deltaY)
         // AND scale by effectiveFactor around (cx, cy)
         // Relative to Container (cx, cy are client coords)
         
         const relCx = cx - containerRect.left;
         const relCy = cy - containerRect.top;
         
         // Start Position
         const oldX = this.state.x;
         const oldY = this.state.y;
         
         // Panned Position
         const pannedX = oldX + deltaX;
         const pannedY = oldY + deltaY;
         
         // Zoomed Position (around relCx, relCy)
         // Point P in content under relCx was: P = (relCx - pannedX) / oldScale (Wait, no, we zoom implies scale change)
         // Formula: newPos = Center - (Center - OldPos) * Factor
         // Here "OldPos" is pannedX.
         
         const newX = relCx - (relCx - pannedX) * effectiveFactor;
         const newY = relCy - (relCy - pannedY) * effectiveFactor;
         
         // 3. Apply Limits
         const { viewportW, viewportH } = this.dims;
         const scaledW = contentW * newScale;
         const scaledH = contentH * newScale;
         
         // --- Consistency with onInteractionUpdate ---
         const margin = BlueprintConfig.panMargin || 0;
         
         let minX, maxX, minY, maxY;
         
         if (scaledW < viewportW) {
             const gapX = (viewportW - scaledW) / 2;
             minX = gapX; 
             maxX = gapX;
         } else {
             // Allow panning past edge by 'margin'
             // Valid range: [viewportW - scaledW - margin, 0 + margin]
             minX = viewportW - scaledW - margin;
             maxX = margin;
         }
         
         if (scaledH < viewportH) {
             const gapY = (viewportH - scaledH) / 2;
             minY = gapY;
             maxY = gapY;
         } else {
             minY = viewportH - scaledH - margin;
             maxY = margin;
         }
         
         // Apply Rubber Banding using Config
         // If we are at fit scale (or smaller), strictly lock position (No Pan allowed)
         const isAtMinScale = newScale <= fitScale * 1.001;
         
         let constrainedX, constrainedY;
         
         if (allowOverscroll && !isAtMinScale) {
             const OVERSCROLL_LIMIT = BlueprintConfig.overscrollLimit || 150;
             constrainedX = this._getRubberBandedVal(newX, minX, maxX, OVERSCROLL_LIMIT);
             constrainedY = this._getRubberBandedVal(newY, minY, maxY, OVERSCROLL_LIMIT);
         } else {
             // Strict Clamping
             constrainedX = newX;
             if (constrainedX < minX) constrainedX = minX;
             if (constrainedX > maxX) constrainedX = maxX;
             
             constrainedY = newY;
             if (constrainedY < minY) constrainedY = minY;
             if (constrainedY > maxY) constrainedY = maxY;
         }

         this.state = {
             x: constrainedX,
             y: constrainedY,
             scale: newScale
         };

         return this.state;
    }

    getConstrainedState() {
        const { viewportW, viewportH, contentW, contentH } = this.dims;
        
        const fitScale = this.getFitScale();
        let targetScale = this.state.scale;
        
        // Max limit relative to fit
        const maxAllowed = fitScale * (BlueprintConfig.maxScale || 5);

        // Snap scale logic
        if (targetScale < fitScale * 0.999) targetScale = fitScale; // Tolerance
        if (targetScale > maxAllowed) targetScale = maxAllowed;

        const scaledW = contentW * targetScale;
        const scaledH = contentH * targetScale;
        
        // --- Consistency with onInteractionUpdate ---
        const margin = BlueprintConfig.panMargin || 0;

        let minX, maxX, minY, maxY;

        if (scaledW < viewportW) {
             const gapX = (viewportW - scaledW) / 2;
             minX = gapX;
             maxX = gapX;
        } else {
             // Valid range includes margin
             minX = viewportW - scaledW - margin;
             maxX = margin;
        }

        if (scaledH < viewportH) {
             const gapY = (viewportH - scaledH) / 2;
             minY = gapY;
             maxY = gapY;
        } else {
             minY = viewportH - scaledH - margin;
             maxY = margin;
        }

        let targetX = this.state.x;
        let targetY = this.state.y;
        
        // X Constraints
        if (targetX < minX) targetX = minX;
        if (targetX > maxX) targetX = maxX;

        // Y Constraints
        if (targetY < minY) targetY = minY;
        if (targetY > maxY) targetY = maxY;
        
        return { x: targetX, y: targetY, scale: targetScale };
    }
    
    shouldSnapBack() {
        const constrained = this.getConstrainedState();
        return (Math.abs(constrained.x - this.state.x) > 0.5 || 
                Math.abs(constrained.y - this.state.y) > 0.5 ||
                Math.abs(constrained.scale - this.state.scale) > 0.001);
    }

    // --- Private / Helpers ---

    _getTouchingAxis() {
        const { viewportW, viewportH, contentW, contentH } = this.dims;
        
        const scaleX = viewportW / contentW;
        const scaleY = viewportH / contentH;
        
        if (Math.abs(scaleX - scaleY) < 0.001) return 'both';
        return scaleX < scaleY ? 'x' : 'y';
    }

    _getRubberBandedVal(val, min, max, limit) {
        if (val >= min && val <= max) return val;
        if (val < min) {
            const diff = min - val;
            return min - limit * (1 - Math.exp(-diff / (limit * 1.5)));
        } else {
             const diff = val - max;
             return max + limit * (1 - Math.exp(-diff / (limit * 1.5)));
        }
    }
}
