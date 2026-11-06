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
