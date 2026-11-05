-- SQL runner wraps the fixture in a transaction and rolls it back.
DO $$
DECLARE org bigint; other_org bigint; un bigint; oc bigint; f bigint; actor uuid:=gen_random_uuid();
 payload jsonb; result jsonb; saved jsonb; patch jsonb; candidate text; reset_patch jsonb; canonical boolean;
BEGIN
 -- Regression: a valid analytics object must not make the PL/pgSQL local k
 -- ambiguous with the jsonb_object_keys alias (42702).
 PERFORM assert_eq(public.apply_form_settings_internal('{"analytics":{"gtm_container":"GTM-AB12"}}',
  '{"communication_tone":"formal"}')#>>'{communication_tone}','formal','analytics validation and ordinary settings save coexist');
 INSERT INTO public.organizations(title) VALUES('Measurement permissions') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Unrelated organization') RETURNING id INTO other_org;
 INSERT INTO public.units(organization,title) VALUES(org,'Organizer') RETURNING id INTO un;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,un,'Summer concert',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id) VALUES(actor);
 INSERT INTO public.user_info(id,organization) VALUES(actor,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view,is_editor_order)
 VALUES(oc,actor,true,true,true);
 INSERT INTO public.forms(occasion,title,is_open) VALUES(oc,'Tickets',false) RETURNING id INTO f;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 payload:=jsonb_build_object('id',f,'occasion',oc);
 PERFORM assert_false(public.can_manage_form_measurement(oc),'editor and seller are not measurement administrators');
 FOREACH candidate IN ARRAY ARRAY['gtm_container','scripts','enhanced_conversions'] LOOP
  patch:=jsonb_build_object('analytics',jsonb_build_object(candidate,CASE WHEN candidate='enhanced_conversions' THEN 'true'::jsonb WHEN candidate='scripts' THEN to_jsonb('<script>window.test=1</script>'::text) ELSE to_jsonb('GTM-AB12'::text) END));
  BEGIN
   PERFORM public.update_form_internal_v1(payload||jsonb_build_object('settings',patch));
   RAISE EXCEPTION 'editor changed measurement';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
   PERFORM public.update_form_internal_v1(payload||jsonb_build_object('data',patch));
   RAISE EXCEPTION 'released metadata bypassed measurement permission';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(other_org,actor,true);
 PERFORM assert_false(public.can_manage_form_measurement(oc),'administrator of another organization has no authority');
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,actor,true);
 PERFORM assert_true(public.can_manage_form_measurement(oc),'highest existing organization role owns both fields');
 patch:='{"analytics":{"gtm_container":"GTM-AB12","scripts":"<script>window.test=1</script>"}}';
 result:=public.update_form_internal_v1(payload||jsonb_build_object('settings',patch));
 PERFORM assert_eq(result->>'code','200','administrator saves measurement using the normal settings mechanism');
 saved:=(SELECT data FROM public.forms WHERE id=f);
 UPDATE public.organization_users SET is_admin=false WHERE organization=org AND "user"=actor;
 -- An ordinary edit may preserve existing measurement, but may neither replace
 -- it nor clear a whole section, through either client generation.
 result:=public.update_form_internal_v1(payload||jsonb_build_object('title','Changed'));
 PERFORM assert_eq(result->>'code','200','editor can preserve administrator settings');
 result:=public.update_form_internal_v1(payload||jsonb_build_object('data','{}'::jsonb));
 PERFORM assert_eq(result->>'code','200','older clients omit and preserve measurement');
 PERFORM assert_eq((SELECT data->'analytics' FROM public.forms WHERE id=f),saved->'analytics','older client cannot erase newer settings');
 BEGIN
  PERFORM public.update_form_internal_v1(payload||jsonb_build_object('settings','{"analytics":null}'::jsonb));
  RAISE EXCEPTION 'editor cleared measurement';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.update_form_internal_v1(payload||jsonb_build_object('data','{"analytics":null}'::jsonb));
  RAISE EXCEPTION 'released client cleared measurement';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 -- Preservation is a normalized comparison, including explicit known keys.
 result:=public.update_form_internal_v1(payload||jsonb_build_object('settings',public.form_settings_from_metadata_internal(saved)));
 PERFORM assert_eq(result->>'code','200','unchanged settings snapshot is accepted');
 BEGIN
  PERFORM public.apply_form_settings_internal('{}',jsonb_build_object('analytics',jsonb_build_object('scripts',repeat('x',public.form_measurement_script_limit_internal()+1))));
  RAISE EXCEPTION 'oversized script accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM assert_eq(length(public.apply_form_settings_internal('{}',jsonb_build_object('analytics',jsonb_build_object('scripts',repeat('x',public.form_measurement_script_limit_internal()))))#>>'{analytics,scripts}'),public.form_measurement_script_limit_internal(),'limit is inclusive');
 FOREACH candidate IN ARRAY ARRAY['gtm-AB12','GTM-','GTM-<script>','GTM-AB 12','https://example.test'] LOOP
  BEGIN
   PERFORM public.apply_form_settings_internal('{}',jsonb_build_object('analytics',jsonb_build_object('gtm_container',candidate)));
   RAISE EXCEPTION 'invalid GTM accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 UPDATE public.organization_users SET is_admin=true WHERE organization=org AND "user"=actor;
 -- Both the pre-conversion presale ingress and the current form must retain
 -- explicit analytics resets, including the editor's empty-fields snapshot.
 FOREACH canonical IN ARRAY ARRAY[false,true] LOOP
  UPDATE public.forms SET data=CASE WHEN canonical THEN '{"design":{"presale_header":"none"}}'::jsonb ELSE '{}'::jsonb END WHERE id=f;
  FOR reset_patch IN SELECT value FROM jsonb_array_elements('[{"analytics":null},{"analytics":{"gtm_container":null,"scripts":null,"enhanced_conversions":null}}]'::jsonb) LOOP
   result:=public.update_form_internal_v1(payload||jsonb_build_object('settings',patch));
   PERFORM assert_eq(result->>'code','200','administrator can restore measurement before reset');
   result:=public.update_form_internal_v1(payload||jsonb_build_object('settings',reset_patch));
   PERFORM assert_eq(result->>'code','200','explicit reset saves through either presale ingress');
   PERFORM assert_false((SELECT data ? 'analytics' FROM public.forms WHERE id=f),'empty measurement fields really remove analytics');
  END LOOP;
 END LOOP;
 BEGIN
  PERFORM public.apply_form_settings_internal('{}','{"analytics":{"enhanced_conversions":"true"}}');
  RAISE EXCEPTION 'non-boolean enhanced conversions accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM assert_eq(public.apply_form_settings_internal('{}','{"analytics":{"enhanced_conversions":true}}')#>'{analytics,enhanced_conversions}','true'::jsonb,'enhanced conversions uses the validated settings path');
 PERFORM assert_false(has_function_privilege('authenticated','public.apply_form_settings_internal(jsonb,jsonb)','EXECUTE'),'private validator is not a write bypass');
 PERFORM assert_false(has_function_privilege('anon','public.form_purchase_datalayer_internal(bigint)','EXECUTE'),'anonymous callers cannot enumerate order analytics');
END $$;
