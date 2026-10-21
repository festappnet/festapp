import { LocalizationService } from '../../services/localization_service.js';

export class BlueprintStrings {
    static get unassignedProduct() { return LocalizationService.tr('FeatureBlueprint.noProductAssigned', {}, 'No product assigned'); }
    static seatState(state) { return LocalizationService.tr(`FeatureBlueprint.seatStates.${state}`); }
    static get viewerMessages() {
        return Object.fromEntries(["viewerLabel", "places", "place", "standing", "availableCount", "confirmQuantity", "addOne", "removeOne", "selectedQuantity", "quantityRejected", "placeUnavailable", "selectedPlaces", "releasedPlaces", "selectionRejected", "backgroundUnavailable", "placesTogether", "pending", "available", "occupied", "reserved", "blocked", "unavailable", "disabled", "sold"].map(key => [key, LocalizationService.tr(`FeatureBlueprint.viewer.${key}`)]));
    }
    static get layoutTitle() { return LocalizationService.tr('FeatureBlueprint.changeTitle', {}, 'Seat layout'); }
    static get layoutUnavailable() { return LocalizationService.tr('FeatureBlueprint.layoutUnavailable', {}, 'This layout is not ready.'); }
    static get close() { return LocalizationService.tr('Common.close', {}, 'Close'); }

    static get zoomControls() { return LocalizationService.tr('FeatureBlueprint.zoomControls', {}, 'Map zoom'); }
    static get zoomIn() { return LocalizationService.tr('FeatureBlueprint.zoomIn', {}, 'Zoom in'); }
    static get zoomOut() { return LocalizationService.tr('FeatureBlueprint.zoomOut', {}, 'Zoom out'); }
    static get fitToScreen() { return LocalizationService.tr('FeatureBlueprint.fitToScreen', {}, 'Fit map'); }
    static get maxTicketsReached() { return LocalizationService.tr('FeatureBlueprint.maxTicketsReached') || "Maximum number of tickets reached"; }
}
