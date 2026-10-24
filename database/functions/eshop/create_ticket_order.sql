CREATE OR REPLACE FUNCTION public.create_ticket_order_internal_v1(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f bigint; target bigint; result jsonb;
BEGIN
 PERFORM public.check_occasion_writable((SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid));
 BEGIN
  SELECT id INTO f FROM public.forms WHERE key=(input_data->>'form')::uuid FOR UPDATE;
  IF f IS NULL THEN RAISE EXCEPTION 'Form not found'; END IF;
  target:=public.allocate_ticket_order_identity_internal(f);
  result:=public.finalize_ticket_order_internal_v1(target,input_data,false);
  IF coalesce((result->>'code')::integer,500)<>200 THEN RAISE EXCEPTION '%',result::text; END IF;
  PERFORM public.notification_center_order_internal(target,'order_created','created');
  RETURN result;
 EXCEPTION WHEN SQLSTATE 'PT429' THEN
  RETURN jsonb_build_object('code',429,'errorCode','ABUSE_LIMIT_EXCEEDED','message','Capacity is temporarily limited. Try again later.');
 WHEN OTHERS THEN
  RETURN CASE WHEN left(SQLERRM,1)='{' THEN SQLERRM::jsonb ELSE jsonb_build_object('code',1013,'message',SQLERRM) END;
 END;
END $$;
REVOKE ALL ON FUNCTION public.create_ticket_order_internal_v1(jsonb) FROM PUBLIC,anon,authenticated;
