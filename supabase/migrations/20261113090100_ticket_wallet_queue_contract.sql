-- Wallet queue forward. Apply only through the documented pause/drain cutover.
DROP FUNCTION IF EXISTS public.finish_ticket_wallet(bigint,uuid,boolean);

-- SOURCE: ticket_wallet/schema.sql
-- Provider metadata only. Deliberately retain identities when a ticket is deleted.
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_integrations (
 organization bigint PRIMARY KEY REFERENCES public.organizations(id),
 issuer text NOT NULL CHECK(issuer ~ '^[0-9]+$'),
 environment text NOT NULL CHECK(environment ~ '^[a-zA-Z0-9_-]{1,40}$'),
 publishing_ready boolean NOT NULL DEFAULT false,
 web_origin text NOT NULL CHECK(web_origin ~ '^https://[^/#?]+$'),
 badge_urls jsonb NOT NULL DEFAULT '{}',
 next_request_at timestamptz NOT NULL DEFAULT now(),
 paused boolean NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_capabilities (
 ticket_id bigint PRIMARY KEY, organization bigint NOT NULL, occasion bigint NOT NULL,
 order_id bigint NOT NULL, generation integer NOT NULL DEFAULT 1,
 token_hash text UNIQUE NOT NULL CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 sealed jsonb NOT NULL, recipient text NOT NULL, message_id uuid NOT NULL,
 expires_at timestamptz NOT NULL, event_end_at timestamptz, revoked_at timestamptz, reissue_after timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_objects (
 ticket_id bigint PRIMARY KEY, organization bigint NOT NULL, occasion bigint NOT NULL,
 issuer text NOT NULL, environment text NOT NULL, object_id text UNIQUE NOT NULL,
 class_id text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, ticket_id bigint NOT NULL,
 generation integer NOT NULL, token_hash text NOT NULL, actor uuid NOT NULL, action text NOT NULL CHECK(action IN ('revoke','reissue')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ticket_wallet_revoked_hash ON eshop.ticket_wallet_audit(token_hash);
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_limits (
 key text PRIMARY KEY, window_at timestamptz NOT NULL, attempts integer NOT NULL
);
ALTER TABLE eshop.ticket_wallet_integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_wallet_capabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_wallet_objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_wallet_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_wallet_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.ticket_wallet_integrations,eshop.ticket_wallet_capabilities,eshop.ticket_wallet_objects,eshop.ticket_wallet_audit,eshop.ticket_wallet_limits FROM PUBLIC,anon,authenticated;

-- SOURCE: ticket_wallet/maintenance.sql
-- Bounded, restartable fanout. A new scope version resets the cursor on its next batch.
CREATE OR REPLACE FUNCTION public.maintain_ticket_wallet(p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s eshop.ticket_wallet_work; w eshop.ticket_wallet_objects; n integer:=0; last_id bigint; batch_size integer:=greatest(1,least(1000,p_limit));
BEGIN
 PERFORM public.require_service_role();
 -- Idempotent adoption includes never-synced, deleted and uncertain identities.
 -- No fake applied version. Legacy leases must have drained before cutover.
 FOR w IN SELECT o.* FROM eshop.ticket_wallet_objects o WHERE NOT EXISTS(
  SELECT 1 FROM eshop.ticket_wallet_work q WHERE q.kind='object' AND q.resource=o.object_id) OR NOT EXISTS(
  SELECT 1 FROM eshop.ticket_wallet_work cls WHERE cls.kind='class' AND cls.resource=o.class_id)
  ORDER BY o.ticket_id LIMIT batch_size LOOP
  PERFORM public.refresh_ticket_wallet_term_internal(w.ticket_id);
  PERFORM public.enqueue_wallet_class_internal(w.ticket_id);
  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[w.ticket_id]);n:=n+1;
 END LOOP;
 SELECT * INTO s FROM eshop.ticket_wallet_work WHERE kind IN ('occasion','organization') AND requested>applied AND due_at<=now()
 ORDER BY dirty_since,kind,resource LIMIT 1 FOR UPDATE SKIP LOCKED;
 IF FOUND THEN
  IF s.cursor_version<>s.requested THEN s.cursor_ticket:=0; END IF;
  last_id:=s.cursor_ticket;
  FOR w IN SELECT * FROM eshop.ticket_wallet_objects WHERE organization=s.organization
   AND (s.kind='organization' OR occasion=s.occasion) AND ticket_id>s.cursor_ticket ORDER BY ticket_id LIMIT batch_size LOOP
   PERFORM public.refresh_ticket_wallet_term_internal(w.ticket_id);
   PERFORM public.enqueue_wallet_class_internal(w.ticket_id);
   PERFORM public.enqueue_ticket_wallet_internal(ARRAY[w.ticket_id]);last_id:=w.ticket_id;n:=n+1;
  END LOOP;
  UPDATE eshop.ticket_wallet_work SET cursor_ticket=last_id,cursor_version=s.requested,captured=s.requested,
   applied=CASE WHEN NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_objects WHERE organization=s.organization AND
    (s.kind='organization' OR occasion=s.occasion) AND ticket_id>last_id) THEN s.requested ELSE applied END
   WHERE provider=s.provider AND kind=s.kind AND resource=s.resource;
 END IF;
 -- Class repair is independently fenced; never acquire a class after object work.
 FOR s IN SELECT * FROM eshop.ticket_wallet_work WHERE kind='class' AND repair_at<=now()
  ORDER BY repair_at,resource LIMIT batch_size FOR UPDATE SKIP LOCKED LOOP
  UPDATE eshop.ticket_wallet_work SET requested=requested+1,due_at=least(due_at,now()),
   dirty_since=CASE WHEN requested=applied THEN now() ELSE dirty_since END,repair_at=now()+interval '1 day'
   WHERE provider=s.provider AND kind=s.kind AND resource=s.resource;
 END LOOP;
 -- Slow remote repair and precise time transitions use the same work owner.
 FOR s IN SELECT * FROM eshop.ticket_wallet_work WHERE kind='object'
  AND (repair_at<=now() OR boundary_at<=now()) ORDER BY least(repair_at,coalesce(boundary_at,repair_at)),resource LIMIT batch_size FOR UPDATE SKIP LOCKED LOOP
  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[s.ticket_id]);
  UPDATE eshop.ticket_wallet_work SET repair_at=now()+interval '1 day',boundary_at=NULL WHERE provider=s.provider AND kind=s.kind AND resource=s.resource;
  n:=n+1;
 END LOOP;
 RETURN jsonb_build_object('scheduled',n);
END $$;
REVOKE ALL ON FUNCTION public.maintain_ticket_wallet(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.maintain_ticket_wallet(integer) TO service_role;

-- SOURCE: ticket_wallet/sync.sql
-- Registration precedes external I/O. Claims lock only the scheduling row.
CREATE OR REPLACE FUNCTION public.claim_ticket_wallet(p_ticket bigint DEFAULT NULL,p_object text DEFAULT NULL,p_class text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE q eshop.ticket_wallet_work; w eshop.ticket_wallet_objects; c eshop.ticket_wallet_capabilities;
 i eshop.ticket_wallet_integrations; lease_id uuid:=extensions.gen_random_uuid(); projection jsonb; added boolean;
BEGIN
 PERFORM public.require_service_role();
 IF p_ticket IS NOT NULL AND p_object IS NOT NULL THEN
  SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket AND revoked_at IS NULL AND expires_at>now();
  SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=c.organization;
  IF c.ticket_id IS NULL OR i.organization IS NULL OR i.paused OR p_object NOT LIKE i.issuer||'.%' OR p_class NOT LIKE i.issuer||'.%' THEN RETURN NULL; END IF;
  INSERT INTO eshop.ticket_wallet_objects(ticket_id,organization,occasion,issuer,environment,object_id,class_id)
  VALUES(c.ticket_id,c.organization,c.occasion,i.issuer,i.environment,p_object,p_class) ON CONFLICT(ticket_id) DO NOTHING;
  added:=FOUND;
  IF added THEN PERFORM public.enqueue_wallet_class_internal(p_ticket); END IF;
  -- An explicit Save retries through the same owner; it cannot steal a lease.
  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket]);
 END IF;
 WITH tenant_turns AS MATERIALIZED (
  SELECT organization,max(claimed_at) last_claim FROM eshop.ticket_wallet_work GROUP BY organization
 )
 SELECT work.* INTO q FROM eshop.ticket_wallet_work work
 JOIN tenant_turns turns ON turns.organization=work.organization WHERE kind IN ('class','object')
 AND requested>applied AND due_at<=now() AND (lease_until IS NULL OR lease_until<=clock_timestamp())
 AND EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations integ WHERE integ.organization=work.organization AND NOT integ.paused)
 AND (p_ticket IS NULL OR (kind='object' AND ticket_id=p_ticket) OR (kind='class' AND resource=(SELECT class_id FROM eshop.ticket_wallet_objects WHERE ticket_id=p_ticket)))
 AND (kind='class' OR EXISTS(SELECT 1 FROM eshop.ticket_wallet_work cls JOIN eshop.ticket_wallet_objects obj ON obj.class_id=cls.resource
  WHERE cls.kind='class' AND obj.ticket_id=work.ticket_id AND cls.applied>0)
  OR NOT EXISTS(SELECT 1 FROM eshop.tickets WHERE id=work.ticket_id)
  OR EXISTS(SELECT 1 FROM eshop.ticket_wallet_capabilities WHERE ticket_id=work.ticket_id AND revoked_at IS NOT NULL))
 ORDER BY turns.last_claim,dirty_since,CASE WHEN kind='class' THEN 0 ELSE 1 END,resource LIMIT 1 FOR UPDATE OF work SKIP LOCKED;
 IF q.resource IS NULL THEN RETURN NULL; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('wallet-claim:'||q.organization,0));
 IF NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=q.organization AND NOT paused) THEN RETURN NULL; END IF;
 UPDATE eshop.ticket_wallet_work SET claimed_at=clock_timestamp(),lease=lease_id,lease_until=clock_timestamp()+interval '45 seconds',captured=requested,
 boundary_at=CASE WHEN q.kind='object' THEN (SELECT min(t) FROM (
  SELECT o.start_time t FROM public.occasions o WHERE o.id=q.occasion UNION ALL
  SELECT o.end_time FROM public.occasions o WHERE o.id=q.occasion UNION ALL
  SELECT cap.expires_at FROM eshop.ticket_wallet_capabilities cap WHERE cap.ticket_id=q.ticket_id) times WHERE t>now()) ELSE NULL END
 WHERE provider=q.provider AND kind=q.kind AND resource=q.resource;
 SELECT * INTO w FROM eshop.ticket_wallet_objects WHERE ticket_id=q.ticket_id;
 projection:=public.ticket_wallet_projection_internal(q.ticket_id);
 IF q.kind='class' THEN
  SELECT jsonb_build_object('state','ACTIVE','ticket',jsonb_build_object('ticket_symbol','class-metadata'),
   'branding',(SELECT jsonb_build_object('APP_NAME',data->'APP_NAME','DEFAULT_URL',data->'DEFAULT_URL','WALLET_LOGO_URL',data->'WALLET_LOGO_URL') FROM public.organizations WHERE id=q.organization),
   'occasion',jsonb_build_object('id',o.id,'title',o.title,'start_time',o.start_time,'end_time',o.end_time,'data',o.data,
   'ticketFeature',(SELECT f FROM jsonb_array_elements(o.features) f WHERE f->>'code'='ticket')))
   INTO projection FROM public.occasions o WHERE id=q.occasion AND organization=q.organization;
 END IF;
 RETURN jsonb_build_object('kind',q.kind,'resource',q.resource,'version',q.requested,'ticketId',w.ticket_id,'organization',w.organization,
 'occasion',w.occasion,'issuer',w.issuer,'environment',w.environment,'objectId',w.object_id,'classId',w.class_id,'lease',lease_id,'projection',projection);
