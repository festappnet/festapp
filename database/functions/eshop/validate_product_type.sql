CREATE OR REPLACE FUNCTION validate_product_type(product_id BIGINT, required_type TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    product_type RECORD;
BEGIN
    -- Retrieve the product's type
    SELECT it.*
    INTO product_type
    FROM eshop.products i
    JOIN eshop.product_types it ON i.product_type = it.id
    WHERE i.id = product_id;

    -- Check if the type matches
    IF product_type IS NULL THEN
        RAISE EXCEPTION 'product with ID % not found or has no type.', product_id;
    END IF;

    IF product_type.type = required_type THEN
        RETURN TRUE;
    ELSE
        RAISE EXCEPTION 'product with ID % is not of type %. Found type: %', product_id, required_type, product_type.type;
    END IF;
END;
$$;
