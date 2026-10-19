import { SeatStates } from './blueprint_config.js';

export class SeatWidgetHelper {
    static get padding() { return 2.5; }
    static get focusedPadding() { return 0.8; }

    /**
     * Get seat color based on state.
     * Matches Flutter SeatWidgetHelper.getSeatColor
     */
    static getSeatColor(state) {
        // ThemeConfig colors
        const colors = {
            darkGreen: 'hsl(122, 50%, 30%)',
            blueColor: 'hsl(262, 50%, 30%)',
            black26: 'rgba(0, 0, 0, 0.26)',
            black87: 'rgba(0, 0, 0, 0.87)',
            black12: 'rgba(0, 0, 0, 0.12)',
            transparent: 'rgba(0, 0, 0, 0)'
        };

        switch (state) {
            case SeatStates.AVAILABLE:
                return colors.darkGreen;
            case SeatStates.SELECTED_BY_ME:
                return colors.darkGreen;
            case SeatStates.SELECTED:
                return colors.black26;
            case SeatStates.BLACK:
                return colors.black87;
            case SeatStates.USED:
                return colors.blueColor;
            case SeatStates.ORDERED:
                return colors.black12;
            case SeatStates.EMPTY:
                return colors.transparent;
            default:
                return colors.transparent;
        }
    }
}
