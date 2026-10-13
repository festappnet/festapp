-- news.search_doc invokes public.f_unaccent() under the inserting user's role.
-- The canonical backend has EXECUTE on unaccent but lacks schema USAGE, so
-- otherwise-authorized news inserts fail while computing the generated column.
-- USAGE allows resolution of existing extension functions; it grants no CREATE,
-- table writes or new function EXECUTE privileges.
GRANT USAGE ON SCHEMA extensions TO authenticated;
