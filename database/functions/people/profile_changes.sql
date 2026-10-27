-- Named changes share the profile receipt/version owner. No new profile writer.
CREATE OR REPLACE FUNCTION public.prepare_profile_change_internal_v1(p_current jsonb,p_intent jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE changes jsonb; spec jsonb:= $contract${"profile":{"name":{"type":"string","maxLength":512,"nullable":true},"surname":{"type":"string","maxLength":512,"nullable":true},"phone":{"type":"string","maxLength":512,"nullable":true},"diet":{"type":"string","maxLength":512,"nullable":true},"text1":{"type":"string","maxLength":512,"nullable":true},"text2":{"type":"string","maxLength":512,"nullable":true},"text3":{"type":"string","maxLength":512,"nullable":true},"sex":{"type":"string","maxLength":32,"nullable":true},"note":{"type":"string","maxLength":8192,"nullable":true},"birthDate":{"type":"string","pattern":"^([0-9]{4}-[0-9]{2}-[0-9]{2})?$","nullable":true}},"roles":{"is_editor":{"type":"boolean"},"is_editor_view":{"type":"boolean"},"is_editor_order":{"type":"boolean"},"is_editor_order_view":{"type":"boolean"},"is_cleaning_crew":{"type":"boolean"},"is_cleaning_blocked":{"type":"boolean"},"is_receptionist":{"type":"boolean"},"is_approver":{"type":"boolean"},"is_approved":{"type":"boolean"},"is_manager":{"type":"boolean"},"is_volunteer":{"type":"boolean"},"role":{"type":"integer","minimum":0,"maximum":2147483647,"nullable":true}}}$contract$::jsonb; kind text;
BEGIN
 IF NOT (p_intent ?| ARRAY['profileChange','roleChange']) THEN RETURN p_intent; END IF;
 IF p_intent ? 'profileChange' AND p_intent ? 'roleChange'
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_intent) k WHERE k NOT IN ('occasion','user','profileChange','roleChange')) THEN
  RAISE invalid_parameter_value USING MESSAGE='one explicit profile or role intent required'; END IF;
 kind:=CASE WHEN p_intent ? 'roleChange' THEN 'roles' ELSE 'profile' END;
 changes:=coalesce(p_intent->'profileChange',p_intent->'roleChange');
 IF jsonb_typeof(changes) IS DISTINCT FROM 'object' THEN RAISE invalid_parameter_value USING MESSAGE='named profile changes required'; END IF;
 PERFORM public.validate_configuration_value_internal_v1(changes,jsonb_build_object('type','object','properties',spec->kind));
 IF kind='profile' THEN
  RETURN jsonb_build_object('occasion',p_intent->'occasion','user',p_intent->'user',
   'data',coalesce(nullif(p_current->'data','null'::jsonb),'{}')||changes);
 END IF;
 RETURN jsonb_build_object('occasion',p_intent->'occasion','user',p_intent->'user',
   'data',coalesce(nullif(p_current->'data','null'::jsonb),'{}')||CASE WHEN changes ? 'is_volunteer' THEN jsonb_build_object('is_volunteer',changes->'is_volunteer') ELSE '{}'::jsonb END)
   ||(changes-'is_volunteer');
END $$;
REVOKE ALL ON FUNCTION public.prepare_profile_change_internal_v1(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
