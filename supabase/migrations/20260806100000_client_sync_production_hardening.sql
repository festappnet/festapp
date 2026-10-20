-- Production hardening for the canonical client_sync_v1 protocol.
-- Forward-only overlay; production execution remains a separately authorized step.
SET lock_timeout = '5s';
SET statement_timeout = '2min';

CREATE OR REPLACE FUNCTION public.release_client_projection_claims_v1(
  p_claim_tokens uuid[]
) RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_released integer;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  IF p_claim_tokens IS NULL OR cardinality(p_claim_tokens)=0
     OR array_position(p_claim_tokens,NULL) IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='non-empty claim tokens required';
  END IF;
  UPDATE public.client_projection_dirty_keys d
  SET claimed_at=NULL,claim_token=NULL
  WHERE d.claim_token=ANY(p_claim_tokens);
  GET DIAGNOSTICS v_released=ROW_COUNT;
  RETURN v_released;
END;
$$;
REVOKE ALL ON FUNCTION public.release_client_projection_claims_v1(uuid[])
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.release_client_projection_claims_v1(uuid[])
  TO service_role;

CREATE OR REPLACE FUNCTION public.refresh_event_public_state_internal_v1(
  p_occasion bigint,p_event_ids bigint[]
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.event_public_state
    (occasion,event,participant_count,saved_count,remaining_capacity,revision,projected_at)
  SELECT e.occasion,e.id,COUNT(DISTINCT eu."user"),COUNT(DISTINCT es."user"),
    CASE WHEN e.max_participants IS NULL THEN NULL
      ELSE GREATEST(e.max_participants-COUNT(DISTINCT eu."user"),0) END,
    COALESCE(s.source_revision,0),now()
  FROM public.events e
  LEFT JOIN public.event_users eu ON eu.event=e.id
  LEFT JOIN public.event_users_saved es ON es.event=e.id
  LEFT JOIN public.client_sync_scopes s ON s.component='live_public'
    AND s.scope_type='occasion' AND s.scope_id=e.occasion
  WHERE e.occasion=p_occasion AND NOT e.is_hidden
    AND (p_event_ids IS NULL OR e.id=ANY(p_event_ids))
  GROUP BY e.occasion,e.id,e.max_participants,s.source_revision
  ON CONFLICT (occasion,event) DO UPDATE SET
    participant_count=EXCLUDED.participant_count,
    saved_count=EXCLUDED.saved_count,
    remaining_capacity=EXCLUDED.remaining_capacity,
    revision=EXCLUDED.revision,projected_at=EXCLUDED.projected_at;

  DELETE FROM public.event_public_state state
  WHERE state.occasion=p_occasion
    AND (p_event_ids IS NULL OR state.event=ANY(p_event_ids))
    AND NOT EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id=state.event AND e.occasion=p_occasion AND NOT e.is_hidden
    );
