DO $$
BEGIN
    ALTER TABLE eshop.payment_info
    ADD COLUMN IF NOT EXISTS data JSONB NULL;
END;
$$;