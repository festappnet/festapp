-- Independent Apple activation on the existing organization connector.
ALTER TABLE eshop.ticket_wallet_integrations
 ADD COLUMN IF NOT EXISTS apple_publishing_ready boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS apple_pass_type_identifier text,
 ADD COLUMN IF NOT EXISTS apple_team_identifier text;
ALTER TABLE eshop.ticket_wallet_integrations ALTER COLUMN issuer DROP NOT NULL;
ALTER TABLE eshop.ticket_wallet_integrations ADD CONSTRAINT ticket_wallet_google_identity CHECK(NOT publishing_ready OR issuer IS NOT NULL);
ALTER TABLE eshop.ticket_wallet_integrations ADD CONSTRAINT ticket_wallet_apple_identity CHECK(
 NOT apple_publishing_ready OR (apple_pass_type_identifier IS NOT NULL AND apple_pass_type_identifier ~ '^pass\.[A-Za-z0-9.-]+$'
 AND apple_team_identifier IS NOT NULL AND apple_team_identifier ~ '^[A-Z0-9]{10}$'));
