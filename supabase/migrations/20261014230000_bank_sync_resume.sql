-- Canonical operation allowlist: database/functions/eshop_bank_sync/schema.sql.
ALTER TABLE eshop.bank_sync_operations
  DROP CONSTRAINT bank_sync_operations_operation_check;
ALTER TABLE eshop.bank_sync_operations
  ADD CONSTRAINT bank_sync_operations_operation_check
  CHECK (operation IN ('create','set_token','rotate_pairing','sync','suspend','resume','update_details'));
