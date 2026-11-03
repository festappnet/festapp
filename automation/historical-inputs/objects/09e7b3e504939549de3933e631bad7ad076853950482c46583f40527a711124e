-- Released clients keep their original {code,data} shapes; all effects use commands.
CREATE OR REPLACE FUNCTION public.create_counseling_slots(p_speaker bigint,p_start timestamptz,
 p_end timestamptz,p_slot_minutes integer,p_place bigint DEFAULT NULL,p_capacity integer DEFAULT 1,
 p_title text DEFAULT NULL,p_break_minutes integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r jsonb;
BEGIN
 IF NOT public.get_is_editor_on_occasion((SELECT occasion FROM public.speakers WHERE id=p_speaker))
 THEN RETURN jsonb_build_object('code',403); END IF;
 r:=public.create_counseling_slots_client_sync_v1(p_speaker,p_start,p_end,p_slot_minutes,p_place,
  p_capacity,p_title,p_break_minutes,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',r->'code','data',r->'data');
END $$;
CREATE OR REPLACE FUNCTION public.delete_empty_counseling_slots(p_speaker bigint,p_from timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r jsonb;
BEGIN
 IF NOT public.get_is_editor_on_occasion((SELECT occasion FROM public.speakers WHERE id=p_speaker))
 THEN RETURN jsonb_build_object('code',403); END IF;
 r:=public.delete_empty_counseling_slots_client_sync_v1(p_speaker,p_from,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',r->'code','data',r->'data');
END $$;

REVOKE ALL ON FUNCTION public.create_counseling_slots(bigint,timestamptz,timestamptz,integer,bigint,integer,text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_counseling_slots(bigint,timestamptz,timestamptz,integer,bigint,integer,text,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.delete_empty_counseling_slots(bigint,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_empty_counseling_slots(bigint,timestamptz) TO authenticated;
