CREATE OR REPLACE FUNCTION public.add_sent_to_customer_flag(history_id BIGINT)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
BEGIN
  UPDATE eshop.orders_history
  SET
    -- Coalesce ensures that if data is NULL, it starts with an empty JSON object
    -- before merging. The || operator merges the two JSONB objects.
    data = COALESCE(data, '{}'::jsonb) || '{"is_sent_to_customer": true}'::jsonb
  WHERE
    id = history_id;
END;
$$;