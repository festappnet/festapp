UPDATE public.forms SET data=jsonb_set(data,'{payments}',public.merge_form_payments_internal(data->'payments',NULL))
 WHERE jsonb_typeof(data)='object' AND data ? 'payments';
UPDATE public.occasion_setup_drafts SET data=public.normalize_setup_payments_internal(data)
 WHERE NOT data ? 'finalizedOccasion';
