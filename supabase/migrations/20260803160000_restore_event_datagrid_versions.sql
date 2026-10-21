-- The client-sync event command uses optimistic concurrency. Admin grid rows
-- must therefore carry the current event aggregate version into the save RPC.
CREATE OR REPLACE FUNCTION public.get_all_events_for_datagrid(
    p_occasion_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    result_jsonb jsonb;
BEGIN
    IF NOT public.get_is_editor_view_on_occasion(p_occasion_id) THEN
        RAISE EXCEPTION
            'Insufficient permissions. User requires editor view rights for this occasion.'
            USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(jsonb_agg(event_row.data), '[]'::jsonb)
    INTO result_jsonb
    FROM (
        SELECT jsonb_build_object(
            'id', e.id,
            'aggregate_version', COALESCE(av.version, 0),
            'is_hidden', e.is_hidden,
            'title', e.title,
            'start_time', e.start_time,
            'end_time', e.end_time,
            'max_participants', e.max_participants,
            'split_for_men_women', e.split_for_men_women,
            'is_group_event', e.is_group_event,
            'type', e.type,
            'data', e.data,
            'places', CASE
                WHEN p.id IS NULL THEN NULL::jsonb
                ELSE jsonb_build_object('id', p.id, 'title', p.title)
            END,
            'event_groups', (
                SELECT COALESCE(
                    jsonb_agg(jsonb_build_object('event_parent', eg.event_parent)),
                    '[]'::jsonb
                )
                FROM public.event_groups eg
                WHERE eg.event_child = e.id
            ),
            'event_roles', (
                SELECT COALESCE(
                    jsonb_agg(jsonb_build_object('role', er.role)),
                    '[]'::jsonb
                )
                FROM public.event_roles er
                WHERE er.event = e.id
            ),
            'event_users_saved', (
                SELECT jsonb_agg(jsonb_build_object('count', totals.count))
                FROM (
                    SELECT count(*) AS count
                    FROM public.event_users_saved eus
                    WHERE eus.event = e.id
                ) totals
            ),
            'event_users', (
                SELECT jsonb_agg(jsonb_build_object('count', totals.count))
                FROM (
                    SELECT count(*) AS count
                    FROM public.event_users eu
                    WHERE eu.event = e.id
                ) totals
            )
        ) AS data
        FROM public.events e
        LEFT JOIN public.places p ON p.id = e.place
        LEFT JOIN public.client_aggregate_versions av
          ON av.aggregate_type = 'event'
         AND av.scope_type = 'occasion'
         AND av.scope_id = p_occasion_id
         AND av.aggregate_id = e.id::text
        WHERE e.occasion = p_occasion_id
        ORDER BY e.start_time ASC
    ) AS event_row;

    RETURN result_jsonb;
END;
$$;

