-- Installed implementation support is separate from the runtime write switch.
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS refund_write_supported boolean NOT NULL DEFAULT false;
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS partial_refund_supported boolean NOT NULL DEFAULT false;
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS refund_observation_supported boolean NOT NULL DEFAULT false;
UPDATE eshop.payment_providers SET refund_write_supported=true,partial_refund_supported=true,refund_observation_supported=true
 WHERE provider_key IN ('bank','cash','stripe');
UPDATE eshop.payment_providers SET refund_observation_supported=true WHERE provider_key='barion';
