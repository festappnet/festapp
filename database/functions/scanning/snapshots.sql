CREATE OR REPLACE FUNCTION public.prepare_scanner_snapshot(p_session uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; sid uuid:=gen_random_uuid(); v_manifest jsonb;
 policy jsonb; max_items bigint; max_bytes bigint; items bigint; bytes bigint;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token); SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 IF NOT (cfg.config#>>'{offline,enabled}')::boolean OR s.offline_until<=now() THEN RAISE insufficient_privilege USING MESSAGE='offline_disabled'; END IF;
 -- Bound repeated materialization per device, in addition to existing operation/export policy.
 PERFORM pg_advisory_xact_lock(hashtextextended(p_session::text,5318));
 IF EXISTS(SELECT 1 FROM public.scanner_snapshots WHERE session_id=p_session AND created_at>now()-interval '60 seconds') THEN
  RETURN jsonb_build_object('code',429,'reason','snapshot_rate_limit','retry_after_ms',60000,'server_time',now()); END IF;
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 policy:=public.abuse_effective_rules_v1('scan.export',(SELECT unit FROM public.occasions WHERE id=s.occasion_id),(SELECT organization FROM public.occasions WHERE id=s.occasion_id));
 SELECT (r->>'base_limit')::bigint INTO max_items FROM jsonb_array_elements(policy->'rules') r WHERE r->>'rule_key'='scan.export.items';
 SELECT (r->>'base_limit')::bigint INTO max_bytes FROM jsonb_array_elements(policy->'rules') r WHERE r->>'rule_key'='scan.export.bytes';
 IF max_items IS NULL OR max_bytes IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 INSERT INTO public.scanner_snapshots(id,session_id,manifest,expires_at) VALUES(sid,p_session,'{}',s.offline_until);
 -- Exactly one statement snapshot supplies pages AND manifest. Never paginate live tickets.
 WITH projected AS MATERIALIZED (
  SELECT ticket_id,dto,row_number() OVER(ORDER BY ticket_id) rn FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config)
 ), pages AS MATERIALIZED (
  SELECT ((rn-1)/200)::integer idx,jsonb_agg(dto ORDER BY rn)::text payload,count(*) n FROM projected GROUP BY ((rn-1)/200)::integer
 ), stored AS (
  INSERT INTO public.scanner_snapshot_pages(snapshot_id,page_index,payload_text,digest)
  SELECT sid,idx,payload,encode(digest(convert_to(payload,'UTF8'),'sha256'),'hex') FROM pages RETURNING *
 ) SELECT jsonb_build_object('schema_version',1,'snapshot_id',sid,'session_id',p_session,'occasion_id',s.occasion_id,'epoch',s.epoch,
 'settings_revision',cfg.revision,'server_time',now(),'expires_at',s.offline_until,'ticket_count',(SELECT count(*) FROM projected),
 'byte_count',coalesce(sum(octet_length(payload_text)),0),'pages',coalesce(jsonb_agg(jsonb_build_object('index',page_index,'digest',digest) ORDER BY page_index),'[]'::jsonb))
 INTO v_manifest FROM stored;
 items:=(v_manifest->>'ticket_count')::bigint; bytes:=(v_manifest->>'byte_count')::bigint;
 IF items>max_items OR bytes>max_bytes THEN
  DELETE FROM public.scanner_snapshots WHERE id=sid;
  RETURN jsonb_build_object('code',429,'reason','snapshot_policy_limit','server_time',now()); END IF;
 UPDATE public.scanner_snapshots SET manifest=v_manifest WHERE id=sid;
 -- Snapshot cleanup only; receipts and unresolved operations are never TTL deleted.
 DELETE FROM public.scanner_snapshots WHERE expires_at<now()-interval '24 hours';
 RETURN jsonb_build_object('code',200,'data',v_manifest,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.get_scanner_snapshot_page(p_session uuid,p_token text,p_snapshot uuid,p_page integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 SELECT jsonb_build_object('payload_text',pg.payload_text,'digest',pg.digest,'page_index',pg.page_index) INTO result
 FROM public.scanner_snapshot_pages pg JOIN public.scanner_snapshots sn ON sn.id=pg.snapshot_id
 WHERE sn.id=p_snapshot AND sn.session_id=p_session AND sn.expires_at>now() AND pg.page_index=p_page;
 RETURN jsonb_build_object('code',CASE WHEN result IS NULL THEN 404 ELSE 200 END,'data',result,'server_time',now());
END $$;
REVOKE ALL ON FUNCTION public.prepare_scanner_snapshot(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_scanner_snapshot(uuid,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_scanner_snapshot_page(uuid,text,uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_snapshot_page(uuid,text,uuid,integer) TO anon,authenticated,service_role;
