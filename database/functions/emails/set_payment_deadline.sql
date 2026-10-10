CREATE OR REPLACE FUNCTION public.set_payment_deadline(p_payment_info_id bigint,p_new_deadline timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE o record; v_seconds bigint;
BEGIN
 PERFORM public.check_payment_info_is_mutable(p_payment_info_id);
 UPDATE eshop.payment_info SET deadline=p_new_deadline,data=coalesce(data,'{}')||'{"current_version_reminded":false}'::jsonb,
 email_reminder_version=email_reminder_version+1 WHERE id=p_payment_info_id;
 FOR o IN SELECT DISTINCT occ.id,occ.features FROM eshop.orders ord JOIN public.occasions occ ON occ.id=ord.occasion WHERE ord.payment_info=p_payment_info_id LOOP
  SELECT (f->>'reminder_interval_seconds')::bigint INTO v_seconds FROM jsonb_array_elements(o.features) f WHERE f->>'code'='form';
  PERFORM public.queue_payment_reminders(o.id,coalesce(v_seconds,0));
 END LOOP;
END $$;
