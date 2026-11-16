BEGIN;
DO $$
DECLARE result jsonb;
BEGIN
 result := public.apply_form_settings_internal('{"unrelated":"preserved","waitlist":{"other":"preserved"}}', '{"waitlist":{"show_count":false}}');
 ASSERT result#>'{waitlist,show_count}' = 'false'::jsonb;
 ASSERT result->>'unrelated' = 'preserved';
 ASSERT result#>>'{waitlist,other}' = 'preserved';
 result := public.apply_form_settings_internal(result, '{"waitlist":{"show_count":null}}');
 ASSERT NOT (result->'waitlist') ? 'show_count';
 ASSERT result#>>'{waitlist,other}' = 'preserved';
 ASSERT public.form_settings_from_metadata_internal('{"waitlist":{"show_count":false}}')#>'{waitlist,show_count}' = 'false'::jsonb;
 BEGIN
  PERFORM public.apply_form_settings_internal('{}', '{"waitlist":{"show_count":"false"}}');
  RAISE EXCEPTION 'Non-boolean display setting accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
END $$;
ROLLBACK;
