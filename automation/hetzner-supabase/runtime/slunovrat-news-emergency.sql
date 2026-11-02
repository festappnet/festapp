-- Temporary native-client bridge, explicitly limited to the Winter Edition.
-- Run inside a transaction with psql -v expires_at=<UTC timestamp>.
-- Temporary operational adapters expire with the grants. The release workflow
-- must schedule slunovrat-news-emergency-remove.sql and verify their removal.
\set ON_ERROR_STOP on
SELECT :'expires_at'::timestamptz > statement_timestamp()
   AND :'expires_at'::timestamptz <= statement_timestamp() + interval '48 hours'
   AS valid_emergency_deadline \gset
\if :valid_emergency_deadline
\else
DO $$ BEGIN RAISE EXCEPTION 'Emergency deadline must be within 48 hours'; END $$;
\endif
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id=19 AND title='Slunovrat')
    OR NOT EXISTS (SELECT 1 FROM public.occasions
      WHERE id=1072594 AND organization=19 AND unit=999
        AND link='2025we-copy-5e6268f4')
    OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.news'::regclass)
    OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.news'::regclass
      AND polname='Enable insert for editors' AND polcmd='a') THEN
    RAISE EXCEPTION 'Slunovrat emergency news identity/RLS mismatch';
  END IF;
END $$;
CREATE POLICY slunovrat_news_emergency_20261102 ON public.news
AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (
  occasion=1072594 AND created_by=auth.uid()
  AND public.can_write_news(occasion)
  AND statement_timestamp() < :'expires_at'::timestamptz
);
GRANT INSERT (occasion,message,created_by) ON public.news TO authenticated;

-- Keep modern readers current when the legacy client saves a news row.
CREATE FUNCTION public.slunovrat_legacy_news_emergency_20261102() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE command_id uuid:=gen_random_uuid(); actor uuid:=auth.uid(); response jsonb;
BEGIN
  IF statement_timestamp()>=TG_ARGV[0]::timestamptz OR NEW.occasion IS DISTINCT FROM 1072594
    OR NEW.created_by IS DISTINCT FROM actor OR NOT public.can_write_news(NEW.occasion)
    OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=NEW.occasion
      AND organization=19 AND unit=999 AND is_hidden=false) THEN
    RAISE insufficient_privilege USING MESSAGE='legacy news bridge unavailable';
  END IF;
  IF NEW.message IS NULL OR octet_length(NEW.message) NOT BETWEEN 1 AND 524288 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid legacy news';
  END IF;
  PERFORM public.begin_client_mutation_v1(command_id,'content.news.publish',NEW.occasion,
    actor,encode(extensions.digest(convert_to(to_jsonb(NEW)::text,'UTF8'),'sha256'),'hex'));
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES('news','occasion',NEW.occasion,NEW.id::text,1);
  response:=public.complete_client_mutation_applied_v1(command_id,NEW.occasion,
    'content.news.publish','content',jsonb_build_array(jsonb_build_object(
      'entityType','news','entityId',NEW.id,'operation','insert','safeLabel','News',
      'changedFields',jsonb_build_array('message'))),ARRAY['content_catalog'],'[]','[]',
    jsonb_build_object('version',1,'news',to_jsonb(NEW),'notificationQueued',false));
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.slunovrat_legacy_news_emergency_20261102() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER slunovrat_legacy_news_emergency_20261102
AFTER INSERT ON public.news FOR EACH ROW
WHEN (current_user='authenticated' AND NEW.occasion=1072594)
EXECUTE FUNCTION public.slunovrat_legacy_news_emergency_20261102(:'expires_at');

-- A legacy REST INSERT becomes a canonical admitted intent, rather than an
-- unaudited notification row. Canonical SECURITY DEFINER writers skip this
-- adapter through the trigger's invoker-role condition.
CREATE FUNCTION public.slunovrat_legacy_push_emergency_20261102() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE revision bigint; published bigint;
BEGIN
  IF statement_timestamp()>=TG_ARGV[0]::timestamptz OR NEW.occasion IS DISTINCT FROM 1072594
    OR NEW.organization IS DISTINCT FROM 19 OR NEW.user_id IS DISTINCT FROM auth.uid()
    OR auth.uid() IS NULL OR NOT public.can_write_news(NEW.occasion)
    OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=NEW.occasion
      AND organization=19 AND unit=999 AND is_hidden=false) THEN
    RAISE insufficient_privilege USING MESSAGE='legacy notification bridge unavailable';
  END IF;
  IF NEW.content IS NULL OR octet_length(NEW.content) NOT BETWEEN 1 AND 65536
    OR octet_length(coalesce(NEW.heading,''))>2048
    OR NEW.data IS NOT NULL AND NEW.data<>'{"path":"news"}'::jsonb THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid legacy news notification';
  END IF;
  SELECT source_revision INTO revision FROM public.client_sync_scopes
    WHERE component='content_catalog' AND scope_type='occasion' AND scope_id=NEW.occasion;
  SELECT max(published_revision) INTO published FROM public.client_sync_publications
    WHERE component='content_catalog' AND scope_type='occasion' AND scope_id=NEW.occasion;
  IF revision IS NULL THEN
    RAISE configuration_limit_exceeded USING MESSAGE='news content scope unavailable';
  END IF;
  IF coalesce(published,0)>=revision THEN
    PERFORM public.enqueue_notification_v1(NEW.occasion,NEW.heading,NEW.content,NEW."to",NEW.data);
  ELSE
    PERFORM public.charge_notification_intent_v1(NEW.occasion,auth.uid(),NEW."to",NEW.heading,NEW.content);
    INSERT INTO public.news_notification_outbox(command_id,occasion,organization,user_id,
      required_content_revision,"to",heading,content,data,abuse_admitted_at)
    VALUES(gen_random_uuid(),NEW.occasion,19,auth.uid(),revision,NEW."to",NEW.heading,
      NEW.content,jsonb_build_object('path','news'),statement_timestamp());
  END IF;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.slunovrat_legacy_push_emergency_20261102() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER slunovrat_legacy_push_emergency_20261102
BEFORE INSERT ON public.log_notifications FOR EACH ROW
WHEN (current_user='authenticated')
EXECUTE FUNCTION public.slunovrat_legacy_push_emergency_20261102(:'expires_at');
GRANT INSERT (occasion,organization,"to",heading,content,data) ON public.log_notifications TO authenticated;
NOTIFY pgrst, 'reload schema';
