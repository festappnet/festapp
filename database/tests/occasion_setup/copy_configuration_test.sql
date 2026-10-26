-- Configuration-only copy must retain capacity and program eligibility/structure.
DO $$
DECLARE actor uuid; org bigint; un bigint; oc bigint; form_id bigint; parent_id bigint; child_id bigint;
 place_id bigint; role_id bigint; exclusive_id bigint; source jsonb; draft jsonb; response jsonb; target bigint;
 payload jsonb; command uuid:=gen_random_uuid(); count_before bigint; saved jsonb;
 target_parent bigint; target_child bigint; target_place bigint; target_role bigint; target_exclusive bigint;
BEGIN
 PERFORM create_user_for_test('setup-copy-config','setup-copy-'||gen_random_uuid()||'@example.invalid');
 actor:=get_user_id('setup-copy-config');
 INSERT INTO public.organizations(title,data) VALUES('Setup copy configuration','{"IS_APP_SUPPORTED":true}') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Copy unit',org) RETURNING id INTO un;
 INSERT INTO public.unit_users("user",unit,is_editor,is_manager) VALUES(actor,un,true,true);
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,un,'Copy source','copy-source-'||gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.forms(occasion,title,link,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds)
 VALUES(oc,'Limited registration','capacity-'||gen_random_uuid(),10,true,false,3600) RETURNING id INTO form_id;
 INSERT INTO public.form_fields(form,type,title,"order") VALUES(form_id,'name','Name',0);
 INSERT INTO public.places(occasion,unit,title,is_hidden,coordinates,"order") VALUES(oc,un,'Private hall',true,'{"latLng":{"lat":50,"lng":14}}',7) RETURNING id INTO place_id;
 INSERT INTO public.role_info(occasion,title) VALUES(oc,'Eligible group') RETURNING id INTO role_id;
 INSERT INTO public.exclusive_groups(occasion,title) VALUES(oc,'Choose one') RETURNING id INTO exclusive_id;
 INSERT INTO public.events(occasion,title,start_time,end_time,max_participants,is_hidden,is_group_event,split_for_men_women,type,place,"order")
 VALUES(oc,'Hidden parent',now(),now()+interval '1 hour',23,true,true,true,'workshop',place_id,3) RETURNING id INTO parent_id;
 INSERT INTO public.events(occasion,title,start_time,end_time,place) VALUES(oc,'Child',now(),now()+interval '1 hour',place_id) RETURNING id INTO child_id;
 INSERT INTO public.event_groups(event_parent,event_child) VALUES(parent_id,child_id);
 INSERT INTO public.event_users(event,"user") VALUES(parent_id,actor);
 INSERT INTO public.event_roles(event,role) VALUES(parent_id,role_id),(child_id,role_id);
 INSERT INTO public.exclusive_events(event,"group") VALUES(parent_id,exclusive_id),(child_id,exclusive_id);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM assert_false(has_function_privilege('authenticated','public.materialize_occasion_setup_program_internal(jsonb,bigint,bigint)','EXECUTE'),'Program materializer is internal');
 SELECT x INTO source FROM jsonb_array_elements(public.get_occasion_setup_sources(un)) x WHERE (x#>>'{occasion,id}')::bigint=oc;
 PERFORM assert_eq((source#>>'{forms,0,participant_capacity}')::int,10,'Source preserves capacity');
 PERFORM assert_eq(source#>'{forms,0,waitlist_enabled}','true'::jsonb,'Source preserves waitlist');
 draft:=public.create_occasion_setup_draft(gen_random_uuid(),un);
 PERFORM assert_eq(jsonb_array_length(draft#>'{data,defaultConfiguration,forms}'),1,'App-supported wizard has canonical default form');
 -- Recover an older empty default snapshot without replacing the user's form.
 draft:=public.save_occasion_setup_draft((draft->>'id')::uuid,(draft->>'revision')::bigint,
   jsonb_set(jsonb_set(draft->'data','{defaultConfiguration,forms}','[]'),'{formDraft,title}','"Keep my form"')||'{"title":"Keep my title"}',0);
 BEGIN PERFORM public.initialize_occasion_setup_draft_defaults((draft->>'id')::uuid,1);
  RAISE EXCEPTION 'Stale default repair accepted'; EXCEPTION WHEN serialization_failure THEN NULL; END;
 saved:=public.initialize_occasion_setup_draft_defaults((draft->>'id')::uuid,(draft->>'revision')::bigint);
 PERFORM assert_eq(saved#>>'{data,title}','Keep my title','Repair retains event edits');
 PERFORM assert_eq(saved#>>'{data,formDraft,title}','Keep my form','Repair retains form edits');
 PERFORM assert_eq(jsonb_array_length(saved#>'{data,defaultConfiguration,forms}'),1,'Repair installs usable canonical defaults');
 PERFORM assert_eq(public.initialize_occasion_setup_draft_defaults((draft->>'id')::uuid,(draft->>'revision')::bigint),saved,'Default repair retry is idempotent');
 draft:=saved;
 draft:=public.save_occasion_setup_draft((draft->>'id')::uuid,(draft->>'revision')::bigint,
 jsonb_build_object('title','Configuration copy','link','config-copy-'||gen_random_uuid(),'sourceId',oc,
 'start',now(),'end',now()+interval '1 day','formEnabled',true,'formDraft',(source->'forms'->0)-'link',
 'sourceProgram',source->'program','copyProgram',true,'reviewConfirmed',true,'blueprintMode','Bez plánku'),5);
 response:=public.finalize_occasion_setup_draft((draft->>'id')::uuid,(draft->>'revision')::bigint,gen_random_uuid());
 target:=(response#>>'{data,occasionId}')::bigint;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT jsonb_build_array(participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds,is_open) FROM public.forms WHERE occasion=target),'[10,true,false,3600,false]'::jsonb,'Copied form keeps capacity and waitlist configuration closed');
 SELECT id,place INTO target_parent,target_place FROM public.events WHERE occasion=target AND title='Hidden parent';
 SELECT id INTO target_child FROM public.events WHERE occasion=target AND title='Child';
 PERFORM assert_eq((SELECT jsonb_build_array(max_participants,is_hidden,is_group_event,split_for_men_women,type,"order") FROM public.events WHERE id=target_parent),'[23,true,true,true,"workshop",3]'::jsonb,'Copied program retains eligibility and flags');
 PERFORM assert_true(target_parent<>parent_id AND target_child<>child_id,'Program events have fresh IDs');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.event_groups WHERE event_parent=target_parent AND event_child=target_child),'Hierarchy remapped');
 PERFORM assert_not_null(target_place,'Copied event has a place');
 PERFORM assert_true(target_place<>place_id AND (SELECT place=target_place FROM public.events WHERE id=target_child),'Shared place copied once');
 PERFORM assert_true((SELECT occasion=target AND unit=un AND title='Private hall' AND is_hidden AND "order"=7 AND coordinates='{"latLng":{"lat":50,"lng":14}}'::jsonb FROM public.places WHERE id=target_place),'Place configuration retained');
 SELECT id INTO target_role FROM public.role_info WHERE occasion=target AND title='Eligible group';
 PERFORM assert_true(target_role<>role_id AND (SELECT count(*)=2 FROM public.event_roles WHERE role=target_role AND event IN(target_parent,target_child)),'Eligibility role cloned and shared with remapped events');
 SELECT id INTO target_exclusive FROM public.exclusive_groups WHERE occasion=target AND title='Choose one';
 PERFORM assert_true(target_exclusive<>exclusive_id AND (SELECT count(*)=2 FROM public.exclusive_events WHERE "group"=target_exclusive AND event IN(target_parent,target_child)),'Exclusive choices remapped');
 PERFORM assert_eq((SELECT count(*) FROM public.event_users WHERE event IN(target_parent,target_child)),0::bigint,'No program signups copied');
 PERFORM assert_true((SELECT is_hidden AND NOT is_open FROM public.occasions WHERE id=target),'Copied occasion stays hidden and closed');
 SELECT count(*) INTO count_before FROM public.occasions;
 payload:=draft->'data'||jsonb_build_object('title','Broken program copy','link','broken-program-'||gen_random_uuid());
 payload:=jsonb_set(payload,'{sourceProgram}',(SELECT jsonb_agg(CASE WHEN (e->>'id')::bigint=parent_id
   THEN jsonb_set(e,'{children}','[999999999]') ELSE e END) FROM jsonb_array_elements(source->'program') e));
 EXECUTE 'SET LOCAL ROLE authenticated';
 draft:=public.create_occasion_setup_draft(gen_random_uuid(),un);
 draft:=public.save_occasion_setup_draft((draft->>'id')::uuid,(draft->>'revision')::bigint,payload,5);
 BEGIN PERFORM public.finalize_occasion_setup_draft((draft->>'id')::uuid,(draft->>'revision')::bigint,command);
  RAISE EXCEPTION 'Foreign program group accepted';
 EXCEPTION WHEN invalid_parameter_value THEN IF SQLERRM<>'Program group reference missing' THEN RAISE; END IF; END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.occasions),count_before,'Late program error rolls back the entire event');
 EXECUTE 'SET LOCAL ROLE authenticated';
 payload:=jsonb_set(payload,'{sourceProgram}',source->'program');
 draft:=public.save_occasion_setup_draft((draft->>'id')::uuid,(draft->>'revision')::bigint,payload,5);
 response:=public.finalize_occasion_setup_draft((draft->>'id')::uuid,(draft->>'revision')::bigint,command);
 PERFORM assert_eq(response->>'status','applied','Corrected program retries the same command');
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.occasions),count_before+1,'Corrected program commits once');
END $$;
