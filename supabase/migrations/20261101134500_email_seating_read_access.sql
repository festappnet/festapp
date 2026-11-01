-- Email preparation calls invoker SQL that projects seating configuration.
-- Keep client access and all direct writes revoked.
GRANT SELECT ON public.form_seating_transitions TO service_role;
