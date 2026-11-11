-- Forward cutover only. Preserve physical placements and commercial records.
-- Refuse contradictory source bindings instead of choosing another plan.
DO $$
DECLARE row record;
BEGIN
 IF to_regclass('public.form_seating_transitions') IS NOT NULL THEN
   LOCK TABLE public.form_seating_transitions IN EXCLUSIVE MODE;
   IF EXISTS(SELECT form FROM public.form_seating_transitions WHERE state<>'cancelled' AND form IS NOT NULL
     GROUP BY form HAVING count(DISTINCT blueprint)>1) THEN RAISE EXCEPTION 'SEATING_BINDING_AMBIGUOUS'; END IF;
   FOR row IN SELECT DISTINCT t.form,t.blueprint,f.occasion FROM public.form_seating_transitions t
     JOIN public.forms f ON f.id=t.form WHERE t.state<>'cancelled' AND t.blueprint IS NOT NULL ORDER BY t.form LOOP
     IF NOT EXISTS(SELECT 1 FROM eshop.blueprints b JOIN public.occasions o ON o.id=row.occasion
       WHERE b.id=row.blueprint AND b.occasion=o.id AND b.organization=o.organization AND b.layout->>'schemaVersion'='2') THEN
       RAISE EXCEPTION 'SEATING_BINDING_INVALID'; END IF;
     IF EXISTS(SELECT 1 FROM public.forms WHERE id=row.form AND blueprint IS NOT NULL AND blueprint<>row.blueprint) THEN
       RAISE EXCEPTION 'SEATING_BINDING_AMBIGUOUS'; END IF;
     IF EXISTS(SELECT 1 FROM public.occasions WHERE id=row.occasion AND jsonb_path_exists(features,
       '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN
       IF EXISTS(SELECT 1 FROM public.form_fields WHERE form=row.form AND type='spot' AND NOT is_hidden) THEN
         PERFORM public.lock_blueprint_scope_internal(ARRAY[row.occasion]);
         PERFORM public.check_form_capacity_settings_internal(row.form,jsonb_build_object('blueprint',row.blueprint));
         UPDATE public.forms SET blueprint=row.blueprint,capacity_revision=capacity_revision+1,updated_at=clock_timestamp()
         WHERE id=row.form;
         INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
         VALUES('form','occasion',row.occasion,row.form::text,1)
         ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
         SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
         PERFORM public.notification_center_form_capacity_internal(row.form);
       END IF;
     END IF;
     IF NOT EXISTS(SELECT 1 FROM public.blueprint_seating_sources_internal(row.blueprint) WHERE form_id=row.form) THEN
       RAISE EXCEPTION 'SEATING_SOURCE_AMBIGUOUS'; END IF;
   END LOOP;
 END IF;
 -- Also repair the same missing association where no transition was created.
 PERFORM public.sync_form_blueprint_internal(id) FROM public.forms f WHERE f.blueprint IS NULL AND
   EXISTS(SELECT 1 FROM public.form_fields WHERE form=f.id AND type='spot' AND NOT is_hidden) ORDER BY id;
END $$;

DROP FUNCTION IF EXISTS public.publish_seating_transitions(uuid,uuid[],text,uuid);
DROP FUNCTION IF EXISTS public.preview_seating_publication(uuid);
DROP FUNCTION IF EXISTS public.seating_publication_preview_internal(uuid);
DROP FUNCTION IF EXISTS public.start_seating_configuration(bigint,bigint,uuid);
DROP FUNCTION IF EXISTS public.cancel_seating_configuration(uuid,bigint,uuid);
DROP FUNCTION IF EXISTS public.start_seating_configuration_internal(bigint,bigint);
DROP FUNCTION IF EXISTS public.set_ticket_seat_assignments(uuid,jsonb,text,uuid);
DROP FUNCTION IF EXISTS public.preview_ticket_seat_assignment(uuid,jsonb);
DROP FUNCTION IF EXISTS public.seating_assignment_preview_internal(uuid,jsonb);
DROP FUNCTION IF EXISTS public.seating_assignment_scope_internal(uuid,jsonb);
DROP FUNCTION IF EXISTS public.get_seating_transition_context(uuid,text,text,bigint,integer);
DROP FUNCTION IF EXISTS public.seating_admissions_internal(uuid);
DROP FUNCTION IF EXISTS public.assert_published_admission_seating_internal(bigint,bigint,bigint);
DELETE FROM public.client_sync_component_sources WHERE registry_version=1 AND source_relation=to_regclass('public.form_seating_transitions');
DROP TABLE IF EXISTS public.form_seating_transitions;
UPDATE public.client_sync_component_sources SET canonical_writers=ARRAY(SELECT writer FROM unnest(canonical_writers) writer
 WHERE writer NOT IN ('start_seating_configuration','cancel_seating_configuration','publish_seating_transitions')) WHERE registry_version=1;
