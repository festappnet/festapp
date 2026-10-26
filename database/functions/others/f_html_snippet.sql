-- f_html_snippet — turns an HTML description into a clean plain-text snippet
-- for list subtitles (GlobalSearch results, etc.).
--
-- The previous approach (`LEFT(description, 120)`) cut the *raw HTML* blindly,
-- which produced dangling tags (a stray "<"), mid-word cuts, and — because
-- markup eats into the budget — wildly variable amounts of actual text. This
-- helper instead:
--   1. removes HTML tags,
--   2. collapses whitespace,
--   3. truncates to p_limit characters at a word boundary, and
--   4. appends an ellipsis ONLY when the text was actually shortened.
-- Text at or under the limit comes back whole, so short snippets never get a
-- dangling "…".
CREATE OR REPLACE FUNCTION public.f_html_snippet(p_html text, p_limit integer DEFAULT 160)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 PARALLEL SAFE
AS $function$
    WITH cleaned AS (
        SELECT btrim(
                 regexp_replace(
                   regexp_replace(
                     -- drop complete tags, then any dangling unterminated "<…"
                     regexp_replace(coalesce(p_html, ''), '<[^>]*>', ' ', 'g'),
                     '<[^>]*$', '', 'g'
                   ),
                   '\s+', ' ', 'g'
                 )
               ) AS t
    )
    SELECT CASE
             WHEN length(t) <= p_limit THEN t
             -- Drop the partial trailing word, then mark the cut.
             ELSE btrim(regexp_replace(LEFT(t, p_limit), '\s\S*$', '')) || '…'
           END
    FROM cleaned;
$function$;
