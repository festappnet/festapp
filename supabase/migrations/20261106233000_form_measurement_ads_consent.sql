-- Consent as state for Consent Mode, staff exclusion and the consent notice settings on Unit.
-- Generated from packages/festapp_contracts/configuration-settings.json.
CREATE OR REPLACE FUNCTION public.configuration_settings_contract_internal_v1() RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $contract$
 SELECT $json${"occasion":{"place_name":{"type":"string","nullable":true,"maxLength":8192},"reply_to":{"type":"email","nullable":true},"timezone":{"type":"timezone","nullable":true},"image":{"type":"string","nullable":true,"maxLength":8192}},"unit":{"reply_to":{"type":"email","nullable":true},"communication_tone":{"type":"string","enum":["formal","informal"],"nullable":true},"timezone":{"type":"timezone","nullable":true},"measurement_enabled":{"type":"boolean"},"measurement_consent_layout":{"type":"string","enum":["bar","modal"],"nullable":true},"measurement_consent_title":{"type":"string","nullable":true,"maxLength":80},"measurement_consent_text":{"type":"string","nullable":true,"maxLength":500},"measurement_gtm_container":{"type":"string","nullable":true,"maxLength":36,"pattern":"^GTM-[A-Z0-9]{4,32}$"},"measurement_scripts":{"type":"string","nullable":true,"maxLength":5000},"measurement_privacy_url":{"type":"string","nullable":true,"maxLength":2048,"pattern":"^(https://[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*(:([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?([/?#][^\\s\\\\]*)?)?$"}},"features":{"ticket":{"is_enabled":{"type":"boolean"},"can_scan_manually":{"type":"boolean"},"show_hidden_note":{"type":"boolean"}},"form":{"is_enabled":{"type":"boolean"},"external_form_link":{"type":"string","nullable":true,"maxLength":8192},"external_price":{"type":"string","nullable":true,"maxLength":8192},"reserve_button_title":{"type":"string","nullable":true,"maxLength":8192},"use_external_form":{"type":"boolean"},"reminder_is_enabled":{"type":"boolean","nullable":true},"reminder_interval_seconds":{"type":"integer","nullable":true,"minimum":0,"maximum":31536000},"deadline_duration_seconds":{"type":"integer","nullable":true,"minimum":0,"maximum":31536000}},"songbook":{"is_enabled":{"type":"boolean"}},"game":{"is_enabled":{"type":"boolean"}},"user_groups":{"is_enabled":{"type":"boolean"}},"my_schedule":{"is_enabled":{"type":"boolean"}},"services":{"is_enabled":{"type":"boolean"},"services_mode":{"type":"string","enum":["stay","capacity_groups"]},"allow_accommodation":{"type":"boolean"},"allow_food":{"type":"boolean"}},"entry_code":{"is_enabled":{"type":"boolean"}},"companions":{"is_enabled":{"type":"boolean"},"max_companions":{"type":"integer","nullable":true,"minimum":0,"maximum":31536000},"allow_user_create":{"type":"boolean"},"allow_admin_assign":{"type":"boolean"}},"blueprint":{"is_enabled":{"type":"boolean"}},"timetable":{"is_enabled":{"type":"boolean"}},"map":{"is_enabled":{"type":"boolean"},"defaultMapZoom":{"type":"number","minimum":0,"maximum":24},"defaultMapLocation":{"type":"object","properties":{"lat":{"type":"number","minimum":-90,"maximum":90},"lng":{"type":"number","minimum":-180,"maximum":180}},"required":["lat","lng"]},"map_layer":{"type":"object","properties":{"logo":{"type":"string","nullable":true,"maxLength":8192},"text":{"type":"string","nullable":true,"maxLength":8192},"logo_link":{"type":"string","nullable":true,"maxLength":8192},"text_link":{"type":"string","nullable":true,"maxLength":8192},"layer_link":{"type":"string","nullable":true,"maxLength":8192},"offlineMapBundleManifestURL":{"type":"string","nullable":true,"maxLength":8192},"forceOfflineMap":{"type":"boolean"}}},"map_layer_offline":{"type":"object","properties":{"logo":{"type":"string","nullable":true,"maxLength":8192},"text":{"type":"string","nullable":true,"maxLength":8192},"logo_link":{"type":"string","nullable":true,"maxLength":8192},"text_link":{"type":"string","nullable":true,"maxLength":8192},"layer_link":{"type":"string","nullable":true,"maxLength":8192},"offlineMapBundleManifestURL":{"type":"string","nullable":true,"maxLength":8192},"forceOfflineMap":{"type":"boolean"}}}},"quotes":{"is_enabled":{"type":"boolean"}},"workshops":{"is_enabled":{"type":"boolean"},"start_time":{"type":"datetime","nullable":true},"registration_not_open_message":{"type":"string","nullable":true,"maxLength":8192}},"volunteers":{"is_enabled":{"type":"boolean"}},"schedule":{"is_enabled":{"type":"boolean"},"schedule_type":{"type":"string","nullable":true,"enum":["basic","advanced","light"]},"enable_children":{"type":"boolean"},"break_definition":{"type":"string","enum":["time","place"]},"afternoon_break_time":{"type":"string","pattern":"^([01][0-9]|2[0-3]):[0-5][0-9]$"},"evening_break_time":{"type":"string","pattern":"^([01][0-9]|2[0-3]):[0-5][0-9]$"},"event_types":{"type":"array","maxItems":100,"items":{"type":"object","properties":{"code":{"type":"string","maxLength":512},"title":{"type":"string","maxLength":512},"colorDefinition":{"type":"string","maxLength":512}},"required":["code","title","colorDefinition"]}}},"contract":{"is_enabled":{"type":"boolean"},"transport":{"type":"string","nullable":true,"maxLength":8192},"departure_point":{"type":"string","nullable":true,"maxLength":8192},"place_of_stay":{"type":"string","nullable":true,"maxLength":8192},"tour_name":{"type":"string","nullable":true,"maxLength":8192},"tour_date":{"type":"string","nullable":true,"maxLength":8192},"notes":{"type":"string","nullable":true,"maxLength":8192},"number_of_days":{"type":"string","nullable":true,"maxLength":8192},"payment_info":{"type":"string","nullable":true,"maxLength":8192}},"deposit":{"is_enabled":{"type":"boolean"},"deposit_mode":{"type":"string","enum":["real","virtual"]},"deposit_deadline":{"type":"string","nullable":true,"maxLength":8192},"deposit_deadline_days":{"type":"integer","nullable":true,"minimum":0,"maximum":31536000},"meta_surcharge_description":{"type":"string","nullable":true,"maxLength":8192}},"import":{"is_enabled":{"type":"boolean"},"import_from_csv":{"type":"boolean"},"import_from_tickets":{"type":"boolean"},"auto_import":{"type":"boolean"}},"global_search":{"is_enabled":{"type":"boolean"}},"event_feedback":{"is_enabled":{"type":"boolean"}},"program_notifications":{"is_enabled":{"type":"boolean"}},"counseling":{"is_enabled":{"type":"boolean"},"counseling_event_type":{"type":"string","nullable":true,"maxLength":8192},"registration_start_time":{"type":"datetime","nullable":true},"max_active_bookings":{"type":"integer","nullable":true,"minimum":0,"maximum":31536000}},"cleaning":{"is_enabled":{"type":"boolean"}},"reception":{"is_enabled":{"type":"boolean"}}},"appOnly":["workshops","map","songbook","game","my_schedule","user_groups","entry_code","timetable","volunteers","companions","schedule","import","global_search","event_feedback","program_notifications","counseling","cleaning","reception"]}$json$::jsonb;
