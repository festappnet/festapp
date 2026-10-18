\set ON_ERROR_STOP on
BEGIN READ ONLY;
-- Read every nongenerated application field, excluding the same named history
-- boundary as the migration inventory. Results stay inside the private drill.
-- Select by URL/decoder punctuation, not literal routes/hosts: embedded JSON
-- slashes and HTML entities must reach the structural parser as well.
SELECT format('SELECT v.value FROM %I.%I t CROSS JOIN LATERAL jsonb_each(to_jsonb(t)) v WHERE v.key=ANY(%L::text[]) AND v.value::text ~ %L;',
 n.nspname,c.relname,
 (SELECT array_agg(a.attname::text) FROM pg_attribute a WHERE a.attrelid=c.oid
  AND a.attnum>0 AND NOT a.attisdropped AND a.attgenerated=''),
 '[/&\\]')
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('public','eshop') AND c.relkind IN ('r','p') AND NOT c.relispartition
 AND c.relname NOT LIKE 'log\_%' ESCAPE '\'
 AND c.relname NOT IN ('email_messages','email_delivery_attempts','email_provider_events',
  'client_commit_items','client_mutation_receipts')
ORDER BY n.nspname,c.relname
\gexec
-- Mutable queued messages are current; completed delivery/replay/audit stays history.
SELECT to_jsonb(m) FROM public.email_messages m
WHERE workflow_state IN ('pending','blocked','preparing','sending','retry_wait')
 AND to_jsonb(m)::text ~ '[/&\\]';
COMMIT;
