export const OccasionCardAction = Object.freeze({
    reserve: 'reserve',
    details: 'details',
    app: 'app',
});

export function resolveOccasionCardAction({
    hasFormFeature,
    isDescriptionEmpty,
    isAppSupported,
}) {
    if (hasFormFeature && (!isAppSupported || isDescriptionEmpty)) {
        return OccasionCardAction.reserve;
    }
    if (hasFormFeature) return OccasionCardAction.details;
    return OccasionCardAction.app;
}
