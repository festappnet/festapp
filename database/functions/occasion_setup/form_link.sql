-- Suggestions consult the same global reservations (including tombstones) as
-- final writes. This is a preview, not a claim or an alternate allocator.
CREATE OR REPLACE FUNCTION public.suggest_occasion_setup_form_link(p_id uuid,p_title text,p_requested_link text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; base text; candidate text; suffix integer:=1; year text;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF length(coalesce(p_title,''))>500 OR length(coalesce(p_requested_link,''))>80 THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid public link input'; END IF;
 base:=trim(both '-' from regexp_replace(public.f_unaccent(left(coalesce(p_title,''),500)),'[^a-z0-9]+','-','g'));
 base:=trim(trailing '-' from left(base,64));
 IF base='' THEN base:='akce'; END IF;
 year:=substring(coalesce(d.data->>'start',d.data->>'start_time','') from '^([0-9]{4})-');
 IF year IS NOT NULL AND base !~ '[0-9]{4}' THEN base:=base||'-'||year; END IF;
 candidate:=base;
 WHILE EXISTS(SELECT 1 FROM public.form_link_reservations WHERE slug=candidate) LOOP
  suffix:=suffix+1; candidate:=base||'-'||suffix;
  IF suffix>1000 THEN candidate:=base||'-'||left(replace(d.id::text,'-',''),8); EXIT; END IF;
 END LOOP;
 -- Deterministic bounded fallback, still checked rather than presumed free.
 IF EXISTS(SELECT 1 FROM public.form_link_reservations WHERE slug=candidate) THEN
  RAISE unique_violation USING MESSAGE='Public link suggestions exhausted'; END IF;
 RETURN jsonb_build_object('suggestion',candidate,'available',
  CASE WHEN p_requested_link IS NULL OR p_requested_link='' THEN NULL
  ELSE p_requested_link ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    AND NOT EXISTS(SELECT 1 FROM public.form_link_reservations WHERE slug=p_requested_link) END);
END $$;
REVOKE ALL ON FUNCTION public.suggest_occasion_setup_form_link(uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.suggest_occasion_setup_form_link(uuid,text,text) TO authenticated;
