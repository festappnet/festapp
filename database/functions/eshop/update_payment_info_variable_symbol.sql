CREATE OR REPLACE FUNCTION public.update_payment_info_variable_symbol(
  p_payment_info_id bigint,
  p_variable_symbol bigint
)
  RETURNS void
  LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.check_payment_info_is_mutable(p_payment_info_id);
  UPDATE eshop.payment_info
     SET variable_symbol = p_variable_symbol
   WHERE id = p_payment_info_id;
END;
$$;
