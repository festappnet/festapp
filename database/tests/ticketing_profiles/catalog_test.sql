DO $$
DECLARE en_org bigint; cs_org bigint; foreign_org bigint; en_unit bigint; cs_unit bigint; other_unit bigint;
 own_id bigint; foreign_id bigint; hidden_id bigint; src text:='catalog-'||gen_random_uuid(); other_src text:='catalog-other-'||gen_random_uuid();
 result jsonb; o_link text:='catalog-'||gen_random_uuid();
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('EN catalog test','{"CATALOG_SOURCE_POLICY":"explicit"}') RETURNING id INTO en_org;
 INSERT INTO public.organizations(title,data) VALUES('CS catalog test','{"CATALOG_SOURCE_POLICY":"explicit"}') RETURNING id INTO cs_org;
 INSERT INTO public.organizations(title) VALUES('Foreign catalog test') RETURNING id INTO foreign_org;
 INSERT INTO public.units(title,organization) VALUES('EN',en_org) RETURNING id INTO en_unit;
 INSERT INTO public.units(title,organization) VALUES('CS',cs_org) RETURNING id INTO cs_unit;
 INSERT INTO public.units(title,organization) VALUES('Foreign',foreign_org) RETURNING id INTO other_unit;
 INSERT INTO public.occasions(start_time,end_time,title,organization,unit,link,is_hidden,is_promoted)
 VALUES(now(),now()+interval '1 day','Czech event',cs_org,cs_unit,o_link,false,true) RETURNING id INTO foreign_id;
 PERFORM public.reserve_public_link_internal('occasion',foreign_id,o_link,true);
 INSERT INTO public.external_sync_sources(source_name,supabase_url,anon_key) VALUES(src,'https://catalog.example.invalid','fixture'),(other_src,'https://other.example.invalid','fixture');
 INSERT INTO public.external_occasions_cache(external_id,link,source_name) VALUES(1,o_link,src);
 INSERT INTO public.occasions(start_time,end_time,title,organization,unit,link,is_hidden,is_promoted)
 VALUES(now(),now()+interval '1 day','Other source',foreign_org,other_unit,'other-'||gen_random_uuid(),false,true) RETURNING id INTO hidden_id;
 INSERT INTO public.external_occasions_cache(external_id,link,source_name) SELECT 2,link,other_src FROM public.occasions WHERE id=hidden_id;
 IF jsonb_array_length(public.get_available_occasions(en_org)->'occasions')<>0 OR jsonb_array_length(public.get_public_occasions(en_org)->'occasions')<>0 THEN
  RAISE EXCEPTION 'Empty EN catalog leaked a foreign event'; END IF;
 IF public.get_occasion_seo_data(o_link,'event',en_org) IS NOT NULL THEN RAISE EXCEPTION 'Foreign event indexed on EN host'; END IF;
 INSERT INTO public.occasions(start_time,end_time,title,organization,unit,link,is_hidden,is_promoted)
 VALUES(now(),now()+interval '1 day','Own English event',en_org,en_unit,'own-'||gen_random_uuid(),false,true) RETURNING id INTO own_id;
 INSERT INTO public.occasions(start_time,end_time,title,organization,unit,link,is_hidden,is_promoted)
 VALUES(now(),now()+interval '1 day','Hidden',en_org,en_unit,'hidden-'||gen_random_uuid(),true,true),(now(),now()+interval '1 day','Not promoted',en_org,en_unit,'unpromoted-'||gen_random_uuid(),false,false);
 IF jsonb_array_length(public.get_available_occasions(en_org)->'occasions')<>1 OR jsonb_array_length(public.get_public_occasions(en_org)->'occasions')<>1 THEN
  RAISE EXCEPTION 'EN own visibility changed'; END IF;
 -- A tenant without the opt-in retains both original catalog projections.
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_available_occasions(foreign_org)->'occasions') x WHERE (x->>'id')::bigint=foreign_id)
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_public_occasions(foreign_org)->'occasions') x WHERE (x->>'id')::bigint=foreign_id) THEN
  RAISE EXCEPTION 'Existing tenant external catalog behavior changed'; END IF;
 -- Existing service-only source maps explicitly opt in one source.
 INSERT INTO public.external_sync_maps(source_name,target_org_id,target_unit_id,remote_link_base) VALUES(src,en_org,en_unit,'https://source.example.invalid');
 IF jsonb_array_length(public.get_available_occasions(en_org)->'occasions')<>2 OR jsonb_array_length(public.get_public_occasions(en_org)->'occasions')<>2 THEN
  RAISE EXCEPTION 'Explicit source admission failed'; END IF;
 IF public.get_occasion_seo_data(o_link,'event',en_org) IS NULL THEN RAISE EXCEPTION 'Explicit source SEO was lost'; END IF;
 IF jsonb_array_length(public.get_available_occasions(cs_org)->'occasions')<>1 THEN RAISE EXCEPTION 'CS own catalog changed'; END IF;
 DELETE FROM public.external_sync_maps WHERE target_org_id=en_org;
 IF jsonb_array_length(public.get_available_occasions(en_org)->'occasions')<>1 THEN RAISE EXCEPTION 'Removed source still admitted'; END IF;
END $$;
