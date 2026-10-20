import { SeatWidgetHelper } from './seat_widget_helper.js';
import { SeatStates } from './blueprint_config.js';
import { BlueprintIcons } from './blueprint_icons.js';

export class SeatStyler {
    /**
     * Applies the appropriate visual style to a seat element based on its object state.
     * @param {HTMLElement} element - The container element for the seat visual.
     * @param {Object} obj - The seat data object (must contain state).
     * @param {number} seatSize - The current pixel size of the seat grid.
     */
    static applyStyle(element, obj, seatSize) {
        // defined in flutter: SeatWidgetHelper
        const baseSize = 40;
        const scale = seatSize / baseSize; // Scale relative to flutter's 40px standard

        // User requested "rectangles smaller" -> Increase padding
        const padding = SeatWidgetHelper.padding * 1.8 * scale; 
        const focusedPadding = SeatWidgetHelper.focusedPadding * scale;
        
        // User requested "much more rounded". 
        const baseRadius = 8.0; 
        const borderRadiusVal = baseRadius * scale;

        const state = obj.state || SeatStates.AVAILABLE; 
        
        let color = SeatWidgetHelper.getSeatColor(state);
        let cursor = 'default';
        let margin = 0;
        let radius = 0;
        let content = '';

        // Logic branching based on state to determine layout props (margin, radius, cursor)
        switch (state) {
            case SeatStates.AVAILABLE: 
            case SeatStates.SELECTED: 
                cursor = 'pointer';
                margin = padding;
                radius = borderRadiusVal;
                break;
            case SeatStates.SELECTED_BY_ME:
                cursor = 'pointer';
                margin = focusedPadding;
                radius = borderRadiusVal; 
                // Checkmark
                content = BlueprintIcons.checkmark;
                break;
            case SeatStates.ORDERED:
                margin = padding;
                radius = borderRadiusVal;
                // X Icon (Refined)
                content = BlueprintIcons.orderX;
                break;
            case SeatStates.USED:
            case SeatStates.TAKEN: // aliases
                color = SeatWidgetHelper.getSeatColor(SeatStates.USED); // Ensure aliasing works
                margin = padding;
                radius = borderRadiusVal;
                break;
            case SeatStates.BLACK:
                margin = 0; 
                radius = 0; 
                break;
            default:
                break;
        }

        // Apply to element (the outer container for the seat)
        element.innerHTML = '';
        // Reset container inheritance issues if any (but classes should handle it)
        element.className = 'blueprint-seat-visual-inner'; // Used for inner visuals usually but we reuse or reset

        const visual = document.createElement('div');
        visual.className = 'blueprint-seat-visual';
        
        // Dynamic Styles
        visual.style.width = `calc(100% - ${margin * 2}px)`;
        visual.style.height = `calc(100% - ${margin * 2}px)`;
        visual.style.margin = `${margin}px`;
        visual.style.backgroundColor = color;
        visual.style.borderRadius = `${radius}px`; 
        visual.style.cursor = cursor;
        
        if (content) {
            visual.innerHTML = content;
        }

        element.appendChild(visual);
    }
}
