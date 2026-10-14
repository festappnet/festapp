CREATE OR REPLACE FUNCTION public.is_demo_occasion(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.demo_occasions WHERE occasion=p_occasion);
$$;
CREATE OR REPLACE FUNCTION public.is_demo_bank_account(p_bank_account bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.demo_occasions WHERE bank_account=p_bank_account);
$$;
CREATE OR REPLACE FUNCTION public.can_read_demo_occasion(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND EXISTS(
  SELECT 1 FROM public.demo_occasions d JOIN public.user_info u
   ON u.organization=d.organization AND u.id=auth.uid()
  WHERE d.occasion=p_occasion AND d.is_listed);
$$;
CREATE OR REPLACE FUNCTION public.check_occasion_writable(p_occasion bigint)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF public.is_demo_occasion(p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='DEMO_OCCASION_READ_ONLY';
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.check_bank_account_writable(p_bank_account bigint)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF public.is_demo_bank_account(p_bank_account) THEN
  RAISE insufficient_privilege USING MESSAGE='DEMO_BANK_ACCOUNT_READ_ONLY';
 END IF;
END $$;
-- This policy is shared by destination discovery and the receipted copy command.
CREATE OR REPLACE FUNCTION public.can_copy_occasion_source(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND CASE WHEN public.is_demo_occasion(p_occasion)
  THEN public.can_read_demo_occasion(p_occasion)
  ELSE EXISTS(SELECT 1 FROM public.occasions o WHERE o.id=p_occasion
    AND public.get_is_manager_on_unit(o.unit)) END;
$$;
CREATE OR REPLACE FUNCTION public.is_demo_unit(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.demo_occasions d JOIN public.occasions o
  ON o.id=d.occasion WHERE o.unit=p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_copy_occasion_source(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_copy_occasion_source(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.demo_unit_can_read(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT NOT public.is_demo_unit(p_unit) OR EXISTS(SELECT 1 FROM public.demo_occasions d
  JOIN public.occasions o ON o.id=d.occasion WHERE o.unit=p_unit AND public.can_read_demo_occasion(d.occasion));
$$;
