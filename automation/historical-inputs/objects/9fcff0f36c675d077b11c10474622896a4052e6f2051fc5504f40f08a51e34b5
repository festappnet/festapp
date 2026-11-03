DROP FUNCTION IF EXISTS public.get_user_groups(BIGINT);

CREATE OR REPLACE FUNCTION public.get_user_groups(p_occasion_id BIGINT)
RETURNS JSONB
SET search_path = public, extensions AS $$
DECLARE
    -- Retrieve the user ID from the authentication context
    current_user_id UUID := auth.uid();
BEGIN
    -- This function retrieves all groups a user is a member of for a specific occasion,
    -- including their admin status for each group.
    -- It joins the user_groups table (which defines membership and roles)
    -- with the user_group_info table (which contains group details)
    -- and filters the results by the provided occasion ID.
    -- The result is aggregated into a single JSONB object (dictionary) where keys are group IDs.

    RETURN (
        SELECT
            -- COALESCE ensures that if the user is not in any groups for this occasion,
            -- an empty JSON object '{}' is returned instead of NULL.
            COALESCE(
                jsonb_object_agg(
                    ugi.id, -- The group ID is used as the key.
                    -- jsonb_build_object constructs a JSON object for each group.
                    jsonb_build_object(
                        'id', ugi.id,
                        'title', ugi.title,
                        'type', ugi.type,
                        'place', ugi.place,
                        'description', ugi.description,
                        'occasion', ugi.occasion,
                        'data', ugi.data,
                        'is_admin', ug.is_admin
                    )
                ),
                '{}'::JSONB
            )
        FROM
            -- ug is the membership link table
            public.user_groups ug
        JOIN
            -- ugi contains the actual information about the group
            public.user_group_info ugi ON ug."group" = ugi.id
        WHERE
            -- Filter to get groups for the currently authenticated user
            ug."user" = current_user_id
            -- AND filter by the specific occasion ID passed to the function
            AND ugi.occasion = p_occasion_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
