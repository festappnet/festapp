ALTER TABLE eshop.stripe_checkout_attempts ADD COLUMN return_base_url text;
ALTER TABLE eshop.stripe_checkout_attempts ADD COLUMN refund_cursor text CHECK(refund_cursor IS NULL OR refund_cursor ~ '^re_[A-Za-z0-9]+$');
ALTER TABLE eshop.stripe_checkout_attempts ADD COLUMN session_lookup_cursor text CHECK(session_lookup_cursor IS NULL OR session_lookup_cursor ~ '^cs_[A-Za-z0-9_]+$');
ALTER TABLE eshop.stripe_checkout_attempts ADD COLUMN session_lookup_found text CHECK(session_lookup_found IS NULL OR session_lookup_found ~ '^cs_[A-Za-z0-9_]+$');
