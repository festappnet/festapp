-- Drafts are private workspace objects, never public occasions.
CREATE TABLE IF NOT EXISTS public.occasion_setup_drafts (
  id uuid PRIMARY KEY,
  unit bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
  organization bigint NOT NULL REFERENCES public.organizations(id),
  author uuid NOT NULL REFERENCES auth.users(id),
  data jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(data) = 'object' AND octet_length(data::text) <= 262144),
  revision bigint NOT NULL DEFAULT 1,
  current_step integer NOT NULL DEFAULT 0 CHECK (current_step BETWEEN 0 AND 5),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.occasion_setup_drafts DROP CONSTRAINT IF EXISTS occasion_setup_drafts_current_step_check;
ALTER TABLE public.occasion_setup_drafts ADD CONSTRAINT occasion_setup_drafts_current_step_check CHECK (current_step BETWEEN 0 AND 5);
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

-- Client-generated UUID makes creating an empty draft safe to retry.
CREATE OR REPLACE FUNCTION public.create_occasion_setup_draft(p_id uuid, p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
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
  RETURN to_jsonb(d);
END $$;

CREATE OR REPLACE FUNCTION public.save_occasion_setup_draft(p_id uuid, p_expected_revision bigint, p_data jsonb, p_step integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  -- Retry a successfully committed identical save without changing its revision.
  IF d.revision = p_expected_revision + 1 AND d.data = p_data AND d.current_step = p_step THEN
    RETURN to_jsonb(d);
  END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001';
  END IF;
  IF p_data IS NULL OR jsonb_typeof(p_data) <> 'object' OR octet_length(p_data::text) > 262144 OR p_step IS NULL OR p_step NOT BETWEEN 0 AND 5 THEN
    RAISE EXCEPTION 'Invalid draft' USING ERRCODE = '22023';
  END IF;
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

-- Configuration only: no responses, orders, customers or reservation secrets.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_sources(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Source access denied' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'occasion', jsonb_build_object('id',o.id,'title',o.title,'link',o.link,
      'start_time',o.start_time,'end_time',o.end_time,'description',o.description,
      'data',o.data,'features',o.features,'is_open',false,'is_hidden',true),
    'forms', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'title',f.title,'link',f.link,'type',f.type,'data',f.data,'header',f.header,
      'header_off',f.header_off,'deadline_duration_seconds',f.deadline_duration_seconds,
      'is_open',false,'blueprint',f.blueprint,
      'fields',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'title',ff.title,'description',ff.description,'data',ff.data,'type',ff.type,
        'is_required',ff.is_required,'is_hidden',ff.is_hidden,'order',ff."order",
        'is_ticket_field',ff.is_ticket_field,
        'product_type_data',(SELECT jsonb_build_object('id',pt.id,'title',pt.title,
          'description',pt.description,'type',pt.type,'data',pt.data,
          'products',COALESCE((SELECT jsonb_agg(jsonb_build_object(
            'id',p.id,'title',p.title,'description',p.description,'price',p.price,
            'currency_code',p.currency_code,'maximum',p.maximum,'data',p.data,
            'is_hidden',p.is_hidden,'order',p."order") ORDER BY p."order",p.id)
            FROM eshop.products p WHERE p.product_type=pt.id),'[]'::jsonb))
          FROM eshop.product_types pt WHERE pt.id=ff.product_type)) ORDER BY ff."order",ff.id)
        FROM public.form_fields ff WHERE ff.form=f.id),'[]'::jsonb)) ORDER BY f.id)
      FROM public.forms f WHERE f.occasion=o.id),'[]'::jsonb),
    'blueprints',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',b.id,'title',b.title,'configuration',b.configuration,'groups',b.groups,
      'background_svg',b.background_svg,
      'objects',COALESCE((SELECT jsonb_agg((obj - 'state' - 'order_product_ticket' - 'secret') ||
        jsonb_build_object('state','available','product',s.product,'title',COALESCE(s.title,obj->>'title')))
        FROM jsonb_array_elements(COALESCE(b.objects,'[]'::jsonb)) obj
        LEFT JOIN eshop.spots s ON s.id=NULLIF(obj->>'id','')::bigint AND s.blueprint=b.id),'[]'::jsonb)) ORDER BY b.id)
      FROM eshop.blueprints b WHERE b.occasion=o.id),'[]'::jsonb),
    'program',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',e.title,
      'start_time',e.start_time,'end_time',e.end_time,'description',e.description))
      FROM public.events e WHERE e.occasion=o.id),'[]'::jsonb),
    'information',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',i.title,
      'description',i.description,'type',i.type,'data',i.data) ORDER BY i."order",i.id)
      FROM public.information i WHERE i.occasion=o.id),'[]'::jsonb)
    ) ORDER BY o.start_time DESC,o.id DESC) FROM public.occasions o WHERE o.unit=p_unit),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_sources(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_sources(bigint) TO authenticated;
