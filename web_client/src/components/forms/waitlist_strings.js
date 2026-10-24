import { LocalizationService } from '../../services/localization_service.js';
export class WaitlistStrings {
    static text(key) { if (key === 'ABUSE_LIMIT_EXCEEDED' || key === 'PT429') return LocalizationService.tr('Common.resourceLimited'); return LocalizationService.tr(`Waitlist.${key}`); }
    static get settings() { return LocalizationService.tr('Waitlist.settings'); }
    static get capacity() { return LocalizationService.tr('Waitlist.capacity'); }
    static get unlimited() { return LocalizationService.tr('Waitlist.unlimited'); }
    static get enabled() { return LocalizationService.tr('Waitlist.enabled'); }
    static get showRemaining() { return LocalizationService.tr('Waitlist.showRemaining'); }
    static get durationHours() { return LocalizationService.tr('Waitlist.durationHours'); }
    static get positiveNumber() { return LocalizationService.tr('Waitlist.positiveNumber'); }
    static get activeEntries() { return LocalizationService.tr('Waitlist.activeEntries'); }
    static get title() { return LocalizationService.tr('Waitlist.title'); }
    static get explanation() { return LocalizationService.tr('Waitlist.explanation'); }
    static get full() { return LocalizationService.tr('Waitlist.full'); }
    static get registered() { return LocalizationService.tr('Waitlist.registered'); }
    static get register() { return LocalizationService.tr('Waitlist.register'); }
    static get accept() { return LocalizationService.tr('Waitlist.accept'); }
    static get decline() { return LocalizationService.tr('Waitlist.decline'); }
    static get withdraw() { return LocalizationService.tr('Waitlist.withdraw'); }
    static get send() { return LocalizationService.tr('Waitlist.send'); }
    static get expired() { return LocalizationService.tr('Waitlist.expired'); }
    static get productAvailability() { return LocalizationService.tr('Waitlist.productAvailability'); }
    static get selectPeople() { return LocalizationService.tr('Waitlist.selectPeople'); }
    static get remaining() { return LocalizationService.tr('Waitlist.remaining'); }
    static get confirm() { return LocalizationService.tr('Waitlist.confirm'); }
    static get stale() { return LocalizationService.tr('Waitlist.stale'); }
    static get queued() { return LocalizationService.tr('Waitlist.queued'); }
    static get detail() { return LocalizationService.tr('Waitlist.detail'); }
    static get offers() { return LocalizationService.tr('Waitlist.offers'); }
    static get cancel() { return LocalizationService.tr('Waitlist.cancel'); }
    static get linkedOrders() { return LocalizationService.tr('Waitlist.linkedOrders'); }
    static get invalid() { return LocalizationService.tr('Waitlist.invalid'); }
    static get refresh() { return LocalizationService.tr('Waitlist.refresh'); }
    static get count() { return LocalizationService.tr('Waitlist.count'); }
    static get expiresAt() { return LocalizationService.tr('Waitlist.expiresAt'); }
}
