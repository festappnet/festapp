-- Secret uniqueness is enforced across all events, including simultaneous writers.
CREATE UNIQUE INDEX IF NOT EXISTS occasions_hidden_scan_secret_unique_idx
 ON public.occasions_hidden(secret) WHERE secret IS NOT NULL;

-- Both initialization and explicit rotation use the same stored occasion lock
-- and the existing authorized write owner. Clients never allocate credentials.
CREATE OR REPLACE FUNCTION public.get_or_create_scan_code(occasion_link text, p_rotate boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE oc public.occasions; existing text; candidate text;
 attempt integer; result jsonb;
BEGIN
 p_rotate:=coalesce(p_rotate,false);
 SELECT * INTO oc FROM public.occasions WHERE id=public.resolve_occasion_link_internal(occasion_link);
 IF oc.id IS NULL THEN RETURN jsonb_build_object('code',404,'message','Occasion link does not exist.'); END IF;
 IF (p_rotate AND NOT public.can_write_orders(oc.id))
    OR (NOT p_rotate AND NOT public.can_read_orders(oc.id)) THEN
   RETURN jsonb_build_object('code',403,'message','User is not authorized for this occasion.');
 END IF;
 SELECT * INTO oc FROM public.occasions WHERE id=oc.id FOR UPDATE;
 SELECT h.secret INTO existing FROM public.occasions_hidden h WHERE h.id=oc.occasion_hidden;
 IF NOT p_rotate AND existing IS NOT NULL AND EXISTS (
   SELECT 1 FROM public.get_scanner_occasion_for_scan_code_internal(existing) proof WHERE proof.id=oc.id
 ) THEN RETURN jsonb_build_object('code',200,'scan_code',existing); END IF;
 IF NOT public.can_write_orders(oc.id) THEN
   RETURN jsonb_build_object('code',403,'message','User is not authorized to initialize this scanner.');
 END IF;
 FOR attempt IN 1..32 LOOP
   candidate:=public.generate_scanner_access_code_internal();
   -- A rotation must actually replace the old credential, even on a random hit.
   IF candidate IS NOT DISTINCT FROM existing THEN CONTINUE; END IF;
   result:=public.update_scan_code(occasion_link,candidate);
   IF result->>'code'='200' THEN RETURN result||jsonb_build_object('scan_code',candidate); END IF;
   IF result->>'reason' IS DISTINCT FROM 'scan_code_collision' THEN RETURN result; END IF;
 END LOOP;
 RETURN jsonb_build_object('code',503,'message','Unable to allocate a unique scan code.');
END $$;
REVOKE ALL ON FUNCTION public.get_or_create_scan_code(text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_scan_code(text,boolean) TO authenticated,service_role;
