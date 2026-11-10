-- forms.blueprint is the sole saved association. Saving never publishes a
-- second resource: the form's existing schedule/open flag controls sales.
CREATE OR REPLACE FUNCTION public.sync_form_blueprint_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; bp bigint; candidates integer;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[f.occasion]);
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=f.occasion AND
   jsonb_path_exists(features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN RETURN; END IF;
 bp:=f.blueprint;
 IF NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=f.id AND type='spot' AND NOT is_hidden) THEN
   -- An explicitly disabled selector returns to ordinary product choices.
   IF NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=f.id AND type='spot' AND is_hidden) THEN RETURN; END IF;
   bp:=NULL;
 ELSE
 IF bp IS NULL THEN
   SELECT count(*),min(id) INTO candidates,bp FROM eshop.blueprints
   WHERE occasion=f.occasion AND layout->>'schemaVersion'='2';
   IF candidates=0 THEN RETURN; END IF;
   IF candidates<>1 THEN RAISE EXCEPTION 'BLUEPRINT_SELECTION_REQUIRED'; END IF;
 END IF;
 END IF;
 IF bp IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.blueprints b JOIN public.occasions o ON o.id=f.occasion
   WHERE b.id=bp AND b.occasion=f.occasion AND b.organization=o.organization AND b.layout->>'schemaVersion'='2') THEN
   RAISE EXCEPTION 'BLUEPRINT_LAYOUT_MIGRATION_REQUIRED'; END IF;
 IF f.blueprint IS DISTINCT FROM bp THEN
   PERFORM public.check_form_capacity_settings_internal(f.id,jsonb_build_object('blueprint',bp));
   UPDATE public.forms SET blueprint=bp,capacity_revision=capacity_revision+1,updated_at=clock_timestamp() WHERE id=f.id;
   INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
   VALUES('form','occasion',f.occasion,f.id::text,1)
   ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
   SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
   PERFORM public.notification_center_form_capacity_internal(f.id);
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.sync_form_blueprint_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
