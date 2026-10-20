-- Migration: support_external_id_sync_fix

-- Drop the partial index if it exists
DROP INDEX IF EXISTS public.idx_occasions_external_source_id;

-- Create full unique index (Postgres treats (NULL, NULL) as distinct, so native occasions are fine)
ALTER TABLE public.occasions ADD COLUMN IF NOT EXISTS external_source TEXT;
ALTER TABLE public.occasions ADD COLUMN IF NOT EXISTS external_id BIGINT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_occasions_external_source_id 
ON public.occasions (external_source, external_id);

-- Note: We assume cache table changes from previous run are fine.
-- But let's re-ensure cache schema just in case.
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='external_occasions_cache' AND column_name='external_id') THEN
        TRUNCATE public.external_occasions_cache;
        ALTER TABLE public.external_occasions_cache ADD COLUMN external_id BIGINT;
        ALTER TABLE public.external_occasions_cache DROP CONSTRAINT IF EXISTS external_occasions_cache_pkey;
        ALTER TABLE public.external_occasions_cache ADD CONSTRAINT external_occasions_cache_pkey PRIMARY KEY (source_name, external_id);
    END IF;
END $$;
