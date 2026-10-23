-- Apply after schema, invariant guards, document infrastructure and commands.
GRANT EXECUTE ON FUNCTION public.create_ticket_batch_client_sync_v1(bigint,text,jsonb,uuid,uuid),
 public.sell_ticket_batch_items_client_sync_v1(uuid,bigint[],jsonb,boolean,uuid),
 public.void_ticket_batch_items_client_sync_v1(uuid,bigint[],text,uuid) TO authenticated;
