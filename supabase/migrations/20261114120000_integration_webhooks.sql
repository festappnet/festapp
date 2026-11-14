-- Transactional integration webhooks; no application triggers or outbound SQL HTTP.

-- SOURCE: user_permissions/webhook_operations.sql
CREATE OR REPLACE FUNCTION public.can_manage_webhooks(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.can_read_orders(p_occasion) AND public.can_write_orders(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_manage_webhooks(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_webhooks(bigint) TO authenticated;

-- SOURCE: integration_webhooks/webhooks.sql
-- Durable routing and transactional fanout. Secrets remain in the integration
-- runtime's encrypted credential owner, never in these tables.
CREATE TABLE IF NOT EXISTS public.integration_webhook_subscriptions (
 id uuid PRIMARY KEY, actor uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 organization bigint NOT NULL, occasion bigint NOT NULL REFERENCES public.occasions(id) ON DELETE CASCADE,
 unit bigint, form bigint REFERENCES public.forms(id) ON DELETE CASCADE,
 binding text NOT NULL CHECK(binding ~ '^[a-f0-9]{64}$'),
 expires_at timestamptz NOT NULL, state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','paused','deleted','disabled')),
 version integer NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS public.integration_webhook_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization bigint NOT NULL,
 occasion bigint NOT NULL REFERENCES public.occasions(id) ON DELETE CASCADE,
 order_id bigint REFERENCES eshop.orders(id) ON DELETE CASCADE,
 form bigint REFERENCES public.forms(id) ON DELETE CASCADE,
 event_type text NOT NULL, body text, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(event_type,order_id), CHECK(body IS NULL OR octet_length(body)<=262144)
);
CREATE TABLE IF NOT EXISTS public.integration_webhook_deliveries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), subscription uuid NOT NULL REFERENCES public.integration_webhook_subscriptions(id) ON DELETE CASCADE,
 event uuid NOT NULL REFERENCES public.integration_webhook_events(id) ON DELETE CASCADE,
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','leased','succeeded','exhausted','blocked')),
 attempts integer NOT NULL DEFAULT 0, series integer NOT NULL DEFAULT 1,
 first_attempt_at timestamptz, next_due timestamptz NOT NULL DEFAULT clock_timestamp(),
 lease uuid, lease_until timestamptz, http_status integer, error_category text,
 history jsonb NOT NULL DEFAULT '[]', created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(subscription,event)
);
CREATE TABLE IF NOT EXISTS public.integration_webhook_commands (
 id uuid NOT NULL, binding text NOT NULL, actor uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 request_hash text NOT NULL, response jsonb NOT NULL, expires_at timestamptz NOT NULL,
 PRIMARY KEY(actor,binding,id)
);
CREATE INDEX IF NOT EXISTS integration_webhook_routes ON public.integration_webhook_subscriptions(occasion,form) WHERE state='active';
CREATE INDEX IF NOT EXISTS integration_webhook_due ON public.integration_webhook_deliveries(subscription,next_due) WHERE state IN ('pending','leased');
CREATE INDEX IF NOT EXISTS integration_webhook_owner ON public.integration_webhook_subscriptions(actor,binding,occasion);
CREATE INDEX IF NOT EXISTS integration_webhook_organization ON public.integration_webhook_subscriptions(organization);
CREATE INDEX IF NOT EXISTS integration_webhook_retention ON public.integration_webhook_events(created_at) WHERE body IS NOT NULL;
ALTER TABLE public.integration_webhook_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_webhook_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_webhook_commands ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.integration_webhook_subscriptions,public.integration_webhook_events,public.integration_webhook_deliveries,public.integration_webhook_commands FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.webhook_subscription_dto_internal(p_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('id',s.id,'occasionId',s.occasion,'formId',s.form,'version',s.version,'state',s.state,'expiresAt',s.expires_at)
 FROM public.integration_webhook_subscriptions s WHERE s.id=p_id;
$$;
REVOKE ALL ON FUNCTION public.webhook_subscription_dto_internal(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Called only from the initial-order owner AFTER successful finalization. The
-- same order transaction owns both the immutable event and every recipient row.
CREATE OR REPLACE FUNCTION public.emit_order_webhook_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders%ROWTYPE; org bigint; ev uuid:=gen_random_uuid(); payload jsonb; body_text text;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='webhook order missing'; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=o.occasion;
 PERFORM pg_advisory_xact_lock(hashtextextended('integration-webhooks:'||org,0));
 IF NOT EXISTS(SELECT 1 FROM public.integration_webhook_subscriptions s WHERE s.occasion=o.occasion AND s.organization=org
   AND (s.form IS NULL OR s.form=o.form) AND s.state='active' AND s.expires_at>clock_timestamp()) THEN RETURN; END IF;
 IF EXISTS(SELECT 1 FROM public.integration_webhook_events WHERE event_type='net.festapp.order.created.v1' AND order_id=p_order) THEN RETURN; END IF;
 -- A bounded durable backlog never silently drops a committed occurrence.
 IF (SELECT count(*) FROM public.integration_webhook_deliveries d JOIN public.integration_webhook_subscriptions s ON s.id=d.subscription
     WHERE s.organization=org AND d.state IN ('pending','leased'))+(SELECT count(*) FROM public.integration_webhook_subscriptions s WHERE s.occasion=o.occasion AND s.organization=org AND (s.form IS NULL OR s.form=o.form) AND s.state='active' AND s.expires_at>clock_timestamp())>100000 THEN
   RAISE program_limit_exceeded USING MESSAGE='webhook backlog capacity exhausted'; END IF;
 payload:=jsonb_build_object('specversion','1.0','id',ev,'source','https://api.festapp.net/integrations/organizations/'||org,
   'type','net.festapp.order.created.v1','subject','orders/'||o.id,'time',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'datacontenttype','application/json','data',jsonb_build_object('orderId',o.id,'occasionId',o.occasion,'formId',o.form,
   'customer',jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email','phone',o.data->>'phone'),
   'responses',coalesce(o.data->'fields','[]'::jsonb),
   'formFields',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'type',f.type) ORDER BY f.id),'[]') FROM public.form_fields f WHERE f.form=o.form AND NOT f.is_hidden),
   'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'responses',public.extract_ticket_answers_internal(o.form,jsonb_build_object('fields',t.data->'fields'))->'fields') ORDER BY t.id),'[]')
     FROM eshop.tickets t WHERE t.id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id))));
 body_text:=payload::text;
 INSERT INTO public.integration_webhook_events(id,organization,occasion,order_id,form,event_type,body)
 VALUES(ev,org,o.occasion,o.id,o.form,'net.festapp.order.created.v1',body_text)
 ON CONFLICT(event_type,order_id) DO NOTHING;
 IF NOT FOUND THEN RETURN; END IF;
 INSERT INTO public.integration_webhook_deliveries(subscription,event)
 SELECT s.id,ev FROM public.integration_webhook_subscriptions s WHERE s.occasion=o.occasion AND s.organization=org
 AND (s.form IS NULL OR s.form=o.form) AND s.state='active' AND s.expires_at>clock_timestamp();
