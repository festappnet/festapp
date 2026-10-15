-- One-time adoption of exact stored URLs; never changes canonical links/titles.
INSERT INTO public.occasion_link_reservations(slug,occasion)
 SELECT link,CASE WHEN count(*)=1 THEN min(id) END FROM public.occasions
 WHERE link IS NOT NULL AND link<>'' GROUP BY link;
INSERT INTO public.legacy_occasion_link_bindings(slug,organization,occasion)
 SELECT o.link,o.organization,o.id FROM public.occasions o
 JOIN public.occasion_link_reservations r ON r.slug=o.link
 WHERE r.occasion IS NULL;
INSERT INTO public.form_link_reservations(slug,form)
 SELECT link,id FROM public.forms WHERE link IS NOT NULL AND link<>'';
