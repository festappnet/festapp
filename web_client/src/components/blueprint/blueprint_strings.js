import { LocalizationService } from '../../services/localization_service.js';

export class BlueprintStrings {
    static get zoomControls() { return LocalizationService.tr('FeatureBlueprint.zoomControls', {}, 'Map zoom'); }
    static get zoomIn() { return LocalizationService.tr('FeatureBlueprint.zoomIn', {}, 'Zoom in'); }
    static get zoomOut() { return LocalizationService.tr('FeatureBlueprint.zoomOut', {}, 'Zoom out'); }
    static get fitToScreen() { return LocalizationService.tr('FeatureBlueprint.fitToScreen', {}, 'Fit map'); }
    static get maxTicketsReached() { return LocalizationService.tr('FeatureBlueprint.maxTicketsReached') || "Maximum number of tickets reached"; }
}
