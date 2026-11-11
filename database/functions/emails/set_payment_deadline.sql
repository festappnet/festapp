CREATE OR REPLACE FUNCTION public.set_payment_deadline(p_payment_info_id bigint,p_new_deadline timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE o record;
BEGIN
  PERFORM public.check_bank_account_writable((SELECT bank_account FROM eshop.payment_info WHERE id=p_payment_info_id));
 PERFORM public.check_payment_info_is_mutable(p_payment_info_id);
 IF p_new_deadline IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=p_payment_info_id AND payment_method='cash') THEN RAISE EXCEPTION 'CASH_DEADLINE_FORBIDDEN'; END IF;
 UPDATE eshop.payment_info SET deadline=p_new_deadline,
 deposit_deadline=CASE WHEN p_new_deadline IS NULL THEN NULL ELSE deposit_deadline END,
 data=coalesce(data,'{}')||jsonb_build_object('current_version_reminded',false,'payment_policy',coalesce(data->'payment_policy','{}')||jsonb_build_object('mode',CASE WHEN p_new_deadline IS NULL THEN 'none' ELSE 'custom' END)),
 email_reminder_version=email_reminder_version+1 WHERE id=p_payment_info_id;
 FOR o IN SELECT DISTINCT occ.id FROM eshop.orders ord JOIN public.occasions occ ON occ.id=ord.occasion WHERE ord.payment_info=p_payment_info_id LOOP
  PERFORM public.queue_payment_reminders_internal(o.id,p_payment_info_id);
 END LOOP;
END $$;
