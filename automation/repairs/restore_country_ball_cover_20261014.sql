-- One scoped metadata recovery after restoring the exact public JPEG to R2.
-- Idempotent. Does not alter occasion settings, tickets, orders or other assets.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $restore$
DECLARE image_id bigint;
 cover text := 'https://img.festapp.net/images/32316/1772094968899-r0cg0z-1772094968608.jpg';
BEGIN
 IF session_user <> 'postgres' THEN RAISE insufficient_privilege; END IF;
 PERFORM 1 FROM public.occasions WHERE id=32316 AND organization=3
   AND link='skautskyples2026-copy-ae6d7140' AND data->>'image'=cover FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Country ball cover recovery target changed'; END IF;
 INSERT INTO public.images(link,occasion)
 SELECT cover,32316 WHERE NOT EXISTS(SELECT 1 FROM public.images WHERE link=cover)
 RETURNING id INTO image_id;
 IF image_id IS NOT NULL THEN
  PERFORM public.record_client_sync_commit_v1(32316,'image.restore','content',
   jsonb_build_array(jsonb_build_object('entityType','occasion_image',
    'entityId',image_id::text,'operation','insert','safeLabel','Country ball cover',
    'changedFields',jsonb_build_array('link'))),
   ARRAY['occasion_config'],'[]'::jsonb,'[]'::jsonb,'system',
   'Restore missing public cover image from its verified cached JPEG');
 END IF;
END $restore$;
COMMIT;
