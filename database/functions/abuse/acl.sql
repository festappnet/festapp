-- Older invoker/definer wrappers are internal implementation details too.
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE INSERT,UPDATE,DELETE ON public.organizations FROM anon,authenticated;
