import {LocalizationService} from '../../services/localization_service.js';
export const paymentMethodText=key=>LocalizationService.tr('PaymentMethods.'+key);
export const paymentMethodRecipient=name=>paymentMethodText('recipient').replace('{name}',name);
export const paymentMethodReservation=seconds=>paymentMethodText('reservation').replace('{minutes}',String(Math.ceil(seconds/60)));
