-- Global defaults use the normal inherited resolver and wrapper. Locale/tone
-- phrases are supplied to the same editor preview and production substitutions.
INSERT INTO public.email_templates(code,subject,html)
SELECT v.code,'{{sale_opening_subject}} - {{occasion_title}}',v.html FROM (VALUES
 ('sale_opening_opened','<h2>{{sale_opening_heading}}</h2><p>{{occasion_title}}</p><p>{{sale_opening_action}}</p><p>{{sale_opening_disclaimer}}</p><p>{{sale_opening_unsubscribe}}</p>')
) v(code,html) WHERE NOT EXISTS(SELECT 1 FROM public.email_templates t WHERE t.code=v.code
 AND t.organization IS NULL AND t.unit IS NULL AND t.occasion IS NULL);
