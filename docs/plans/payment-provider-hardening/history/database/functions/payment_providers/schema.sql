-- Installed connectors are migration-owned configuration, never client input.
CREATE TABLE eshop.payment_providers (
 provider_key text PRIMARY KEY CHECK(provider_key ~ '^[a-z][a-z0-9_-]{0,31}$'),
 handler regprocedure,
 source_field text UNIQUE,
 legacy_connection_field text UNIQUE,
 CHECK((provider_key='bank' AND handler IS NULL AND source_field IS NULL)
    OR (provider_key<>'bank' AND handler IS NOT NULL AND source_field IS NOT NULL))
);
ALTER TABLE eshop.payment_providers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.payment_providers FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO eshop.payment_providers(provider_key) VALUES('bank');
-- The existing Stripe connection column belongs to that connector. Other
-- connectors may have their own typed storage without changing payment_info.
ALTER TABLE eshop.payment_info DROP CONSTRAINT payment_info_payment_method_check;
ALTER TABLE eshop.payment_info DROP CONSTRAINT payment_info_stripe_identity;
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_provider_instructions CHECK(
 payment_method='bank' OR (bank_account IS NULL AND variable_symbol IS NULL
  AND creditor_reference IS NULL AND deposit_amount IS NULL));
