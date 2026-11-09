BEGIN READ ONLY;
SELECT 'templates' AS source,count(*) AS affected FROM public.email_templates
 WHERE coalesce(subject,'')||coalesce(html,'') ~ '\{\{[[:space:]]*(order_symbol|occasion_title)[[:space:]]*\}\}'
UNION ALL SELECT 'wrappers',count(*) FROM public.email_wrappers
 WHERE html ~ '\{\{[[:space:]]*(order_symbol|occasion_title)[[:space:]]*\}\}'
UNION ALL SELECT 'drafts',count(*) FROM public.occasion_setup_drafts d
 WHERE EXISTS(SELECT 1 FROM jsonb_each(CASE WHEN jsonb_typeof(d.data->'emailTemplateOverrides')='object'
   THEN d.data->'emailTemplateOverrides' ELSE '{}'::jsonb END) item
  WHERE coalesce(item.value->>'subject','')||coalesce(item.value->>'html','')
   ~ '\{\{[[:space:]]*(order_symbol|occasion_title)[[:space:]]*\}\}');
SELECT paused,(SELECT count(*) FROM public.email_messages WHERE workflow_state IN ('preparing','sending')) AS in_flight
 FROM public.email_capacity;
COMMIT;
