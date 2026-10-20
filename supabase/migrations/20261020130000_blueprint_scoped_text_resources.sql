-- Prepared geometry belongs to an authorized editor scope. These rows are not
-- readable by clients; readers project only the descriptors needed by a layout.
CREATE TABLE IF NOT EXISTS public.blueprint_text_resources (
 scope_key text NOT NULL,
 occasion bigint REFERENCES public.occasions(id) ON DELETE CASCADE,
 setup_draft uuid REFERENCES public.occasion_setup_drafts(id) ON DELETE CASCADE,
 resource_id text NOT NULL,
 resource_kind text NOT NULL CHECK(resource_kind IN ('text','number')),
 payload jsonb NOT NULL CHECK(jsonb_typeof(payload)='object' AND octet_length(payload::text)<=8388608),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(scope_key,resource_id),
 CHECK((occasion IS NULL)<>(setup_draft IS NULL)),
 CHECK(scope_key=CASE WHEN occasion IS NOT NULL THEN 'occasion:'||occasion::text ELSE 'setup:'||setup_draft::text END)
);
ALTER TABLE public.blueprint_text_resources ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.blueprint_text_resources FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.register_blueprint_text_resources(p_occasion bigint,p_setup_draft uuid,p_resources jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE scope text; item record; old jsonb; kind text; collection text;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE insufficient_privilege USING MESSAGE='text service required'; END IF;
 IF (p_occasion IS NULL)=(p_setup_draft IS NULL) OR p_resources->>'protocol' IS DISTINCT FROM '2'
 OR jsonb_typeof(p_resources->'textLayouts') IS DISTINCT FROM 'object' OR jsonb_typeof(p_resources->'numberSymbols') IS DISTINCT FROM 'object'
 OR octet_length(p_resources::text)>16777216 THEN RAISE invalid_parameter_value USING MESSAGE='BLUEPRINT_INVALID_TEXT_RESOURCES'; END IF;
 scope:=CASE WHEN p_occasion IS NOT NULL THEN 'occasion:'||p_occasion::text ELSE 'setup:'||p_setup_draft::text END;
 PERFORM pg_advisory_xact_lock(hashtextextended('blueprint-text:'||scope,0));
 FOREACH collection IN ARRAY ARRAY['textLayouts','numberSymbols'] LOOP
  kind:=CASE collection WHEN 'textLayouts' THEN 'text' ELSE 'number' END;
  FOR item IN SELECT key,value FROM jsonb_each(p_resources->collection) LOOP
   IF jsonb_typeof(item.value) IS DISTINCT FROM 'object' OR item.value->>'id' IS NULL
    OR (kind='text' AND (item.key IS DISTINCT FROM item.value->>'id' OR item.key !~ '^layout-text:[a-f0-9]{64}$' OR item.value#>>'{descriptor,layoutResourceProtocol}' IS DISTINCT FROM '2'))
    OR (kind='number' AND (item.key IS DISTINCT FROM item.value->>'fontFaceId' OR item.value->>'id' !~ '^layout-number:[a-f0-9]{64}$'))
    THEN RAISE invalid_parameter_value USING MESSAGE='BLUEPRINT_INVALID_TEXT_RESOURCE'; END IF;
   SELECT payload INTO old FROM public.blueprint_text_resources WHERE scope_key=scope AND resource_id=item.value->>'id';
   IF FOUND THEN
    IF old IS DISTINCT FROM item.value THEN RAISE check_violation USING MESSAGE='BLUEPRINT_TEXT_RESOURCE_IMMUTABLE'; END IF;
   ELSE
    INSERT INTO public.blueprint_text_resources(scope_key,occasion,setup_draft,resource_id,resource_kind,payload)
     VALUES(scope,p_occasion,p_setup_draft,item.value->>'id',kind,item.value);
   END IF;
  END LOOP;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.register_blueprint_text_resources(bigint,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.register_blueprint_text_resources(bigint,uuid,jsonb) TO service_role;
