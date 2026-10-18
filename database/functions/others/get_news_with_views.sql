CREATE OR REPLACE FUNCTION get_news_with_views(oc bigint)
RETURNS TABLE(
    id bigint,
    created_at timestamp with time zone,
    message text,
    name text,
    surname text,
    views bigint
)
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$

BEGIN
    -- Check if the user has access to the occasion
    PERFORM public.get_occasion_for_context_v1(oc);

    -- Return the news data with the total views count, ordered by highest news_id
    RETURN QUERY
    SELECT
        n.id,
        n.created_at,
        n.message,
        -- Return NULL for name and surname if created_by is NULL
        CASE WHEN n.created_by IS NULL THEN NULL ELSE ui.name END AS name,
        CASE WHEN n.created_by IS NULL THEN NULL ELSE ui.surname END AS surname,
        COUNT(un."user") AS views  -- Counting all users who have interacted with the news
    FROM
        public.news n
    LEFT JOIN
        public.user_info ui ON ui.id = n.created_by  -- Join user_info to get the name and surname
    LEFT JOIN
        public.user_news un ON un.news_id = n.id AND un.occasion = oc  -- Join with user_news to count users for the specific occasion
    WHERE
        n.occasion = oc
    GROUP BY
        n.id, ui.name, ui.surname
    ORDER BY
        n.id DESC;  -- Sorting by news_id in descending order (highest first)

END;
$$;
REVOKE ALL ON FUNCTION public.get_news_with_views(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_news_with_views(bigint) TO anon,authenticated,service_role;
