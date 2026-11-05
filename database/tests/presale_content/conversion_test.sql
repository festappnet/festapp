-- test-setup: database/functions/eshop_forms/form_settings.sql
-- test-setup: database/functions/presale_content/archive.sql
-- test-setup: database/functions/eshop_forms/form_creation_domain.sql
-- test-setup: database/functions/eshop_forms/update_form.sql
-- test-setup: database/functions/eshop_forms/update_form_client_sync_v1.sql
DO $$
DECLARE org bigint; unit_id bigint; occ bigint; fid bigint; actor uuid; original jsonb; source_hash text; conversion uuid:=gen_random_uuid();
 legacy_form bigint; result jsonb; after_data jsonb; patch jsonb; receipt jsonb;
BEGIN
 PERFORM create_user_for_test('presale_author','presale-author@example.invalid'); actor:=get_user_id('presale_author');
 INSERT INTO public.organizations(title) VALUES('Presale tests') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Organizer',org) RETURNING id INTO unit_id;
 INSERT INTO public.unit_users(unit,"user",is_editor) VALUES(unit_id,actor,true);
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time)
 VALUES('Event',gen_random_uuid()::text,org,unit_id,now()+interval '3 days',now()+interval '4 days') RETURNING id INTO occ;
 original:='{"schedule":{"countdown_title":"<p>Main</p>","before_start_message":"<p>Private</p>","show_before_start_message":false,"enable_countdown":false},"design":{"theme_mode":"dark"}}';
 INSERT INTO public.forms(title,occasion,is_open,data) VALUES('Form',occ,false,original) RETURNING id INTO fid;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 -- A shared schema release must preserve other unconverted tenants. Current
 -- UI/MCP expose no second editor, but released clients still have an ingress.
 INSERT INTO public.forms(title,occasion,is_open,data) VALUES('Unconverted',occ,false,original) RETURNING id INTO legacy_form;
 receipt:=public.update_form_client_sync_v1(jsonb_build_object('id',legacy_form,'occasion',occ,'title','Legacy unchanged',
  'data',original),gen_random_uuid());
 PERFORM assert_eq((receipt->>'code')::int,200,'Installed full save on unconverted form remains supported');
 PERFORM assert_eq((SELECT data#>>'{schedule,before_start_message}' FROM public.forms WHERE id=legacy_form),'<p>Private</p>','Unconverted hidden text preserved');
 receipt:=public.update_form_client_sync_v1(jsonb_build_object('id',legacy_form,'occasion',occ,
  'settings','{"schedule":{"before_start_message":"<p>Legacy edit</p>","show_before_start_message":true}}'::jsonb),gen_random_uuid());
 PERFORM assert_eq((receipt->>'code')::int,200,'Installed settings adapter stays bounded for unconverted forms');
 PERFORM assert_eq((SELECT data#>>'{schedule,before_start_message}' FROM public.forms WHERE id=legacy_form),'<p>Legacy edit</p>','Unconverted legacy ingress updates its retained field');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.form_presale_content_archive WHERE form=legacy_form),'Other form is not implicitly converted');
 BEGIN
  PERFORM public.guard_form_presale_write_internal(original,'{"settings":{"design":{"presale_header":"event_and_date"}}}');
  RAISE EXCEPTION 'archive bypass accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 source_hash:=encode(extensions.digest(convert_to(original::text,'UTF8'),'sha256'),'hex');
 BEGIN
  PERFORM public.convert_form_presale_content(fid,1,source_hash,'<p>Main</p>',conversion);
  RAISE EXCEPTION 'version conflict accepted';
 EXCEPTION WHEN serialization_failure THEN NULL; END;
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.form_presale_content_archive WHERE form=fid),'Conflict rolls back archive');
 BEGIN
  PERFORM public.convert_form_presale_content(fid,0,source_hash,repeat('x',65537),conversion);
  RAISE EXCEPTION 'oversized conversion accepted';
 EXCEPTION WHEN invalid_parameter_value OR program_limit_exceeded THEN NULL; END;
 PERFORM assert_eq((SELECT data FROM public.forms WHERE id=fid),original,'Oversize never truncates or mutates');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.form_presale_content_archive WHERE form=fid),'Oversize rolls back archive');
 result:=public.convert_form_presale_content(fid,0,source_hash,'<p>Main</p>',conversion);
 PERFORM assert_eq((result->>'version')::bigint,1::bigint,'Conversion increments form version');
 SELECT data INTO after_data FROM public.forms WHERE id=fid;
 PERFORM assert_eq(after_data#>>'{schedule,countdown_title}','<p>Main</p>','One active document');
 PERFORM assert_eq(after_data#>>'{design,presale_header}','none','Legacy header stays absent');
 PERFORM assert_false(after_data->'schedule' ? 'before_start_message','Retired document removed from public metadata');
 PERFORM assert_eq(public.get_form_presale_archive(fid)->>'secondaryHtml','<p>Private</p>','Author can recover hidden text');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.sale_opening_campaigns WHERE form_id=fid),'Conversion never creates campaign');
 result:=public.convert_form_presale_content(fid,0,source_hash,'<p>Main</p>',conversion);
 PERFORM assert_true((result->>'replayed')::boolean,'Retry is idempotent');
 PERFORM assert_eq((SELECT count(*) FROM public.form_presale_content_archive WHERE form=fid),1::bigint,'One archive');
 BEGIN
  PERFORM public.convert_form_presale_content(fid,0,source_hash,'Changed',conversion);
  RAISE EXCEPTION 'identity changed';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM assert_false(has_table_privilege('anon','public.form_presale_content_archive','SELECT'),'Archive never public');
 PERFORM assert_false(has_table_privilege('authenticated','public.form_presale_content_archive','SELECT'),'Archive requires checked read');
 patch:=public.guard_form_presale_write_internal(after_data,'{"data":{"schedule":{"countdown_title":"<p>Main</p>","enable_countdown":false,"before_start_message":null,"show_before_start_message":false},"design":{"theme_mode":"light"}}}');
 PERFORM assert_eq(patch#>>'{data,design,presale_header}','none','Released full save cannot erase heading');
 BEGIN
  PERFORM public.guard_form_presale_write_internal(after_data,'{"settings":{"schedule":{"countdown_title":"changed"}}}');
  RAISE EXCEPTION 'unversioned page write accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.guard_form_presale_write_internal(after_data,'{"expected_aggregate_version":1,"settings":{"schedule":{"before_start_message":"private"}}}');
  RAISE EXCEPTION 'retired document accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 patch:=public.guard_form_presale_write_internal(after_data,'{"expected_aggregate_version":1,"settings":{"design":null}}');
 patch:=public.apply_form_settings_internal(after_data,patch->'settings');
 PERFORM assert_eq(patch#>>'{design,presale_header}','none','Design reset preserves protected heading');
 PERFORM assert_true(patch#>>'{design,theme_mode}' IS NULL,'Design reset still clears other known keys');
 -- Exercise the actual installed-client adapter, not just the private guard.
 receipt:=public.update_form_client_sync_v1(jsonb_build_object('id',fid,'occasion',occ,'title','Renamed','settings',jsonb_build_object('design',jsonb_build_object('theme_mode','light'))),gen_random_uuid());
 PERFORM assert_eq((receipt->>'code')::int,200,'Unrelated installed-client write permitted');
 PERFORM assert_eq((SELECT data#>>'{design,presale_header}' FROM public.forms WHERE id=fid),'none','Writer preserves header');
 receipt:=public.update_form_client_sync_v1(jsonb_build_object('id',fid,'occasion',occ,'expected_aggregate_version',0,'settings','{}'::jsonb),gen_random_uuid());
 PERFORM assert_eq((receipt->>'code')::int,409,'Stale current client conflicts');
 BEGIN
  PERFORM public.update_form_client_sync_v1(jsonb_build_object('id',fid,'occasion',occ,'settings',
   jsonb_build_object('schedule',jsonb_build_object('countdown_title','Unsafe old edit'))),gen_random_uuid());
  RAISE EXCEPTION 'installed unversioned page write accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM assert_eq((SELECT data#>>'{schedule,countdown_title}' FROM public.forms WHERE id=fid),'<p>Main</p>','Rejected legacy write rolls back');
 receipt:=public.update_form_client_sync_v1(jsonb_build_object('id',fid,'occasion',occ,'expected_aggregate_version',2,'settings',
  '{"design":{"presale_header":"event_and_date"},"schedule":{"countdown_title":"<p>Current edit</p>"}}'::jsonb),gen_random_uuid());
 PERFORM assert_eq((receipt->>'code')::int,200,'Current versioned author can edit page');
 PERFORM assert_eq((SELECT data#>>'{design,presale_header}' FROM public.forms WHERE id=fid),'event_and_date','Current explicit heading saved');
 PERFORM assert_true((public.presale_conversion_budgets_internal('{}',repeat('ž',30000),'{}')->>'blocked')::boolean,'Multibyte transport limit enforced');
 PERFORM assert_true((public.presale_conversion_budgets_internal('{}','small',
  jsonb_build_object('productVersions',(SELECT jsonb_object_agg(i::text,0) FROM generate_series(1,5000) i)))->>'blocked')::boolean,
  'Preflight includes the real parent writer version maps in the transport budget');
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.get_form_presale_archive(fid); RAISE EXCEPTION 'foreign read accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.convert_form_presale_content(fid,0,source_hash,'<p>Main</p>',conversion); RAISE EXCEPTION 'foreign replay accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 -- Authorless legacy rows still have a safe operational migration path, owned
 -- only by the real database operator and bound to the explicitly selected org.
 INSERT INTO public.units(title,organization) VALUES('Orphaned organizer',org) RETURNING id INTO unit_id;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time)
 VALUES('Orphaned event',gen_random_uuid()::text,org,unit_id,now()+interval '3 days',now()+interval '4 days') RETURNING id INTO occ;
 INSERT INTO public.forms(title,occasion,is_open,data) VALUES('Orphaned form',occ,false,original) RETURNING id INTO legacy_form;
 PERFORM assert_false(public.can_author_forms(occ),'Orphan has no current author');
 BEGIN
  PERFORM public.convert_form_presale_content(legacy_form,0,source_hash,'<p>Main</p>',gen_random_uuid());
  RAISE EXCEPTION 'public orphan conversion accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.convert_form_presale_content_internal(org+1,legacy_form,0,source_hash,'<p>Main</p>',gen_random_uuid());
  RAISE EXCEPTION 'foreign operational scope accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM assert_false(has_function_privilege('anon','public.convert_form_presale_content_internal(bigint,bigint,bigint,text,text,uuid)','EXECUTE'),'Operator core not anonymous');
 PERFORM assert_false(has_function_privilege('authenticated','public.convert_form_presale_content_internal(bigint,bigint,bigint,text,text,uuid)','EXECUTE'),'Operator core not an author API');
 PERFORM assert_false(has_function_privilege('service_role','public.convert_form_presale_content_internal(bigint,bigint,bigint,text,text,uuid)','EXECUTE'),'Operator core is not service-role RPC');
 result:=public.convert_form_presale_content_internal(org,legacy_form,0,source_hash,'<p>Main</p>',gen_random_uuid());
 PERFORM assert_eq((result->>'version')::bigint,1::bigint,'Actual postgres operator converts orphan through same core');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.form_presale_content_archive WHERE form=legacy_form),'Orphan original is archived atomically');
END $$;