$contract$;
REVOKE ALL ON FUNCTION public.configuration_settings_contract_internal_v1() FROM PUBLIC,anon,authenticated,service_role;

-- Single status owner. Configuration belongs to Unit; forms contain only intent.
CREATE OR REPLACE FUNCTION public.form_measurement_status_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH scope AS MATERIALIZED (
  SELECT coalesce(public.normalize_form_metadata_internal(f.data)#>'{analytics,enabled}'='true'::jsonb,false) requested,
   coalesce(org.data->'FORM_MEASUREMENT_ENABLED'='true'::jsonb,false) organization_enabled,
   coalesce(u.data->'measurement_enabled'='true'::jsonb,false) unit_enabled,
   coalesce(length(u.data->>'measurement_privacy_url') BETWEEN 1 AND 2048
    AND (u.data->>'measurement_privacy_url') ~ (public.configuration_settings_contract_internal_v1()#>>'{unit,measurement_privacy_url,pattern}'),false) privacy_policy_valid,
   coalesce(p.enabled,false) allowed,coalesce(p.revision,0) revision,
   coalesce(nullif(btrim(u.data->>'measurement_gtm_container'),''),nullif(u.data->>'measurement_scripts','')) IS NOT NULL destination,
   coalesce(r.runtime_profile='gtm-v1' AND r.runtime_origin ~ '^https://[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\.pages\.dev$'
    AND cardinality(r.parent_origins)>0 AND NOT public.is_demo_occasion(f.occasion),false) supported
  FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
  JOIN public.units u ON u.id=o.unit AND u.organization=o.organization
  JOIN public.organizations org ON org.id=o.organization
  LEFT JOIN analytics.organization_policy p ON p.organization=o.organization
  LEFT JOIN analytics.unit_runtime r ON r.unit=u.id
  WHERE f.id=p_form
 ) SELECT jsonb_build_object('requested_enabled',requested,'organization_allowed',allowed,
  'organization_enabled',organization_enabled,'unit_enabled',unit_enabled,
  'runtime_supported',supported,'eligible',requested AND allowed AND organization_enabled AND unit_enabled AND destination AND supported AND privacy_policy_valid,
  'policy_revision',revision,'consent_required',true,'enhanced_conversions_unavailable',false,
  'blocked_reasons',to_jsonb(array_remove(ARRAY[
   CASE WHEN NOT requested THEN 'disabled' END,
   CASE WHEN NOT allowed THEN 'organization_not_enabled' END,
   CASE WHEN NOT organization_enabled THEN 'organization_disabled' END,
   CASE WHEN NOT unit_enabled THEN 'unit_disabled' END,
   CASE WHEN NOT supported THEN 'runtime_unavailable' END,
   CASE WHEN NOT destination THEN 'no_destination' END,
   CASE WHEN NOT privacy_policy_valid THEN 'no_privacy_policy' END],NULL))) FROM scope;
$$;
REVOKE ALL ON FUNCTION public.form_measurement_status_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.form_measurement_runtime_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH status AS MATERIALIZED (
  SELECT public.form_measurement_status_internal(p_form) AS s
 )
 SELECT jsonb_build_object('enabled',s->'requested_enabled','organization_allowed',s->'organization_allowed',
  'runtime_supported',s->'runtime_supported','eligible',s->'eligible','organization',o.organization,'unit',u.id,
  'runtime_origin',CASE WHEN s->'eligible'='true'::jsonb THEN r.runtime_origin END,
  'privacy_url',CASE WHEN s->'eligible'='true'::jsonb THEN u.data->>'measurement_privacy_url' END,
  'consent_notice',CASE WHEN s->'eligible'='true'::jsonb THEN jsonb_build_object('layout',coalesce(u.data->>'measurement_consent_layout','bar'),
   'title',nullif(btrim(u.data->>'measurement_consent_title'),''),'text',nullif(btrim(u.data->>'measurement_consent_text'),'')) END,
  'approved_hosts',CASE WHEN s->'eligible'='true'::jsonb THEN to_jsonb(r.parent_origins) ELSE '[]'::jsonb END,
  'configuration_revision',md5(jsonb_build_array(u.data->'measurement_gtm_container',u.data->'measurement_scripts',
   u.data->'measurement_enabled',org.data->'FORM_MEASUREMENT_ENABLED',s->'requested_enabled')::text),
  'runtime_revision',coalesce(r.revision,0),'policy_revision',s->'policy_revision','valid_for_seconds',60,'consent_required',true)
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN public.units u ON u.id=o.unit AND u.organization=o.organization
 JOIN public.organizations org ON org.id=o.organization
 LEFT JOIN analytics.organization_policy p ON p.organization=o.organization
  LEFT JOIN analytics.unit_runtime r ON r.unit=u.id
 CROSS JOIN status
 WHERE f.id=p_form;
$$;
REVOKE ALL ON FUNCTION public.form_measurement_runtime_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Who is asking, from the caller's JWT. Administrators of the organization and managers
-- of the Unit that owns the form are not measured; the browser cannot decide this itself.
CREATE OR REPLACE FUNCTION public.form_measurement_visitor_role_internal(p_form bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN auth.uid() IS NULL THEN 'anonymous'
  WHEN EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form
   AND (public.can_manage_organization_settings(o.organization) OR public.can_manage_unit_configuration(o.unit))) THEN 'staff'
  ELSE 'visitor' END;
$$;
REVOKE ALL ON FUNCTION public.form_measurement_visitor_role_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Browser renewal returns minimal effective policy, never destination code/IDs.
CREATE OR REPLACE FUNCTION public.get_form_measurement_policy(p_form_link text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint:=public.resolve_form_link_internal(p_form_link);
BEGIN
 IF NOT public.can_read_public_form_measurement(fid) THEN RETURN NULL; END IF;
 RETURN public.form_measurement_runtime_internal(fid)||jsonb_build_object('visitor_role',public.form_measurement_visitor_role_internal(fid));
END $$;
REVOKE ALL ON FUNCTION public.get_form_measurement_policy(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_form_measurement_policy(text) TO anon,authenticated,service_role;

-- Only the runtime server receives Unit configuration; its credential never
-- appears in the HTML, messages, public policy, logs or parent application.
CREATE OR REPLACE FUNCTION public.get_form_measurement_runtime_config(
 p_form_link text,p_organization bigint,p_unit bigint,p_runtime_origin text,p_parent_origin text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint:=public.resolve_form_link_internal(p_form_link); result jsonb;
BEGIN
 IF NOT public.can_read_form_measurement_runtime(fid,p_organization,p_unit,p_runtime_origin,p_parent_origin) THEN
  RAISE insufficient_privilege USING MESSAGE='form measurement runtime unavailable';
 END IF;
 SELECT jsonb_build_object('organization',o.organization,'unit',u.id,'form_id',f.id,'form_link',f.link,
  'runtime_origin',r.runtime_origin,'parent_origin',p_parent_origin,'profile',r.runtime_profile,
  'ancestor_origins',r.parent_origins,'collector_origins',r.collector_origins,'policy',public.form_measurement_runtime_internal(f.id)-ARRAY['privacy_url','consent_notice','approved_hosts'],
  'gtm_container',u.data->>'measurement_gtm_container','scripts',u.data->>'measurement_scripts') INTO result
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN public.units u ON u.id=o.unit AND u.organization=o.organization
 JOIN analytics.unit_runtime r ON r.unit=u.id
 WHERE f.id=fid;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_form_measurement_runtime_config(text,bigint,bigint,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_form_measurement_runtime_config(text,bigint,bigint,text,text) TO service_role;
