-- Order lists and payment details resolve movements by payment, independently
-- of the bank's external transaction identity.
CREATE INDEX IF NOT EXISTS transactions_payment_info_idx
 ON eshop.transactions(payment_info);
CREATE INDEX IF NOT EXISTS orders_payment_info_idx
 ON eshop.orders(payment_info);
CREATE INDEX IF NOT EXISTS refund_requests_payment_info_idx
 ON eshop.refund_requests(payment_info);
CREATE INDEX IF NOT EXISTS refund_settlements_request_id_idx
 ON eshop.refund_settlements(request_id);
