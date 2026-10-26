-- Callers hold the activation gate before the domain form lock, then source state.
CREATE OR REPLACE FUNCTION public.notification_center_form_availability_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp(),p_actor uuid DEFAULT auth.uid(),p_baseline boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; org bigint; old public.notification_center_source_state; current_config jsonb;
 previous jsonb; evaluated jsonb; boundary record; serial bigint; reason text;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form;
 SELECT organization INTO org FROM public.occasions WHERE id=f.occasion;
 IF org IS NULL OR NOT public.notification_center_initialized_internal(org) THEN RETURN; END IF;
 PERFORM 1 FROM public.forms WHERE id=p_form FOR UPDATE;
 SELECT * INTO old FROM public.notification_center_source_state WHERE organization=org AND source_key='form-availability:'||p_form FOR UPDATE;
 IF FOUND THEN p_at:=greatest(p_at,old.observed_at); END IF;
 current_config:=public.get_form_availability_snapshot_internal(p_form,p_at)||jsonb_build_object('title',f.title,'formId',f.id);
 IF old.state->>'createdXid'=pg_current_xact_id()::text THEN
  p_baseline:=true;
  current_config:=current_config||jsonb_build_object('createdXid',pg_current_xact_id()::text);
 END IF;
 IF old.source_key IS NULL OR p_baseline THEN
  INSERT INTO public.notification_center_source_state(organization,source_key,state,next_evaluation_at,observed_at)
  VALUES(org,'form-availability:'||p_form,current_config,(current_config->>'nextEvaluationAt')::timestamptz,p_at)
  ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,next_evaluation_at=excluded.next_evaluation_at,observed_at=excluded.observed_at;
  RETURN;
 END IF;
 previous:=old.state; serial:=old.episode;
 -- Replay the OLD configuration before comparing a newly saved configuration.
 FOR boundary IN SELECT t,occurred,why FROM (VALUES
  ((previous->>'startAt')::timestamptz,(previous->>'startAt')::timestamptz,'schedule_start'),
  ((previous->>'endAt')::timestamptz+interval '1 microsecond',(previous->>'endAt')::timestamptz,'schedule_end')) b(t,occurred,why)
  WHERE t>old.observed_at AND t<=p_at ORDER BY t LOOP
  evaluated:=public.get_form_availability_from_config_internal(previous,boundary.t);
  IF (previous->>'isWindowOpen')::boolean IS DISTINCT FROM (evaluated->>'isWindowOpen')::boolean THEN
   serial:=serial+1;
   PERFORM public.notification_center_publish_internal(org,f.occasion,CASE WHEN (evaluated->>'isWindowOpen')::boolean THEN 'form_opened' ELSE 'form_closed' END,
    'form-availability:'||p_form||':transition:'||serial,
    jsonb_build_object('formId',f.id,'title',previous->>'title','from',previous->>'gate','to',evaluated->>'gate','reason',boundary.why,
     'effectiveAt',boundary.occurred,'registrationMode',public.get_form_registration_mode_internal(f.id,boundary.t)),NULL,boundary.occurred);
  END IF;
  previous:=evaluated;
 END LOOP;
 evaluated:=public.get_form_availability_from_config_internal(previous,p_at);
 IF (evaluated->>'isWindowOpen')::boolean IS DISTINCT FROM (current_config->>'isWindowOpen')::boolean THEN
  serial:=serial+1;
  reason:=CASE WHEN evaluated->'manualOpen' IS DISTINCT FROM current_config->'manualOpen' THEN 'manual' ELSE 'schedule_changed' END;
  PERFORM public.notification_center_publish_internal(org,f.occasion,CASE WHEN (current_config->>'isWindowOpen')::boolean THEN 'form_opened' ELSE 'form_closed' END,
   'form-availability:'||p_form||':transition:'||serial,
   jsonb_build_object('formId',f.id,'title',f.title,'from',evaluated->>'gate','to',current_config->>'gate','reason',reason,
    'effectiveAt',p_at,'registrationMode',public.get_form_registration_mode_internal(f.id,p_at)),p_actor,p_at);
 END IF;
 UPDATE public.notification_center_source_state SET state=current_config,episode=serial,observed_at=p_at,
 next_evaluation_at=(current_config->>'nextEvaluationAt')::timestamptz WHERE organization=org AND source_key='form-availability:'||p_form;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_evaluate_forms_internal(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE candidate record; n integer:=0; at_time timestamptz:=clock_timestamp(); after_id bigint; last_id bigint;
BEGIN
 INSERT INTO public.notification_center_maintenance(name) VALUES('form-availability') ON CONFLICT DO NOTHING;
 SELECT cursor INTO after_id FROM public.notification_center_maintenance WHERE name='form-availability' FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN RETURN 0; END IF;
 -- Never lock a source before its form. Busy forms remain due for the next tick.
 FOR candidate IN SELECT s.organization,(s.state->>'formId')::bigint form_id FROM public.notification_center_source_state s
 JOIN public.notification_center_organizations a ON a.organization=s.organization
 WHERE s.next_evaluation_at<=at_time ORDER BY ((s.state->>'formId')::bigint>after_id) DESC,(s.state->>'formId')::bigint LIMIT greatest(1,least(p_limit,500)) LOOP
  last_id:=candidate.form_id;
  IF NOT pg_try_advisory_xact_lock_shared(hashtextextended('notification-center-organization:'||candidate.organization,0)) THEN CONTINUE; END IF;
  PERFORM 1 FROM public.forms WHERE id=candidate.form_id FOR UPDATE SKIP LOCKED;
  IF FOUND THEN
   PERFORM public.notification_center_form_availability_internal(candidate.form_id,at_time,NULL); n:=n+1;
  ELSIF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=candidate.form_id) THEN
   DELETE FROM public.notification_center_source_state WHERE organization=candidate.organization AND source_key='form-availability:'||candidate.form_id;
  END IF;
 END LOOP;
 UPDATE public.notification_center_maintenance SET cursor=coalesce(last_id,0) WHERE name='form-availability';
 RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_form_availability_internal(bigint,timestamptz,uuid,boolean),
 public.notification_center_evaluate_forms_internal(integer) FROM PUBLIC,anon,authenticated,service_role;

-- Wizard/create/copy commands may save the new form again in the same transaction.
-- That authoring is still creation, not an existing form opening for recipients.
CREATE OR REPLACE FUNCTION public.notification_center_form_created_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_form_availability_internal(p_form,clock_timestamp(),auth.uid(),true);
 UPDATE public.notification_center_source_state SET state=state||jsonb_build_object('createdXid',pg_current_xact_id()::text)
 WHERE source_key='form-availability:'||p_form AND organization=(SELECT oc.organization FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE f.id=p_form);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_form_created_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