END $$;
REVOKE ALL ON FUNCTION public.emit_order_webhook_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.integration_webhook_api_v1(
 p_occasion bigint,p_organization bigint,p_unit bigint,p_binding text,p_action text,p_input jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.integration_webhook_subscriptions%ROWTYPE; d public.integration_webhook_deliveries%ROWTYPE;
 sid uuid; cmd uuid; h text; result jsonb; prior public.integration_webhook_commands%ROWTYPE;
 occ_unit bigint; ev uuid; payload text; n timestamptz:=clock_timestamp(); v_state text;
BEGIN
 -- Same live resource/actor permission fence as the existing order adapter.
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit,false);
 IF p_action NOT IN ('list','deliveries') AND public.can_manage_webhooks(p_occasion) IS DISTINCT FROM TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='webhook management unavailable'; END IF;
 IF auth.uid() IS NULL OR p_binding IS NULL OR p_binding !~ '^[a-f0-9]{64}$' OR jsonb_typeof(p_input)<>'object'
   OR octet_length(p_input::text)>10240 OR p_action IS NULL OR p_action NOT IN
   ('list','create','update','delete','rotate_secret','test','deliveries','redeliver','claim','authorize','complete') THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid webhook operation'; END IF;
 SELECT unit INTO occ_unit FROM public.occasions WHERE id=p_occasion;
 IF p_action='list' THEN
   RETURN jsonb_build_object('subscriptions',(SELECT coalesce(jsonb_agg(public.webhook_subscription_dto_internal(id) ORDER BY created_at,id),'[]')
     FROM public.integration_webhook_subscriptions WHERE actor=auth.uid() AND binding=p_binding AND occasion=p_occasion AND organization=p_organization AND unit IS NOT DISTINCT FROM occ_unit AND state<>'deleted' AND expires_at>n));
 END IF;
 sid:=(p_input->>'subscriptionId')::uuid;
 IF sid IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='subscription identity required'; END IF;
 IF p_action='create' AND p_input->>'formId' IS NOT NULL THEN
   -- Acquire the FK's domain lock before the fanout fence. Checkout holds this
   -- form before emitting; reversing these locks would deadlock registration.
   PERFORM 1 FROM public.forms WHERE id=(p_input->>'formId')::bigint AND occasion=p_occasion FOR KEY SHARE;
   IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='form scope mismatch'; END IF;
 END IF;
 IF p_action IN ('create','update','delete','rotate_secret') THEN
   PERFORM pg_advisory_xact_lock(hashtextextended('integration-webhooks:'||p_organization,0));
 END IF;
 IF p_action<>'create' THEN
   SELECT * INTO s FROM public.integration_webhook_subscriptions WHERE id=sid AND actor=auth.uid() AND binding=p_binding
     AND occasion=p_occasion AND organization=p_organization AND unit IS NOT DISTINCT FROM occ_unit FOR NO KEY UPDATE;
   IF NOT FOUND OR s.expires_at<=n THEN RAISE insufficient_privilege USING MESSAGE='webhook subscription unavailable'; END IF;
 END IF;
 IF p_action IN ('create','update','delete','rotate_secret','test','redeliver') THEN
   cmd:=(p_input->>'commandId')::uuid;
   IF cmd IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='command identity required'; END IF;
   h:=encode(extensions.digest(convert_to(jsonb_build_array(p_action,p_occasion,p_organization,p_input)::text,'UTF8'),'sha256'),'hex');
   -- Actor-wide command lock also serializes test/redeliver commands.
   PERFORM pg_advisory_xact_lock(hashtextextended('webhook-command:'||auth.uid()||':'||cmd,0));
   SELECT * INTO prior FROM public.integration_webhook_commands WHERE actor=auth.uid() AND binding=p_binding AND id=cmd;
   IF FOUND THEN
     IF prior.request_hash<>h THEN RAISE invalid_parameter_value USING MESSAGE='webhook command changed'; END IF;
     IF prior.expires_at<=n THEN RAISE invalid_parameter_value USING MESSAGE='webhook command expired'; END IF;
     IF NOT EXISTS(SELECT 1 FROM public.integration_webhook_subscriptions x WHERE x.id=sid AND x.actor=auth.uid() AND x.binding=p_binding AND x.organization=p_organization AND x.occasion=p_occasion AND x.unit IS NOT DISTINCT FROM occ_unit AND x.expires_at>n AND (x.state<>'deleted' OR p_action='delete')) THEN
       RAISE insufficient_privilege USING MESSAGE='webhook receipt scope unavailable'; END IF;
     RETURN prior.response||jsonb_build_object('replayed',true);
   END IF;
 END IF;
 IF p_action='create' THEN
   IF (p_input->>'expiresAt')::timestamptz<=n OR (p_input->>'expiresAt')::timestamptz>n+interval '366 days'
     OR p_input->>'expiresAt' IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invalid subscription expiry'; END IF;
   IF EXISTS(SELECT 1 FROM public.integration_webhook_subscriptions WHERE id=sid) THEN RAISE invalid_parameter_value USING MESSAGE='subscription identity reused'; END IF;
   IF (SELECT count(*) FROM public.integration_webhook_subscriptions WHERE actor=auth.uid() AND binding=p_binding AND occasion=p_occasion AND state<>'deleted' AND expires_at>n)>=10 THEN
     RAISE program_limit_exceeded USING MESSAGE='subscription capacity exhausted'; END IF;
   IF p_input->>'formId' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.forms WHERE id=(p_input->>'formId')::bigint AND occasion=p_occasion) THEN
     RAISE invalid_parameter_value USING MESSAGE='form scope mismatch'; END IF;
   INSERT INTO public.integration_webhook_subscriptions(id,actor,organization,occasion,unit,form,binding,expires_at)
   VALUES(sid,auth.uid(),p_organization,p_occasion,occ_unit,(p_input->>'formId')::bigint,p_binding,(p_input->>'expiresAt')::timestamptz);
   result:=jsonb_build_object('subscription',public.webhook_subscription_dto_internal(sid));
 ELSIF p_action IN ('update','delete','rotate_secret') THEN
   IF s.state='deleted' OR s.version IS DISTINCT FROM (p_input->>'expectedVersion')::integer THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='webhook version changed'; END IF;
   v_state:=CASE WHEN p_action='delete' THEN 'deleted' WHEN p_action='update' THEN p_input->>'state' ELSE s.state END;
   IF v_state IS NULL OR v_state NOT IN ('active','paused','deleted') THEN RAISE invalid_parameter_value USING MESSAGE='invalid webhook state'; END IF;
   UPDATE public.integration_webhook_subscriptions SET state=v_state,version=version+1 WHERE id=sid;
   IF v_state='deleted' THEN UPDATE public.integration_webhook_deliveries SET state='blocked',lease=NULL,lease_until=NULL WHERE subscription=sid AND state IN ('pending','leased'); END IF;
   result:=jsonb_build_object('subscription',public.webhook_subscription_dto_internal(sid));
 ELSIF p_action='test' THEN
   IF s.state<>'active' THEN RAISE invalid_parameter_value USING MESSAGE='subscription inactive'; END IF;
   ev:=gen_random_uuid();
   payload:=jsonb_build_object('specversion','1.0','id',ev,'source','https://api.festapp.net/integrations/organizations/'||p_organization,
    'type','net.festapp.webhook.test.v1','subject','webhooks/test','time',to_char(n AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'datacontenttype','application/json','data',jsonb_build_object('test',true,'occasionId',p_occasion))::text;
   INSERT INTO public.integration_webhook_events(id,organization,occasion,form,event_type,body) VALUES(ev,p_organization,p_occasion,s.form,'net.festapp.webhook.test.v1',payload);
   INSERT INTO public.integration_webhook_deliveries(subscription,event) VALUES(sid,ev) RETURNING * INTO d;
   result:=jsonb_build_object('deliveryId',d.id);
 ELSIF p_action='redeliver' THEN
   IF s.state<>'active' THEN RAISE invalid_parameter_value USING MESSAGE='subscription inactive'; END IF;
   UPDATE public.integration_webhook_deliveries x SET state='pending',attempts=0,series=series+1,first_attempt_at=NULL,next_due=n,lease=NULL,lease_until=NULL
   WHERE x.id=(p_input->>'deliveryId')::uuid AND x.subscription=sid AND x.state IN ('succeeded','exhausted')
     AND EXISTS(SELECT 1 FROM public.integration_webhook_events e WHERE e.id=x.event AND e.body IS NOT NULL AND e.created_at>n-interval '7 days')
   RETURNING * INTO d;
   IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='delivery not redeliverable'; END IF;
   result:=jsonb_build_object('deliveryId',d.id);
 ELSIF p_action='deliveries' THEN
   RETURN jsonb_build_object('deliveries',(SELECT coalesce(jsonb_agg(x.dto ORDER BY x.id DESC),'[]') FROM (
    SELECT q.id,q.created_at,jsonb_build_object('id',q.id,'eventId',q.event,'state',q.state,'attempts',q.attempts,'series',q.series,'httpStatus',q.http_status,'errorCategory',q.error_category,'history',q.history) dto
    FROM public.integration_webhook_deliveries q WHERE q.subscription=sid AND ((p_input->>'before') IS NULL OR q.id<(p_input->>'before')::uuid)
    ORDER BY q.id DESC LIMIT 50) x));
 ELSIF p_action='claim' THEN
   IF s.state<>'active' THEN RETURN '{}'::jsonb; END IF;
   IF EXISTS(SELECT 1 FROM public.integration_webhook_deliveries WHERE subscription=sid AND state='leased' AND lease_until>n) THEN RETURN '{}'::jsonb; END IF;
   SELECT * INTO d FROM public.integration_webhook_deliveries WHERE subscription=sid AND
    ((state='pending' AND next_due<=n) OR (state='leased' AND lease_until<=n)) ORDER BY next_due,id LIMIT 1 FOR UPDATE SKIP LOCKED;
   IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
   IF d.attempts>=16 OR d.first_attempt_at<=n-interval '72 hours' OR NOT EXISTS(SELECT 1 FROM public.integration_webhook_events e WHERE e.id=d.event AND e.body IS NOT NULL AND e.created_at>n-interval '7 days') THEN
     UPDATE public.integration_webhook_deliveries SET state='exhausted',lease=NULL,lease_until=NULL WHERE id=d.id;
     RETURN '{}'::jsonb;
   END IF;
   IF NOT EXISTS(SELECT 1 FROM public.integration_webhook_events e WHERE e.id=d.event AND e.occasion=s.occasion AND e.organization=s.organization AND (s.form IS NULL OR e.form=s.form)
     AND (e.order_id IS NULL OR EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=e.order_id AND o.occasion=e.occasion AND o.form IS NOT DISTINCT FROM e.form))) THEN
     UPDATE public.integration_webhook_deliveries SET state='blocked',lease=NULL,lease_until=NULL WHERE id=d.id;
     RETURN '{}'::jsonb;
   END IF;
   UPDATE public.integration_webhook_deliveries SET state='leased',lease=gen_random_uuid(),lease_until=n+interval '30 seconds',
     attempts=attempts+1,first_attempt_at=coalesce(first_attempt_at,n) WHERE id=d.id RETURNING * INTO d;
   SELECT body INTO payload FROM public.integration_webhook_events WHERE id=d.event;
   RETURN jsonb_build_object('id',d.id,'eventId',d.event,'lease',d.lease,'attempt',d.attempts,'firstAttemptAt',d.first_attempt_at,'body',payload,'version',s.version);
 ELSIF p_action='authorize' THEN
   IF s.state<>'active' OR s.version IS DISTINCT FROM (p_input->>'expectedVersion')::integer THEN RAISE insufficient_privilege USING MESSAGE='dispatch binding changed'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.integration_webhook_deliveries q JOIN public.integration_webhook_events e ON e.id=q.event
     WHERE q.id=(p_input->>'deliveryId')::uuid AND q.subscription=sid AND q.lease=(p_input->>'lease')::uuid AND q.state='leased' AND q.lease_until>n
     AND e.body IS NOT NULL AND e.created_at>n-interval '7 days' AND e.occasion=s.occasion AND e.organization=s.organization AND (s.form IS NULL OR e.form=s.form)
     AND (e.order_id IS NULL OR EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=e.order_id AND o.occasion=e.occasion AND o.form IS NOT DISTINCT FROM e.form))) THEN
     RAISE insufficient_privilege USING MESSAGE='dispatch lease expired'; END IF;
   RETURN jsonb_build_object('authorized',true);
 ELSIF p_action='complete' THEN
   v_state:=p_input->>'state';
   IF v_state IS NULL OR v_state NOT IN ('succeeded','pending','exhausted','blocked') OR (p_input->>'httpStatus')::integer NOT BETWEEN 200 AND 599
      OR (p_input->>'errorCategory') IS NOT NULL AND p_input->>'errorCategory' NOT IN ('network','timeout','destination','http','revoked') THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid completion'; END IF;
   IF v_state='pending' AND ((p_input->>'nextDue')::timestamptz IS NULL OR (p_input->>'nextDue')::timestamptz<n OR (p_input->>'nextDue')::timestamptz>n+interval '72 hours') THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid retry deadline'; END IF;
   UPDATE public.integration_webhook_deliveries x SET state=v_state,lease=NULL,lease_until=NULL,
     next_due=coalesce((p_input->>'nextDue')::timestamptz,n),http_status=(p_input->>'httpStatus')::integer,error_category=p_input->>'errorCategory',
     history=(SELECT coalesce(jsonb_agg(value ORDER BY ord),'[]') FROM jsonb_array_elements(x.history||jsonb_build_array(jsonb_build_object('at',n,'series',x.series,'attempt',x.attempts,'status',p_input->'httpStatus','error',p_input->'errorCategory'))) WITH ORDINALITY v(value,ord) WHERE ord>jsonb_array_length(x.history)-14)
   WHERE x.id=(p_input->>'deliveryId')::uuid AND x.subscription=sid AND x.state='leased' AND x.lease=(p_input->>'lease')::uuid AND x.lease_until>n;
   IF NOT FOUND THEN RETURN jsonb_build_object('completed',false); END IF;
   IF (p_input->>'httpStatus')::integer=410 THEN UPDATE public.integration_webhook_subscriptions SET state='disabled',version=version+1 WHERE id=sid; END IF;
   RETURN jsonb_build_object('completed',true);

 END IF;
 result:=result||jsonb_build_object('commandId',cmd,'replayed',false);
 INSERT INTO public.integration_webhook_commands(id,binding,actor,request_hash,response,expires_at) VALUES(cmd,p_binding,auth.uid(),h,result,CASE WHEN p_action='create' THEN (p_input->>'expiresAt')::timestamptz ELSE s.expires_at END);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.integration_webhook_api_v1(bigint,bigint,bigint,text,text,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.integration_webhook_api_v1(bigint,bigint,bigint,text,text,jsonb) TO authenticated;

-- Existing pg_cron is the retention backstop even when every consent has
-- expired. This internal deletion-only job exposes no data and sends no HTTP.
CREATE OR REPLACE FUNCTION public.purge_integration_webhooks_internal()
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 UPDATE public.integration_webhook_events SET body=NULL WHERE id IN(SELECT id FROM public.integration_webhook_events WHERE body IS NOT NULL AND created_at<clock_timestamp()-interval '7 days' LIMIT 10000);
 UPDATE public.integration_webhook_deliveries SET state='blocked',lease=NULL,lease_until=NULL WHERE id IN(
   SELECT d.id FROM public.integration_webhook_deliveries d JOIN public.integration_webhook_subscriptions s ON s.id=d.subscription
   WHERE d.state IN ('pending','leased') AND (s.expires_at<=clock_timestamp() OR s.state='deleted') LIMIT 10000);
 UPDATE public.integration_webhook_deliveries SET state='exhausted',lease=NULL,lease_until=NULL WHERE id IN(
   SELECT d.id FROM public.integration_webhook_deliveries d JOIN public.integration_webhook_events e ON e.id=d.event
   WHERE d.state IN ('pending','leased') AND (d.state='pending' OR d.lease_until<=clock_timestamp())
     AND (e.body IS NULL OR d.first_attempt_at<=clock_timestamp()-interval '72 hours') LIMIT 10000);
 DELETE FROM public.integration_webhook_deliveries WHERE id IN(SELECT id FROM public.integration_webhook_deliveries WHERE created_at<clock_timestamp()-interval '30 days' LIMIT 10000);
 DELETE FROM public.integration_webhook_events WHERE id IN(SELECT e.id FROM public.integration_webhook_events e WHERE e.created_at<clock_timestamp()-interval '7 days' AND NOT EXISTS(SELECT 1 FROM public.integration_webhook_deliveries d WHERE d.event=e.id) LIMIT 10000);
 DELETE FROM public.integration_webhook_commands WHERE expires_at<=clock_timestamp();
 DELETE FROM public.integration_webhook_subscriptions WHERE expires_at<clock_timestamp()-interval '30 days';
END $$;
REVOKE ALL ON FUNCTION public.purge_integration_webhooks_internal() FROM PUBLIC,anon,authenticated,service_role;
SELECT cron.schedule('integration-webhook-retention','*/10 * * * *','SELECT public.purge_integration_webhooks_internal()');

-- SOURCE: eshop/create_ticket_order.sql
CREATE OR REPLACE FUNCTION public.create_ticket_order_internal_v1(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f bigint; target bigint; result jsonb;
BEGIN
 PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid)]);
 PERFORM public.check_occasion_writable((SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid));
 BEGIN
  SELECT id INTO f FROM public.forms WHERE key=(input_data->>'form')::uuid FOR UPDATE;
  IF f IS NULL THEN RAISE EXCEPTION 'Form not found'; END IF;
  target:=public.allocate_ticket_order_identity_internal(f);
  result:=public.finalize_ticket_order_internal_v1(target,input_data,false);
  IF coalesce((result->>'code')::integer,500)<>200 THEN RAISE EXCEPTION '%',result::text; END IF;
  PERFORM public.notification_center_order_internal(target,'order_created','created');
  PERFORM public.emit_order_webhook_internal(target);
  RETURN result;
 EXCEPTION WHEN SQLSTATE 'PT429' THEN
  RETURN jsonb_build_object('code',429,'errorCode','ABUSE_LIMIT_EXCEEDED','message','Capacity is temporarily limited. Try again later.');
 WHEN OTHERS THEN
  RETURN CASE WHEN left(SQLERRM,1)='{' THEN SQLERRM::jsonb ELSE jsonb_build_object('code',1013,'message',SQLERRM) END;
 END;
END $$;
REVOKE ALL ON FUNCTION public.create_ticket_order_internal_v1(jsonb) FROM PUBLIC,anon,authenticated;
