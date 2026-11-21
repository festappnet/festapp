DO $$
DECLARE metadata jsonb;
BEGIN
 metadata := public.apply_form_settings_internal('{"other":"keep"}','{"show_payment_qr_in_email":true}');
 ASSERT metadata = '{"other":"keep","show_payment_qr_in_email":true}'::jsonb;
 ASSERT public.apply_form_settings_internal(metadata,public.form_settings_from_metadata_internal('{}'))->'show_payment_qr_in_email' = 'true'::jsonb;
 metadata := public.apply_form_settings_internal(metadata,'{"show_payment_qr_in_email":false}');
 ASSERT metadata->'show_payment_qr_in_email' = 'false'::jsonb;
 ASSERT NOT public.apply_form_settings_internal(metadata,'{"show_payment_qr_in_email":null}') ? 'show_payment_qr_in_email';
 BEGIN
  PERFORM public.apply_form_settings_internal('{}','{"show_payment_qr_in_email":"true"}');
  RAISE EXCEPTION 'String setting was accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
END $$;
