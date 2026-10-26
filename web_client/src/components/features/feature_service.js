/**
 * Default currency for visual-only meta surcharge when admin leaves the per-product
 * currency field empty. Matches the placeholder shown in the admin input.
 * Independent of the product price currency (surcharge doesn't go through the bank).
 */
export const DEFAULT_META_SURCHARGE_CURRENCY = 'EUR';

export class FeatureService {
    static get FeatureConstants() {
        return {
            ticket: 'ticket',
            form: 'form',
            workshop: 'workshops',
            map: 'map',
            deposit: 'deposit'
        };
    }

    static isFeatureEnabled(featureCode, features) {
        if (!features || !Array.isArray(features)) return false;
        // Check for 'is_enabled' (DB) or 'isEnabled' (Model)
        return features.some(f => f.code === featureCode && (f.is_enabled === true || f.isEnabled === true));
    }

    static getFeatureDetails(featureCode, features) {
        if (!features || !Array.isArray(features)) return null;
        const feature = features.find(f => f.code === featureCode && (f.is_enabled === true || f.isEnabled === true));
        return feature ? feature.data : null;
    }

    /**
     * Returns the deposit feature object if enabled, or null.
     */
    static getDepositFeature(features) {
        if (!features || !Array.isArray(features)) return null;
        return features.find(f => f.code === 'deposit' && (f.is_enabled === true || f.isEnabled === true)) || null;
    }

    /**
     * Returns true when DepositFeature is enabled and configured in virtual (visual-only) mode.
     */
    static isDepositVirtualMode(features) {
        const depositFeature = FeatureService.getDepositFeature(features);
        if (!depositFeature) return false;
        return depositFeature.deposit_mode === 'virtual';
    }

    /**
     * Returns the configured global meta-surcharge description (visual-only),
     * or null when DepositFeature is off, in real mode, or the description is empty.
     */
    static getMetaSurchargeDescription(features) {
        if (!FeatureService.isDepositVirtualMode(features)) return null;
        const depositFeature = FeatureService.getDepositFeature(features);
        const desc = depositFeature && depositFeature.meta_surcharge_description;
        return (typeof desc === 'string' && desc.trim().length > 0) ? desc : null;
    }

    /**
     * Returns true if deposit payment option should be offered to the customer.
     * Mirrors Flutter's FeatureService.isDepositChoiceAvailable().
     * False in virtual mode (no real payment).
     * @param {Array} features - occasion features array
     * @param {Date|null} eventStartTime - occasion start time
     */
    static isDepositChoiceAvailable(features, eventStartTime) {
        const depositFeature = FeatureService.getDepositFeature(features);
        if (!depositFeature) return false;
        if (depositFeature.deposit_mode === 'virtual') return false;

        // On-site deadline: always available
        if (depositFeature.deposit_deadline === 'on_site') return true;

        // Days-before deadline: check if we're still before the cutoff
        if (!eventStartTime) return false;
        const days = depositFeature.deposit_deadline_days;
        if (days == null) return false;

        const cutoff = new Date(eventStartTime.getTime() - days * 24 * 60 * 60 * 1000);
        return new Date() < cutoff;
    }
}
