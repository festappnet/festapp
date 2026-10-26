DO $$
BEGIN
    ALTER TABLE public.occasions
    ADD COLUMN is_promoted boolean NOT NULL DEFAULT false;

END;
$$;