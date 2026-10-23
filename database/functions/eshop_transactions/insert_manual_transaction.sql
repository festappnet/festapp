CREATE OR REPLACE FUNCTION public.insert_manual_transaction(
    p_amount double precision,
    p_currency text,
    p_unit_id int,
    p_variable_symbol text,
    p_date text,
    p_note text DEFAULT NULL,
    p_payment_info_id int DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM public.check_is_manager_on_unit(p_unit_id);
    PERFORM public.insert_manual_transaction_internal_v1(p_amount::numeric,p_currency,p_unit_id::bigint,
      p_variable_symbol,p_date::timestamptz,p_note,p_payment_info_id::bigint);
END;
$$;

REVOKE ALL ON FUNCTION public.insert_manual_transaction(double precision,text,integer,text,text,text,integer)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision,text,integer,text,text,text,integer)
  TO authenticated;
