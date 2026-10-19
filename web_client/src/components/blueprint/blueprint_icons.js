
import { BlueprintConfig } from './blueprint_config.js';

export const BlueprintIcons = {
    get checkmark() {
        return `<svg viewBox="0 0 24 24" style="width:70%;height:70%;display:block;"><path d="M5 12 L9 16 L19 6" fill="none" stroke="white" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" /></svg>`;
    },
    
    get orderX() {
        const color = BlueprintConfig.colors.lessContrastyBlack;
        return `<svg viewBox="0 0 24 24" style="width:70%;height:70%;display:block;">
            <line x1="3" y1="3" x2="21" y2="21" stroke="${color}" stroke-width="1.5" stroke-linecap="round" />
            <line x1="21" y1="3" x2="3" y2="21" stroke="${color}" stroke-width="1.5" stroke-linecap="round" />
        </svg>`;
    }
};
