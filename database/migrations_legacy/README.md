# Legacy pre-Supabase migrations

The `0.x.sql` files in this directory predate Supabase CLI migration tracking.
They are retained as historical upgrade records only. Their changes are already
included in the versioned local schema baseline, and they must not be moved back
to `supabase/migrations/`: their semantic-version filenames are not valid
Supabase migration versions and the files assume an already provisioned Festapp
database.

Active forward migrations live exclusively in `supabase/migrations/` and use a
unique `YYYYMMDDHHMMSS_name.sql` filename.
