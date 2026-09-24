-- A paid EUR order exposes one RF whose numeric payload is its unchanged VS.
DO $$
DECLARE
  v_org_id bigint;
  v_unit_id bigint;
  v_occasion_id bigint;
  v_form_id bigint;
  v_form_key uuid;
  v_product_type_id bigint;
  v_product_id bigint;
  v_spot_id bigint;
  v_bank_account_id bigint;
  v_secret_id bigint;
  v_result jsonb;
  v_payment_info_id bigint;
  v_variable_symbol bigint;
  v_creditor_reference text;
BEGIN
  INSERT INTO public.organizations (title)
  VALUES (E'Hvězda\nMořská') RETURNING id INTO v_org_id;
  INSERT INTO public.units (title, organization)
  VALUES ('EUR RF test unit', v_org_id) RETURNING id INTO v_unit_id;

  INSERT INTO eshop.secrets (secret)
  VALUES ('eur_rf_test_secret') RETURNING id INTO v_secret_id;
  INSERT INTO eshop.bank_accounts (
    title, account_number, creditor_name, supported_currencies, secret, type
  ) VALUES (
    'EUR RF test bank', 'DE71110220330123456789', NULL,
    ARRAY['EUR'], v_secret_id, 'FIO'
  ) RETURNING id INTO v_bank_account_id;
  INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
  VALUES (v_unit_id, v_bank_account_id, 1);

  INSERT INTO public.occasions (title, unit, link, start_time, end_time)
  VALUES (
    'EUR RF test occasion', v_unit_id,
    'eur-rf-test-' || floor(random() * 100000)::text,
    now(), now() + interval '1 day'
  ) RETURNING id INTO v_occasion_id;
  INSERT INTO public.forms (title, occasion, is_open)
  VALUES ('EUR RF test form', v_occasion_id, true)
  RETURNING id, key INTO v_form_id, v_form_key;
  INSERT INTO eshop.product_types (title, occasion, type)
  VALUES ('EUR RF test product type', v_occasion_id, 'spot')
  RETURNING id INTO v_product_type_id;
  INSERT INTO eshop.products (
    title, product_type, currency_code, price, is_hidden, occasion
  ) VALUES (
    'EUR RF test product', v_product_type_id, 'EUR', 12.30, false, v_occasion_id
  ) RETURNING id INTO v_product_id;
  INSERT INTO public.form_fields (form, product_type)
  VALUES (v_form_id, v_product_type_id);
  INSERT INTO eshop.spots (title, product, occasion, secret)
  VALUES ('EUR RF test spot', v_product_id, v_occasion_id, gen_random_uuid())
  RETURNING id INTO v_spot_id;

  SELECT public.create_ticket_order(jsonb_build_object(
    'form', v_form_key,
    'email', 'eur-rf@example.com',
    'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_id),
    'ticket', jsonb_build_array(jsonb_build_object('spot', v_spot_id))
  )) INTO v_result;

  PERFORM assert_eq((v_result->>'code')::integer, 200, 'EUR order must succeed');
  PERFORM assert_eq(v_result->'order'->'payment_info'->>'creditor_name',
    'Hvězda Mořská', 'missing account payee must fall back to clean organization title');
  v_payment_info_id := (v_result->'order'->'payment_info'->>'id')::bigint;
  SELECT variable_symbol, creditor_reference
  INTO v_variable_symbol, v_creditor_reference
  FROM eshop.payment_info WHERE id = v_payment_info_id;

  PERFORM assert_true(v_variable_symbol::text ~ '^[0-9]{1,10}$',
    'EUR order VS must contain one to ten digits');
  PERFORM assert_eq(v_creditor_reference,
    public.generate_creditor_reference(v_variable_symbol),
    'EUR RF must be the checksum wrapper around the unchanged VS');
  PERFORM assert_eq(v_result->'order'->'payment_info'->>'creditor_reference',
    v_creditor_reference, 'order response must expose the stored RF');
END;
$$ LANGUAGE plpgsql;
