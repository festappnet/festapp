CREATE OR REPLACE FUNCTION public.queue_payment_reminders(p_occasion_id BIGINT, p_seconds_before_deadline BIGINT)
RETURNS VOID
SET search_path = public, extensions AS $$
DECLARE
  v_interval INTERVAL;
BEGIN


  UPDATE public.email_messages SET workflow_state='cancelled',last_error='reminder_superseded',lease_token=NULL,lease_until=NULL
  WHERE (occasion=p_occasion_id OR order_id IN (SELECT id FROM eshop.orders WHERE payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id))) AND message_kind='order_reminder' AND workflow_state IN ('pending','retry_wait','blocked','preparing');
  UPDATE eshop.payment_info pi SET email_reminder_version=email_reminder_version+1
  WHERE EXISTS(SELECT 1 FROM eshop.orders o WHERE o.payment_info=pi.id AND o.occasion=p_occasion_id);


  v_interval := make_interval(secs => p_seconds_before_deadline);




  PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object(
      'order_id', o.id
    ),occ.organization,o.occasion,occ.unit,pi.deadline - CASE WHEN o.occasion=p_occasion_id THEN v_interval ELSE make_interval(secs=>coalesce((form_settings.feature->>'reminder_interval_seconds')::bigint,86400)) END) FROM eshop.payment_info pi
  JOIN
    eshop.orders o ON pi.id = o.payment_info
  JOIN
    public.occasions occ ON o.occasion = occ.id


  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'form'
  ) form_settings ON TRUE


  LEFT JOIN public.forms f ON f.key = (o.data->>'form')::uuid
  WHERE
    (o.occasion=p_occasion_id OR o.payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id))
    AND o.state = 'ordered'
    AND pi.deadline IS NOT NULL



    AND (pi.data->>'current_version_reminded')::boolean IS NOT TRUE


    AND (form_settings.feature->>'is_enabled')::boolean IS TRUE

    AND (form_settings.feature->>'reminder_is_enabled')::boolean IS TRUE


    AND COALESCE((f.data->>'is_reminder_enabled')::boolean, TRUE) IS TRUE;








  PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object(
      'order_id', o.id,
      'is_deposit_reminder', true
    ),occ.organization,o.occasion,occ.unit,(occ.start_time - make_interval(days => (deposit_settings.feature->>'deposit_deadline_days')::int)) - CASE WHEN o.occasion=p_occasion_id THEN v_interval ELSE make_interval(secs=>coalesce((form_settings.feature->>'reminder_interval_seconds')::bigint,86400)) END) FROM eshop.payment_info pi
  JOIN
    eshop.orders o ON pi.id = o.payment_info
  JOIN
    public.occasions occ ON o.occasion = occ.id

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'deposit'
  ) deposit_settings ON TRUE

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'form'
  ) form_settings ON TRUE
  LEFT JOIN public.forms f ON f.key = (o.data->>'form')::uuid
  WHERE
    (o.occasion=p_occasion_id OR o.payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id))
    AND o.state = 'paid'
    AND pi.deposit_amount IS NOT NULL
    AND pi.paid < pi.amount

    AND (deposit_settings.feature->>'is_enabled')::boolean IS TRUE

    AND (deposit_settings.feature->>'deposit_deadline') IS DISTINCT FROM 'on_site'

    AND (deposit_settings.feature->>'deposit_deadline_days') IS NOT NULL

    AND occ.start_time IS NOT NULL

    AND (form_settings.feature->>'is_enabled')::boolean IS TRUE
    AND (form_settings.feature->>'reminder_is_enabled')::boolean IS TRUE
    AND COALESCE((f.data->>'is_reminder_enabled')::boolean, TRUE) IS TRUE;

END;
$$ LANGUAGE plpgsql;
