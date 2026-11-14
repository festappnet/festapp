-- Apple Wallet device updates and certificate-authenticated APNs scheduling.

-- SOURCE: ticket_wallet/apple_updates_schema.sql
-- Provider-local presentation and registration state; admission stays canonical.
CREATE SEQUENCE IF NOT EXISTS eshop.apple_ticket_wallet_update_tag;
CREATE TABLE IF NOT EXISTS eshop.apple_ticket_wallet_passes (
 ticket_id bigint PRIMARY KEY, organization bigint NOT NULL, occasion bigint NOT NULL,
 environment text NOT NULL, serial text UNIQUE NOT NULL, pass_type text NOT NULL, team text NOT NULL,
 auth_hash text NOT NULL CHECK(auth_hash ~ '^[a-f0-9]{64}$'), auth_sealed jsonb NOT NULL,
 projection jsonb NOT NULL, projection_hash text NOT NULL,
 update_tag bigint NOT NULL DEFAULT nextval('eshop.apple_ticket_wallet_update_tag'),
 updated_at timestamptz NOT NULL DEFAULT date_trunc('second',clock_timestamp()),
 next_check timestamptz NOT NULL DEFAULT now(), lease uuid, lease_until timestamptz,
 failures integer NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS apple_ticket_wallet_due ON eshop.apple_ticket_wallet_passes(next_check,ticket_id);
CREATE TABLE IF NOT EXISTS eshop.apple_ticket_wallet_devices (
 device text NOT NULL, pass_type text NOT NULL, serial text NOT NULL REFERENCES eshop.apple_ticket_wallet_passes(serial),
 push_token text NOT NULL, notified_tag bigint NOT NULL DEFAULT 0,
 PRIMARY KEY(device,pass_type,serial)
);
ALTER TABLE eshop.apple_ticket_wallet_passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.apple_ticket_wallet_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.apple_ticket_wallet_passes,eshop.apple_ticket_wallet_devices FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE eshop.apple_ticket_wallet_update_tag FROM PUBLIC,anon,authenticated;

-- SOURCE: ticket_wallet/apple_updates.sql
CREATE OR REPLACE FUNCTION public.refresh_apple_ticket_wallet_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE w eshop.apple_ticket_wallet_passes; v_projection jsonb; fingerprint text;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO w FROM eshop.apple_ticket_wallet_passes WHERE ticket_id=p_ticket FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 PERFORM public.refresh_ticket_wallet_term_internal(p_ticket);
 v_projection:=public.ticket_wallet_projection_internal(p_ticket);
 -- Deleted/revoked tickets retain the last presentation, marked void, without losing identity.
 IF v_projection->>'state'='INACTIVE' THEN v_projection:=w.projection||jsonb_build_object('state','INACTIVE'); END IF;
 fingerprint:=encode(extensions.digest(v_projection::text,'sha256'),'hex');
 IF fingerprint IS DISTINCT FROM w.projection_hash THEN
  UPDATE eshop.apple_ticket_wallet_passes SET projection=v_projection,projection_hash=fingerprint,
   update_tag=nextval('eshop.apple_ticket_wallet_update_tag'),
   updated_at=greatest(date_trunc('second',clock_timestamp()),date_trunc('second',w.updated_at)+interval '1 second'),next_check=now()
  WHERE ticket_id=p_ticket;
 END IF;
END $$;

CREATE OR REPLACE FUNCTION public.register_apple_ticket_wallet(p_capability_hash text,p_serial text,p_pass_type text,p_team text,p_auth_hash text DEFAULT NULL,p_sealed jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.ticket_wallet_capabilities; i eshop.ticket_wallet_integrations; w eshop.apple_ticket_wallet_passes; v_projection jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_capability_hash AND revoked_at IS NULL AND expires_at>now() FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=c.organization AND apple_publishing_ready AND NOT paused;
 IF NOT FOUND OR i.apple_pass_type_identifier IS DISTINCT FROM p_pass_type OR i.apple_team_identifier IS DISTINCT FROM p_team
 OR p_serial !~ '^festapp_[a-f0-9]{64}$' THEN RETURN NULL; END IF;
 v_projection:=public.ticket_wallet_projection_internal(c.ticket_id);
 IF v_projection->>'state' NOT IN ('ACTIVE','COMPLETED') THEN RETURN NULL; END IF;
 SELECT * INTO w FROM eshop.apple_ticket_wallet_passes WHERE ticket_id=c.ticket_id;
 IF w.ticket_id IS NULL AND p_auth_hash ~ '^[a-f0-9]{64}$' AND p_sealed IS NOT NULL THEN
  INSERT INTO eshop.apple_ticket_wallet_passes(ticket_id,organization,occasion,environment,serial,pass_type,team,auth_hash,auth_sealed,projection,projection_hash)
  VALUES(c.ticket_id,c.organization,c.occasion,i.environment,p_serial,p_pass_type,p_team,p_auth_hash,p_sealed,v_projection,encode(extensions.digest(v_projection::text,'sha256'),'hex'))
  ON CONFLICT(ticket_id) DO NOTHING;
 END IF;
 PERFORM public.refresh_apple_ticket_wallet_internal(c.ticket_id);
 SELECT * INTO w FROM eshop.apple_ticket_wallet_passes WHERE ticket_id=c.ticket_id;
 IF w.ticket_id IS NULL OR w.serial IS DISTINCT FROM p_serial OR w.environment IS DISTINCT FROM i.environment
 OR w.pass_type IS DISTINCT FROM p_pass_type OR w.team IS DISTINCT FROM p_team THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('ticketId',w.ticket_id,'organization',w.organization,'occasion',w.occasion,'environment',w.environment,
  'serial',w.serial,'passTypeIdentifier',w.pass_type,'teamIdentifier',w.team,'authSealed',w.auth_sealed,'authHash',w.auth_hash,
  'projection',w.projection,'updateTag',w.update_tag::text,'updatedAt',w.updated_at);
END $$;

CREATE OR REPLACE FUNCTION public.get_apple_ticket_wallet(p_pass_type text,p_serial text,p_auth_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE w eshop.apple_ticket_wallet_passes;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO w FROM eshop.apple_ticket_wallet_passes WHERE pass_type=p_pass_type AND serial=p_serial AND auth_hash=p_auth_hash;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=w.organization AND NOT paused
 AND apple_pass_type_identifier=w.pass_type AND apple_team_identifier=w.team AND environment=w.environment) THEN RETURN NULL; END IF;
 PERFORM public.refresh_apple_ticket_wallet_internal(w.ticket_id);
 SELECT * INTO w FROM eshop.apple_ticket_wallet_passes WHERE ticket_id=w.ticket_id;
 RETURN jsonb_build_object('ticketId',w.ticket_id,'organization',w.organization,'occasion',w.occasion,'environment',w.environment,
  'serial',w.serial,'passTypeIdentifier',w.pass_type,'teamIdentifier',w.team,'authSealed',w.auth_sealed,'authHash',w.auth_hash,
  'projection',w.projection,'updateTag',w.update_tag::text,'updatedAt',w.updated_at);
END $$;

CREATE OR REPLACE FUNCTION public.register_apple_wallet_device(p_device text,p_pass_type text,p_serial text,p_auth_hash text,p_push_token text DEFAULT NULL,p_remove boolean DEFAULT false)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE context jsonb; existing boolean;
BEGIN
 PERFORM public.require_service_role();
 IF (length(p_device) NOT BETWEEN 16 AND 256 OR p_device !~ '^[A-Za-z0-9._-]+$') OR p_device IS NULL THEN RETURN 401; END IF;
 context:=public.get_apple_ticket_wallet(p_pass_type,p_serial,p_auth_hash);
 IF context IS NULL THEN RETURN 401; END IF;
 IF p_remove THEN
  DELETE FROM eshop.apple_ticket_wallet_devices WHERE device=p_device AND pass_type=p_pass_type AND serial=p_serial;RETURN 200;
 END IF;
 IF p_push_token IS NULL OR (length(p_push_token) NOT BETWEEN 32 AND 512 OR p_push_token !~ '^[a-fA-F0-9]+$') THEN RETURN 400; END IF;
 SELECT EXISTS(SELECT 1 FROM eshop.apple_ticket_wallet_devices WHERE device=p_device AND pass_type=p_pass_type AND serial=p_serial) INTO existing;
 INSERT INTO eshop.apple_ticket_wallet_devices(device,pass_type,serial,push_token,notified_tag)
 VALUES(p_device,p_pass_type,p_serial,p_push_token,0)
 ON CONFLICT(device,pass_type,serial) DO UPDATE SET push_token=excluded.push_token,notified_tag=CASE WHEN apple_ticket_wallet_devices.push_token IS DISTINCT FROM excluded.push_token THEN 0 ELSE apple_ticket_wallet_devices.notified_tag END;
 UPDATE eshop.apple_ticket_wallet_passes SET next_check=now() WHERE serial=p_serial;
 RETURN CASE WHEN existing THEN 200 ELSE 201 END;
END $$;

CREATE OR REPLACE FUNCTION public.list_apple_wallet_updates(p_device text,p_pass_type text,p_since text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; latest bigint; ticket bigint;
BEGIN
 PERFORM public.require_service_role();
 IF p_device IS NULL OR (length(p_device) NOT BETWEEN 16 AND 256 OR p_device !~ '^[A-Za-z0-9._-]+$') OR (p_since IS NOT NULL AND p_since !~ '^[0-9]{1,18}$') THEN RETURN NULL; END IF;
 -- Device library identifiers are opaque Apple capabilities, never a customer/ticket lookup.
 FOR ticket IN SELECT w.ticket_id FROM eshop.apple_ticket_wallet_passes w JOIN eshop.apple_ticket_wallet_devices d ON d.serial=w.serial AND d.pass_type=w.pass_type
 WHERE d.device=p_device AND d.pass_type=p_pass_type LOOP
  PERFORM public.refresh_apple_ticket_wallet_internal(ticket);
 END LOOP;
 SELECT jsonb_agg(w.serial ORDER BY w.serial),max(w.update_tag) INTO result,latest
 FROM eshop.apple_ticket_wallet_passes w JOIN eshop.apple_ticket_wallet_devices d ON d.serial=w.serial AND d.pass_type=w.pass_type
 JOIN eshop.ticket_wallet_integrations i ON i.organization=w.organization AND NOT i.paused
 WHERE d.device=p_device AND d.pass_type=p_pass_type AND (p_since IS NULL OR w.update_tag>p_since::bigint);
 IF result IS NULL THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('serialNumbers',result,'lastUpdated',latest::text);
END $$;

CREATE OR REPLACE FUNCTION public.claim_apple_ticket_wallet()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE w eshop.apple_ticket_wallet_passes; lease_id uuid:=extensions.gen_random_uuid();
BEGIN
 PERFORM public.require_service_role();
 SELECT a.* INTO w FROM eshop.apple_ticket_wallet_passes a JOIN eshop.ticket_wallet_integrations i ON i.organization=a.organization
 WHERE NOT i.paused AND i.apple_pass_type_identifier=a.pass_type AND i.apple_team_identifier=a.team AND i.environment=a.environment
 AND a.next_check<=now() AND (a.lease_until IS NULL OR a.lease_until<=clock_timestamp())
 ORDER BY a.next_check,a.ticket_id FOR UPDATE OF a SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN NULL; END IF;
 PERFORM public.refresh_apple_ticket_wallet_internal(w.ticket_id);
 UPDATE eshop.apple_ticket_wallet_passes SET lease=lease_id,lease_until=clock_timestamp()+interval '45 seconds',next_check=now()+interval '1 minute' WHERE ticket_id=w.ticket_id RETURNING * INTO w;
 RETURN jsonb_build_object('ticketId',w.ticket_id,'lease',lease_id,'passTypeIdentifier',w.pass_type,'teamIdentifier',w.team,'updateTag',w.update_tag::text);
END $$;

CREATE OR REPLACE FUNCTION public.apple_wallet_push_targets(p_ticket bigint,p_lease uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE w eshop.apple_ticket_wallet_passes;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO w FROM eshop.apple_ticket_wallet_passes WHERE ticket_id=p_ticket AND lease=p_lease AND lease_until>clock_timestamp()+interval '5 seconds';
 IF NOT FOUND THEN RAISE EXCEPTION 'wallet_lease_lost'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(x),'[]') FROM (SELECT DISTINCT d.push_token AS "pushToken" FROM eshop.apple_ticket_wallet_devices d
 WHERE d.serial=w.serial AND d.pass_type=w.pass_type AND d.notified_tag<w.update_tag ORDER BY d.push_token LIMIT 20) x);
END $$;

CREATE OR REPLACE FUNCTION public.finish_apple_wallet_push(p_ticket bigint,p_lease uuid,p_push_token text,p_tag bigint,p_invalid boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE w eshop.apple_ticket_wallet_passes;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO w FROM eshop.apple_ticket_wallet_passes WHERE ticket_id=p_ticket AND lease=p_lease AND lease_until>clock_timestamp() FOR UPDATE;
 IF NOT FOUND OR p_tag>w.update_tag THEN RETURN false; END IF;
 IF p_invalid THEN DELETE FROM eshop.apple_ticket_wallet_devices WHERE pass_type=w.pass_type AND push_token=p_push_token;
 ELSE UPDATE eshop.apple_ticket_wallet_devices SET notified_tag=greatest(notified_tag,p_tag) WHERE serial=w.serial AND pass_type=w.pass_type AND push_token=p_push_token;END IF;
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.finish_apple_ticket_wallet(p_ticket bigint,p_lease uuid,p_ok boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.apple_ticket_wallet_passes w SET lease=NULL,lease_until=NULL,
  failures=CASE WHEN p_ok THEN 0 ELSE least(failures+1,20) END,
  next_check=CASE WHEN NOT p_ok THEN now()+make_interval(secs=>least(3600,15*power(2,least(failures,8)))::integer)
  WHEN EXISTS(SELECT 1 FROM eshop.apple_ticket_wallet_devices d WHERE d.serial=w.serial AND d.pass_type=w.pass_type AND d.notified_tag<w.update_tag) THEN now()
  ELSE now()+interval '1 minute' END
 WHERE ticket_id=p_ticket AND lease=p_lease AND lease_until>clock_timestamp();
 RETURN FOUND;
END $$;

CREATE OR REPLACE FUNCTION public.allow_apple_wallet_request(p_source text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE n integer;
BEGIN
 PERFORM public.require_service_role();
 IF p_source IS NULL OR p_source !~ '^[a-f0-9]{64}$' THEN RETURN false; END IF;
 INSERT INTO eshop.ticket_wallet_limits(key,window_at,attempts) VALUES('apple:'||p_source,now(),1)
 ON CONFLICT(key) DO UPDATE SET attempts=CASE WHEN ticket_wallet_limits.window_at<now()-interval '1 minute' THEN 1 ELSE ticket_wallet_limits.attempts+1 END,
 window_at=CASE WHEN ticket_wallet_limits.window_at<now()-interval '1 minute' THEN now() ELSE ticket_wallet_limits.window_at END RETURNING attempts INTO n;
 DELETE FROM eshop.ticket_wallet_limits WHERE window_at<now()-interval '10 minutes';
 RETURN n<=120;
END $$;
REVOKE ALL ON FUNCTION public.refresh_apple_ticket_wallet_internal(bigint),public.register_apple_ticket_wallet(text,text,text,text,text,jsonb),public.get_apple_ticket_wallet(text,text,text),public.register_apple_wallet_device(text,text,text,text,text,boolean),public.list_apple_wallet_updates(text,text,text),public.claim_apple_ticket_wallet(),public.apple_wallet_push_targets(bigint,uuid),public.finish_apple_wallet_push(bigint,uuid,text,bigint,boolean),public.finish_apple_ticket_wallet(bigint,uuid,boolean),public.allow_apple_wallet_request(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_apple_ticket_wallet_internal(bigint),public.register_apple_ticket_wallet(text,text,text,text,text,jsonb),public.get_apple_ticket_wallet(text,text,text),public.register_apple_wallet_device(text,text,text,text,text,boolean),public.list_apple_wallet_updates(text,text,text),public.claim_apple_ticket_wallet(),public.apple_wallet_push_targets(bigint,uuid),public.finish_apple_wallet_push(bigint,uuid,text,bigint,boolean),public.finish_apple_ticket_wallet(bigint,uuid,boolean),public.allow_apple_wallet_request(text) TO service_role;

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
 IF target IS NULL OR (NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_work w JOIN eshop.ticket_wallet_integrations i ON i.organization=w.organization WHERE NOT i.paused AND w.kind IN ('class','object') AND w.requested>w.applied AND w.due_at<=now() AND (w.lease_until IS NULL OR w.lease_until<=now())) AND NOT EXISTS(SELECT 1 FROM eshop.apple_ticket_wallet_passes a JOIN eshop.ticket_wallet_integrations i ON i.organization=a.organization WHERE NOT i.paused AND a.next_check<=now() AND (a.lease_until IS NULL OR a.lease_until<=clock_timestamp()))) THEN RETURN; END IF;
 PERFORM net.http_post(url:=target,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
END $$;
REVOKE ALL ON FUNCTION public.wake_ticket_wallet_worker() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.wake_ticket_wallet_worker() TO service_role;
-- Deployment schedules this service-only owner using the existing trusted cron owner.
-- No trigger, paid dispatch or tenant activation is performed by the migration.

-- The existing scheduler is owned by control-plane postgres. Upgrade that single
-- job with automation/ticket-wallet/update-control-plane-scheduler.sql after probes.
-- No runtime-DB schedule is installed by this source.
