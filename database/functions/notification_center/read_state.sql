-- Personal attention state: opening sees a snapshot; following reads one batch.
ALTER TABLE public.notification_center_user_state ADD COLUMN IF NOT EXISTS seen_through_sequence bigint NOT NULL DEFAULT 0;
CREATE TABLE IF NOT EXISTS public.notification_center_read_batches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 recipient uuid NOT NULL, group_key text NOT NULL,
 after_sequence bigint NOT NULL, through_sequence bigint NOT NULL,
 read_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(after_sequence>=0 AND through_sequence>after_sequence),
 UNIQUE(organization,recipient,group_key,through_sequence)
);
ALTER TABLE public.notification_center_read_batches ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_center_read_batches FROM PUBLIC,anon,authenticated,service_role;

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
  ORDER BY b.through_sequence LIMIT 1),
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

CREATE OR REPLACE FUNCTION public.mark_notification_center_item_read(p_organization bigint,p_scope jsonb)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE id text:=p_scope->>'id'; base text; lower_bound bigint; upper_bound bigint;
 actual_upper bigint; baseline bigint; last_read bigint; occ bigint; snap bigint;
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 IF coalesce(p_scope->>'snapshot','') !~ '^[0-9]{1,18}$' THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_snapshot'; END IF;
 SELECT read_through_sequence,least((p_scope->>'snapshot')::bigint,last_delivery_sequence)
  INTO baseline,snap FROM public.notification_center_user_state
  WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 IF id ~ '^occasion-kind:[0-9]{1,18}:[a-z_]+:batch:[0-9]{1,18}$' THEN
  base:=regexp_replace(id,':batch:[0-9]+$','');
  lower_bound:=substring(id from ':batch:([0-9]+)$')::bigint;
  occ:=split_part(id,':',2)::bigint;
  PERFORM public.notification_center_check_context(p_organization,occ);
 ELSIF id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
  base:='event:'||id; lower_bound:=0;
 ELSE
  RETURN false;
 END IF;
 IF p_scope ? 'throughSequence' AND coalesce(p_scope->>'throughSequence','') !~ '^[0-9]{1,18}$' THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_snapshot'; END IF;
 upper_bound:=least(coalesce((p_scope->>'throughSequence')::bigint,snap),snap);
 SELECT max((v.delivery).sequence) INTO actual_upper
 FROM public.notification_center_visible_internal(p_organization,snap,occ) v
 WHERE (v.delivery).sequence>lower_bound AND (v.delivery).sequence<=upper_bound
  AND public.notification_center_in_center_internal(v.event,clock_timestamp())
  AND CASE WHEN occ IS NOT NULL THEN
   'occasion-kind:'||(v.event).occasion||':'||(v.event).kind=base
   ELSE 'event:'||(v.event).id=base END
  AND NOT coalesce((v.event).actor=auth.uid() AND (v.event).kind IN ('order_created','order_cancelled'),false);
 IF actual_upper IS NULL THEN RETURN false; END IF;
 SELECT coalesce(max(through_sequence),0) INTO last_read FROM public.notification_center_read_batches
 WHERE organization=p_organization AND recipient=auth.uid() AND group_key=base;
 lower_bound:=greatest(lower_bound,baseline,last_read);
 IF actual_upper<=lower_bound THEN RETURN true; END IF;
 INSERT INTO public.notification_center_read_batches(organization,recipient,group_key,after_sequence,through_sequence)
 VALUES(p_organization,auth.uid(),base,lower_bound,actual_upper) ON CONFLICT DO NOTHING;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.mark_notification_center_item_read(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.mark_notification_center_item_read(bigint,jsonb) TO authenticated;
