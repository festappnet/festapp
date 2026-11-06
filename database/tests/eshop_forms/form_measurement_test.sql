-- Intent lives only on Form; destination configuration lives only on Unit.
DO $$
DECLARE value jsonb; rejected boolean; patch jsonb;
BEGIN
 PERFORM assert_eq(public.apply_form_settings_internal('{}','{"analytics":{"enabled":true}}')#>'{analytics,enabled}','true'::jsonb,'enabled boolean accepted');
 value:=public.apply_form_settings_internal('{"analytics":{"enabled":true}}','{"analytics":{"enabled":false}}');
 PERFORM assert_eq(value#>'{analytics,enabled}','false'::jsonb,'off preserved explicitly');
 PERFORM assert_true(public.apply_form_settings_internal(value,'{"analytics":null}')->'analytics' IS NULL,'reset clears intent');
 PERFORM assert_true(public.apply_form_settings_internal(value,'{"analytics":{"enabled":null}}')->'analytics' IS NULL,'null resets to default off');
 FOR patch IN SELECT jsonb_array_elements('[{"analytics":{"enabled":"true"}},{"analytics":{"gtm_container":"GTM-AB12"}},{"analytics":{"scripts":"alert(1)"}},{"analytics":{"enhanced_conversions":true}}]'::jsonb) LOOP
  rejected:=false;
  BEGIN PERFORM public.apply_form_settings_internal('{}',patch);EXCEPTION WHEN invalid_parameter_value THEN rejected:=true;END;
  PERFORM assert_true(rejected,'old destination or nonboolean form settings rejected');
 END LOOP;
 PERFORM public.validate_configuration_value_internal_v1('"GTM-AB12"'::jsonb,public.configuration_settings_contract_internal_v1()#>'{unit,measurement_gtm_container}');
 rejected:=false;
 BEGIN PERFORM public.validate_configuration_value_internal_v1('"bad"'::jsonb,public.configuration_settings_contract_internal_v1()#>'{unit,measurement_gtm_container}');EXCEPTION WHEN invalid_parameter_value THEN rejected:=true;END;
 PERFORM assert_true(rejected,'Unit GTM validator owns destination format');
END $$;

DO $$
DECLARE rule jsonb:=public.configuration_settings_contract_internal_v1()#>'{unit,measurement_privacy_url}'; value text; rejected boolean; stored jsonb;
BEGIN
 PERFORM public.validate_configuration_value_internal_v1(to_jsonb('https://organizer.example/privacy'::text),rule);
 PERFORM public.validate_configuration_value_internal_v1('null',rule);
 PERFORM public.validate_configuration_value_internal_v1('""',rule);
 FOR value IN SELECT unnest(ARRAY['javascript:alert(1)','data:text/plain,x','http://example.com','/privacy','https://user:pass@example.com','https://@example.com','https://example.com:99999','https://example.com/'||repeat('x',2048)]) LOOP
  rejected:=false;
  BEGIN PERFORM public.validate_configuration_value_internal_v1(to_jsonb(value),rule);
  EXCEPTION WHEN invalid_parameter_value THEN rejected:=true; END;
  PERFORM assert_true(rejected,'invalid privacy URL rejected');
 END LOOP;
 stored:=public.merge_configuration_settings_internal_v1('{}','{"measurement_privacy_url":"https://organizer.example/privacy"}','unit');
 PERFORM assert_eq(public.merge_configuration_settings_internal_v1(stored,'{}','unit'),stored,'omission preserves URL');
 PERFORM assert_false(public.merge_configuration_settings_internal_v1(stored,'{"measurement_privacy_url":null}','unit') ? 'measurement_privacy_url','null clears URL');
END $$;
