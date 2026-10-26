CREATE OR REPLACE FUNCTION extract_history_products_with_price(history_data jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE
SET search_path = public, extensions AS $$
  SELECT COALESCE(
    -- Step 2: Aggregate the distinct product objects into a single JSONB array,
    -- ordering them by the 'id' field cast to an integer.
    jsonb_agg(p.product_object ORDER BY (p.product_object->>'id')::int),

    -- If the aggregation is null (no products found), return an empty array.
    '[]'::jsonb
  )
  FROM (
    -- Step 1: Create a derived table (subquery) of distinct product objects.
    -- This subquery unnests the tickets and products, builds the desired
    -- {'id': ..., 'price': ...} object, and returns only the unique ones.
    SELECT DISTINCT
      jsonb_build_object('id', product->>'id', 'price', product->>'price') AS product_object
    FROM
      jsonb_array_elements(history_data->'tickets') AS ticket,
      jsonb_array_elements(ticket->'products') AS product
  ) AS p;
$$;