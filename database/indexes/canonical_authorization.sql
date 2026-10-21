-- Context discovery filters a unit before sorting/limiting its occasions.
-- The original schema had only identity/external-source indexes, forcing a
-- scan of unrelated units even for an eight-occasion context. This is a plain
-- resource index, not a materialized permission result or an ACL cache.
CREATE INDEX IF NOT EXISTS occasions_unit_start_time_authorization_idx
 ON public.occasions (unit, start_time DESC);
