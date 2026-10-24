-- psql -v organization_id=<verified selected organization>; no message/history changes.
WITH recovered AS (
 UPDATE public.notification_center_events e SET status='recovered'
 FROM public.email_messages m JOIN eshop.orders o ON o.id=m.order_id
 JOIN public.occasions oc ON oc.id=o.occasion
 WHERE oc.organization=:'organization_id'::bigint AND o.state='storno'
   AND m.occasion=o.occasion AND m.organization=oc.organization
   AND m.message_kind<>'order_storno' AND e.organization=m.organization
   AND e.kind='email_problem' AND e.source_key='email:'||m.message_id
   AND e.status IS DISTINCT FROM 'recovered'
 RETURNING e.id
) SELECT count(*) AS recovered_order_email_alerts FROM recovered;
