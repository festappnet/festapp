import { OrderItemStrings } from '../eshop/order_item_strings.js';
export const paymentMethodText=(key, options)=>OrderItemStrings.text('PaymentMethods.'+key, options);
export const paymentMethodRecipient=name=>paymentMethodText('recipient').replace('{name}',name);
export const paymentMethodReservation=seconds=>paymentMethodText('reservation').replace('{minutes}',String(Math.ceil(seconds/60)));
