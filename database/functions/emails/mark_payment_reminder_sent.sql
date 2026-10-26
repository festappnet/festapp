CREATE OR REPLACE FUNCTION public.mark_payment_reminder_sent(p_payment_info_id BIGINT)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
BEGIN
  -- This function updates the 'data' JSONB column in the eshop.payment_info table
  -- for a specific payment record. It marks that a reminder has been sent and
  -- appends the current timestamp to an array of sent reminders.
  UPDATE eshop.payment_info
  SET
    -- This operation updates the 'data' field by merging it with a new JSONB object.
    -- The new object sets 'current_version_reminded' to true and updates the
    -- 'reminder_sent_at' field.
    data = COALESCE(data, '{}'::jsonb) || jsonb_build_object(
      'current_version_reminded', true,
      -- The 'reminder_sent_at' value is constructed by taking the existing array
      -- (or an empty array '[]' if it doesn't exist) and appending the current
      -- timestamp to it.
      'reminder_sent_at', COALESCE(data->'reminder_sent_at', '[]'::jsonb) || jsonb_build_array(NOW())
    )
  WHERE
    id = p_payment_info_id;
END;
$$;
