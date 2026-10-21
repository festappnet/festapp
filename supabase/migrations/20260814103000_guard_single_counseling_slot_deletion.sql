-- A delete initiated from the speaker editor must never be able to delete an
-- ordinary program event or the counseling entry point.
CREATE OR REPLACE FUNCTION public.resolve_counseling_slot_delete_occasion_internal_v1(
  p_speaker BIGINT,
  p_event BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_occasion BIGINT;
BEGIN
  SELECT s.occasion INTO v_occasion
  FROM public.speakers s
  WHERE s.id = p_speaker;
  IF v_occasion IS NULL THEN RETURN NULL; END IF;
  IF auth.uid() IS NULL OR NOT public.get_is_editor_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor required';
  END IF;
  PERFORM 1
  FROM public.events e
  JOIN public.event_speakers es
    ON es.event = e.id AND es.speaker = p_speaker
  WHERE e.id = p_event
    AND e.occasion = v_occasion
    AND COALESCE((e.data->>'is_counseling_slot')::BOOLEAN, FALSE)
  FOR UPDATE OF e;
  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN v_occasion;
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_counseling_slot_delete_occasion_internal_v1(BIGINT, BIGINT)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_counseling_slot(p_speaker BIGINT, p_event BIGINT)
RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF public.resolve_counseling_slot_delete_occasion_internal_v1(p_speaker, p_event) IS NULL THEN
    RETURN jsonb_build_object('code', 400, 'message', 'counseling slot required');
  END IF;
  RETURN public.delete_event(p_event);
END;
$$;
REVOKE ALL ON FUNCTION public.delete_counseling_slot(BIGINT, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_counseling_slot(BIGINT, BIGINT) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_counseling_slot_client_sync_v1(
  p_speaker BIGINT, p_event_id BIGINT, p_command_id UUID,
  p_expected_version BIGINT
)
RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_occasion BIGINT;
BEGIN
  v_occasion := public.resolve_counseling_slot_delete_occasion_internal_v1(
    p_speaker, p_event_id);
  IF v_occasion IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'rejected', 'code', 400,
      'data', jsonb_build_object('eventId', p_event_id, 'deleted', FALSE),
      'mutation', jsonb_build_object(
        'commandId', p_command_id, 'receiptId', p_command_id,
        'commitId', NULL, 'replayed', FALSE, 'occurredAt', clock_timestamp()),
      'sync', jsonb_build_object('replacements', '[]'::jsonb));
  END IF;
  RETURN public.delete_event_client_sync_v1(
    v_occasion, p_event_id, p_command_id, p_expected_version);
END;
$$;
REVOKE ALL ON FUNCTION public.delete_counseling_slot_client_sync_v1(BIGINT, BIGINT, UUID, BIGINT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_counseling_slot_client_sync_v1(BIGINT, BIGINT, UUID, BIGINT)
  TO authenticated;

UPDATE public.client_sync_component_sources
SET canonical_writers = array_append(
  canonical_writers,
  'delete_counseling_slot_client_sync_v1'
)
WHERE registry_version = 1
  AND source_relation IN ('public.events', 'public.event_speakers')
  AND component IN ('program_catalog', 'content_catalog')
  AND NOT ('delete_counseling_slot_client_sync_v1' = ANY(canonical_writers));
