-- Temporary maintenance only: registered synthetic fixtures in an explicit tenant.
-- layouts.sql must be loaded first. Product references are resolved per occasion.
CREATE OR REPLACE FUNCTION pg_temp.refresh_demo_artwork(p_org bigint)
RETURNS void LANGUAGE plpgsql AS $artwork$
DECLARE d record; current_data jsonb; current_features jsonb; next_data jsonb;
 next_features jsonb; layout jsonb; admission_type bigint; cover text; background text;
 base text := 'https://img.festapp.net/images/demo-occasions/20261014/';
 asset text;
BEGIN
 IF current_user <> 'postgres' THEN RAISE insufficient_privilege; END IF;
 PERFORM pg_advisory_xact_lock(7141014,p_org::integer);
 IF (SELECT count(*) FROM public.demo_occasions WHERE organization=p_org AND fixture_version='2026-10-14.3') <> 3 THEN
  RAISE EXCEPTION 'Expected three registered demo fixtures';
 END IF;
 FOR d IN SELECT * FROM public.demo_occasions
  WHERE organization=p_org AND fixture_version='2026-10-14.3' ORDER BY sort_order LOOP
  SELECT data,features INTO STRICT current_data,current_features FROM public.occasions
   WHERE id=d.occasion AND organization=p_org FOR UPDATE;
  cover:=base||d.demo_key||'-cover-v1.jpg';
  next_data:=jsonb_set(coalesce(current_data,'{}'),'{image}',to_jsonb(cover));
  next_features:=current_features;
  IF d.demo_key IN ('ball','concert') THEN
   SELECT content INTO STRICT layout FROM pg_temp.demo_ticket_layouts WHERE demo_key=d.demo_key;
   SELECT id INTO STRICT admission_type FROM eshop.product_types WHERE occasion=d.occasion AND type='spot';
   SELECT jsonb_set(layout,'{templates,wide,elements}',jsonb_agg(
    CASE WHEN e->>'binding'='productType' THEN jsonb_set(e,'{productTypeId}',to_jsonb(admission_type)) ELSE e END ORDER BY n))
    INTO layout FROM jsonb_array_elements(layout#>'{templates,wide,elements}') WITH ORDINALITY a(e,n);
   PERFORM public.validate_ticket_layout_references(d.occasion,layout);
   background:=base||d.demo_key||'-ticket-v1.jpg';
   SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' THEN f||jsonb_build_object(
    'is_enabled',true,'ticket_type','wide','background',background,'layout',layout) ELSE f END ORDER BY n)
    INTO next_features FROM jsonb_array_elements(current_features) WITH ORDINALITY a(f,n);
  ELSE
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(current_features) f WHERE f->>'code'='ticket' AND (f->>'is_enabled')::boolean) THEN
    RAISE EXCEPTION 'Weekend must not issue admission tickets';
   END IF;
  END IF;
  -- Register every referenced image so the ordinary media picker/copier owns it.
  FOR asset IN SELECT cover UNION SELECT background WHERE d.demo_key IN ('ball','concert') LOOP
   INSERT INTO public.images(link,occasion) SELECT asset,d.occasion
    WHERE NOT EXISTS(SELECT 1 FROM public.images WHERE occasion=d.occasion AND link=asset);
  END LOOP;
  IF next_data IS DISTINCT FROM current_data OR next_features IS DISTINCT FROM current_features THEN
   UPDATE public.occasions SET data=next_data,features=next_features,updated_at=now() WHERE id=d.occasion AND organization=p_org;
   PERFORM public.record_client_sync_commit_v1(d.occasion,'demo.artwork','configuration',
    jsonb_build_array(jsonb_build_object('entityType','occasion','entityId',d.occasion::text,
     'operation','update','safeLabel',d.demo_key,'changedFields',jsonb_build_array('data.image','features.ticket'))),
    ARRAY['occasion_config'],'[]'::jsonb,'[]'::jsonb,'system','Refresh registered demo artwork and editable ticket layout');
  END IF;
 END LOOP;
END $artwork$;
