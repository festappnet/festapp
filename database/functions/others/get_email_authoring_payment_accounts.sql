-- Read-only display metadata for the permission-gated email authoring endpoint.
-- The caller must first authorize the hierarchy through get_entity_email_templates.
CREATE OR REPLACE FUNCTION public.get_email_authoring_payment_accounts(
  p_unit_id bigint,
  p_occasion_id bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_organization bigint;
  v_linked jsonb;
  v_form_accounts jsonb;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Service role required' USING ERRCODE = '42501';
  END IF;

  SELECT u.organization INTO v_organization
  FROM public.units u
  JOIN public.organizations o ON o.id = u.organization
  WHERE u.id = p_unit_id;
  IF v_organization IS NULL THEN
    RAISE EXCEPTION 'Invalid email authoring unit' USING ERRCODE = '22023';
  END IF;
  IF p_occasion_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.occasions o
    WHERE o.id = p_occasion_id AND o.unit = p_unit_id
      AND o.organization = v_organization
  ) THEN
    RAISE EXCEPTION 'Invalid email authoring occasion hierarchy' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'priority', uba.priority,
    'bank_accounts', jsonb_build_object(
      'id', ba.id,
      'type', ba.type,
      'account_number', ba.account_number,
      'account_number_human_readable', ba.account_number_human_readable,
      'supported_currencies', ba.supported_currencies
    )
  ) ORDER BY uba.priority, ba.id), '[]'::jsonb)
  INTO v_linked
  FROM eshop.unit_bank_accounts uba
  JOIN eshop.bank_accounts ba ON ba.id = uba.bank_account
  WHERE uba.unit = p_unit_id AND ba.type IS DISTINCT FROM 'CASH';

  SELECT COALESCE(jsonb_agg(account_id ORDER BY account_id), '[]'::jsonb)
  INTO v_form_accounts
  FROM (
    SELECT DISTINCT f.bank_account AS account_id
    FROM public.forms f
    JOIN eshop.unit_bank_accounts uba
      ON uba.bank_account = f.bank_account AND uba.unit = p_unit_id
    JOIN eshop.bank_accounts ba ON ba.id = f.bank_account
    WHERE f.occasion = p_occasion_id AND ba.type IS DISTINCT FROM 'CASH'
  ) configured;

  RETURN jsonb_build_object('linkedAccounts', v_linked, 'formAccountIds', v_form_accounts);
END;
$$;

REVOKE ALL ON FUNCTION public.get_email_authoring_payment_accounts(bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_authoring_payment_accounts(bigint, bigint) TO service_role;
