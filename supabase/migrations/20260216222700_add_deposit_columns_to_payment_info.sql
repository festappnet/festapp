ALTER TABLE eshop.payment_info
ADD COLUMN IF NOT EXISTS deposit_amount NUMERIC(10, 2) DEFAULT NULL;

COMMENT ON COLUMN eshop.payment_info.deposit_amount IS 'Deposit amount required for order to be marked as paid. NULL means full amount required (backward compatible).';

ALTER TABLE eshop.payment_info
ADD COLUMN IF NOT EXISTS deposit_deadline TIMESTAMPTZ DEFAULT NULL;

COMMENT ON COLUMN eshop.payment_info.deposit_deadline IS 'Deadline for surcharge payment. NULL with deposit_amount set means on-site payment.';
