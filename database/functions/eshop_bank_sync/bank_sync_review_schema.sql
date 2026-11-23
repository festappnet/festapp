-- Internal ingestion evidence is separate from the bounded BankSync receipt.
ALTER TABLE eshop.bank_sync_inbox ADD COLUMN IF NOT EXISTS diagnostics jsonb;
CREATE INDEX IF NOT EXISTS transactions_email_confirmed_review_idx
 ON eshop.transactions(bank_account_id,amount,date) WHERE ingest_source='banksync_email_confirmed';
CREATE INDEX IF NOT EXISTS transactions_bank_email_duplicate_idx
 ON eshop.transactions(bank_account_id,date)
 WHERE ingest_source IN ('banksync_email_confirmed','banksync_api','fio_api','legacy_api','legacy');
CREATE INDEX IF NOT EXISTS bank_sync_inbox_unresolved_queue_idx
 ON eshop.bank_sync_inbox(connection_id,received_at,delivery_id) WHERE resolution IS NULL;
CREATE INDEX IF NOT EXISTS bank_sync_inbox_email_observation_idx
 ON eshop.bank_sync_inbox(connection_id,remote_transaction_id,received_at,delivery_id)
 WHERE (payload->'data'->>'source') ~ '(^|_)email$';
CREATE INDEX IF NOT EXISTS bank_sync_inbox_api_review_idx
 ON eshop.bank_sync_inbox(((diagnostics->>'transaction_id')::bigint))
 WHERE diagnostics->>'reason'='stored_unpaired_possible_duplicate';

CREATE UNIQUE INDEX IF NOT EXISTS bank_sync_inbox_reviewed_email_receipt_uidx
 ON eshop.bank_sync_inbox(((resolution->>'existing_transaction_id')::bigint))
 WHERE resolution->>'action'='api_same_movement';

CREATE TABLE IF NOT EXISTS eshop.bank_sync_review_signing_key (
 singleton boolean PRIMARY KEY CHECK(singleton),
 secret bytea NOT NULL DEFAULT extensions.gen_random_bytes(32)
);
INSERT INTO eshop.bank_sync_review_signing_key(singleton) VALUES(true) ON CONFLICT DO NOTHING;
ALTER TABLE eshop.bank_sync_review_signing_key ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.bank_sync_review_signing_key FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS eshop.bank_sync_api_review_events (
 instance_id text NOT NULL,
 consumer_app_id text NOT NULL,
 delivery_id text NOT NULL,
 revision integer NOT NULL CHECK(revision>0),
 decision jsonb NOT NULL,
 PRIMARY KEY(instance_id,consumer_app_id,delivery_id,revision),
 FOREIGN KEY(instance_id,consumer_app_id,delivery_id)
   REFERENCES eshop.bank_sync_inbox(instance_id,consumer_app_id,delivery_id)
);
ALTER TABLE eshop.bank_sync_api_review_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.bank_sync_api_review_events FROM PUBLIC,anon,authenticated,service_role;
