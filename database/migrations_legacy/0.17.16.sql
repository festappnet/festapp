/**
 * This script updates the 'form' column in the 'eshop.orders' table.
 * It fetches the 'form' UUID from the JSONB 'data' column of each order.
 * It then looks up the corresponding 'id' (BIGINT) from the 'public.forms' table
 * by matching the UUID against the 'public.forms.key' column.
 * Finally, it sets the 'eshop.orders.form' (which is a BIGINT foreign key) to this found 'id'.
 */
UPDATE eshop.orders AS o
SET
  form = pf.id
FROM
  public.forms AS pf
WHERE
  -- 1. Match the form's UUID key (pf.key) with the UUID stored in the order's JSON data (o.data ->> 'form')
  -- We must cast the text value from the JSON to a UUID type to match the column.
  pf.key = (o.data ->> 'form')::uuid
  -- 2. (Recommended) Only update rows where the 'form' column is not already set.
  -- This prevents re-running the update on rows that are already correct
  -- and makes the script safe to run multiple times.
  AND o.form IS NULL;