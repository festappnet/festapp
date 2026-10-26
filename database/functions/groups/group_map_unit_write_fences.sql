-- Current app writers are commands. Installed DML clients must upgrade before
-- this forward ACL cutover is activated; trusted definer owners retain access.
REVOKE INSERT,UPDATE,DELETE ON public.user_group_info,public.user_groups,public.places,public.units FROM anon,authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.user_info,public.occasion_users FROM anon,authenticated;
-- Flattened CSV includes its validation; the renamed body cannot bypass it.
-- The unused profile overload is retired by the authorization contraction.
REVOKE ALL ON FUNCTION public.import_occasion_users_from_csv_apply_v1(bigint,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE INSERT,UPDATE,DELETE ON public.occasions FROM anon,authenticated;
-- Unused invoker maintenance routine is not an application mutation surface.
REVOKE ALL ON FUNCTION public.shift_occasion_schedule_backward(bigint,integer) FROM PUBLIC,anon,authenticated,service_role;
