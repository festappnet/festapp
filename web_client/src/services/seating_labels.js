import { LocalizationService } from './localization_service.js';

export function seatingPlacementText(placement, legacyTitle) {
    const label = placement?.labelKey ? LocalizationService.tr(`OrderOverview.${placement.labelKey}`) : '';
    return [label, placement ? placement.value : legacyTitle].filter(Boolean).join(placement?.separator ?? ' ');
}

export function orderItemSeatingText(item) {
    const group = seatingPlacementText(
        item.placement,
        item.isStanding ? item.standingAreaTitle : item.spotGroupTitle,
    );
    const seatTitle = String(item.spotTitle ?? '').trim();
    const seat = !item.isStanding && seatTitle ? `${LocalizationService.tr('OrderOverview.seat')}: ${seatTitle}` : '';
    return [group, seat].filter(Boolean).join(' · ');
}
