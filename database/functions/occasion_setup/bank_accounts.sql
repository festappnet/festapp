CREATE OR REPLACE FUNCTION public.occasion_setup_bank_fingerprint_internal(p_bank bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT encode(extensions.digest(convert_to(jsonb_build_object('id',b.id,'account',b.account_number,
  'currencies',b.supported_currencies)::text,'UTF8'),'sha256'),'hex') FROM eshop.bank_accounts b WHERE b.id=p_bank;
$$;
REVOKE ALL ON FUNCTION public.occasion_setup_bank_fingerprint_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Draft editors see payment instructions, never credentials or account-admin
-- operations. Creating/linking accounts continues through the existing unit UI.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_bank_accounts(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 RETURN jsonb_build_object('canManage',public.get_is_manager_on_unit(d.unit),'accounts',coalesce((
  SELECT jsonb_agg(jsonb_build_object('id',b.id,'title',b.title,
    'display',coalesce(nullif(b.account_number_human_readable,''),b.account_number),
    'currencies',b.supported_currencies,'priority',u.priority,
    'fingerprint',public.occasion_setup_bank_fingerprint_internal(b.id)) ORDER BY u.priority,b.id)
  FROM eshop.unit_bank_accounts u JOIN eshop.bank_accounts b ON b.id=u.bank_account
  WHERE u.unit=d.unit AND b.type<>'CASH'),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_bank_accounts(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_bank_accounts(uuid) TO authenticated;
