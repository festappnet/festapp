CREATE OR REPLACE FUNCTION public.normalize_creditor_reference(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = public, extensions
AS $$
  SELECT upper(regexp_replace(p_value, '[[:space:]]', '', 'g'));
$$;

CREATE OR REPLACE FUNCTION public.is_valid_creditor_reference(p_value text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = public, extensions
AS $$
DECLARE
  v_value text := public.normalize_creditor_reference(p_value);
  v_rearranged text;
  v_expanded text := '';
  v_char text;
  v_remainder integer := 0;
  v_index integer;
BEGIN
  IF v_value !~ '^RF[0-9]{2}[A-Z0-9]{1,21}$' THEN
    RETURN false;
  END IF;

  v_rearranged := substring(v_value FROM 5) || substring(v_value FROM 1 FOR 4);
  FOR v_index IN 1..length(v_rearranged) LOOP
    v_char := substring(v_rearranged FROM v_index FOR 1);
    IF v_char ~ '[0-9]' THEN
      v_expanded := v_expanded || v_char;
    ELSE
      v_expanded := v_expanded || (ascii(v_char) - 55)::text;
    END IF;
  END LOOP;

  FOR v_index IN 1..length(v_expanded) LOOP
    v_remainder := (v_remainder * 10 + substring(v_expanded FROM v_index FOR 1)::integer) % 97;
  END LOOP;
  RETURN v_remainder = 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_creditor_reference(p_variable_symbol bigint)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = public, extensions
AS $$
DECLARE
  v_payload text;
  v_expanded text := '';
  v_char text;
  v_remainder integer := 0;
  v_index integer;
  v_result text;
BEGIN
  IF p_variable_symbol <= 0 OR p_variable_symbol > 9999999999 THEN
    RAISE EXCEPTION 'PAYMENT_REFERENCE_INVALID_VARIABLE_SYMBOL';
  END IF;
  v_payload := p_variable_symbol::text;

  FOR v_index IN 1..length(v_payload || 'RF00') LOOP
    v_char := substring(v_payload || 'RF00' FROM v_index FOR 1);
    IF v_char ~ '[0-9]' THEN
      v_expanded := v_expanded || v_char;
    ELSE
      v_expanded := v_expanded || (ascii(v_char) - 55)::text;
    END IF;
  END LOOP;
  FOR v_index IN 1..length(v_expanded) LOOP
    v_remainder := (v_remainder * 10 + substring(v_expanded FROM v_index FOR 1)::integer) % 97;
  END LOOP;
  v_result := 'RF' || lpad((98 - v_remainder)::text, 2, '0') || v_payload;
  IF NOT public.is_valid_creditor_reference(v_result) THEN
    RAISE EXCEPTION 'PAYMENT_REFERENCE_GENERATION_FAILED';
  END IF;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_valid_iban(p_value text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = public, extensions
AS $$
DECLARE
  v_iban text := upper(regexp_replace(p_value, '[[:space:]]', '', 'g'));
  v_rearranged text;
  v_char text;
  v_expanded text;
  v_remainder integer := 0;
  v_index integer;
  v_digit_index integer;
BEGIN
  IF v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' THEN RETURN false; END IF;
  v_rearranged := substring(v_iban FROM 5) || substring(v_iban FROM 1 FOR 4);
  FOR v_index IN 1..length(v_rearranged) LOOP
    v_char := substring(v_rearranged FROM v_index FOR 1);
    v_expanded := CASE WHEN v_char ~ '[0-9]' THEN v_char ELSE (ascii(v_char) - 55)::text END;
    FOR v_digit_index IN 1..length(v_expanded) LOOP
      v_remainder := (v_remainder * 10 + substring(v_expanded FROM v_digit_index FOR 1)::integer) % 97;
    END LOOP;
  END LOOP;
  RETURN v_remainder = 1;
END;
$$;
