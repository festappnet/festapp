-- Shared notification classification, DTO and receipt grouping.
-- Serving adapters own scopes; these owners retain domain policy and history.
CREATE OR REPLACE FUNCTION public.notification_center_order_activity_internal(p_kind text)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_kind IN ('order_created','order_cancelled','waitlist_registered','offer_accepted','offer_declined','offer_expired');
$$;

CREATE OR REPLACE FUNCTION public.notification_center_batch_internal(
 e public.notification_center_events,d public.notification_center_deliveries)
RETURNS TABLE(batch_id text,is_read boolean,after_sequence bigint,through_sequence bigint,group_key text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH state AS (
  SELECT coalesce((SELECT read_through_sequence FROM public.notification_center_user_state
   WHERE organization=d.organization AND recipient=d.recipient),0) baseline,
   CASE WHEN e.occasion IS NOT NULL AND e.kind NOT IN ('email_problem','bank_problem')
    THEN 'occasion-kind:'||e.occasion||':'||e.kind ELSE 'event:'||e.id END key),
 receipt AS (
  SELECT b.* FROM public.notification_center_read_batches b,state s
  WHERE b.organization=d.organization AND b.recipient=d.recipient AND b.group_key=s.key
   AND d.sequence>b.after_sequence AND d.sequence<=b.through_sequence
  ORDER BY b.through_sequence,b.read_at,b.id LIMIT 1),
 bounds AS (
  SELECT s.*,greatest(s.baseline,coalesce((SELECT max(b.through_sequence)
   FROM public.notification_center_read_batches b WHERE b.organization=d.organization
    AND b.recipient=d.recipient AND b.group_key=s.key),0)) last_read,
   e.actor=d.recipient AND e.kind IN ('order_created','order_cancelled') own_action FROM state s)
 SELECT CASE WHEN coalesce(s.own_action,false) THEN s.key||':self'
   WHEN d.sequence<=s.baseline THEN s.key||':legacy'
   WHEN r.id IS NOT NULL THEN s.key||':batch:'||r.after_sequence
   ELSE s.key||':batch:'||s.last_read END,
  coalesce(s.own_action,false) OR d.sequence<=s.baseline OR r.id IS NOT NULL,
  CASE WHEN coalesce(s.own_action,false) OR d.sequence<=s.baseline THEN 0
   WHEN r.id IS NOT NULL THEN r.after_sequence ELSE s.last_read END,
  CASE WHEN coalesce(s.own_action,false) THEN d.sequence WHEN d.sequence<=s.baseline THEN s.baseline
   WHEN r.id IS NOT NULL THEN r.through_sequence ELSE d.sequence END,s.key
 FROM bounds s LEFT JOIN receipt r ON true;
$$;
REVOKE ALL ON FUNCTION public.notification_center_batch_internal(public.notification_center_events,public.notification_center_deliveries) FROM PUBLIC,anon,authenticated,service_role;


CREATE OR REPLACE FUNCTION public.notification_center_dto(e public.notification_center_events,d public.notification_center_deliveries)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE payload jsonb:=e.data-'bankConnectionId'; account bigint; un bigint; impacts jsonb; customer text; actual_state text; contact jsonb; actual_context jsonb; actual_count bigint;
BEGIN
 IF NOT public.notification_center_allowed(e,auth.uid()) THEN RETURN NULL; END IF;
 IF e.kind='email_problem' AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT payload||jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,'recipient',m.recipient,'customerName',coalesce(
    nullif(trim(concat_ws(' ',o.data->>'name',o.data->>'surname')),''),
    nullif(trim(concat_ws(' ',u.name,u.surname)),''))) INTO payload
  FROM public.email_messages m
  LEFT JOIN eshop.orders o ON o.id=m.order_id AND o.occasion=m.occasion
    AND coalesce(public.can_read_orders(o.occasion),false)
    AND EXISTS(SELECT 1 FROM public.occasions oc WHERE oc.id=o.occasion AND oc.organization=m.organization)
  LEFT JOIN public.user_info u ON u.id=m.recipient_user AND u.organization=m.organization
  WHERE m.message_id=(e.data->>'messageId')::uuid AND m.organization=e.organization
    AND m.occasion IS NOT DISTINCT FROM e.occasion;
  payload:=coalesce(payload,e.data-'bankConnectionId');
 END IF;
 IF e.kind='occasion_joined' AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT nullif(trim(concat_ws(' ',u.name,u.surname)),'') INTO customer
  FROM public.user_info u JOIN public.occasion_users m ON m."user"=u.id
  WHERE m.occasion=e.occasion AND u.organization=e.organization AND u.id=(e.data->>'userId')::uuid;
  payload:=payload||jsonb_build_object('customerName',customer,'state',CASE WHEN EXISTS(
   SELECT 1 FROM public.occasion_users m WHERE m.occasion=e.occasion AND m."user"=(e.data->>'userId')::uuid) THEN 'membership_active' ELSE 'membership_left' END);
 END IF;
 IF e.data ? 'orderId' AND e.occasion IS NOT NULL AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'),o.state,public.notification_center_order_form_context_internal(o.form),
    (SELECT count(DISTINCT x.ticket) FROM eshop.order_product_ticket x WHERE x."order"=o.id)
   INTO contact,actual_state,actual_context,actual_count
   FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization
   WHERE o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion;
  payload:=payload||jsonb_build_object('contact',coalesce(contact,'{}'),'customerName',nullif(trim(concat_ws(' ',contact->>'name',contact->>'surname')),''),'state',coalesce(actual_state,e.data->>'state'));
  -- Legacy events have no captured form context/count; use the authorized live
  -- order only for absent fields. Captured historical facts always win.
  IF public.notification_center_order_activity_internal(e.kind) THEN
   payload:=payload||jsonb_build_object('formContext',coalesce(nullif(e.data->'formContext','null'::jsonb),actual_context),
    'count',coalesce(nullif(e.data->'count','null'::jsonb),CASE WHEN actual_count>0 THEN to_jsonb(actual_count) END));
  END IF;
 END IF;
 IF e.kind='bank_problem' THEN
  SELECT bu.bank_account,u.id INTO account,un FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu
   ON bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
   JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account JOIN public.units u ON u.id=uba.unit
   WHERE c.id=(e.data->>'bankConnectionId')::bigint AND bu."user"=auth.uid() AND public.notification_center_bank_admin(bu.bank_account,auth.uid()) AND u.organization=e.organization AND EXISTS(SELECT 1 FROM public.unit_users um WHERE um.unit=u.id AND um."user"=auth.uid() AND um.is_manager) ORDER BY u.id LIMIT 1;
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

REVOKE ALL ON FUNCTION public.notification_center_order_activity_internal(text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.notification_center_dto(public.notification_center_events,public.notification_center_deliveries) FROM PUBLIC,anon,authenticated;
