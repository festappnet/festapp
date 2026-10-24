-- Identify authorized email incidents from current message and recipient records.
BEGIN;
CREATE OR REPLACE FUNCTION public.notification_center_dto(e public.notification_center_events,d public.notification_center_deliveries)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE payload jsonb:=e.data-'bankConnectionId'; account bigint; un bigint; impacts jsonb; customer text; actual_state text;
BEGIN
 IF e.kind='email_problem' AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT payload||jsonb_build_object('recipient',m.recipient,'customerName',coalesce(
    nullif(trim(concat_ws(' ',o.data->>'name',o.data->>'surname')),''),
    nullif(trim(concat_ws(' ',u.name,u.surname)),''))) INTO payload
  FROM public.email_messages m
  LEFT JOIN eshop.orders o ON o.id=m.order_id AND o.occasion=m.occasion
    AND EXISTS(SELECT 1 FROM public.occasions oc WHERE oc.id=o.occasion AND oc.organization=m.organization)
  LEFT JOIN public.user_info u ON u.id=m.recipient_user AND u.organization=m.organization
  WHERE m.message_id=(e.data->>'messageId')::uuid AND m.organization=e.organization
    AND m.occasion IS NOT DISTINCT FROM e.occasion;
  payload:=coalesce(payload,e.data-'bankConnectionId');
 END IF;
 IF e.data ? 'orderId' AND e.occasion IS NOT NULL THEN
  SELECT nullif(trim(concat_ws(' ',o.data->>'name',o.data->>'surname')),''),o.state INTO customer,actual_state
   FROM eshop.orders o WHERE o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion;
  payload:=payload||jsonb_build_object('customerName',customer,'state',coalesce(actual_state,e.data->>'state'));
 END IF;
 IF e.kind='bank_problem' THEN
  SELECT bu.bank_account,u.id INTO account,un FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu
   ON bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
   JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account JOIN public.units u ON u.id=uba.unit
   WHERE c.id=(e.data->>'bankConnectionId')::bigint AND bu."user"=auth.uid() AND bu.is_admin AND u.organization=e.organization ORDER BY u.id LIMIT 1;
  IF account IS NOT NULL THEN payload:=payload||jsonb_build_object('bankAccountId',account,'unitId',un); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',oc.id,'title',oc.title,'link',oc.link)),'[]') INTO impacts
   FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id AND ou."user"=auth.uid() AND ou.is_editor_order_view
   WHERE oc.organization=e.organization AND oc.id=ANY(e.affected_occasions);
  payload:=payload||jsonb_build_object('affectedOccasions',impacts);
 END IF;
 RETURN (SELECT jsonb_build_object('id',e.id,'sequence',d.sequence,'kind',e.kind,'occurredAt',e.occurred_at,
 'status',e.status,'data',payload,'occasionId',e.occasion,'occasionLink',oc.link,'occasionTitle',oc.title)
 FROM (SELECT 1) seed LEFT JOIN public.occasions oc ON oc.id=e.occasion AND oc.organization=e.organization);
END $$;
COMMIT;
