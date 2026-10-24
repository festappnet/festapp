GRANT SELECT (occasion,bank_account) ON public.demo_occasions TO anon,authenticated;
DROP POLICY IF EXISTS demo_registry_read ON public.demo_occasions;
CREATE POLICY demo_registry_read ON public.demo_occasions FOR SELECT TO authenticated
 USING(public.can_read_demo_occasion(occasion));
