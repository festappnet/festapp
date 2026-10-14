-- Actual occasion titles, shared by fresh fixtures and scoped maintenance.
CREATE OR REPLACE FUNCTION pg_temp.refresh_demo_titles(p_org bigint)
RETURNS void LANGUAGE plpgsql AS $titles$
DECLARE d record; next_title text;
BEGIN
 IF current_user <> 'postgres' THEN RAISE insufficient_privilege; END IF;
 PERFORM pg_advisory_xact_lock(7141014,p_org::integer);
 IF (SELECT count(*) FROM public.demo_occasions WHERE organization=p_org AND fixture_version='2026-10-14.3')<>3 THEN
  RAISE EXCEPTION 'Expected three registered demo fixtures';
 END IF;
 FOR d IN SELECT * FROM public.demo_occasions WHERE organization=p_org AND fixture_version='2026-10-14.3' ORDER BY sort_order LOOP
  next_title:=CASE d.demo_key WHEN 'ball' THEN 'Ples' WHEN 'concert' THEN 'Koncert' WHEN 'weekend' THEN 'Víkendovka' END;
  UPDATE public.occasions SET title=next_title,updated_at=now()
   WHERE id=d.occasion AND organization=p_org AND title IS DISTINCT FROM next_title;
  IF FOUND THEN
   PERFORM public.record_client_sync_commit_v1(d.occasion,'demo.rename','configuration',
    jsonb_build_array(jsonb_build_object('entityType','occasion','entityId',d.occasion::text,
     'operation','update','safeLabel',next_title,'changedFields',jsonb_build_array('title'))),
    ARRAY['occasion_config'],'[]'::jsonb,'[]'::jsonb,'system','Rename registered demonstration occasion');
  END IF;
 END LOOP;
END $titles$;
