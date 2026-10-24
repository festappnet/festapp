GRANT EXECUTE ON FUNCTION public.assert_true(boolean,text), public.assert_false(boolean,text), public.assert_eq(anyelement,anyelement,text) TO authenticated;
DO $$
DECLARE actor uuid; org bigint; foreign_org bigint; target bigint; foreign_unit bigint;
  id uuid := gen_random_uuid(); d jsonb; saved jsonb; initial_count bigint; initial_forms bigint; initial_products bigint; initial_types bigint;
BEGIN
  SELECT ui.id,ui.organization INTO actor,org FROM public.user_info ui LIMIT 1;
  SELECT unit INTO target FROM public.unit_users WHERE "user"=actor AND (is_manager OR is_editor) LIMIT 1;
  SELECT count(*) INTO initial_count FROM public.occasions;
  SELECT count(*) INTO initial_forms FROM public.forms;
  SELECT count(*) INTO initial_products FROM eshop.products;
  SELECT count(*) INTO initial_types FROM eshop.product_types;
  INSERT INTO public.organizations(title) VALUES('Other draft organization') RETURNING public.organizations.id INTO foreign_org;
  INSERT INTO public.units(title,organization) VALUES('Other draft unit',foreign_org) RETURNING public.units.id INTO foreign_unit;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM assert_false(has_table_privilege('authenticated','public.occasion_setup_drafts','SELECT'),'No direct draft reads');
  PERFORM assert_false(has_table_privilege('anon','public.occasion_setup_drafts','SELECT'),'No public drafts');
  PERFORM assert_false(has_function_privilege('anon','public.get_occasion_setup_drafts(bigint)','EXECUTE'),'Public callers cannot invoke draft RPC');
  PERFORM assert_false(has_function_privilege('authenticated','public.build_occasion_setup_configuration(bigint,uuid)','EXECUTE'),'Internal creation snapshot cannot be invoked directly');
  d := public.create_occasion_setup_draft(id,target);
  PERFORM assert_eq(public.get_occasion_setup_draft(id),d,'Single read returns authorized draft');
  PERFORM assert_false(has_function_privilege('anon','public.get_occasion_setup_draft(uuid)','EXECUTE'),'Single read is private');
  PERFORM assert_true(d->'data' ? 'defaultConfiguration','Draft is initialized by the canonical creator');
  PERFORM assert_eq(d->'data'->'formDraft'->>'title','Registration','Canonical form title');
  PERFORM assert_true(d->'data'->'formDraft'->>'deadline_duration_seconds' IS NULL,'New draft deadline inherits without materializing an override');
  PERFORM assert_false(d#>'{data,formDraft,data}' ? 'is_reminder_enabled','New draft reminder inherits without materializing an override');
  PERFORM assert_eq(d->'data'->'formDraft'->'fields'->0->>'type','email','Canonical first field');
  PERFORM assert_true((d->'data'->'formDraft'->'fields'->0->>'is_required')::boolean,'Canonical email is required');
  PERFORM assert_eq(d->'data'->'formDraft'->'fields'->1->>'type','ticket','Canonical ticket field');
  PERFORM assert_eq(d->'data'->'formDraft'->'fields'->2->'product_type_data'->>'type','spot','Canonical spot type');
  PERFORM assert_eq((d->'data'->'formDraft'->'fields'->2->'product_type_data'->'products'->0->>'price')::numeric,100::numeric,'Canonical default product');
  PERFORM assert_eq(public.initialize_occasion_setup_draft_defaults(id,1),d,'Initialization retry is idempotent');
  PERFORM assert_eq(public.create_occasion_setup_draft(id,target),d,'Create retry returns the same draft');
  saved := public.save_occasion_setup_draft(id,1,'{"title":"Saved draft"}',0);
  PERFORM assert_eq((saved->>'revision')::int,2,'Save advances revision');
  PERFORM assert_eq(public.save_occasion_setup_draft(id,1,'{"title":"Saved draft"}',0),saved,'Save retry is idempotent');
  PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_occasion_setup_drafts(target)) x WHERE x->>'id'=id::text),'Saved draft can be resumed');
  BEGIN PERFORM public.save_occasion_setup_draft(id,1,'{"title":"stale"}',0); RAISE EXCEPTION 'stale save accepted'; EXCEPTION WHEN serialization_failure THEN NULL; END;
  BEGIN PERFORM public.delete_occasion_setup_draft(id,target,1); RAISE EXCEPTION 'stale delete accepted'; EXCEPTION WHEN serialization_failure THEN NULL; END;
  BEGIN PERFORM public.save_occasion_setup_draft(id,2,'[]',0); RAISE EXCEPTION 'invalid data accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM public.get_occasion_setup_drafts(foreign_unit); RAISE EXCEPTION 'foreign unit read accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.create_occasion_setup_draft(gen_random_uuid(),foreign_unit); RAISE EXCEPTION 'foreign unit write accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  EXECUTE 'RESET ROLE';
  PERFORM assert_eq((SELECT count(*) FROM public.occasions),initial_count,'Drafts never create public occasions');
  PERFORM assert_eq((SELECT count(*) FROM public.forms),initial_forms,'Provisional forms are rolled back');
  PERFORM assert_eq((SELECT count(*) FROM eshop.products),initial_products,'Provisional products are rolled back');
  PERFORM assert_eq((SELECT count(*) FROM eshop.product_types),initial_types,'Provisional product types are rolled back');
  -- Revoked permissions are rechecked on every save/read/delete.
  DELETE FROM public.unit_users WHERE "user"=actor AND unit=target;
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN PERFORM public.save_occasion_setup_draft(id,2,'{}',0); RAISE EXCEPTION 'revoked editor write accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_occasion_setup_drafts(target); RAISE EXCEPTION 'revoked editor read accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_occasion_setup_draft(id); RAISE EXCEPTION 'revoked editor single read accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.delete_occasion_setup_draft(id,target,2); RAISE EXCEPTION 'revoked editor delete accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  EXECUTE 'RESET ROLE';
  INSERT INTO public.unit_users("user",unit,is_editor) VALUES(actor,target,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  saved := public.save_occasion_setup_draft(id,2,'{"title":"Full Wizard","step":5,"completed":[0,1,2,3,4,5],"formDraft":{"title":"Copied form"}}',5);
  PERFORM assert_eq((saved->>'current_step')::int,5,'Full Wizard step is persisted');
  PERFORM assert_eq(jsonb_array_length(saved->'data'->'completed'),6,'All completed steps are retained');
  saved := public.save_occasion_setup_draft(id,3,
    '{"step":6,"completed":[0,1,3,6,4,2,5]}',6);
  PERFORM assert_eq((saved->>'current_step')::int,6,'Separate blueprint step is persisted');
  PERFORM assert_eq(jsonb_array_length(saved->'data'->'completed'),7,'Seven-step ticket flow is retained');
  PERFORM public.delete_occasion_setup_draft(id,target,4);
  PERFORM public.delete_occasion_setup_draft(id,target,4);
  PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_occasion_setup_drafts(target)) x WHERE x->>'id'=id::text),'Deleted draft disappears');
  EXECUTE 'RESET ROLE';
END $$;

DO $$
DECLARE actor uuid; target bigint; draft_id uuid:=gen_random_uuid(); d jsonb; saved jsonb;
BEGIN
 SELECT ui.id,uu.unit INTO actor,target FROM public.user_info ui JOIN public.unit_users uu ON uu."user"=ui.id WHERE uu.is_manager OR uu.is_editor LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.create_occasion_setup_draft(draft_id,target);
 saved:=public.save_occasion_setup_draft(draft_id,(d->>'revision')::bigint,
   (d->'data') #- '{defaultConfiguration,communicationDefaults}',3);
 d:=public.initialize_occasion_setup_draft_defaults(draft_id,(saved->>'revision')::bigint);
 PERFORM assert_true(d#>'{data,defaultConfiguration}' ? 'communicationDefaults','Older drafts acquire explicit inherited communication context');
 PERFORM assert_eq(d#>'{data,formDraft}',saved#>'{data,formDraft}','Upgrade preserves the complete authored form');
 PERFORM assert_eq(public.initialize_occasion_setup_draft_defaults(draft_id,(d->>'revision')::bigint),d,'Upgrade is idempotent');
 EXECUTE 'RESET ROLE';
END $$;