END $$;

-- A globally unique lease identifies either class or object work.
CREATE OR REPLACE FUNCTION public.reserve_ticket_wallet_request(p_ticket bigint,p_lease uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE q eshop.ticket_wallet_work; w eshop.ticket_wallet_objects; slot timestamptz;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO q FROM eshop.ticket_wallet_work WHERE ticket_id=p_ticket AND lease=p_lease AND lease_until>clock_timestamp()+interval '10 seconds' FOR UPDATE;
 IF q.resource IS NULL THEN RAISE EXCEPTION 'wallet_lease_lost'; END IF;
 SELECT * INTO w FROM eshop.ticket_wallet_objects WHERE ticket_id=q.ticket_id;
 PERFORM pg_advisory_xact_lock(hashtextextended('google-wallet:'||w.issuer,0));
 IF NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=w.organization AND issuer=w.issuer AND environment=w.environment) THEN RAISE EXCEPTION 'wallet_identity_changed'; END IF;
 SELECT greatest(max(next_request_at),clock_timestamp()) INTO slot FROM eshop.ticket_wallet_integrations WHERE issuer=w.issuer;
 IF slot IS NULL OR slot>clock_timestamp()+interval '2 seconds' THEN RAISE EXCEPTION 'wallet_capacity'; END IF;
 UPDATE eshop.ticket_wallet_integrations SET next_request_at=slot+interval '125 milliseconds' WHERE issuer=w.issuer;
 RETURN greatest(0,ceil(extract(epoch FROM slot-clock_timestamp())*1000))::integer;
