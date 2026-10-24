BEGIN READ ONLY;
SET LOCAL statement_timeout='10s';
WITH candidate AS (
 SELECT m."user" actor,et.id template_id,et.occasion target_occasion
 FROM public.occasion_users m JOIN public.occasions own_o ON own_o.id=m.occasion AND own_o.organization=1
 CROSS JOIN public.email_templates et JOIN public.occasions target_o ON target_o.id=et.occasion AND target_o.organization=1
 WHERE m.is_manager IS TRUE AND et.organization=1
 AND NOT EXISTS(SELECT 1 FROM public.organization_users a WHERE a."user"=m."user" AND a.is_admin IS TRUE)
 AND NOT EXISTS(SELECT 1 FROM public.occasion_users x WHERE x.occasion=et.occasion AND x."user"=m."user" AND (x.is_editor_view OR x.is_editor_order_view))
 AND NOT public.is_demo_occasion(et.occasion)
 LIMIT 1
) SELECT set_config('request.jwt.claims',json_build_object('role','authenticated','sub',actor)::text,true) IS NOT NULL AND set_config('audit.template',template_id::text,true) IS NOT NULL AND set_config('audit.occasion',target_occasion::text,true) IS NOT NULL AS candidate_selected FROM candidate;
SET LOCAL ROLE authenticated;
SELECT json_build_object('probe','unscoped_template_manager','candidate_selected',nullif(current_setting('audit.template',true),'') IS NOT NULL,'canonical_occasion_guard_allows',
 public.get_is_editor_view_on_occasion(nullif(current_setting('audit.occasion',true),'')::bigint) OR public.get_is_editor_order_view_on_occasion(nullif(current_setting('audit.occasion',true),'')::bigint),
 'direct_template_visible',EXISTS(SELECT 1 FROM public.email_templates WHERE id=nullif(current_setting('audit.template',true),'')::bigint));
ROLLBACK;
