-- test-setup: database/operations/blueprint-cutover/apply.sql
-- Exercise the public UI lifecycle, not only the lower-level copy function.
DO $$
DECLARE actor uuid; org bigint; un bigint; source bigint; plan bigint; form_id bigint;
 response jsonb; copied bigint; target_plan bigint; command uuid:=gen_random_uuid();
 canonical jsonb; cutover jsonb;
 legacy jsonb:='{"nodes":[],"canvas":{"x":0,"y":0,"fill":"#ffffffff","width":1120,"height":2080},"schemaVersion":1,"defaultTextStyle":{"size":24,"color":"#222222FF","fontId":"builtin:roboto-unpacked:24438383f80387edbbd3a199d7b257258db7003f5b291a7d3fb6fa89483ae57f"},"symbolSetVersion":1}';
BEGIN
 ALTER TABLE eshop.blueprints DROP CONSTRAINT IF EXISTS blueprints_canonical_layout_check;
 ALTER TABLE eshop.blueprints DROP CONSTRAINT IF EXISTS blueprints_retired_geometry_empty_check;
 ALTER TABLE eshop.blueprints ALTER COLUMN layout DROP NOT NULL;
 PERFORM create_user_for_test('copy-empty-legacy','copy-empty-'||command||'@example.invalid');
 actor:=get_user_id('copy-empty-legacy');
 INSERT INTO public.organizations(title) VALUES('Copy empty legacy') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Copy unit',org) RETURNING id INTO un;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,actor,true,true);
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,features)
 VALUES(org,un,'lol','copy-empty-'||command,now(),now()+interval '1 day',
 '[{"code":"form","is_enabled":true},{"code":"ticket","is_enabled":false,"background":""},{"code":"blueprint","is_enabled":true}]') RETURNING id INTO source;
 INSERT INTO eshop.blueprints(occasion,organization,layout) VALUES(source,org,legacy) RETURNING id INTO plan;
 INSERT INTO public.forms(occasion,title,link,blueprint,is_open)
 VALUES(source,'Registration','copy-empty-form-'||command,plan,false) RETURNING id INTO form_id;
 canonical:=$canonical${"attachments":[],"background":null,"canvas":{"fill":"#ffffffff","height":2080,"width":1120,"x":0,"y":0},"nodes":[],"presets":[],"schemaVersion":2,"seatingDefaults":{},"sections":[],"selectionUnits":[],"styles":{"kinds":{"capacityArea":{"label":{"align":"center"}},"furniture":{"label":{"align":"center"}},"shape":{"label":{"align":"center"}},"table":{"label":{"align":"center"}}},"label":{"color":"#222222FF","fontFamilyId":"font-family:c1aa26e906c50e0bd5847a80ad9d93a37f232b71cea76e5ffa37886676a2eda5","orientation":"screen","size":24}},"symbolSetVersion":1,"textPolicy":{"direction":"auto","language":"und"}}$canonical$::jsonb;
 CREATE TEMP TABLE blueprint_cutover_manifest(payload jsonb) ON COMMIT DROP;
 INSERT INTO blueprint_cutover_manifest VALUES(jsonb_build_object('schemaVersion',1,
   'scopeOrganizationIds',jsonb_build_array(org),'plans',jsonb_build_array(jsonb_build_object(
     'source',pg_temp.blueprint_cutover_source(plan),'beforeLayout',legacy,'beforeRevision',0,
     'layout',canonical,'seatBindings','[]'::jsonb,'groupProducts','[]'::jsonb,
     'prepared',jsonb_build_object('protocol',2,'fontFamilies','{}'::jsonb,'textLayouts','{}'::jsonb,'numberSymbols','{}'::jsonb)))));
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 -- Stale or incomplete preparation fails before changing the source.
 UPDATE blueprint_cutover_manifest SET payload=jsonb_set(payload,'{plans,0,beforeRevision}','1');
 BEGIN
  PERFORM pg_temp.apply_blueprint_layout_cutover();
  RAISE EXCEPTION 'Stale proposal accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'BLUEPRINT_CUTOVER_SOURCE_CHANGED:%' THEN RAISE; END IF;
 END;
 UPDATE blueprint_cutover_manifest SET payload=jsonb_set(payload,'{plans,0,beforeRevision}','0');
 PERFORM assert_eq((SELECT layout FROM eshop.blueprints WHERE id=plan),legacy,'Rejected preparation leaves old source untouched');
 cutover:=pg_temp.apply_blueprint_layout_cutover();
 PERFORM assert_eq((cutover->>'plans')::int,1,'One-time cutover converts the stored plan');
 PERFORM assert_eq((SELECT layout FROM eshop.blueprints WHERE id=plan),canonical,'Source is stored canonically before copying');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 SET LOCAL ROLE authenticated;
 response:=public.start_occasion_lifecycle(NULL,NULL,source,'copy',command,NULL,'cs');
 copied:=(response#>>'{data,occasionId}')::bigint;
 PERFORM assert_eq(response->>'code','200','Public copy command succeeds');
 PERFORM assert_true(copied IS NOT NULL,'Copy has an identity');
 PERFORM assert_eq(public.start_occasion_lifecycle(NULL,NULL,source,'copy',command,NULL,'cs')#>>'{data,occasionId}',copied::text,'Lost response replay returns same copy');
 RESET ROLE;
 SELECT id INTO target_plan FROM eshop.blueprints WHERE occasion=copied;
 PERFORM assert_true(target_plan<>plan,'Copy has independent plan');
 PERFORM assert_eq((SELECT layout->>'schemaVersion' FROM eshop.blueprints WHERE id=target_plan),'2','Empty copy has canonical schema');
 PERFORM assert_eq((SELECT layout->'canvas' FROM eshop.blueprints WHERE id=target_plan),legacy->'canvas','Canvas retained');
 PERFORM assert_eq((SELECT blueprint FROM public.forms WHERE occasion=copied),target_plan,'Form binds copied plan');
 PERFORM assert_eq((SELECT layout FROM eshop.blueprints WHERE id=plan),canonical,'Copy leaves its canonical source unchanged');
 PERFORM assert_eq((SELECT title FROM public.occasions WHERE id=copied),'lol (kopie)','Copy title follows locale');
END $$;