END $$;

CREATE OR REPLACE FUNCTION public.finish_ticket_wallet(p_ticket bigint,p_lease uuid,p_ok boolean,p_error text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.ticket_wallet_work q SET lease=NULL,lease_until=NULL,
 applied=CASE WHEN p_ok THEN captured ELSE applied END,
 last_success=CASE WHEN p_ok THEN now() ELSE last_success END,
 due_at=CASE WHEN p_ok THEN now() ELSE now()+make_interval(secs=>least(3600,CASE WHEN p_error='wallet_capacity' THEN 5 ELSE 15*power(2,least(failures,8)) END)::integer) END,
 failures=CASE WHEN p_ok THEN 0 ELSE failures+CASE WHEN p_error='wallet_capacity' THEN 0 ELSE 1 END END,last_error=CASE WHEN p_ok THEN NULL WHEN p_error='wallet_capacity' THEN 'quota_wait' WHEN p_error='wallet_class_pending' THEN 'class_pending' ELSE 'google_sync_unavailable' END
 WHERE ticket_id=p_ticket AND lease=p_lease AND lease_until>clock_timestamp();
 RETURN FOUND;
END $$;

CREATE OR REPLACE FUNCTION public.ticket_wallet_health()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT jsonb_build_object('objects',(SELECT count(*) FROM eshop.ticket_wallet_objects),
 'due',count(*) FILTER(WHERE requested>applied AND due_at<=now()),'dirty',count(*) FILTER(WHERE requested>applied),
 'versionGap',coalesce(sum(requested-applied),0),'oldestDirty',min(dirty_since) FILTER(WHERE requested>applied),
 'leased',count(*) FILTER(WHERE lease_until>now()),'retry',count(*) FILTER(WHERE failures>0 AND failures<10),'quotaWait',count(*) FILTER(WHERE last_error='quota_wait'),
 'persistentErrors',count(*) FILTER(WHERE failures>=10),'lastSuccess',max(last_success),
 'quotaWaitUntil',(SELECT max(next_request_at) FROM eshop.ticket_wallet_integrations),
 'scopes',coalesce(jsonb_agg(jsonb_build_object('kind',kind,'resource',resource,'cursor',cursor_ticket,'version',cursor_version)) FILTER(WHERE kind IN ('occasion','organization') AND requested>applied),'[]')) FROM eshop.ticket_wallet_work);
