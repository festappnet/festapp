BEGIN READ ONLY;
SELECT jsonb_build_object('kind','setup_draft_inventory','drafts',count(*),'ticket_drafts',count(*) FILTER(WHERE data ? 'ticketDraft'),'ticket_draft_schemas',jsonb_agg(DISTINCT data->'ticketDraft'->'layout'->'schemaVersion'),'source_selected',count(*) FILTER(WHERE data->>'sourceId' IS NOT NULL)) FROM public.occasion_setup_drafts WHERE organization=3;
COMMIT;
