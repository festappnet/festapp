-- Fresh tenant; real authenticated draft/finalizer calls; runner rolls all rows back.
-- Assertions stay in this block so revoked shared test-helper grants are irrelevant.
DO $$
DECLARE
 actor uuid := gen_random_uuid(); org bigint; unit_id bigint; foreign_org bigint;
 foreign_unit bigint; restricted_unit bigint; foreign_source bigint; restricted_source bigint;
 draft_id uuid; draft jsonb; payload jsonb; response jsonb; event_id bigint;
 mode text; tone text; form_row public.forms%ROWTYPE; source_key text; denied_source bigint;
 sale_start timestamptz := now()+interval '1 day';
 sale_end timestamptz := now()+interval '10 days';
BEGIN
 INSERT INTO auth.users(id,email,aud,role,created_at)
 VALUES(actor,'ux-flow-'||actor||'@example.invalid','authenticated','authenticated',now());
 INSERT INTO public.organizations(title) VALUES('UX flow tenant') RETURNING id INTO org;
 INSERT INTO public.user_info(id,organization) VALUES(actor,org);
 INSERT INTO public.units(title,organization) VALUES('UX flow unit',org) RETURNING id INTO unit_id;
 INSERT INTO public.unit_users("user",unit,is_editor,is_manager) VALUES(actor,unit_id,true,true);
 INSERT INTO public.units(title,organization) VALUES('Restricted source unit',org) RETURNING id INTO restricted_unit;
 INSERT INTO public.organizations(title) VALUES('Foreign UX flow tenant') RETURNING id INTO foreign_org;
 INSERT INTO public.units(title,organization) VALUES('Foreign source unit',foreign_org) RETURNING id INTO foreign_unit;
 -- Even a manager of the foreign source cannot import it across tenant boundaries.
 INSERT INTO public.unit_users("user",unit,is_editor,is_manager) VALUES(actor,foreign_unit,true,true);
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(foreign_org,foreign_unit,'Foreign source','ux-foreign-'||actor,now(),now()+interval '1 day')
 RETURNING id INTO foreign_source;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,restricted_unit,'Restricted source','ux-restricted-'||actor,now(),now()+interval '1 day')
 RETURNING id INTO restricted_source;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);

 FOREACH mode IN ARRAY ARRAY['scheduled','immediate','preparation'] LOOP
  tone:=CASE mode WHEN 'scheduled' THEN 'formal' WHEN 'immediate' THEN 'informal' ELSE 'inherit' END;
  draft_id:=gen_random_uuid();
  payload:=jsonb_build_object('title','UX sale '||mode,'link','ux-'||draft_id,
    'start',now()+interval '20 days','end',now()+interval '21 days',
    'reviewConfirmed',true,'formEnabled',true,'blueprintMode','none',
    'saleMode',mode,'saleStart',sale_start,'saleEnd',sale_end,
    'replyTo','organizer@example.invalid','communicationTone',tone,
    'formDraft',jsonb_build_object('title','UX registration','link','',
      'fields','[]'::jsonb,'deadline_duration_seconds',0,
      'data',jsonb_build_object('is_reminder_enabled',false,'reminder_interval_seconds',86400,
        -- A copied form's old schedule and tone must not override the new choice.
        'communication_tone','informal',
        'schedule',jsonb_build_object('start_time',now()-interval '2 days','end_time',now()-interval '1 day'))));
  EXECUTE 'SET LOCAL ROLE authenticated';
  draft:=public.create_occasion_setup_draft(draft_id,unit_id);
  draft:=public.save_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,payload,5);
  response:=public.finalize_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,gen_random_uuid());
  EXECUTE 'RESET ROLE';
  event_id:=(response#>>'{data,occasionId}')::bigint;
  IF event_id IS NULL THEN RAISE EXCEPTION 'Missing finalized event for %: %',mode,response; END IF;
  IF (SELECT data->>'reply_to' FROM public.occasions WHERE id=event_id) IS DISTINCT FROM 'organizer@example.invalid' THEN
   RAISE EXCEPTION 'Reply-To was not saved on occasion for %',mode; END IF;
  SELECT * INTO STRICT form_row FROM public.forms WHERE occasion=event_id;
  IF form_row.deadline_duration_seconds IS DISTINCT FROM 0 OR
     form_row.data->'is_reminder_enabled' IS DISTINCT FROM 'false'::jsonb OR
     form_row.data->'reminder_interval_seconds' IS DISTINCT FROM '86400'::jsonb THEN
   RAISE EXCEPTION 'Zero deadline or explicit reminder settings lost for %',mode; END IF;
  IF tone='inherit' THEN
   IF form_row.data ? 'communication_tone' THEN RAISE EXCEPTION 'Inherited tone must not freeze copied tone'; END IF;
  ELSIF form_row.data->>'communication_tone' IS DISTINCT FROM tone THEN
   RAISE EXCEPTION 'Explicit tone % was not saved: %',tone,form_row.data; END IF;
  IF mode='preparation' THEN
   IF form_row.is_open IS DISTINCT FROM false OR
      form_row.data#>'{schedule,sale_preparation}' IS DISTINCT FROM 'true'::jsonb OR
      form_row.data#>'{schedule,start_time}' IS NOT NULL OR
      form_row.data#>'{schedule,end_time}' IS NOT NULL THEN
    RAISE EXCEPTION 'Preparation must close form and remove copied sale times'; END IF;
  ELSE
   IF form_row.is_open IS DISTINCT FROM true OR
      (form_row.data#>>'{schedule,end_time}')::timestamptz IS DISTINCT FROM sale_end THEN
    RAISE EXCEPTION 'Open sale or end time lost for %: %',mode,form_row.data; END IF;
   IF mode='scheduled' AND (form_row.data#>>'{schedule,start_time}')::timestamptz IS DISTINCT FROM sale_start THEN
    RAISE EXCEPTION 'Scheduled start time was not persisted'; END IF;
   IF mode='immediate' AND ((form_row.data#>>'{schedule,start_time}')::timestamptz IS NULL OR
      (form_row.data#>>'{schedule,start_time}')::timestamptz > now()) THEN
    RAISE EXCEPTION 'Immediate sale must start now'; END IF;
  END IF;
 END LOOP;

 -- Independent form/plan source metadata must enforce both permission and tenant.
 FOREACH source_key IN ARRAY ARRAY['formSourceOccasionId','blueprintSourceOccasionId'] LOOP
  FOREACH denied_source IN ARRAY ARRAY[restricted_source,foreign_source] LOOP
   draft_id:=gen_random_uuid();
   payload:=(payload-'formSourceOccasionId'-'blueprintSourceOccasionId') ||
     jsonb_build_object('link','ux-denied-'||draft_id,source_key,denied_source);
   EXECUTE 'SET LOCAL ROLE authenticated';
   draft:=public.create_occasion_setup_draft(draft_id,unit_id);
   draft:=public.save_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,payload,5);
   BEGIN
    PERFORM public.finalize_occasion_setup_draft(draft_id,(draft->>'revision')::bigint,gen_random_uuid());
    RAISE EXCEPTION 'Unauthorized independent % source % accepted',source_key,denied_source;
   EXCEPTION WHEN insufficient_privilege THEN
    IF SQLERRM<>'Configuration source denied' THEN RAISE; END IF;
   END;
   EXECUTE 'RESET ROLE';
   IF EXISTS(SELECT 1 FROM public.occasions WHERE link=payload->>'link') OR
      EXISTS(SELECT 1 FROM public.occasion_setup_drafts WHERE id=draft_id AND data ? 'finalizedOccasion') THEN
    RAISE EXCEPTION 'Denied source created an event or finalized the draft'; END IF;
  END LOOP;
 END LOOP;
 RAISE NOTICE 'UX finalizer schedule, communication, reminder and independent-source regressions passed';
END $$;
