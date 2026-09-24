import { LocalizationService } from '../../services/localization_service.js';

export class PublicOrderStrings {
    static _prefix = 'PublicOrder';

    static _tr(key, tone) {
        if (tone === 'informal') {
            const informalKey = `${key}_informal`;
            const val = LocalizationService.tr(informalKey);
            if (val && val !== informalKey) {
                return val;
            }
        }
        return LocalizationService.tr(key);
    }

    static successTitle(tone, hasTickets = true) {
        if (hasTickets) {
            return PublicOrderStrings._tr(`${PublicOrderStrings._prefix}.successTitle`, tone);
        }
        return PublicOrderStrings._tr(`${PublicOrderStrings._prefix}.successRegistrationTitle`, tone);
    }

    static paymentInfo(tone) {
        return PublicOrderStrings._tr(`${PublicOrderStrings._prefix}.paymentInfo`, tone);
    }

    static confirmationInfo(tone, hasPayment, email) {
        const key = hasPayment ? 'paymentInfo' : 'confirmationInfo';
        const template = PublicOrderStrings._tr(`${PublicOrderStrings._prefix}.${key}${email ? 'WithEmail' : ''}`, tone);
        return email ? template.replace('{email}', email) : template;
    }

    static selectSeat(tone) {
        return PublicOrderStrings._tr(`${PublicOrderStrings._prefix}.selectSeat`, tone);
    }

    static getSubmitButton(hasTickets, tone) {
        if (hasTickets) {
            return PublicOrderStrings._tr(`${PublicOrderStrings._prefix}.submitOrder`, tone);
        }
        return PublicOrderStrings._tr(`${PublicOrderStrings._prefix}.submitRegistration`, tone);
    }

    static get summary() {
        return LocalizationService.tr(`${PublicOrderStrings._prefix}.summary`);
    }

    static get backToForm() {
        return LocalizationService.tr(`${PublicOrderStrings._prefix}.backToForm`);
    }

    static get orderFailed() {
        return LocalizationService.tr(`${PublicOrderStrings._prefix}.orderFailed`);
    }

    static orderError(code) {
        return LocalizationService.tr(`${PublicOrderStrings._prefix}.orderError`, { code: code });
    }

    static productUnavailable(productTitle) {
        return LocalizationService.tr(`${PublicOrderStrings._prefix}.productUnavailable`, { product_title: productTitle });
    }

    static chooseDifferentVariant(tone) {
        return PublicOrderStrings._tr(`${PublicOrderStrings._prefix}.chooseDifferentVariant`, tone);
    }

    static totalPrice(price) {
        return LocalizationService.tr(`${PublicOrderStrings._prefix}.totalPrice`, { price: price });
    }

    static get paymentMethod() {
        return LocalizationService.tr(`${PublicOrderStrings._prefix}.paymentMethod`);
    }

    static get payFullAmount() {
        return LocalizationService.tr(`${PublicOrderStrings._prefix}.payFullAmount`);
    }

    static get payWithDeposit() {
        return LocalizationService.tr(`${PublicOrderStrings._prefix}.payWithDeposit`);
    }

    static get depositInfoOnSite() {
        return LocalizationService.tr(`${PublicOrderStrings._prefix}.depositInfoOnSite`);
    }

    static depositInfoDaysBefore(days) {
        return LocalizationService.tr(`${PublicOrderStrings._prefix}.depositInfoDaysBefore`, { days: days });
    }

    static get bankAccount() { return LocalizationService.tr(`${PublicOrderStrings._prefix}.bankAccount`); }
    static get amountToPay() { return LocalizationService.tr(`${PublicOrderStrings._prefix}.amountToPay`); }
    static get variableSymbol() { return LocalizationService.tr(`${PublicOrderStrings._prefix}.variableSymbol`); }
    static get paymentReference() { return LocalizationService.tr(`${PublicOrderStrings._prefix}.paymentReference`); }
    static get paymentQrTitle() { return LocalizationService.tr(`${PublicOrderStrings._prefix}.paymentQrTitle`); }
    static get paymentQrSubtitle() { return LocalizationService.tr(`${PublicOrderStrings._prefix}.paymentQrSubtitle`); }
    static get downloadQr() { return LocalizationService.tr(`${PublicOrderStrings._prefix}.downloadQr`); }
    static get iban() { return LocalizationService.tr(`${PublicOrderStrings._prefix}.iban`); }
    static get copy() { return LocalizationService.tr(`${PublicOrderStrings._prefix}.copy`); }
    static get showPaymentOptions() { return LocalizationService.tr(`${PublicOrderStrings._prefix}.showPaymentOptions`); }
    static get hidePaymentOptions() { return LocalizationService.tr(`${PublicOrderStrings._prefix}.hidePaymentOptions`); }
}
