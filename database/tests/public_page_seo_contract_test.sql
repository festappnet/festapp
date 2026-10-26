-- Disposable database only; no production data or personal information.
BEGIN;
DO $$
DECLARE unit_id bigint; org_id bigint; event_id bigint; other_id bigint; form_id bigint; result json;
BEGIN
 INSERT INTO public.organizations(title) VALUES ('SEO fixture') RETURNING id INTO org_id;
 INSERT INTO public.units(title,organization) VALUES ('SEO venue unit',org_id) RETURNING id INTO unit_id;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time)
 VALUES ('Event namespace','seo-shared',org_id,unit_id,now(),now()+interval '1 day') RETURNING id INTO event_id;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time)
 VALUES ('Form occasion','seo-other',org_id,unit_id,now(),now()+interval '1 day') RETURNING id INTO other_id;
 INSERT INTO public.forms(occasion,title,link,header) VALUES(other_id,'Saved form','seo-saved','<p>Tickets &amp; dinner</p>') RETURNING id INTO form_id;
 INSERT INTO public.occasion_link_reservations(slug,occasion) VALUES('seo-shared',event_id),('seo-old-event',event_id),('seo-other',other_id);
 INSERT INTO public.form_link_reservations(slug,form) VALUES('seo-shared',form_id),('seo-saved',form_id),('seo-old-form',form_id);
 result := public.get_occasion_seo_data('seo-shared','event');
 IF result->>'title' <> 'Event namespace' OR result->>'occasion_link' <> 'seo-shared' OR result->>'form_link' IS NOT NULL THEN RAISE EXCEPTION 'Event namespace mismatch: %',result; END IF;
 result := public.get_occasion_seo_data('seo-shared','form');
 IF result->>'title' <> 'Form occasion' OR result->>'form_link' <> 'seo-saved' OR result->>'form_title' <> 'Saved form' THEN RAISE EXCEPTION 'Form namespace mismatch: %',result; END IF;
 IF public.get_occasion_seo_data('seo-old-form')->>'form_link' <> 'seo-saved' THEN RAISE EXCEPTION 'Old form alias mismatch'; END IF;
 IF public.get_occasion_seo_data('seo-old-event','event')->>'occasion_link' <> 'seo-shared' THEN RAISE EXCEPTION 'Old event alias mismatch'; END IF;
 result := public.get_form_by_link('seo-saved');
 IF result->>'code' <> '200' OR result->'data'->'seo'->>'form_link' <> 'seo-saved' THEN RAISE EXCEPTION 'Form bundle SEO projection mismatch: %',result; END IF;
 UPDATE public.forms SET is_open=false WHERE id=form_id;
 result := public.get_form_by_link('seo-saved');
 IF result->>'code' <> '400' OR result->'data'->'seo'->>'form_link' <> 'seo-saved' THEN RAISE EXCEPTION 'Closed form SEO projection mismatch: %',result; END IF;
 IF public.get_occasion_seo_data('seo-missing','form') IS NOT NULL THEN RAISE EXCEPTION 'Missing form must be NULL'; END IF;
 IF public.get_occasion_seo_data('seo-other','form') IS NOT NULL THEN RAISE EXCEPTION 'Occasion slug must not resolve a form'; END IF;
 IF public.get_occasion_seo_data('seo-other')->>'title' <> 'Form occasion' THEN RAISE EXCEPTION 'Legacy occasion fallback missing'; END IF;
 IF public.get_occasion_seo_data('seo-saved','event') IS NOT NULL THEN RAISE EXCEPTION 'Form slug must not resolve an event'; END IF;
END $$;
SET LOCAL ROLE anon;
SELECT public.get_occasion_seo_data('seo-missing','event');
ROLLBACK;