END;
$$;
REVOKE ALL ON FUNCTION public.refresh_event_public_state_internal_v1(bigint,bigint[])
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.refresh_event_public_state_v1(
  p_occasion bigint,p_event_ids bigint[]
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  PERFORM public.refresh_event_public_state_internal_v1(p_occasion,p_event_ids);
END; $$;
REVOKE ALL ON FUNCTION public.refresh_event_public_state_v1(bigint,bigint[])
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_event_public_state_v1(bigint,bigint[])
  TO service_role;

ALTER TABLE public.client_mutation_receipts
  ADD COLUMN expired_at timestamptz;
ALTER TABLE public.client_mutation_receipts
  DROP CONSTRAINT client_mutation_receipts_status_check,
  DROP CONSTRAINT client_mutation_receipts_check2;
ALTER TABLE public.client_mutation_receipts
  ADD CONSTRAINT client_mutation_receipts_status_check
    CHECK (status IN ('processing','completed','expired')),
  ADD CONSTRAINT client_mutation_receipts_check2 CHECK (
    (status='processing' AND response IS NULL AND completed_at IS NULL AND expired_at IS NULL)
    OR (status='completed' AND response IS NOT NULL AND completed_at IS NOT NULL AND expired_at IS NULL)
    OR (status='expired' AND response IS NULL AND completed_at IS NOT NULL AND expired_at IS NOT NULL)
  );
DROP INDEX public.client_mutation_receipts_retention_idx;
CREATE INDEX client_mutation_receipts_retention_idx
  ON public.client_mutation_receipts(completed_at)
  WHERE status='completed';

CREATE OR REPLACE FUNCTION public.expired_client_mutation_response_v1(
  p_receipt public.client_mutation_receipts
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'status','expired','code',410,
    'data',jsonb_build_object('message','Command replay window expired'),
    'mutation',jsonb_build_object(
      'commandId',p_receipt.command_id,'receiptId',p_receipt.command_id,
      'commitId',p_receipt.commit_id,'replayed',true,'expired',true,
      'occurredAt',p_receipt.completed_at),
    'sync',jsonb_build_object('replacements','[]'::jsonb)
  );
$$;
REVOKE ALL ON FUNCTION public.expired_client_mutation_response_v1(public.client_mutation_receipts)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.begin_client_mutation_v1(
  p_command_id uuid,p_command_name text,p_occasion bigint,p_actor_id uuid,
  p_request_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_receipt public.client_mutation_receipts%ROWTYPE; v_inserted integer;
BEGIN
  IF p_command_id IS NULL OR p_actor_id IS NULL OR p_actor_id IS DISTINCT FROM auth.uid() THEN
    RAISE insufficient_privilege USING MESSAGE='authenticated command actor required';
  END IF;
  IF p_command_name !~ '^[a-z][a-z0-9_.]{2,95}$'
     OR p_request_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid mutation receipt metadata';
  END IF;
  INSERT INTO public.client_mutation_receipts
    (command_id,command_name,occasion,actor_id,request_sha256)
  VALUES (p_command_id,p_command_name,p_occasion,p_actor_id,p_request_sha256)
  ON CONFLICT (command_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  SELECT * INTO STRICT v_receipt FROM public.client_mutation_receipts
    WHERE command_id=p_command_id FOR UPDATE;
  IF v_receipt.command_name IS DISTINCT FROM p_command_name
     OR v_receipt.occasion IS DISTINCT FROM p_occasion
     OR v_receipt.actor_id IS DISTINCT FROM p_actor_id
     OR v_receipt.request_sha256 IS DISTINCT FROM p_request_sha256 THEN
    RAISE invalid_parameter_value USING MESSAGE='command id was already used with different request data';
  END IF;
  IF v_receipt.status='completed' THEN
    RETURN jsonb_build_object('disposition','replay','response',v_receipt.response);
  ELSIF v_receipt.status='expired' THEN
    RETURN jsonb_build_object('disposition','replay',
      'response',public.expired_client_mutation_response_v1(v_receipt));
  END IF;
  IF v_inserted<>1 THEN RAISE serialization_failure
    USING MESSAGE='incomplete mutation receipt cannot be resumed'; END IF;
  RETURN jsonb_build_object('disposition','claimed');
END; $$;

CREATE OR REPLACE FUNCTION public.begin_anonymous_client_mutation_v1(
  p_command_id uuid,p_command_name text,p_occasion bigint,p_actor_client_id uuid,
  p_request_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_receipt public.client_mutation_receipts%ROWTYPE; v_inserted integer;
BEGIN
  IF auth.uid() IS NOT NULL OR p_actor_client_id IS NULL OR p_command_id IS NULL
     OR p_occasion IS NULL OR p_command_name !~ '^[a-z][a-z0-9_.]{2,95}$'
     OR p_request_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid anonymous mutation receipt claim';
  END IF;
  INSERT INTO public.client_mutation_receipts
    (command_id,command_name,occasion,actor_client_id,request_sha256)
  VALUES (p_command_id,p_command_name,p_occasion,p_actor_client_id,p_request_sha256)
  ON CONFLICT (command_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  SELECT * INTO STRICT v_receipt FROM public.client_mutation_receipts
    WHERE command_id=p_command_id FOR UPDATE;
  IF v_receipt.command_name IS DISTINCT FROM p_command_name
     OR v_receipt.occasion IS DISTINCT FROM p_occasion OR v_receipt.actor_id IS NOT NULL
     OR v_receipt.actor_client_id IS DISTINCT FROM p_actor_client_id
     OR v_receipt.request_sha256 IS DISTINCT FROM p_request_sha256 THEN
    RAISE invalid_parameter_value USING MESSAGE='command id was already used with different request data';
  END IF;
  IF v_receipt.status='completed' THEN
    RETURN jsonb_build_object('disposition','replay','response',v_receipt.response);
  ELSIF v_receipt.status='expired' THEN
    RETURN jsonb_build_object('disposition','replay',
      'response',public.expired_client_mutation_response_v1(v_receipt));
  END IF;
  IF v_inserted<>1 THEN RAISE serialization_failure
    USING MESSAGE='incomplete mutation receipt cannot be resumed'; END IF;
  RETURN jsonb_build_object('disposition','claimed');
END; $$;

CREATE OR REPLACE FUNCTION public.begin_unit_client_mutation_v1(
  p_command_id uuid,p_command_name text,p_unit bigint,p_actor_id uuid,
  p_request_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_receipt public.client_mutation_receipts%ROWTYPE; v_inserted integer;
BEGIN
  IF p_actor_id IS NULL OR p_actor_id IS DISTINCT FROM auth.uid()
     OR p_command_id IS NULL OR p_unit IS NULL
     OR p_command_name !~ '^[a-z][a-z0-9_.]{2,95}$'
     OR p_request_sha256 !~ '^[0-9a-f]{64}$'
     OR NOT public.get_is_manager_on_unit(p_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='invalid unit mutation receipt claim';
  END IF;
  INSERT INTO public.client_mutation_receipts
    (command_id,command_name,unit,actor_id,request_sha256)
  VALUES (p_command_id,p_command_name,p_unit,p_actor_id,p_request_sha256)
  ON CONFLICT (command_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  SELECT * INTO STRICT v_receipt FROM public.client_mutation_receipts
    WHERE command_id=p_command_id FOR UPDATE;
  IF v_receipt.command_name IS DISTINCT FROM p_command_name
     OR v_receipt.occasion IS NOT NULL OR v_receipt.unit IS DISTINCT FROM p_unit
     OR v_receipt.actor_id IS DISTINCT FROM p_actor_id OR v_receipt.actor_client_id IS NOT NULL
     OR v_receipt.request_sha256 IS DISTINCT FROM p_request_sha256 THEN
    RAISE invalid_parameter_value USING MESSAGE='command id was already used with different request data';
  END IF;
  IF v_receipt.status='completed' THEN
    RETURN jsonb_build_object('disposition','replay','response',v_receipt.response);
  ELSIF v_receipt.status='expired' THEN
    RETURN jsonb_build_object('disposition','replay',
      'response',public.expired_client_mutation_response_v1(v_receipt));
  END IF;
  IF v_inserted<>1 THEN RAISE serialization_failure
    USING MESSAGE='incomplete mutation receipt cannot be resumed'; END IF;
  RETURN jsonb_build_object('disposition','claimed');
END; $$;

REVOKE ALL ON FUNCTION public.begin_client_mutation_v1(uuid,text,bigint,uuid,text)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.begin_anonymous_client_mutation_v1(uuid,text,bigint,uuid,text)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.begin_unit_client_mutation_v1(uuid,text,bigint,uuid,text)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.compact_client_mutation_receipts_v1(
  p_cutoff timestamptz,p_limit integer DEFAULT 500
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_count bigint; v_bytes bigint;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  IF p_cutoff IS NULL OR p_cutoff>now()-interval '30 days'
     OR p_limit NOT BETWEEN 1 AND 2000 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid receipt compaction boundary';
  END IF;
  WITH candidates AS (
    SELECT r.command_id,octet_length(r.response::text) response_bytes
    FROM public.client_mutation_receipts r
    WHERE r.status='completed' AND r.completed_at<p_cutoff
    ORDER BY r.completed_at,r.command_id
    FOR UPDATE SKIP LOCKED LIMIT p_limit
  ), updated AS (
    UPDATE public.client_mutation_receipts r
    SET status='expired',response=NULL,expired_at=clock_timestamp()
    FROM candidates c WHERE r.command_id=c.command_id
    RETURNING c.response_bytes
  ) SELECT count(*),COALESCE(sum(response_bytes),0) INTO v_count,v_bytes FROM updated;
  RETURN jsonb_build_object('compacted',v_count,'responseBytesReleasedEstimate',v_bytes);
END; $$;
REVOKE ALL ON FUNCTION public.compact_client_mutation_receipts_v1(timestamptz,integer)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.compact_client_mutation_receipts_v1(timestamptz,integer)
  TO service_role;

CREATE OR REPLACE FUNCTION public.require_client_sync_artifact_cutoff_v1(
  p_cutoff timestamptz
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_cutoff IS NULL OR p_cutoff>now()-interval '7 days' THEN
    RAISE invalid_parameter_value
      USING MESSAGE='client-sync artifact cutoff must preserve the seven-day safety floor';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.require_client_sync_artifact_cutoff_v1(timestamptz)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_client_sync_artifact_retention_candidates_v1(
  p_cutoff timestamptz,p_limit integer DEFAULT 200
) RETURNS TABLE(artifact_url text,published_at timestamptz,byte_size bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  PERFORM public.require_client_sync_artifact_cutoff_v1(p_cutoff);
  IF p_limit NOT BETWEEN 1 AND 1000 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid retention candidate limit';
  END IF;
  RETURN QUERY
  WITH protected_urls AS (
    SELECT h.head_json#>>'{live,url}' url
    FROM public.client_sync_public_heads h
    UNION
    SELECT component.value->>'url'
    FROM public.client_sync_public_heads h
    CROSS JOIN LATERAL jsonb_each(COALESCE(h.head_json#>'{catalog,components}','{}')) component
    UNION
    SELECT component.value->>'url'
    FROM public.client_sync_release_manifests m
    JOIN public.client_sync_public_heads h
      ON h.scope_type=m.scope_type AND h.scope_id=m.scope_id
      AND h.release_revision=m.release_revision
    CROSS JOIN LATERAL jsonb_each(COALESCE(m.manifest->'components','{}')) component
  ), protected_manifests AS (
    SELECT m.artifact_url
    FROM public.client_sync_release_manifests m
    JOIN public.client_sync_public_heads h
      ON h.scope_type=m.scope_type AND h.scope_id=m.scope_id
    WHERE m.release_revision=h.release_revision
       OR m.release_revision=(
         SELECT max(previous.release_revision)
         FROM public.client_sync_release_manifests previous
         WHERE previous.scope_type=m.scope_type AND previous.scope_id=m.scope_id
           AND previous.release_revision<h.release_revision
       )
  ), candidates AS (
    SELECT p.artifact_url,p.published_at,p.byte_size
    FROM public.client_sync_publications p
    WHERE p.published_at<p_cutoff
      AND p.artifact_url LIKE 'https://assets.festapp.net/client-sync/v1/%'
      AND NOT EXISTS (SELECT 1 FROM protected_urls u WHERE u.url=p.artifact_url)
    UNION ALL
    SELECT m.artifact_url,m.published_at,m.byte_size
    FROM public.client_sync_release_manifests m
    WHERE m.published_at<p_cutoff
      AND m.artifact_url LIKE 'https://assets.festapp.net/client-sync/v1/%'
      AND NOT EXISTS (SELECT 1 FROM protected_manifests p WHERE p.artifact_url=m.artifact_url)
  )
  SELECT c.artifact_url,c.published_at,c.byte_size FROM candidates c
  ORDER BY c.published_at,c.artifact_url LIMIT p_limit;
END; $$;
REVOKE ALL ON FUNCTION public.get_client_sync_artifact_retention_candidates_v1(timestamptz,integer)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_client_sync_artifact_retention_candidates_v1(timestamptz,integer)
  TO service_role;

CREATE OR REPLACE FUNCTION public.delete_client_sync_artifact_metadata_v1(
  p_artifact_url text,p_cutoff timestamptz
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_deleted integer:=0; v_part integer;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  PERFORM public.require_client_sync_artifact_cutoff_v1(p_cutoff);
  IF p_artifact_url IS NULL
     OR p_artifact_url NOT LIKE 'https://assets.festapp.net/client-sync/v1/%'
     OR p_artifact_url LIKE '%?%' OR p_artifact_url LIKE '%#%'
     OR p_artifact_url LIKE '%/../%' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid client-sync artifact URL';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.client_sync_public_heads h
    WHERE h.head_json#>>'{live,url}'=p_artifact_url
       OR EXISTS (SELECT 1 FROM jsonb_each(COALESCE(h.head_json#>'{catalog,components}','{}')) c
                  WHERE c.value->>'url'=p_artifact_url)
  ) OR EXISTS (
    SELECT 1 FROM public.client_sync_release_manifests m
    JOIN public.client_sync_public_heads h
      ON h.scope_type=m.scope_type AND h.scope_id=m.scope_id
    WHERE m.artifact_url=p_artifact_url
      AND (m.release_revision=h.release_revision OR m.release_revision=(
        SELECT max(previous.release_revision)
        FROM public.client_sync_release_manifests previous
        WHERE previous.scope_type=m.scope_type AND previous.scope_id=m.scope_id
          AND previous.release_revision<h.release_revision))
  ) THEN
    RETURN false;
  END IF;
  DELETE FROM public.client_sync_publications p
  WHERE p.artifact_url=p_artifact_url
    AND p.published_at<p_cutoff;
  GET DIAGNOSTICS v_deleted=ROW_COUNT;
  DELETE FROM public.client_sync_release_manifests m
  WHERE m.artifact_url=p_artifact_url
    AND m.published_at<p_cutoff;
  GET DIAGNOSTICS v_part=ROW_COUNT;
  RETURN v_deleted+v_part>0;
END; $$;
REVOKE ALL ON FUNCTION public.delete_client_sync_artifact_metadata_v1(text,timestamptz)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.delete_client_sync_artifact_metadata_v1(text,timestamptz)
  TO service_role;

CREATE OR REPLACE FUNCTION public.attach_event_live_projection_v1(
  p_commit_id uuid,p_occasion bigint,p_event_ids bigint[]
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_revision bigint;
BEGIN
  IF p_commit_id IS NULL OR p_occasion IS NULL OR p_event_ids IS NULL
     OR cardinality(p_event_ids)=0 OR array_position(p_event_ids,NULL) IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM public.client_commits c
                    WHERE c.commit_id=p_commit_id AND c.occasion=p_occasion) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid event live projection attachment';
  END IF;
  IF EXISTS (SELECT 1 FROM public.client_commit_components c
             WHERE c.commit_id=p_commit_id AND c.component='live_public'
               AND c.scope_type='occasion' AND c.scope_id=p_occasion) THEN
    RETURN;
  END IF;
  INSERT INTO public.client_sync_scopes(component,scope_type,scope_id,source_revision)
  VALUES ('live_public','occasion',p_occasion,1)
  ON CONFLICT (component,scope_type,scope_id) DO UPDATE
    SET source_revision=public.client_sync_scopes.source_revision+1,updated_at=now()
  RETURNING source_revision INTO v_revision;
  INSERT INTO public.client_commit_components
    (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
  VALUES (p_commit_id,'live_public','occasion',p_occasion,NULL,v_revision);
  INSERT INTO public.client_projection_dirty_keys
    (component,scope_type,scope_id,entity_id,source_revision)
  SELECT 'live_public','occasion',p_occasion,id,v_revision
  FROM (SELECT DISTINCT unnest(p_event_ids) id) ids
  ON CONFLICT (component,scope_type,scope_id,entity_id) DO UPDATE
    SET source_revision=GREATEST(public.client_projection_dirty_keys.source_revision,
        EXCLUDED.source_revision),dirty_since=now(),claimed_at=NULL,claim_token=NULL;
  PERFORM public.refresh_event_public_state_internal_v1(p_occasion,p_event_ids);
END; $$;
REVOKE ALL ON FUNCTION public.attach_event_live_projection_v1(uuid,bigint,bigint[])
  FROM PUBLIC,anon,authenticated;

ALTER FUNCTION public.save_event_client_sync_v1(bigint,uuid,bigint,jsonb)
  RENAME TO save_event_domain_command_internal_v1;
REVOKE ALL ON FUNCTION public.save_event_domain_command_internal_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.save_event_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_event jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_response jsonb; v_commit uuid; v_event bigint;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements_text(CASE
      WHEN jsonb_typeof(p_event->'parentEventIds')='array'
        THEN p_event->'parentEventIds' ELSE '[]'::jsonb END) AS parent(parent_id)
    LEFT JOIN public.events e ON e.id=parent.parent_id::bigint
      AND e.occasion=p_occasion
    WHERE e.id IS NULL
  ) OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements_text(CASE
      WHEN jsonb_typeof(p_event->'eventRoleIds')='array'
        THEN p_event->'eventRoleIds' ELSE '[]'::jsonb END) AS requested_role(role_id)
    LEFT JOIN public.role_info r ON r.id=requested_role.role_id::bigint
      AND r.occasion=p_occasion
    WHERE r.id IS NULL
  ) THEN
    RAISE invalid_parameter_value
      USING MESSAGE='event aggregate contains cross-scope references';
  END IF;
  v_response:=public.save_event_domain_command_internal_v1(
    p_occasion,p_command_id,p_expected_version,p_event);
  IF v_response->>'status'='applied' THEN
    v_commit:=NULLIF(v_response#>>'{mutation,commitId}','')::uuid;
    v_event:=NULLIF(v_response#>>'{data,event,id}','')::bigint;
    IF v_event IS NULL THEN v_event:=NULLIF(v_response#>>'{data,eventId}','')::bigint; END IF;
    IF v_commit IS NOT NULL AND v_event IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=p_occasion AND NOT o.is_hidden) THEN
      PERFORM public.attach_event_live_projection_v1(v_commit,p_occasion,ARRAY[v_event]);
    END IF;
  END IF;
  RETURN v_response;
END; $$;
REVOKE ALL ON FUNCTION public.save_event_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_event_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

ALTER FUNCTION public.create_counseling_slots_client_sync_v1(
  bigint,timestamptz,timestamptz,integer,bigint,integer,text,integer,uuid
) RENAME TO create_counseling_slots_domain_command_internal_v1;
REVOKE ALL ON FUNCTION public.create_counseling_slots_domain_command_internal_v1(
  bigint,timestamptz,timestamptz,integer,bigint,integer,text,integer,uuid
) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.create_counseling_slots_client_sync_v1(
  p_speaker bigint,p_start timestamptz,p_end timestamptz,p_slot_minutes integer,
  p_place bigint,p_capacity integer,p_title text,p_break_minutes integer,
  p_command_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_response jsonb; v_commit uuid; v_occasion bigint; v_ids bigint[];
BEGIN
  v_response:=public.create_counseling_slots_domain_command_internal_v1(
    p_speaker,p_start,p_end,p_slot_minutes,p_place,p_capacity,p_title,
    p_break_minutes,p_command_id);
  IF v_response->>'status'='applied' THEN
    v_commit:=NULLIF(v_response#>>'{mutation,commitId}','')::uuid;
    SELECT s.occasion INTO v_occasion FROM public.speakers s WHERE s.id=p_speaker;
    SELECT COALESCE(array_agg(value::bigint ORDER BY value::bigint),'{}') INTO v_ids
    FROM jsonb_array_elements_text(COALESCE(v_response#>'{data,event_ids}','[]'));
    IF v_commit IS NOT NULL AND cardinality(v_ids)>0
       AND EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=v_occasion AND NOT o.is_hidden) THEN
      PERFORM public.attach_event_live_projection_v1(v_commit,v_occasion,v_ids);
    END IF;
  END IF;
  RETURN v_response;
END; $$;
REVOKE ALL ON FUNCTION public.create_counseling_slots_client_sync_v1(
  bigint,timestamptz,timestamptz,integer,bigint,integer,text,integer,uuid
) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_counseling_slots_client_sync_v1(
  bigint,timestamptz,timestamptz,integer,bigint,integer,text,integer,uuid
) TO authenticated;

ALTER FUNCTION public.create_occasion_client_sync_v1(uuid,jsonb)
  RENAME TO create_occasion_domain_command_internal_v1;
REVOKE ALL ON FUNCTION public.create_occasion_domain_command_internal_v1(uuid,jsonb)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.create_occasion_client_sync_v1(
  p_command_id uuid,p_config jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_config jsonb; v_data jsonb;
BEGIN
  v_data:=CASE WHEN jsonb_typeof(p_config->'data')='object'
    THEN p_config->'data' ELSE '{}'::jsonb END;
  v_config:=jsonb_set(p_config,'{data}',
    jsonb_set(v_data,'{client_sync_v1}','false'::jsonb,true),true);
  RETURN public.create_occasion_domain_command_internal_v1(p_command_id,v_config);
END; $$;
REVOKE ALL ON FUNCTION public.create_occasion_client_sync_v1(uuid,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_occasion_client_sync_v1(uuid,jsonb)
  TO authenticated;

ALTER FUNCTION public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)
  RENAME TO save_occasion_domain_command_internal_v1;
REVOKE ALL ON FUNCTION public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.save_occasion_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_config jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_config jsonb; v_data jsonb; v_enabled boolean; v_hidden boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_occasion(p_occasion)
      OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT COALESCE((o.data->>'client_sync_v1')::boolean,false),o.is_hidden
    INTO v_enabled,v_hidden FROM public.occasions o WHERE o.id=p_occasion;
  IF v_enabled AND NOT v_hidden AND COALESCE((p_config->>'is_hidden')::boolean,false) THEN
    RAISE object_not_in_prerequisite_state
      USING MESSAGE='disable client_sync_v1 before hiding occasion';
  END IF;
  v_data:=CASE WHEN jsonb_typeof(p_config->'data')='object'
    THEN p_config->'data' ELSE '{}'::jsonb END;
  v_config:=jsonb_set(p_config,'{data}',jsonb_set(v_data,'{client_sync_v1}',
    to_jsonb(COALESCE(v_enabled,false)),true),true);
  RETURN public.save_occasion_domain_command_internal_v1(
    p_occasion,p_command_id,p_expected_version,v_config);
END; $$;
REVOKE ALL ON FUNCTION public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

ALTER FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid)
  RENAME TO duplicate_occasion_domain_command_internal_v1;
REVOKE ALL ON FUNCTION public.duplicate_occasion_domain_command_internal_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.duplicate_occasion_client_sync_v1(
  p_occasion bigint,p_command_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_response jsonb; v_new bigint; v_unit bigint;
BEGIN
  SELECT o.unit INTO v_unit FROM public.occasions o WHERE o.id=p_occasion;
  IF auth.uid() IS NULL OR v_unit IS NULL
     OR NOT public.get_is_manager_on_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required';
  END IF;
  v_response:=public.duplicate_occasion_domain_command_internal_v1(p_occasion,p_command_id);
  v_new:=NULLIF(v_response#>>'{data,occasionId}','')::bigint;
  IF v_response->>'status'='applied' AND v_new IS NOT NULL THEN
    UPDATE public.occasions o SET data=jsonb_set(COALESCE(o.data,'{}'),
      '{client_sync_v1}','false'::jsonb,true) WHERE o.id=v_new;
  END IF;
  RETURN v_response;
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid)
  TO authenticated;

ALTER FUNCTION public.delete_occasion_client_sync_v1(bigint,uuid)
  RENAME TO delete_occasion_domain_command_internal_v1;
REVOKE ALL ON FUNCTION public.delete_occasion_domain_command_internal_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.delete_occasion_client_sync_v1(
  p_occasion bigint,p_command_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_unit bigint;
BEGIN
  SELECT o.unit INTO v_unit FROM public.occasions o WHERE o.id=p_occasion;
  IF auth.uid() IS NULL OR v_unit IS NULL OR NOT public.get_is_manager_on_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required';
  END IF;
  IF EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=p_occasion
             AND COALESCE((o.data->>'client_sync_v1')::boolean,false)) THEN
    RAISE object_not_in_prerequisite_state
      USING MESSAGE='disable client_sync_v1 before deleting occasion';
  END IF;
  RETURN public.delete_occasion_domain_command_internal_v1(p_occasion,p_command_id);
END; $$;
REVOKE ALL ON FUNCTION public.delete_occasion_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion_client_sync_v1(bigint,uuid)
  TO authenticated;

-- One audited, generic repair for enabled public scopes that are unhealthy at
-- migration time. No production event or occasion IDs are embedded here.
DO $live_projection_repair$
DECLARE v_occasion record; v_commit uuid; v_revision bigint;
BEGIN
  FOR v_occasion IN
    SELECT o.id
    FROM public.occasions o
    WHERE NOT o.is_hidden
      AND COALESCE((o.data->>'client_sync_v1')::boolean,false)
      AND (
        EXISTS (
          SELECT 1
          FROM public.events e
          LEFT JOIN public.event_public_state state
            ON state.occasion=e.occasion AND state.event=e.id
          WHERE e.occasion=o.id AND NOT e.is_hidden
            AND (state.event IS NULL
              OR state.participant_count IS DISTINCT FROM
                (SELECT count(DISTINCT eu."user") FROM public.event_users eu WHERE eu.event=e.id)
              OR state.saved_count IS DISTINCT FROM
                (SELECT count(DISTINCT saved."user") FROM public.event_users_saved saved WHERE saved.event=e.id)
              OR state.remaining_capacity IS DISTINCT FROM CASE
                WHEN e.max_participants IS NULL THEN NULL
                ELSE GREATEST(e.max_participants-
                  (SELECT count(DISTINCT eu."user") FROM public.event_users eu WHERE eu.event=e.id),0)
              END)
        )
        OR EXISTS (
          SELECT 1 FROM public.event_public_state state
          WHERE state.occasion=o.id AND NOT EXISTS (
            SELECT 1 FROM public.events e
            WHERE e.id=state.event AND e.occasion=o.id AND NOT e.is_hidden
          )
        )
      )
    ORDER BY o.id
  LOOP
    PERFORM 1 FROM public.occasions o WHERE o.id=v_occasion.id FOR UPDATE;
    INSERT INTO public.client_commits
      (occasion,actor_id,actor_display,actor_kind,source,change_class,reason)
    VALUES (v_occasion.id,NULL,NULL,'system','client_sync.live_projection_repair',
      'live_projection','forward migration repaired detected projection drift')
    RETURNING commit_id INTO v_commit;
    INSERT INTO public.client_commit_items
      (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
    VALUES (v_commit,0,'event_public_state',NULL,'publish','Live projection repair',
      ARRAY['projection']);
    INSERT INTO public.client_sync_scopes(component,scope_type,scope_id,source_revision)
    VALUES ('live_public','occasion',v_occasion.id,1)
    ON CONFLICT (component,scope_type,scope_id) DO UPDATE
      SET source_revision=public.client_sync_scopes.source_revision+1,updated_at=now()
    RETURNING source_revision INTO v_revision;
    INSERT INTO public.client_commit_components
      (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
    VALUES (v_commit,'live_public','occasion',v_occasion.id,NULL,v_revision);
    PERFORM public.refresh_event_public_state_internal_v1(v_occasion.id,NULL);
    INSERT INTO public.client_projection_dirty_keys
      (component,scope_type,scope_id,entity_id,source_revision)
    VALUES ('live_public','occasion',v_occasion.id,0,v_revision)
    ON CONFLICT (component,scope_type,scope_id,entity_id) DO UPDATE
      SET source_revision=GREATEST(public.client_projection_dirty_keys.source_revision,
        EXCLUDED.source_revision),dirty_since=now(),claimed_at=NULL,claim_token=NULL;
  END LOOP;
END
$live_projection_repair$;
