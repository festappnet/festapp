DO $$
BEGIN
    ALTER TABLE eshop.orders_history
    ADD COLUMN created_by UUID NULL DEFAULT auth.uid();

    -- Add a foreign key constraint to link the 'created_by' column to the 'user_info' table.
    -- This ensures that every user ID in the history corresponds to a valid user.

    ALTER TABLE eshop.orders_history
    ADD CONSTRAINT orders_history_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES public.user_info(id);
END;
$$;