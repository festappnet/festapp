-- test-setup: database/functions/occasion_setup/finalize.sql
-- Independent configuration sources require both source access and tenant match,
-- even when the corresponding form or blueprint is disabled in the draft.
DO $$
DECLARE
 actor uuid:=gen_random_uuid(); org bigint; foreign_org bigint;
 target_unit bigint; private_unit bigint; foreign_unit bigint;
 private_source bigint; foreign_source bigint; allowed_source bigint;
 draft_id uuid:=gen_random_uuid(); v_command_id uuid; source_key text; source_id bigint;
 payload jsonb; occasions_before bigint; expected_message text; actual_message text;
 actual_state text;
BEGIN
 INSERT INTO auth.users(id,email,aud,role)
 VALUES(actor,'independent-copy-'||actor||'@example.invalid','authenticated','authenticated');
 INSERT INTO public.organizations(title) VALUES('Independent source fixture') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Foreign source fixture') RETURNING id INTO foreign_org;
 INSERT INTO public.user_info(id,organization) VALUES(actor,org);
 INSERT INTO public.units(title,organization) VALUES('Copy destination',org) RETURNING id INTO target_unit;
 INSERT INTO public.units(title,organization) VALUES('Private same-tenant source',org) RETURNING id INTO private_unit;
 INSERT INTO public.units(title,organization) VALUES('Authorized foreign source',foreign_org) RETURNING id INTO foreign_unit;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor)
 VALUES(target_unit,actor,true,true),(foreign_unit,actor,true,true);
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,private_unit,'Unauthorized same-tenant source',gen_random_uuid()::text,now(),now()+interval '1 day')
 RETURNING id INTO private_source;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(foreign_org,foreign_unit,'Authorized foreign-tenant source',gen_random_uuid()::text,now(),now()+interval '1 day')
 RETURNING id INTO foreign_source;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,target_unit,'Authorized same-tenant source',gen_random_uuid()::text,now(),now()+interval '1 day')
 RETURNING id INTO allowed_source;
 INSERT INTO eshop.blueprints(occasion,organization,title,objects)
 SELECT id,organization,'Independent source fixture','[]'::jsonb FROM public.occasions
 WHERE id IN(private_source,foreign_source,allowed_source);
 INSERT INTO public.occasion_setup_drafts(id,unit,organization,author,data)
 VALUES(draft_id,target_unit,org,actor,'{}');
 SELECT count(*) INTO occasions_before FROM public.occasions;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 IF NOT public.can_create_occasion(target_unit)
    OR public.can_copy_occasion_source(private_source)
    OR NOT public.can_copy_occasion_source(foreign_source)
    OR NOT public.can_copy_occasion_source(allowed_source) THEN
  RAISE EXCEPTION 'Independent source fixture has incorrect access predicates';
 END IF;
 EXECUTE 'RESET ROLE';
 FOREACH source_key IN ARRAY ARRAY['formSourceOccasionId','blueprintSourceOccasionId','blueprintSourceId'] LOOP
  FOREACH source_id IN ARRAY ARRAY[private_source,foreign_source,allowed_source] LOOP
   v_command_id:=gen_random_uuid();
   -- Missing review deliberately stops an authorized control immediately after
   -- source checks, proving rejection happens before any materialization.
   payload:=jsonb_build_object('formEnabled',false,
     'blueprintMode',CASE WHEN source_key='blueprintSourceId' THEN 'copy' ELSE 'none' END,
     source_key,CASE WHEN source_key='blueprintSourceId' THEN
       (SELECT id FROM eshop.blueprints WHERE occasion=source_id LIMIT 1) ELSE source_id END);
   -- A client-provided allowed scope must not override the selected stored plan.
   IF source_key='blueprintSourceId' THEN
    payload:=payload||jsonb_build_object('blueprintSourceOccasionId',allowed_source);
   END IF;
   UPDATE public.occasion_setup_drafts SET data=payload WHERE id=draft_id;
   expected_message:=CASE WHEN source_id=allowed_source THEN 'Draft review required' ELSE 'Configuration source denied' END;
   EXECUTE 'SET LOCAL ROLE authenticated';
   BEGIN
    PERFORM public.finalize_occasion_setup_draft(draft_id,1,v_command_id);
    RAISE EXCEPTION 'Independent source check unexpectedly finalized a draft';
   EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN
    GET STACKED DIAGNOSTICS actual_message=MESSAGE_TEXT,actual_state=RETURNED_SQLSTATE;
    IF actual_message IS DISTINCT FROM expected_message
       OR actual_state IS DISTINCT FROM (CASE WHEN source_id=allowed_source THEN '22023' ELSE '42501' END) THEN
     RAISE EXCEPTION 'Unexpected % source % result: % (%)',source_key,source_id,actual_message,actual_state;
    END IF;
   END;
   EXECUTE 'RESET ROLE';
   IF EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=v_command_id) THEN
    RAISE EXCEPTION 'Source rejection retained a mutation receipt';
   END IF;
  END LOOP;
 END LOOP;
 IF (SELECT count(*) FROM public.occasions)<>occasions_before
    OR EXISTS(SELECT 1 FROM public.occasion_setup_drafts WHERE id=draft_id AND data ? 'finalizedOccasion') THEN
  RAISE EXCEPTION 'Source checks mutated the destination aggregate';
 END IF;
 RAISE NOTICE 'Independent form and blueprint sources enforce access and tenant boundaries before materialization';
END $$;
