-- Deterministic projection on the existing finalizer's authorized draft.
CREATE OR REPLACE FUNCTION public.normalize_occasion_setup_type_internal(p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE payload jsonb:=p_data; event_kind text; appearance jsonb; shared_font text;
BEGIN
 event_kind:=payload->>'eventKind';
 IF event_kind IS NOT NULL AND (event_kind NOT IN ('regular','concert','ball') OR coalesce((payload->>'eventKindNeedsConfirmation')::boolean,false)) THEN
  RAISE invalid_parameter_value USING MESSAGE='Confirm event kind'; END IF;
 IF event_kind IS NOT NULL THEN
  payload:=jsonb_set(payload,'{formEnabled}','true');
  IF event_kind<>'ball' THEN payload:=payload || '{"blueprintMode":"none"}'; END IF;
  IF event_kind='regular' THEN payload:=payload-'ticketDraft'; END IF;
  IF event_kind<>'ball' AND jsonb_typeof(payload#>'{formDraft,fields}')='array' THEN
   payload:=jsonb_set(payload,'{formDraft,fields}',coalesce((SELECT jsonb_agg(field) FROM jsonb_array_elements(payload#>'{formDraft,fields}') field WHERE field->>'type' IS DISTINCT FROM 'spot' AND (event_kind<>'regular' OR field->>'type' IS DISTINCT FROM 'ticket')),'[]'::jsonb));
  END IF;
 END IF;
 IF event_kind IS NOT NULL AND (jsonb_typeof(payload->'formDraft') IS DISTINCT FROM 'object' OR jsonb_typeof(payload->'appearance') IS DISTINCT FROM 'object') THEN
  RAISE invalid_parameter_value USING MESSAGE='Active form and appearance required'; END IF;
 IF event_kind IN ('concert','ball') AND jsonb_typeof(payload->'ticketDraft') IS DISTINCT FROM 'object' THEN
  RAISE invalid_parameter_value USING MESSAGE='Active ticket configuration required'; END IF;
 appearance:=payload->'appearance';
 IF appearance IS NOT NULL THEN
  IF jsonb_typeof(appearance)<>'object' OR coalesce(appearance->>'primary','') !~ '^[A-Fa-f0-9]{6}$' OR coalesce(appearance->>'secondary','') !~ '^[A-Fa-f0-9]{6}$'
    OR jsonb_typeof(appearance->'gradient') IS DISTINCT FROM 'boolean' THEN RAISE invalid_parameter_value USING MESSAGE='Invalid shared appearance'; END IF;
  shared_font:=CASE appearance->>'fontFamily'
    WHEN 'Roboto' THEN 'builtin:roboto-unpacked:24438383f80387edbbd3a199d7b257258db7003f5b291a7d3fb6fa89483ae57f'
    WHEN 'Roboto Slab' THEN 'builtin:roboto-slab-static:b93b5ad2eada842f450bff812f180ac517c82916c9d0dda446322e8d275b4f09'
    WHEN 'Russo One' THEN 'builtin:russo-one-unpacked:54b087e1ffbcfe8837d59e8cbda823e5690cbb8101afe23b31f3a6c70b6dad6b' END;
  IF shared_font IS NULL AND coalesce((appearance->>'preserveSource')::boolean,false)=false THEN RAISE invalid_parameter_value USING MESSAGE='Unsupported shared font'; END IF;
  IF coalesce((appearance->>'preserveSource')::boolean,false)=false THEN
   IF replace(payload#>>'{formDraft,data,design,primary_color}','#','') IS DISTINCT FROM appearance->>'primary'
    OR replace(payload#>>'{formDraft,data,design,secondary_color}','#','') IS DISTINCT FROM appearance->>'secondary'
    OR payload#>>'{formDraft,data,design,font_family}' IS DISTINCT FROM appearance->>'fontFamily'
    OR payload#>>'{formDraft,data,design,background_mode}' IS DISTINCT FROM (CASE WHEN (appearance->>'gradient')::boolean THEN 'gradient' ELSE 'solid' END)
    THEN RAISE invalid_parameter_value USING MESSAGE='Shared form style mismatch'; END IF;
   IF event_kind IN ('concert','ball') AND (payload#>'{ticketDraft,layout,templates}' IS NULL OR EXISTS(
    SELECT 1 FROM jsonb_each(payload#>'{ticketDraft,layout,templates}') t
    WHERE t.value->>'fontId' IS DISTINCT FROM shared_font OR t.value->>'canvasColor' IS DISTINCT FROM appearance->>'primary'
     OR (CASE WHEN (appearance->>'gradient')::boolean THEN t.value->'canvasGradient' IS DISTINCT FROM jsonb_build_array(appearance->>'primary',appearance->>'secondary') ELSE t.value ? 'canvasGradient' END)))
    THEN RAISE invalid_parameter_value USING MESSAGE='Shared ticket style mismatch'; END IF;
  END IF;
  -- A custom copied layout retains its detailed style until the user chooses
  -- a shared style. New shared styles are materialized by the one draft mapper.
  IF appearance->>'id'<>'custom' AND payload#>>'{formDraft,data,design,font_family}' IS DISTINCT FROM appearance->>'fontFamily' THEN
    RAISE invalid_parameter_value USING MESSAGE='Form appearance mismatch'; END IF;
 END IF;


 IF event_kind IS NOT NULL THEN payload:=jsonb_set(payload,'{formDraft,title}',payload->'title'); END IF;
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.normalize_occasion_setup_type_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;
