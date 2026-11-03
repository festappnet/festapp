CREATE OR REPLACE FUNCTION get_reply_to_email_for_order(
    p_order_id BIGINT
)
RETURNS TEXT
LANGUAGE sql
STABLE
SET search_path = public, extensions
AS $$
    -- by joining its occasion and extracting the email from the occasion's 'data'.
    -- If occasion's reply_to is null, it falls back to the unit's reply_to.
    SELECT
        COALESCE(occ.data->>'reply_to', u.data->>'reply_to')
    FROM
        eshop.orders AS ord
    JOIN
        public.occasions AS occ ON ord.occasion = occ.id
    LEFT JOIN
        public.units AS u ON occ.unit = u.id
    WHERE
        ord.id = p_order_id;
$$;