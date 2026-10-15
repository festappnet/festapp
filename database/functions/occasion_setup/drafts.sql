-- Drafts are private workspace objects, never public occasions.
CREATE TABLE IF NOT EXISTS public.occasion_setup_drafts (
  id uuid PRIMARY KEY,
  unit bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
  organization bigint NOT NULL REFERENCES public.organizations(id),
  author uuid NOT NULL REFERENCES auth.users(id),
  data jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(data) = 'object' AND octet_length(data::text) <= 262144),
  revision bigint NOT NULL DEFAULT 1,
  current_step integer NOT NULL DEFAULT 0 CHECK (current_step BETWEEN 0 AND 6),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.occasion_setup_drafts DROP CONSTRAINT IF EXISTS occasion_setup_drafts_current_step_check;
ALTER TABLE public.occasion_setup_drafts ADD CONSTRAINT occasion_setup_drafts_current_step_check CHECK (current_step BETWEEN 0 AND 6);
CREATE INDEX IF NOT EXISTS occasion_setup_drafts_unit_idx ON public.occasion_setup_drafts(unit);
ALTER TABLE public.occasion_setup_drafts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.occasion_setup_drafts FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_drafts(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY updated_at DESC)
    FROM public.occasion_setup_drafts d WHERE unit = p_unit), '[]'::jsonb);
END $$;

-- Run the canonical creator inside a rollback-only subtransaction. Its
-- complete configuration survives in a PL/pgSQL variable, but no occasion,
-- form, product, reminders or other rows escape into the normal application.
-- PostgreSQL sequences may advance; those IDs are draft-local references.
CREATE OR REPLACE FUNCTION public.build_occasion_setup_configuration(p_unit bigint, p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE configuration jsonb; organization_id bigint;
  provisional_link text := 'draft-' || p_id::text;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  SELECT organization INTO organization_id FROM public.units WHERE id = p_unit;
  BEGIN
    PERFORM public.update_occasion_internal_v1(jsonb_build_object(
      'unit',p_unit,'organization',organization_id,'title','',
      'link',provisional_link,'is_hidden',true,'is_open',false,
      'start_time',now()+interval '30 days','end_time',now()+interval '33 days'));
    SELECT item INTO configuration
      FROM jsonb_array_elements(public.get_occasion_setup_sources(p_unit)) item
      WHERE item->'occasion'->>'link' = provisional_link;
    IF configuration IS NULL THEN RAISE EXCEPTION 'Creation configuration missing'; END IF;
    RAISE EXCEPTION 'Rollback provisional creation' USING ERRCODE = 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN
    -- Variables retain their values while all writes in the block roll back.
    NULL;
  END;
  configuration := jsonb_set(configuration,'{occasion,link}','""'::jsonb);
  configuration := jsonb_set(configuration,'{forms}',coalesce((SELECT jsonb_agg(jsonb_set(f,'{link}','""'::jsonb))
    FROM jsonb_array_elements(configuration->'forms') f),'[]'::jsonb));
  RETURN configuration;
END $$;
REVOKE ALL ON FUNCTION public.build_occasion_setup_configuration(bigint,uuid) FROM PUBLIC,anon,authenticated;

-- Client-generated UUID makes canonical draft initialization safe to retry.
CREATE OR REPLACE FUNCTION public.create_occasion_setup_draft(p_id uuid, p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts; configuration jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.occasion_setup_drafts(id,unit,organization,author)
    SELECT p_id,id,organization,auth.uid() FROM public.units WHERE id = p_unit
    ON CONFLICT (id) DO NOTHING;
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id;
  IF d.unit IS DISTINCT FROM p_unit OR d.author IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF NOT (d.data ? 'defaultConfiguration') THEN
    configuration := public.build_occasion_setup_configuration(p_unit,p_id);
    UPDATE public.occasion_setup_drafts SET data =
      jsonb_build_object('defaultConfiguration',configuration,
        'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true)
      || d.data WHERE id = p_id RETURNING * INTO d;
  END IF;
  RETURN to_jsonb(d);
END $$;

CREATE OR REPLACE FUNCTION public.initialize_occasion_setup_draft_defaults(p_id uuid, p_expected_revision bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts; configuration jsonb;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF d.data ? 'defaultConfiguration' THEN RETURN to_jsonb(d); END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001';
  END IF;
  configuration := public.build_occasion_setup_configuration(d.unit,p_id);
  UPDATE public.occasion_setup_drafts SET data =
    jsonb_build_object('defaultConfiguration',configuration,
      'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true)
    || d.data, revision = revision+1, updated_at=now()
    WHERE id=p_id RETURNING * INTO d;
  RETURN to_jsonb(d);
END $$;
REVOKE ALL ON FUNCTION public.initialize_occasion_setup_draft_defaults(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.initialize_occasion_setup_draft_defaults(uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_occasion_setup_draft(p_id uuid, p_expected_revision bigint, p_data jsonb, p_step integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
  p_data := p_data - 'finalizedOccasion' - 'finalizeResponse';
  IF p_data IS NULL OR jsonb_typeof(p_data) <> 'object' OR octet_length(p_data::text) > 262144 OR p_step IS NULL OR p_step NOT BETWEEN 0 AND 6 THEN
    RAISE EXCEPTION 'Invalid draft' USING ERRCODE = '22023'; END IF;
  IF d.data ? 'copy_locale' THEN p_data := jsonb_set(p_data,'{copy_locale}',d.data->'copy_locale'); END IF;
  IF p_data ? 'copy_locale' AND p_data->>'sourceId' IS NOT NULL
     AND coalesce((p_data->>'copy_title_edited')::boolean,false)=false AND coalesce(p_data->>'title','')='' THEN
    IF NOT public.can_copy_occasion_source((p_data->>'sourceId')::bigint) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=(p_data->>'sourceId')::bigint AND organization=d.organization) THEN
      RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
    IF d.revision=p_expected_revision+1 AND d.data->>'sourceId'=p_data->>'sourceId' THEN
      p_data := jsonb_set(p_data,'{title}',d.data->'title');
    ELSE
      p_data := jsonb_set(p_data,'{title}',to_jsonb(public.copy_occasion_title_internal(
        (SELECT title FROM public.occasions WHERE id=(p_data->>'sourceId')::bigint),p_data->>'copy_locale')));
    END IF;
  END IF;
  IF d.revision = p_expected_revision + 1 AND d.data = p_data AND d.current_step = p_step THEN RETURN to_jsonb(d); END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001'; END IF;
  UPDATE public.occasion_setup_drafts SET data = p_data, current_step = p_step,
    revision = revision + 1, updated_at = now() WHERE id = p_id RETURNING * INTO d;
  RETURN to_jsonb(d);
END $$;

CREATE OR REPLACE FUNCTION public.delete_occasion_setup_draft(p_id uuid, p_unit bigint, p_expected_revision bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF d.unit <> p_unit THEN RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501'; END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001';
  END IF;
  DELETE FROM public.occasion_setup_drafts WHERE id = p_id;
END $$;

REVOKE ALL ON FUNCTION public.get_occasion_setup_drafts(bigint), public.create_occasion_setup_draft(uuid,bigint),
  public.save_occasion_setup_draft(uuid,bigint,jsonb,integer), public.delete_occasion_setup_draft(uuid,bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_drafts(bigint), public.create_occasion_setup_draft(uuid,bigint),
  public.save_occasion_setup_draft(uuid,bigint,jsonb,integer), public.delete_occasion_setup_draft(uuid,bigint,bigint) TO authenticated;
