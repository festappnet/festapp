DO $$
BEGIN
    -- Migration to add the 'form' relationship to 'eshop.orders'

    -- Step 1: Add the new 'form' column to the 'eshop.orders' table.
    -- The column is nullable (BIGINT NULL) to allow for existing orders
    -- that may not have an associated form.
    ALTER TABLE eshop.orders
    ADD COLUMN form BIGINT NULL;

    -- Step 2: Add the foreign key constraint to the new 'form' column.
    -- This creates a link to the 'id' column in the 'public.forms' table
    -- and names the constraint 'orders_form_fkey'.
    ALTER TABLE eshop.orders
    ADD CONSTRAINT orders_form_fkey
    FOREIGN KEY (form) REFERENCES public.forms (id);

END;
$$;