END $$;
REVOKE ALL ON FUNCTION public.claim_ticket_wallet(bigint,text,text),public.reserve_ticket_wallet_request(bigint,uuid),public.finish_ticket_wallet(bigint,uuid,boolean,text),public.ticket_wallet_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_ticket_wallet(bigint,text,text),public.reserve_ticket_wallet_request(bigint,uuid),public.finish_ticket_wallet(bigint,uuid,boolean,text),public.ticket_wallet_health() TO service_role;

-- SOURCE: ticket_wallet/worker.sql
-- Disabled until operations supplies the canonical endpoint; no network activity on migration.
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_worker (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 worker_url text CHECK(worker_url ~ '^https://[^ ]+/functions/v1/sync-ticket-wallet$')
);
ALTER TABLE eshop.ticket_wallet_worker ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.ticket_wallet_worker FROM PUBLIC,anon,authenticated;
INSERT INTO eshop.ticket_wallet_worker(singleton) VALUES(true) ON CONFLICT DO NOTHING;
CREATE OR REPLACE FUNCTION public.wake_ticket_wallet_worker()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE target text;
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.maintain_ticket_wallet(100);
 SELECT worker_url INTO target FROM eshop.ticket_wallet_worker WHERE singleton;
 IF target IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_work w JOIN eshop.ticket_wallet_integrations i ON i.organization=w.organization WHERE NOT i.paused AND w.kind IN ('class','object') AND w.requested>w.applied AND w.due_at<=now() AND (w.lease_until IS NULL OR w.lease_until<=now())) THEN RETURN; END IF;
 PERFORM net.http_post(url:=target,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
END $$;
REVOKE ALL ON FUNCTION public.wake_ticket_wallet_worker() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.wake_ticket_wallet_worker() TO service_role;
-- Deployment schedules this service-only owner using the existing trusted cron owner.
-- No trigger, paid dispatch or tenant activation is performed by the migration.

-- The existing scheduler is owned by control-plane postgres. Upgrade that single
-- job with automation/ticket-wallet/update-control-plane-scheduler.sql after probes.
-- No runtime-DB schedule is installed by this source.

-- SOURCE: ticket_wallet/contract.sql
-- Install only under tenant pause, after the old worker has drained.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM eshop.ticket_wallet_objects WHERE lease_until>clock_timestamp()) THEN
  RAISE EXCEPTION 'wallet_legacy_leases_not_drained';
 END IF;
 IF EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE NOT paused) THEN
  RAISE EXCEPTION 'wallet_cutover_requires_pause';
 END IF;
END $$;
DROP INDEX IF EXISTS eshop.ticket_wallet_due;
ALTER TABLE eshop.ticket_wallet_objects DROP COLUMN IF EXISTS lease,DROP COLUMN IF EXISTS lease_until,
 DROP COLUMN IF EXISTS next_attempt,DROP COLUMN IF EXISTS last_synced,DROP COLUMN IF EXISTS failures,DROP COLUMN IF EXISTS last_error;

-- Historical bootstrap could install a dormant runtime-DB schedule. The actual
-- deployment scheduler is the single verified control-plane job, updated separately.
DO $$ DECLARE old_job bigint; BEGIN
 IF EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
  FOR old_job IN SELECT jobid FROM cron.job WHERE jobname='festapp_google_ticket_wallet' LOOP
   PERFORM cron.unschedule(old_job);
  END LOOP;
 END IF;
END $$;
